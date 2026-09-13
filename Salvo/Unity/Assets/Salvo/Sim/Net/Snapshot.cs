using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// One player's state as it crosses the wire.
    /// </summary>
    /// <remarks>
    /// A deliberately small subset of <see cref="PlayerRuntime"/>. Everything a remote client
    /// needs to draw a player and predict its own, and nothing else: no score (sent separately
    /// and rarely), no reserve ammunition for other players, no bot goal, no last attacker.
    ///
    /// <para>The ammunition field is the interesting omission. A client is told its <em>own</em>
    /// magazine because it needs it to predict, and is told nothing about anyone else's, because
    /// knowing an opponent is reloading is a real competitive advantage that the UI is not
    /// supposed to grant.</para>
    /// </remarks>
    public struct PlayerSnapshot
    {
        public PlayerId Id;
        public Team Team;
        public Vec3 Position;
        public ViewAngles View;
        public float CrouchAmount;
        public bool IsAlive;
        public bool IsGrounded;
        public WeaponSlot HeldSlot;
        public byte Health;          // 0..255, plenty for a 100-health game with room for buffs
        public byte Armour;
        public ushort Magazine;      // only meaningful for the receiving client's own player

        public bool Matches(PlayerSnapshot other) =>
            Id == other.Id && Team == other.Team && Position == other.Position
            && View.Pitch == other.View.Pitch && View.Yaw == other.View.Yaw
            && CrouchAmount == other.CrouchAmount && IsAlive == other.IsAlive
            && IsGrounded == other.IsGrounded && HeldSlot == other.HeldSlot
            && Health == other.Health && Armour == other.Armour && Magazine == other.Magazine;
    }

    /// <summary>The authoritative state of the world at one tick.</summary>
    public sealed class WorldSnapshot
    {
        public int Tick;
        public MatchPhase Phase;
        public int AlphaScore;
        public int BravoScore;
        public readonly List<PlayerSnapshot> Players = new List<PlayerSnapshot>();

        /// <summary>The tick of the snapshot this one was encoded against, or -1 for a full
        /// snapshot. Echoed so a client can tell whether it holds the baseline.</summary>
        public int BaselineTick = -1;

        public void Clear()
        {
            Players.Clear();
            BaselineTick = -1;
        }

        public bool TryGet(PlayerId id, out PlayerSnapshot snapshot)
        {
            for (int i = 0; i < Players.Count; i++)
            {
                if (Players[i].Id != id) continue;
                snapshot = Players[i];
                return true;
            }
            snapshot = default;
            return false;
        }

        public WorldSnapshot CopyFrom(WorldSnapshot other)
        {
            Tick = other.Tick;
            Phase = other.Phase;
            AlphaScore = other.AlphaScore;
            BravoScore = other.BravoScore;
            BaselineTick = other.BaselineTick;
            Players.Clear();
            Players.AddRange(other.Players);
            return this;
        }

        /// <summary>Builds a snapshot from the authoritative match. Server side only.</summary>
        public static WorldSnapshot Capture(MatchSimulation match, WorldSnapshot into = null)
        {
            WorldSnapshot snapshot = into ?? new WorldSnapshot();
            snapshot.Clear();
            snapshot.Tick = match.Tick;
            snapshot.Phase = match.Phase;
            snapshot.AlphaScore = match.Mode.TeamScore(Team.Alpha);
            snapshot.BravoScore = match.Mode.TeamScore(Team.Bravo);

            IReadOnlyList<PlayerRuntime> players = match.Players;
            for (int i = 0; i < players.Count; i++)
            {
                PlayerRuntime player = players[i];
                if (!player.IsConnected) continue;
                snapshot.Players.Add(new PlayerSnapshot
                {
                    Id = player.Id,
                    Team = player.Team,
                    Position = player.Movement.Position,
                    View = player.Movement.View,
                    CrouchAmount = player.Movement.CrouchAmount,
                    IsAlive = player.IsAlive,
                    IsGrounded = player.Movement.IsGrounded,
                    HeldSlot = player.HeldSlot,
                    Health = (byte)SalvoMath.Clamp((int)(player.Vitals.Health + 0.5f), 0, 255),
                    Armour = (byte)SalvoMath.Clamp((int)(player.Vitals.Armour + 0.5f), 0, 255),
                    Magazine = (ushort)SalvoMath.Clamp(player.HeldWeapon.Magazine, 0, 65535),
                });
            }
            return snapshot;
        }
    }

    /// <summary>
    /// Turns snapshots into bits and back.
    /// </summary>
    /// <remarks>
    /// Delta encoding against a baseline the client has acknowledged. A player who is standing
    /// still costs one bit; one who is sprinting costs the fields that changed. That is where
    /// the bandwidth budget is actually met — not in the field widths, which only decide the
    /// cost of the players who *are* moving.
    ///
    /// <para>The baseline is a snapshot the client has <em>confirmed receiving</em>, never simply
    /// the last one sent. Encoding against an unacknowledged baseline means one lost packet
    /// corrupts every snapshot after it, and the corruption is silent: positions decode to
    /// plausible-looking wrong values rather than failing.</para>
    /// </remarks>
    public static class SnapshotCodec
    {
        // The map is 80 m across with room to spare; 16 bits over 256 m is 4 mm precision, which
        // is far below what any player can perceive and well below the collision skin width.
        private const float PositionMin = -128f;
        private const float PositionMax = 128f;
        private const int PositionBits = 16;
        private const float HeightMin = -32f;
        private const float HeightMax = 96f;
        private const int HeightBits = 14;

        private const int ViewBits = 12;       // ~0.09 degrees, finer than any player aims
        private const int CrouchBits = 5;      // 32 steps across a 0.18 s transition
        private const int MagazineBits = 10;   // up to 1023 rounds
        private const int ScoreBits = 12;      // up to 4095

        public static void Encode(BitWriter writer, WorldSnapshot snapshot, WorldSnapshot baseline)
        {
            writer.WriteUInt((uint)snapshot.Tick);
            writer.WriteBits((uint)snapshot.Phase, 3);
            writer.WriteRanged(snapshot.AlphaScore, 0, (1 << ScoreBits) - 1);
            writer.WriteRanged(snapshot.BravoScore, 0, (1 << ScoreBits) - 1);

            bool hasBaseline = baseline != null;
            writer.WriteBool(hasBaseline);
            if (hasBaseline) writer.WriteUInt((uint)baseline.Tick);

            writer.WriteRanged(snapshot.Players.Count, 0, 63);
            for (int i = 0; i < snapshot.Players.Count; i++)
            {
                PlayerSnapshot player = snapshot.Players[i];
                writer.WriteRanged(player.Id.Raw, 0, 63);

                PlayerSnapshot previous = default;
                bool hasPrevious = hasBaseline && baseline.TryGet(player.Id, out previous);

                // One bit for "nothing about this player changed". This is the whole point of
                // delta encoding: in a 10-player match most players are not moving on most ticks.
                //
                // The comparison is against the server's un-quantised baseline, while the client
                // reconstructs from quantised values. That cannot drift: whenever the server says
                // "changed" it also sends the quantised value, so the client is reset to exactly
                // what the server would quantise to, and whenever it says "unchanged" the values
                // were bit-identical. It does mean a sub-quantum movement is sent as a change
                // that decodes to the same number — a few wasted bits, not a wrong position.
                bool unchanged = hasPrevious && player.Matches(previous);
                writer.WriteBool(unchanged);
                if (unchanged) continue;

                EncodePlayer(writer, player, hasPrevious, previous);
            }
        }

        private static void EncodePlayer(BitWriter writer, PlayerSnapshot player,
                                         bool hasPrevious, PlayerSnapshot previous)
        {
            bool WriteChanged(bool changed) { writer.WriteBool(changed); return changed; }

            if (WriteChanged(!hasPrevious || player.Position != previous.Position))
            {
                writer.WriteQuantised(player.Position.X, PositionMin, PositionMax, PositionBits);
                writer.WriteQuantised(player.Position.Y, HeightMin, HeightMax, HeightBits);
                writer.WriteQuantised(player.Position.Z, PositionMin, PositionMax, PositionBits);
            }

            if (WriteChanged(!hasPrevious
                             || player.View.Pitch != previous.View.Pitch
                             || player.View.Yaw != previous.View.Yaw))
            {
                writer.WriteAngle(player.View.Pitch, ViewBits);
                writer.WriteAngle(player.View.Yaw, ViewBits);
            }

            if (WriteChanged(!hasPrevious || player.CrouchAmount != previous.CrouchAmount))
                writer.WriteQuantised(player.CrouchAmount, 0f, 1f, CrouchBits);

            if (WriteChanged(!hasPrevious
                             || player.Health != previous.Health
                             || player.Armour != previous.Armour
                             || player.IsAlive != previous.IsAlive))
            {
                writer.WriteByte(player.Health);
                writer.WriteByte(player.Armour);
                writer.WriteBool(player.IsAlive);
            }

            if (WriteChanged(!hasPrevious
                             || player.HeldSlot != previous.HeldSlot
                             || player.Magazine != previous.Magazine
                             || player.Team != previous.Team
                             || player.IsGrounded != previous.IsGrounded))
            {
                writer.WriteBits((uint)player.HeldSlot, 2);
                writer.WriteBits(player.Magazine, MagazineBits);
                writer.WriteBits((uint)player.Team, 2);
                writer.WriteBool(player.IsGrounded);
            }
        }

        /// <summary>
        /// Decodes into <paramref name="into"/>.
        /// </summary>
        /// <param name="baselineLookup">
        /// Supplies the snapshot a delta was encoded against. Returning null means the client no
        /// longer holds that baseline, and the packet is undecodable — which the caller must
        /// treat as a dropped packet, not as an error, because it is a normal consequence of
        /// loss.
        /// </param>
        /// <returns>False when the baseline is missing. <paramref name="into"/> is then unusable.</returns>
        public static bool Decode(BitReader reader, WorldSnapshot into,
                                  System.Func<int, WorldSnapshot> baselineLookup)
        {
            into.Clear();
            into.Tick = (int)reader.ReadUInt();
            into.Phase = (MatchPhase)reader.ReadBits(3);
            into.AlphaScore = reader.ReadRanged(0, (1 << ScoreBits) - 1);
            into.BravoScore = reader.ReadRanged(0, (1 << ScoreBits) - 1);

            WorldSnapshot baseline = null;
            if (reader.ReadBool())
            {
                int baselineTick = (int)reader.ReadUInt();
                into.BaselineTick = baselineTick;
                baseline = baselineLookup?.Invoke(baselineTick);
                if (baseline == null) return false;
            }

            int count = reader.ReadRanged(0, 63);
            for (int i = 0; i < count; i++)
            {
                var player = new PlayerSnapshot { Id = new PlayerId(reader.ReadRanged(0, 63)) };
                PlayerSnapshot previous = default;
                bool hasPrevious = baseline != null && baseline.TryGet(player.Id, out previous);

                if (reader.ReadBool())
                {
                    // Unchanged. Only meaningful if we hold the previous state; without it the
                    // stream is unrecoverable and saying so beats inventing a default player at
                    // the origin.
                    if (!hasPrevious) return false;
                    into.Players.Add(previous);
                    continue;
                }

                player = DecodePlayer(reader, player, hasPrevious, previous);
                into.Players.Add(player);
            }
            return true;
        }

        private static PlayerSnapshot DecodePlayer(BitReader reader, PlayerSnapshot player,
                                                   bool hasPrevious, PlayerSnapshot previous)
        {
            if (reader.ReadBool())
            {
                player.Position = new Vec3(
                    reader.ReadQuantised(PositionMin, PositionMax, PositionBits),
                    reader.ReadQuantised(HeightMin, HeightMax, HeightBits),
                    reader.ReadQuantised(PositionMin, PositionMax, PositionBits));
            }
            else if (hasPrevious) player.Position = previous.Position;

            if (reader.ReadBool())
            {
                float pitch = reader.ReadAngle(ViewBits);
                float yaw = reader.ReadAngle(ViewBits);
                player.View = new ViewAngles(pitch, yaw);
            }
            else if (hasPrevious) player.View = previous.View;

            if (reader.ReadBool()) player.CrouchAmount = reader.ReadQuantised(0f, 1f, CrouchBits);
            else if (hasPrevious) player.CrouchAmount = previous.CrouchAmount;

            if (reader.ReadBool())
            {
                player.Health = reader.ReadByte();
                player.Armour = reader.ReadByte();
                player.IsAlive = reader.ReadBool();
            }
            else if (hasPrevious)
            {
                player.Health = previous.Health;
                player.Armour = previous.Armour;
                player.IsAlive = previous.IsAlive;
            }

            if (reader.ReadBool())
            {
                player.HeldSlot = (WeaponSlot)reader.ReadBits(2);
                player.Magazine = (ushort)reader.ReadBits(MagazineBits);
                player.Team = (Team)reader.ReadBits(2);
                player.IsGrounded = reader.ReadBool();
            }
            else if (hasPrevious)
            {
                player.HeldSlot = previous.HeldSlot;
                player.Magazine = previous.Magazine;
                player.Team = previous.Team;
                player.IsGrounded = previous.IsGrounded;
            }
            return player;
        }
    }
}
