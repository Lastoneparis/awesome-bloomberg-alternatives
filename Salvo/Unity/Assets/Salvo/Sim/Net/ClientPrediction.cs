using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Runs the local player's movement ahead of the server and corrects it when the server
    /// disagrees.
    /// </summary>
    /// <remarks>
    /// Without prediction, pressing forward does nothing until a packet has gone to the server
    /// and a snapshot has come back — one round trip, 100 ms on a decent connection, 300 ms on a
    /// bad one. That is not a small degradation; it is the difference between a game that feels
    /// like a game and one that feels broken.
    ///
    /// <para>So the client runs <see cref="MovementSimulation"/> on its own input immediately,
    /// and keeps every input it has sent. When a snapshot arrives stamped with the last input
    /// the server processed, the client compares the server's position against what it predicted
    /// for that same tick. If they agree, the inputs up to that tick are discarded and nothing
    /// visible happens. If they disagree, the client snaps to the server's state and
    /// <em>replays</em> every input since — which is why the movement model had to be a pure
    /// function of state and input.</para>
    ///
    /// <para>The error threshold is the whole design in one number. Too tight and the client
    /// re-simulates constantly because floating-point addition is not associative across two
    /// machines; too loose and real divergence is left uncorrected until it is a teleport. It is
    /// set just above the noise floor of the quantisation the snapshot applies, because below
    /// that the "disagreement" is the wire format, not the simulation.</para>
    /// </remarks>
    public sealed class ClientPrediction
    {
        /// <summary>
        /// Position error, in metres, above which the client re-simulates. The snapshot
        /// quantises position to about 4 mm, so anything under a centimetre is the format
        /// talking rather than the simulation.
        /// </summary>
        public const float ReconcileThreshold = 0.01f;

        private struct PendingInput
        {
            public PlayerInput Input;
            public MovementState PredictedAfter;
        }

        private readonly List<PendingInput> _pending = new List<PendingInput>();
        private readonly CollisionWorld _world;
        private readonly MovementTuning _tuning;

        public MovementState State;

        /// <summary>How many times the client has had to rewind and replay. A rising number
        /// under a stable connection means client and server are diverging, which is a bug
        /// rather than a network condition.</summary>
        public int Reconciliations { get; private set; }
        /// <summary>Total inputs replayed. The CPU cost of being wrong.</summary>
        public int InputsReplayed { get; private set; }
        /// <summary>
        /// The largest disagreement ever seen between what the client predicted for a tick and
        /// what the server produced for that same tick, in metres.
        /// </summary>
        /// <remarks>
        /// Compared per input tick, which is the only comparison that means anything. The gap
        /// between the client's <em>current</em> position and the server's current position is
        /// always about latency times speed — half a metre on a 90 ms connection — and that is
        /// prediction working, not failing. Measuring that instead is the easiest way to
        /// conclude the netcode is broken when it is fine.
        /// </remarks>
        public float WorstError { get; private set; }

        /// <summary>Mean per-tick disagreement across every snapshot compared so far.</summary>
        public float MeanError => _errorSamples == 0 ? 0f : (float)(_errorSum / _errorSamples);
        public int ErrorSamples => _errorSamples;

        private double _errorSum;
        private int _errorSamples;

        public int PendingCount => _pending.Count;

        public ClientPrediction(CollisionWorld world, MovementTuning tuning, MovementState initial)
        {
            _world = world;
            _tuning = tuning;
            State = initial;
        }

        /// <summary>
        /// Applies one input locally and remembers it until the server confirms that tick.
        /// </summary>
        public void Predict(PlayerInput input, float speedMultiplier)
        {
            MovementSimulation.Step(ref State, input, _world, _tuning, speedMultiplier,
                                    FixedClock.TickInterval);
            _pending.Add(new PendingInput { Input = input, PredictedAfter = State });

            // A client that has sent two seconds of input without hearing anything is not
            // mispredicting, it is disconnected. Dropping the oldest keeps this bounded rather
            // than letting a stalled connection grow the buffer without limit.
            const int maxPending = FixedClock.TicksPerSecond * 2;
            if (_pending.Count > maxPending) _pending.RemoveRange(0, _pending.Count - maxPending);
        }

        /// <summary>
        /// Takes the server's authoritative state for <paramref name="acknowledgedTick"/> and
        /// corrects the prediction if it was wrong.
        /// </summary>
        /// <param name="speedMultiplierFor">
        /// Supplies the movement multiplier for a replayed tick. Passed as a function because it
        /// depends on the weapon held at the time, which the caller knows and this does not.
        /// </param>
        /// <returns>True if a correction was applied.</returns>
        public bool Reconcile(int acknowledgedTick, MovementState authoritative,
                              System.Func<PlayerInput, float> speedMultiplierFor)
        {
            int index = _pending.FindIndex(p => p.Input.Tick == acknowledgedTick);
            if (index < 0)
            {
                // The server acknowledged a tick we no longer hold. Either the buffer was
                // trimmed after a long stall, or this is a duplicate of an older packet. Trust
                // the server's state outright and start again from it: guessing would put us
                // back where we already know we were wrong.
                if (acknowledgedTick > LatestPendingTick())
                {
                    State = authoritative;
                    _pending.Clear();
                    Reconciliations++;
                    return true;
                }
                return false;
            }

            float error = Vec3.Distance(_pending[index].PredictedAfter.Position,
                                        authoritative.Position);
            if (error > WorstError) WorstError = error;
            _errorSum += error;
            _errorSamples++;

            if (error <= ReconcileThreshold)
            {
                // Agreed. Everything up to and including this tick is confirmed and can go.
                _pending.RemoveRange(0, index + 1);
                return false;
            }

            Reconciliations++;
            State = authoritative;
            _pending.RemoveRange(0, index + 1);

            // Replay what the server has not seen yet. This is the step that makes a correction
            // invisible: without it the player would be yanked back to where they were a round
            // trip ago and have to walk the distance again.
            for (int i = 0; i < _pending.Count; i++)
            {
                PlayerInput input = _pending[i].Input;
                MovementSimulation.Step(ref State, input, _world, _tuning,
                                        speedMultiplierFor?.Invoke(input) ?? 1f,
                                        FixedClock.TickInterval);
                _pending[i] = new PendingInput { Input = input, PredictedAfter = State };
                InputsReplayed++;
            }
            return true;
        }

        private int LatestPendingTick() =>
            _pending.Count == 0 ? int.MinValue : _pending[_pending.Count - 1].Input.Tick;

        public void Reset(MovementState state)
        {
            State = state;
            _pending.Clear();
        }
    }

    /// <summary>
    /// Draws other players slightly in the past so they move smoothly.
    /// </summary>
    /// <remarks>
    /// Snapshots arrive 20 or 30 times a second, and unevenly. Drawing each one as it lands
    /// makes every other player stutter. So the client renders remote players at a fixed delay
    /// behind the newest snapshot and interpolates between the two that straddle that moment.
    ///
    /// <para>The delay is a real cost, and it is worth naming honestly: everyone else is drawn
    /// where they were 100 ms ago. That is exactly the error the server's lag compensation exists
    /// to undo, which is why the two have to be designed together — the interpolation delay is
    /// part of what the server rewinds by.</para>
    ///
    /// <para>Extrapolation past the newest snapshot is deliberately not done. Guessing where a
    /// player will be produces confident, wrong positions during exactly the moments that matter
    /// — a player changing direction in a fight — and the correction is a visible snap. Holding
    /// the last known position is duller and more honest.</para>
    /// </remarks>
    public sealed class SnapshotInterpolator
    {
        /// <summary>
        /// How far behind the newest snapshot to render, in seconds. Two snapshot intervals at
        /// 20 Hz: enough that one lost packet does not leave the buffer empty, which is the
        /// point of the delay rather than smoothness alone.
        /// </summary>
        public float DelaySeconds = 0.1f;

        private readonly List<WorldSnapshot> _buffer = new List<WorldSnapshot>();
        private readonly int _capacity;

        public int BufferedCount => _buffer.Count;
        /// <summary>Times the buffer had nothing to interpolate between. A non-zero value means
        /// the delay is too short for this connection.</summary>
        public int Starvations { get; private set; }

        public SnapshotInterpolator(int capacity = 32) { _capacity = capacity; }

        public void Add(WorldSnapshot snapshot)
        {
            // Out-of-order arrivals are inserted, not appended. Appending would leave the buffer
            // unsorted and the search below would pick the wrong pair — which looks like a player
            // briefly jumping backwards, on precisely the connections where reordering happens.
            int index = _buffer.Count;
            while (index > 0 && _buffer[index - 1].Tick > snapshot.Tick) index--;
            if (index > 0 && _buffer[index - 1].Tick == snapshot.Tick) return;   // duplicate
            _buffer.Insert(index, snapshot);

            while (_buffer.Count > _capacity) _buffer.RemoveAt(0);
        }

        /// <summary>
        /// The interpolated state of one player at the render moment.
        /// </summary>
        /// <param name="nowTick">The client's current tick estimate of server time.</param>
        public bool TryGet(PlayerId id, int nowTick, out PlayerSnapshot result)
        {
            result = default;
            if (_buffer.Count == 0) { Starvations++; return false; }

            float targetTick = nowTick - DelaySeconds * FixedClock.TicksPerSecond;

            WorldSnapshot before = null, after = null;
            for (int i = 0; i < _buffer.Count; i++)
            {
                if (_buffer[i].Tick <= targetTick) before = _buffer[i];
                else { after = _buffer[i]; break; }
            }

            if (before == null)
            {
                // The render moment is older than anything buffered: we have only just connected.
                // Showing the oldest known state beats showing nothing.
                Starvations++;
                return _buffer[0].TryGet(id, out result);
            }
            if (after == null)
            {
                // Nothing newer to interpolate towards. Hold, do not extrapolate.
                Starvations++;
                return before.TryGet(id, out result);
            }

            if (!before.TryGet(id, out PlayerSnapshot a)) return after.TryGet(id, out result);
            if (!after.TryGet(id, out PlayerSnapshot b)) { result = a; return true; }

            float span = after.Tick - before.Tick;
            float t = span <= 0f ? 0f : SalvoMath.Clamp01((targetTick - before.Tick) / span);

            result = a;
            result.Position = Vec3.Lerp(a.Position, b.Position, t);
            // Angles are interpolated the short way round. Lerping the raw values sends a player
            // spinning the long way whenever their yaw crosses pi, which happens constantly.
            result.View = new ViewAngles(
                a.View.Pitch + SalvoMath.AngleDelta(a.View.Pitch, b.View.Pitch) * t,
                a.View.Yaw + SalvoMath.AngleDelta(a.View.Yaw, b.View.Yaw) * t);
            result.CrouchAmount = SalvoMath.Lerp(a.CrouchAmount, b.CrouchAmount, t);
            // Discrete state takes the older value: a player is alive until the snapshot that
            // says otherwise has actually been reached, never half-dead in between.
            result.IsAlive = a.IsAlive;
            result.Health = a.Health;
            result.Armour = a.Armour;
            return true;
        }

        public void Clear()
        {
            _buffer.Clear();
            Starvations = 0;
        }
    }
}
