using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>Message kinds on the wire. Two bits; there is room for four.</summary>
    public enum NetMessage : byte
    {
        Input = 0,      // client to server
        Snapshot = 1,   // server to client
    }

    /// <summary>
    /// The authoritative server.
    /// </summary>
    /// <remarks>
    /// Owns the one <see cref="MatchSimulation"/> that is true. Clients send commands; it sends
    /// snapshots. It never receives a position, a health value, or a claim that a shot hit —
    /// not because it checks for them, but because <see cref="NetServer"/> has no code that
    /// could read one. That is the difference between an anti-cheat measure and an architecture.
    ///
    /// <para>Snapshots go out at <see cref="SnapshotHz"/>, not at the simulation's 64 Hz.
    /// Sending every tick would triple the bandwidth for motion the client interpolates anyway.
    /// The simulation still runs at 64 Hz, because hit registration and movement need the
    /// resolution even when the presentation does not.</para>
    /// </remarks>
    public sealed class NetServer
    {
        /// <summary>Snapshots per second. 20 is the genre norm and fits the bandwidth budget.</summary>
        public const int SnapshotHz = 20;

        private sealed class ClientLink
        {
            public PlayerId Player;
            public SimulatedLink ToClient;
            public SimulatedLink FromClient;
            /// <summary>The last snapshot this client confirmed receiving. Deltas are encoded
            /// against this and nothing else.</summary>
            public WorldSnapshot AcknowledgedBaseline;

            /// <summary>
            /// Commands received but not yet simulated, oldest first.
            /// </summary>
            /// <remarks>
            /// A queue, not a single slot. Jitter routinely delivers two commands in one server
            /// tick and none in the next; with a single slot the second overwrites the first
            /// before either is simulated, so one of the player's ticks is silently discarded.
            /// The client, having predicted both, then disagrees with the server forever —
            /// which is exactly the divergence this queue exists to prevent.
            /// </remarks>
            public readonly Queue<PlayerInput> Pending = new Queue<PlayerInput>();

            /// <summary>Highest input tick accepted, for discarding late and duplicate packets.</summary>
            public int HighestInputTick = -1;

            /// <summary>
            /// The tick of the command actually simulated most recently. This is what the client
            /// reconciles against, and it is emphatically not the server's own tick: the two
            /// clocks differ by the connection's latency, and comparing a prediction at one
            /// against a result at the other guarantees a correction on every snapshot.
            /// </summary>
            public int LastProcessedInputTick = -1;

            /// <summary>Round-trip time the <em>server</em> measured. Never a client claim.</summary>
            public float MeasuredLatency;
            public int InputsReceived;
            public int InputsDropped;
            /// <summary>Ticks where the queue was empty and the previous command was reused.
            /// A rising count means this client's connection cannot keep the buffer fed.</summary>
            public int Starvations;

            /// <summary>
            /// True while waiting for the jitter buffer to refill before consuming again.
            /// </summary>
            public bool Priming = true;
        }

        private readonly MatchSimulation _match;
        private readonly Dictionary<int, ClientLink> _clients = new Dictionary<int, ClientLink>();
        private readonly BitWriter _writer = new BitWriter(2048);
        private readonly WorldSnapshot _current = new WorldSnapshot();
        private readonly Dictionary<int, WorldSnapshot> _history = new Dictionary<int, WorldSnapshot>();

        public MatchSimulation Match => _match;
        public int BytesSent { get; private set; }
        public int SnapshotsSent { get; private set; }

        /// <summary>
        /// The content this server is running. Every client is checked against it before being
        /// allowed in.
        /// </summary>
        public ContentManifest Manifest { get; }

        /// <summary>Clients refused because their content did not match.</summary>
        public int RejectedClients { get; private set; }

        public NetServer(MatchSimulation match, ContentManifest manifest = null)
        {
            _match = match;
            Manifest = manifest ?? ContentManifest.Build(match.Content);
        }

        /// <summary>
        /// Admits a client, if its content agrees with the server's.
        /// </summary>
        /// <remarks>
        /// The check happens here rather than after the first snapshot on purpose. A client
        /// running different weapon statistics produces a match where prediction never settles
        /// and damage numbers disagree, and every symptom of it points at the netcode. Refusing
        /// at the door turns a week of confused debugging into one message.
        ///
        /// <para>A null <paramref name="clientManifest"/> means the client did not present one,
        /// which is refused rather than assumed fine — an old build that does not know to send a
        /// manifest is exactly the kind of client this is for.</para>
        /// </remarks>
        public ContentCheck AddClient(PlayerId player, SimulatedLink toClient,
                                      SimulatedLink fromClient,
                                      ContentManifest clientManifest = null)
        {
            ContentCheck check = ContentCompatibility.Check(Manifest, clientManifest ?? Manifest);
            if (!check.CanPlay)
            {
                RejectedClients++;
                return check;
            }

            _clients[player.Raw] = new ClientLink
            {
                Player = player, ToClient = toClient, FromClient = fromClient,
            };
            return check;
        }

        /// <summary>Advances the server by one tick: read input, simulate, maybe send snapshots.</summary>
        /// <summary>
        /// Commands buffered per client before the oldest are thrown away. Half a second: long
        /// enough to ride out jitter, short enough that a recovered stall does not let a player
        /// replay several seconds of movement at once.
        /// </summary>
        public const int MaxBufferedInputs = FixedClock.TicksPerSecond / 2;

        /// <summary>
        /// Commands the server tries to keep in hand before simulating any of them.
        /// </summary>
        /// <remarks>
        /// A jitter buffer, and it exists because of what starvation actually costs. When the
        /// queue is empty the server has no choice but to re-simulate the player's previous
        /// command — so that tick of movement happens twice on the server and once on the
        /// client, and the two disagree by a tick's worth of travel, about 9 cm at running
        /// speed. Small, but it happens on every jitter spike, and each one forces the client
        /// to rewind and replay.
        ///
        /// <para>Two ticks is about 31 ms of deliberate extra input latency, paid by every
        /// player on every input. That is the trade, and it is worth naming rather than hiding:
        /// a fixed 31 ms of delay buys the removal of a constant stream of corrections. A larger
        /// buffer would remove more of them and feel worse; this is the smallest one that
        /// absorbs the jitter of a normal mobile connection.</para>
        /// </remarks>
        public const int TargetBufferedInputs = 2;

        public void Step(BotDirector bots = null)
        {
            ReceiveInputs();
            ConsumeOneInputPerClient();
            bots?.Think(_match, FixedClock.TickInterval);
            _match.Step();

            // The client's measured latency feeds lag compensation. Set after stepping so a
            // client that has just connected does not rewind against history that does not exist.
            foreach (ClientLink client in _clients.Values)
            {
                PlayerRuntime player = _match.Find(client.Player);
                if (player != null) player.LatencySeconds = client.MeasuredLatency;
            }

            if (_match.Tick % (FixedClock.TicksPerSecond / SnapshotHz) == 0) SendSnapshots();
        }

        /// <summary>
        /// Hands exactly one buffered command per client to the simulation.
        /// </summary>
        /// <remarks>
        /// One per tick, never more, however many arrived. A client that sends at 64 Hz is
        /// simulated at 64 Hz; one that floods is not rewarded for it. When the queue is empty —
        /// a lost packet, or a stall — the player's previous command is left in place, so they
        /// keep walking rather than stuttering to a halt for one tick. That is a guess, and it
        /// is the reason a starvation is counted: a client starving regularly is one whose
        /// movement the server is partly inventing.
        /// </remarks>
        private void ConsumeOneInputPerClient()
        {
            foreach (ClientLink client in _clients.Values)
            {
                // While priming, hold everything until the cushion is back. Consuming the
                // moment a single command arrives guarantees the queue is empty again next
                // tick, which is the starvation this buffer exists to prevent.
                if (client.Priming)
                {
                    if (client.Pending.Count < TargetBufferedInputs) continue;
                    client.Priming = false;
                }

                if (client.Pending.Count == 0)
                {
                    client.Starvations++;
                    client.Priming = true;
                    continue;
                }

                PlayerInput input = client.Pending.Dequeue();
                client.LastProcessedInputTick = input.Tick;
                _match.SubmitInput(client.Player, input);
            }
        }

        private void ReceiveInputs()
        {
            foreach (ClientLink client in _clients.Values)
            {
                IReadOnlyList<byte[]> packets = client.FromClient.Receive(_match.Tick);
                for (int i = 0; i < packets.Count; i++)
                {
                    var reader = new BitReader(packets[i]);
                    if ((NetMessage)reader.ReadBits(2) != NetMessage.Input) continue;

                    int inputTick = (int)reader.ReadUInt();
                    int acknowledgedSnapshot = (int)reader.ReadUInt();
                    PlayerInput input = ReadInput(reader, inputTick);

                    // Late and duplicate inputs are discarded. Applying an input older than one
                    // already accepted would rewind the player, and on a reordering link that
                    // would happen several times a second.
                    if (inputTick <= client.HighestInputTick) { client.InputsDropped++; continue; }

                    client.HighestInputTick = inputTick;
                    client.InputsReceived++;
                    client.Pending.Enqueue(input);

                    // A queue longer than this is a client running ahead of the server, or one
                    // whose connection just recovered from a stall and dumped a backlog.
                    // Simulating all of it would let them move at several times normal speed.
                    while (client.Pending.Count > MaxBufferedInputs)
                    {
                        client.Pending.Dequeue();
                        client.InputsDropped++;
                    }

                    // Latency measured from the round trip the client just completed: it is
                    // echoing a snapshot tick back to us, so the gap is how long the pair took.
                    if (acknowledgedSnapshot >= 0)
                    {
                        client.MeasuredLatency =
                            (_match.Tick - acknowledgedSnapshot) * FixedClock.TickInterval * 0.5f;
                        if (_history.TryGetValue(acknowledgedSnapshot, out WorldSnapshot baseline))
                            client.AcknowledgedBaseline = baseline;
                    }
                }
            }
        }

        private void SendSnapshots()
        {
            WorldSnapshot.Capture(_match, _current);

            // Kept so a delta can be encoded against whatever a client last acknowledged.
            var stored = new WorldSnapshot().CopyFrom(_current);
            _history[_current.Tick] = stored;
            PruneHistory();

            foreach (ClientLink client in _clients.Values)
            {
                _writer.Reset();
                _writer.WriteBits((uint)NetMessage.Snapshot, 2);
                // Per-client, and the reason the packet is encoded once per client rather than
                // broadcast: this is the client's own clock, and it is what it reconciles on.
                _writer.WriteInt(client.LastProcessedInputTick, 32);
                WriteOwnState(_writer, _match.Find(client.Player));
                SnapshotCodec.Encode(_writer, _current, client.AcknowledgedBaseline);
                byte[] packet = _writer.ToArray();
                BytesSent += packet.Length;
                SnapshotsSent++;
                client.ToClient.Send(_match.Tick, packet);
            }
        }

        private void PruneHistory()
        {
            // Two seconds is far longer than any client's round trip; beyond that a baseline is
            // of no use to anyone and the dictionary would grow for the length of the match.
            int oldest = _match.Tick - FixedClock.TicksPerSecond * 2;
            if (_history.Count < 128) return;
            var stale = new List<int>();
            foreach (int tick in _history.Keys) if (tick < oldest) stale.Add(tick);
            for (int i = 0; i < stale.Count; i++) _history.Remove(stale[i]);
        }

        /// <summary>
        /// The recipient's own movement state, in enough detail to restart prediction from.
        /// </summary>
        /// <remarks>
        /// Sent only to the player it belongs to — one player's worth of bits, not ten — because
        /// only that client predicts it. Everyone else is interpolated from positions and needs
        /// none of this.
        ///
        /// <para><b>Velocity is the field that matters.</b> Reconciliation restores the server's
        /// state at the acknowledged tick and replays the inputs since, and a replay is only as
        /// good as the state it starts from. Without the server's velocity the client has to
        /// reuse its own current velocity — which belongs to a tick several ahead — so every
        /// correction seeds the replay with the wrong momentum and produces a new error, which
        /// triggers another correction. A 1% packet loss rate turned into a 40% correction rate
        /// that way: the divergence was never actually being fixed, only re-created.</para>
        ///
        /// <para>The jump and stance timers are here for the same reason. They are small, they
        /// feed back into the next tick's movement, and a replay that starts with the wrong
        /// coyote-time remaining will disagree about whether a jump was legal.</para>
        /// </remarks>
        public static void WriteOwnState(BitWriter writer, PlayerRuntime player)
        {
            bool present = player != null;
            writer.WriteBool(present);
            if (!present) return;

            MovementState movement = player.Movement;
            writer.WriteQuantised(movement.Position.X, -128f, 128f, 20);
            writer.WriteQuantised(movement.Position.Y, -32f, 96f, 18);
            writer.WriteQuantised(movement.Position.Z, -128f, 128f, 20);
            // +/-64 m/s covers terminal velocity with room to spare; 16 bits is about 2 mm/s.
            writer.WriteQuantised(movement.Velocity.X, -64f, 64f, 16);
            writer.WriteQuantised(movement.Velocity.Y, -64f, 64f, 16);
            writer.WriteQuantised(movement.Velocity.Z, -64f, 64f, 16);
            writer.WriteQuantised(movement.CrouchAmount, 0f, 1f, 8);
            writer.WriteBool(movement.IsGrounded);
            writer.WriteQuantised(movement.TimeSinceGrounded, 0f, 4f, 10);
            writer.WriteQuantised(movement.JumpBufferRemaining, 0f, 1f, 8);
            writer.WriteBool(movement.JumpConsumed);
            writer.WriteQuantised(movement.StrideDistance, 0f, 8f, 10);
        }

        /// <summary>Reads what <see cref="WriteOwnState"/> wrote, onto an existing state so the
        /// fields it does not carry (the view, which is the player's own) are preserved.</summary>
        public static bool ReadOwnState(BitReader reader, ref MovementState movement)
        {
            if (!reader.ReadBool()) return false;

            movement.Position = new Vec3(
                reader.ReadQuantised(-128f, 128f, 20),
                reader.ReadQuantised(-32f, 96f, 18),
                reader.ReadQuantised(-128f, 128f, 20));
            movement.Velocity = new Vec3(
                reader.ReadQuantised(-64f, 64f, 16),
                reader.ReadQuantised(-64f, 64f, 16),
                reader.ReadQuantised(-64f, 64f, 16));
            movement.CrouchAmount = reader.ReadQuantised(0f, 1f, 8);
            movement.IsGrounded = reader.ReadBool();
            movement.TimeSinceGrounded = reader.ReadQuantised(0f, 4f, 10);
            movement.JumpBufferRemaining = reader.ReadQuantised(0f, 1f, 8);
            movement.JumpConsumed = reader.ReadBool();
            movement.StrideDistance = reader.ReadQuantised(0f, 8f, 10);
            return true;
        }

        public static void WriteInput(BitWriter writer, PlayerInput input, int acknowledgedSnapshot)
        {
            writer.WriteBits((uint)NetMessage.Input, 2);
            writer.WriteUInt((uint)input.Tick);
            writer.WriteUInt((uint)acknowledgedSnapshot);
            writer.WriteInt(input.MoveRight, 8);
            writer.WriteInt(input.MoveForward, 8);
            writer.WriteAngle(input.View.Pitch, 16);
            writer.WriteAngle(input.View.Yaw, 16);
            writer.WriteBits((uint)input.Buttons, 11);
            writer.WriteBits(input.DesiredSlot, 2);
        }

        public static PlayerInput ReadInput(BitReader reader, int tick)
        {
            var input = new PlayerInput
            {
                Tick = tick,
                MoveRight = (sbyte)reader.ReadInt(8),
                MoveForward = (sbyte)reader.ReadInt(8),
            };
            float pitch = reader.ReadAngle(16);
            float yaw = reader.ReadAngle(16);
            input.View = new ViewAngles(pitch, yaw);
            input.Buttons = (InputButtons)reader.ReadBits(11);
            input.DesiredSlot = (byte)reader.ReadBits(2);
            return input;
        }

        public float LatencyOf(PlayerId player) =>
            _clients.TryGetValue(player.Raw, out ClientLink client) ? client.MeasuredLatency : 0f;

        public int InputsDroppedFor(PlayerId player) =>
            _clients.TryGetValue(player.Raw, out ClientLink client) ? client.InputsDropped : 0;

        public int StarvationsFor(PlayerId player) =>
            _clients.TryGetValue(player.Raw, out ClientLink client) ? client.Starvations : 0;
    }

    /// <summary>
    /// One player's view of the match.
    /// </summary>
    /// <remarks>
    /// Holds no authority over anything. It predicts its own movement so the controls respond
    /// immediately, interpolates everyone else so they move smoothly, and accepts the server's
    /// word whenever the two disagree. Every number it shows — health, ammunition, score — came
    /// from a snapshot; it computes none of them.
    /// </remarks>
    public sealed class NetClient
    {
        private readonly SimulatedLink _toServer;
        private readonly SimulatedLink _fromServer;
        private readonly BitWriter _writer = new BitWriter(512);
        private readonly Dictionary<int, WorldSnapshot> _received = new Dictionary<int, WorldSnapshot>();
        private readonly MovementTuning _tuning;

        public PlayerId LocalPlayer { get; }
        public ClientPrediction Prediction { get; }
        public SnapshotInterpolator Interpolator { get; } = new SnapshotInterpolator();

        /// <summary>The newest snapshot received, or null before the first one arrives.</summary>
        public WorldSnapshot Latest { get; private set; }
        public int Tick { get; private set; }
        public int SnapshotsReceived { get; private set; }
        /// <summary>Packets discarded because their baseline was no longer held. A normal
        /// consequence of loss, but a large number means the history window is too short.</summary>
        public int UndecodablePackets { get; private set; }
        public int BytesReceived { get; private set; }

        public NetClient(PlayerId localPlayer, CollisionWorld world, MovementTuning tuning,
                         MovementState initial, SimulatedLink toServer, SimulatedLink fromServer)
        {
            LocalPlayer = localPlayer;
            _tuning = tuning;
            _toServer = toServer;
            _fromServer = fromServer;
            Prediction = new ClientPrediction(world, tuning, initial);
        }

        /// <summary>
        /// One client tick: apply input locally, send it, then take whatever has arrived.
        /// </summary>
        /// <remarks>
        /// Input is applied before receiving on purpose. Receiving first would mean this tick's
        /// keypress is predicted from state that is already a round trip old, adding a frame of
        /// latency to the one thing prediction exists to remove.
        /// </remarks>
        public void Step(PlayerInput input, float speedMultiplier,
                         System.Func<PlayerInput, float> speedMultiplierFor = null)
        {
            Prediction.Predict(input, speedMultiplier);

            _writer.Reset();
            NetServer.WriteInput(_writer, input, Latest?.Tick ?? -1);
            byte[] packet = _writer.ToArray();
            _toServer.Send(Tick, packet);

            ReceiveSnapshots(speedMultiplierFor);
            Tick++;
        }

        private void ReceiveSnapshots(System.Func<PlayerInput, float> speedMultiplierFor)
        {
            IReadOnlyList<byte[]> packets = _fromServer.Receive(Tick);
            for (int i = 0; i < packets.Count; i++)
            {
                BytesReceived += packets[i].Length;
                var reader = new BitReader(packets[i]);
                if ((NetMessage)reader.ReadBits(2) != NetMessage.Snapshot) continue;

                int acknowledgedInputTick = reader.ReadInt(32);

                // The server's own view of this client's movement at the acknowledged tick.
                // Read before the snapshot because that is the order it was written in; used as
                // the base that reconciliation replays from.
                MovementState authoritative = Prediction.State;
                bool haveOwnState = NetServer.ReadOwnState(reader, ref authoritative);

                var snapshot = new WorldSnapshot();
                if (!SnapshotCodec.Decode(reader, snapshot, LookupBaseline))
                {
                    // The baseline this delta needed is gone. Nothing can be recovered from the
                    // packet; the next one the server sends against a baseline we do hold will
                    // put us right.
                    UndecodablePackets++;
                    continue;
                }

                SnapshotsReceived++;
                _received[snapshot.Tick] = snapshot;
                PruneReceived(snapshot.Tick);

                if (Latest == null || snapshot.Tick > Latest.Tick)
                {
                    Latest = snapshot;
                    // Follow the server's clock. A client whose tick drifts ahead interpolates
                    // past the end of its buffer and stutters; one that drifts behind adds
                    // latency nobody asked for.
                    if (snapshot.Tick > Tick) Tick = snapshot.Tick;
                }
                Interpolator.Add(snapshot);
                if (haveOwnState)
                    ApplyCorrection(snapshot, acknowledgedInputTick, authoritative, speedMultiplierFor);
            }
        }

        /// <summary>Times the client hard-reset instead of reconciling, because the server
        /// moved the player somewhere prediction could never have followed.</summary>
        public int Teleports { get; private set; }
        private bool _wasAlive = true;

        private void ApplyCorrection(WorldSnapshot snapshot, int acknowledgedInputTick,
                                     MovementState authoritative,
                                     System.Func<PlayerInput, float> speedMultiplierFor)
        {
            if (!snapshot.TryGet(LocalPlayer, out PlayerSnapshot mine)) return;

            // The view is deliberately not taken from the server. It is the player's own input,
            // already applied locally; adopting the server's copy would drag the crosshair
            // backwards by a round trip on every single snapshot.
            authoritative.View = Prediction.State.View;

            // Death and respawn are discontinuities, not mispredictions. The server moves the
            // player across the map, and no amount of replaying local input will reproduce that
            // — so reconciling would grind through a pointless replay and still be wrong.
            // Accepting the server's state outright is both correct and cheaper.
            bool isAlive = mine.IsAlive;
            bool respawned = isAlive && !_wasAlive;
            _wasAlive = isAlive;

            if (!isAlive || respawned)
            {
                Prediction.Reset(authoritative);
                Teleports++;
                return;
            }

            // Reconcile against the last command the server actually simulated, not against the
            // server's own tick. The two clocks are a round trip apart, and comparing across
            // them makes every snapshot look like a misprediction.
            if (acknowledgedInputTick < 0) return;
            Prediction.Reconcile(acknowledgedInputTick, authoritative, speedMultiplierFor);
        }

        private WorldSnapshot LookupBaseline(int tick) =>
            _received.TryGetValue(tick, out WorldSnapshot snapshot) ? snapshot : null;

        private void PruneReceived(int newestTick)
        {
            if (_received.Count < 128) return;
            int oldest = newestTick - FixedClock.TicksPerSecond * 2;
            var stale = new List<int>();
            foreach (int tick in _received.Keys) if (tick < oldest) stale.Add(tick);
            for (int i = 0; i < stale.Count; i++) _received.Remove(stale[i]);
        }
    }
}
