using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>Where one player was on one past tick.</summary>
    public struct HistoricPose
    {
        public int Tick;
        public Vec3 Position;
        public float Height;
        public ViewAngles View;
        public bool IsAlive;

        public PlayerHitboxes Hitboxes => PlayerHitboxes.For(Position, Height, View);
    }

    /// <summary>
    /// Remembers where every player was, so the server can judge a shot against the world the
    /// shooter actually saw.
    /// </summary>
    /// <remarks>
    /// Without this, a player with 80 ms of latency must lead every target by 80 ms, because
    /// by the time their shot arrives the server has moved everyone on. That is unplayable, and
    /// no amount of client-side smoothing fixes it — the shot has to be judged against the past.
    ///
    /// <para>The cost is real and worth stating plainly: rewinding means a player who has
    /// already stepped behind a wall on their own screen can still be killed by someone who
    /// saw them in the open. That is the standard trade in this genre. The alternative — making
    /// the shooter lead their target by their own ping — is worse, and punishes the player with
    /// the worse connection twice.</para>
    ///
    /// <para>The rewind is bounded by <see cref="MaxRewindSeconds"/>. A client claiming a large
    /// latency is claiming a large rewind, which is a straightforward cheat: shoot at where
    /// someone was a second ago. The clamp is the defence, and it is applied to a value the
    /// <em>server</em> measured, never to one the client reported.</para>
    /// </remarks>
    public sealed class LagCompensation
    {
        /// <summary>Beyond this, the rewind is clamped. 250 ms covers a bad mobile connection;
        /// past it, the game stops bending reality for one player.</summary>
        public const float MaxRewindSeconds = 0.25f;

        private readonly int _capacity;
        private readonly Dictionary<int, HistoricPose[]> _byPlayer = new Dictionary<int, HistoricPose[]>();
        private readonly Dictionary<int, int> _writeIndex = new Dictionary<int, int>();
        private readonly List<ShootableTarget> _scratch = new List<ShootableTarget>();

        public int Capacity => _capacity;

        public LagCompensation(float historySeconds = MaxRewindSeconds + 0.1f)
        {
            _capacity = System.Math.Max(2, (int)System.Math.Ceiling(historySeconds * FixedClock.TicksPerSecond));
        }

        public void Forget(PlayerId player)
        {
            _byPlayer.Remove(player.Raw);
            _writeIndex.Remove(player.Raw);
        }

        public void Clear()
        {
            _byPlayer.Clear();
            _writeIndex.Clear();
        }

        /// <summary>Records a player's pose for this tick. Called once per player per tick by
        /// the server, after the movement step.</summary>
        public void Record(PlayerId player, int tick, MovementState movement, bool isAlive)
        {
            if (!_byPlayer.TryGetValue(player.Raw, out HistoricPose[] ring))
            {
                ring = new HistoricPose[_capacity];
                // Pre-filled with the current pose so a player who has only just joined is not
                // temporarily invisible to lag-compensated traces.
                for (int i = 0; i < ring.Length; i++)
                {
                    ring[i] = new HistoricPose
                    {
                        Tick = int.MinValue,
                        Position = movement.Position,
                        Height = movement.Height,
                        View = movement.View,
                        IsAlive = isAlive,
                    };
                }
                _byPlayer[player.Raw] = ring;
                _writeIndex[player.Raw] = 0;
            }

            int index = _writeIndex[player.Raw];
            ring[index] = new HistoricPose
            {
                Tick = tick,
                Position = movement.Position,
                Height = movement.Height,
                View = movement.View,
                IsAlive = isAlive,
            };
            _writeIndex[player.Raw] = (index + 1) % ring.Length;
        }

        /// <summary>
        /// The tick to rewind to for a shooter with the given server-measured latency.
        /// </summary>
        public static int RewindTarget(int currentTick, float latencySeconds)
        {
            float clamped = SalvoMath.Clamp(latencySeconds, 0f, MaxRewindSeconds);
            return currentTick - (int)System.Math.Round(clamped * FixedClock.TicksPerSecond);
        }

        /// <summary>
        /// The pose closest to <paramref name="tick"/>, or the most recent one if the history
        /// does not reach back that far.
        /// </summary>
        public bool TryGetPose(PlayerId player, int tick, out HistoricPose pose)
        {
            pose = default;
            if (!_byPlayer.TryGetValue(player.Raw, out HistoricPose[] ring)) return false;

            bool found = false;
            int bestDistance = int.MaxValue;
            for (int i = 0; i < ring.Length; i++)
            {
                if (ring[i].Tick == int.MinValue) continue;
                int distance = System.Math.Abs(ring[i].Tick - tick);
                if (distance < bestDistance)
                {
                    bestDistance = distance;
                    pose = ring[i];
                    found = true;
                }
            }
            return found;
        }

        /// <summary>
        /// Builds the target list for a shot, with every player rewound to where the shooter
        /// saw them. The returned list is reused between calls — copy it if you need to keep it.
        /// </summary>
        public IReadOnlyList<ShootableTarget> RewindTargets(
            int tick, IReadOnlyList<PlayerId> players, IReadOnlyList<Team> teams)
        {
            _scratch.Clear();
            for (int i = 0; i < players.Count; i++)
            {
                if (!TryGetPose(players[i], tick, out HistoricPose pose)) continue;
                _scratch.Add(new ShootableTarget
                {
                    Id = players[i],
                    Team = i < teams.Count ? teams[i] : Team.None,
                    Hitboxes = pose.Hitboxes,
                    IsAlive = pose.IsAlive,
                });
            }
            return _scratch;
        }
    }
}
