using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// An unreliable network, simulated deterministically.
    /// </summary>
    /// <remarks>
    /// The most valuable thing in the networking layer, and the reason any of the rest can be
    /// trusted. Netcode that is only ever exercised on localhost is netcode that has never been
    /// tested: latency is zero, nothing is ever lost, and nothing ever arrives out of order, so
    /// every bug that matters is invisible. This link makes those conditions the default.
    ///
    /// <para>It is deterministic, seeded from the same <see cref="DeterministicRandom"/> the rest
    /// of the simulation uses. A flaky network test that cannot be reproduced is worse than no
    /// test — it trains everyone to re-run CI until it passes.</para>
    ///
    /// <para>Delivery is modelled in ticks rather than milliseconds because the simulation is
    /// tick-driven, and converting at the boundary once is less error-prone than converting at
    /// every send.</para>
    /// </remarks>
    public sealed class SimulatedLink
    {
        private struct InFlight
        {
            public int DeliverAtTick;
            public byte[] Payload;
            public ulong Sequence;      // for stable ordering of packets due on the same tick
        }

        private readonly List<InFlight> _inFlight = new List<InFlight>();
        private readonly List<byte[]> _ready = new List<byte[]>();
        private DeterministicRandom _random;
        private ulong _sequence;

        /// <summary>One-way latency in seconds. Round-trip is twice this.</summary>
        public float LatencySeconds;
        /// <summary>Random variation added to each packet's latency, in seconds.</summary>
        public float JitterSeconds;
        /// <summary>Probability in 0..1 that a packet is dropped.</summary>
        public float LossChance;
        /// <summary>
        /// Probability that a packet is delayed by an extra tick or two, arriving after one sent
        /// later. Separate from jitter because reordering is what actually breaks naive code —
        /// jitter alone usually preserves order.
        /// </summary>
        public float ReorderChance;

        public int PacketsSent { get; private set; }
        public int PacketsDropped { get; private set; }
        public int PacketsDelivered { get; private set; }
        public int PacketsInFlight => _inFlight.Count;

        public SimulatedLink(uint seed = 1, float latencySeconds = 0f, float jitterSeconds = 0f,
                             float lossChance = 0f, float reorderChance = 0f)
        {
            _random = new DeterministicRandom(seed);
            LatencySeconds = latencySeconds;
            JitterSeconds = jitterSeconds;
            LossChance = lossChance;
            ReorderChance = reorderChance;
        }

        /// <summary>A perfect link. Useful for isolating a bug that is not the network's.</summary>
        public static SimulatedLink Perfect() => new SimulatedLink();

        /// <summary>Roughly a decent mobile connection: 60 ms each way, some jitter, 1% loss.</summary>
        public static SimulatedLink Mobile(uint seed = 1) =>
            new SimulatedLink(seed, 0.06f, 0.015f, 0.01f, 0.02f);

        /// <summary>Roughly a bad one: 150 ms each way, heavy jitter, 5% loss.</summary>
        public static SimulatedLink Poor(uint seed = 1) =>
            new SimulatedLink(seed, 0.15f, 0.04f, 0.05f, 0.06f);

        public void Send(int currentTick, byte[] payload)
        {
            PacketsSent++;
            if (LossChance > 0f && _random.NextBool(LossChance))
            {
                PacketsDropped++;
                return;
            }

            float delay = LatencySeconds;
            if (JitterSeconds > 0f) delay += _random.NextFloat(0f, JitterSeconds);
            int delayTicks = (int)System.Math.Round(delay * FixedClock.TicksPerSecond);
            if (ReorderChance > 0f && _random.NextBool(ReorderChance))
                delayTicks += _random.NextInt(1, 4);

            _inFlight.Add(new InFlight
            {
                // Always at least the next tick. A packet that arrives on the tick it was sent
                // is a packet that travelled at infinite speed, and code written against that
                // works locally and nowhere else.
                DeliverAtTick = currentTick + System.Math.Max(1, delayTicks),
                Payload = payload,
                Sequence = _sequence++,
            });
        }

        private readonly List<InFlight> _dueScratch = new List<InFlight>();

        /// <summary>
        /// Everything due by <paramref name="currentTick"/>, in arrival order. The returned list
        /// is reused between calls.
        /// </summary>
        /// <remarks>
        /// Ordered by delivery tick first and send order second. Both halves matter: a packet
        /// this link decided to delay must actually arrive after one sent later, or the reorder
        /// setting does nothing; and two packets due on the same tick must arrive in the order
        /// they were sent, or every burst is silently shuffled and the reordering under test is
        /// not the reordering configured.
        /// </remarks>
        public IReadOnlyList<byte[]> Receive(int currentTick)
        {
            _ready.Clear();
            _dueScratch.Clear();

            for (int i = _inFlight.Count - 1; i >= 0; i--)
            {
                if (_inFlight[i].DeliverAtTick > currentTick) continue;
                _dueScratch.Add(_inFlight[i]);
                _inFlight.RemoveAt(i);
            }

            _dueScratch.Sort((a, b) =>
            {
                int byTick = a.DeliverAtTick.CompareTo(b.DeliverAtTick);
                // Never returns 0 for distinct packets, so List.Sort being unstable cannot
                // make the order depend on how the elements happened to be arranged.
                return byTick != 0 ? byTick : a.Sequence.CompareTo(b.Sequence);
            });

            for (int i = 0; i < _dueScratch.Count; i++) _ready.Add(_dueScratch[i].Payload);
            PacketsDelivered += _ready.Count;
            return _ready;
        }

        public void Clear()
        {
            _inFlight.Clear();
            _ready.Clear();
        }

        public override string ToString() =>
            $"link {LatencySeconds * 1000f:F0}ms ±{JitterSeconds * 1000f:F0}ms, "
            + $"{LossChance:P0} loss — sent {PacketsSent}, dropped {PacketsDropped}, "
            + $"delivered {PacketsDelivered}";
    }
}
