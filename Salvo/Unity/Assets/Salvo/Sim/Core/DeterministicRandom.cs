namespace Salvo.Sim
{
    /// <summary>
    /// A small, fast, fully specified pseudo-random generator.
    /// </summary>
    /// <remarks>
    /// <see cref="System.Random"/> is unusable here and <c>UnityEngine.Random</c> doubly so.
    /// Not because they are slow, but because neither guarantees that a given seed produces a
    /// given sequence across runtimes or versions — and this game needs exactly that. Bullet
    /// spread is rolled on the server and <em>predicted</em> on the client; if the two
    /// generators disagree by one number, every shot a player fires appears to land somewhere
    /// other than where their client drew it.
    ///
    /// <para>This is xorshift128 with the parameters from Marsaglia's 2003 paper. It is not
    /// cryptographic and must never be used for anything where that matters (match-making
    /// seeds, loot, anything a player could profit from predicting). It is used because it is
    /// three instructions, has no hidden state, and produces the same bits everywhere.</para>
    ///
    /// <para>A struct, and copied by value on purpose: rewinding a simulation for
    /// reconciliation means rewinding the RNG with it, and that only works if the state is
    /// part of the snapshot rather than sitting behind a reference.</para>
    /// </remarks>
    public struct DeterministicRandom
    {
        private uint _x, _y, _z, _w;

        public DeterministicRandom(uint seed)
        {
            // Seed zero would leave the generator stuck at zero forever, so it is mapped to a
            // fixed non-zero constant rather than rejected: callers pass tick numbers, and
            // tick zero is a perfectly reasonable thing to seed with.
            if (seed == 0u) seed = 0x9E3779B9u;
            _x = seed;
            _y = seed ^ 0x6C078965u;
            _z = seed ^ 0x9E3779B9u;
            _w = seed ^ 0x85EBCA6Bu;
            // Discard the first few outputs, which are strongly correlated with the seed.
            // Without this, consecutive ticks produce visibly similar spread patterns.
            for (int i = 0; i < 8; i++) NextUInt();
        }

        /// <summary>
        /// Seeds from several values at once — typically (match seed, tick, player). Combining
        /// them here rather than at the call site keeps every caller using the same mixing,
        /// which is what stops two players on the same tick sharing a spread pattern.
        /// </summary>
        public static DeterministicRandom Seeded(uint a, uint b, uint c = 0u)
        {
            // Three rounds of a 32-bit finaliser (the murmur3 one). Cheap, and good enough
            // that adjacent ticks decorrelate.
            uint h = a * 0x9E3779B9u;
            h ^= b + 0x9E3779B9u + (h << 6) + (h >> 2);
            h ^= c + 0x85EBCA6Bu + (h << 6) + (h >> 2);
            h ^= h >> 16; h *= 0x85EBCA6Bu;
            h ^= h >> 13; h *= 0xC2B2AE35u;
            h ^= h >> 16;
            return new DeterministicRandom(h);
        }

        public uint NextUInt()
        {
            uint t = _x ^ (_x << 11);
            _x = _y; _y = _z; _z = _w;
            _w = _w ^ (_w >> 19) ^ t ^ (t >> 8);
            return _w;
        }

        /// <summary>Uniform in [0, 1). Never returns 1, so it is safe as a Lerp parameter
        /// and as an index scale.</summary>
        public float NextFloat()
        {
            // 24 bits, which is exactly the float mantissa: using all 32 would round some
            // values up to 1.0f and quietly break every caller that indexes with it.
            return (NextUInt() >> 8) * (1f / 16777216f);
        }

        public float NextFloat(float min, float max) => min + NextFloat() * (max - min);

        /// <summary>Uniform in [0, exclusiveMax). Returns 0 for a non-positive bound.</summary>
        public int NextInt(int exclusiveMax)
        {
            if (exclusiveMax <= 0) return 0;
            return (int)(NextUInt() % (uint)exclusiveMax);
        }

        public int NextInt(int min, int exclusiveMax) =>
            min + NextInt(System.Math.Max(0, exclusiveMax - min));

        public bool NextBool(float probability) => NextFloat() < probability;

        /// <summary>
        /// A point uniformly distributed inside the unit disc, used for bullet spread.
        /// </summary>
        /// <remarks>
        /// The square root is not decoration. Sampling radius uniformly would concentrate
        /// shots at the centre of the cone and make every weapon far more accurate than its
        /// spread number claims — which is exactly the sort of bug that only shows up as
        /// "the numbers in the UI are lying".
        /// </remarks>
        public void NextPointInDisc(out float x, out float y)
        {
            float angle = NextFloat() * SalvoMath.TwoPi;
            float radius = (float)System.Math.Sqrt(NextFloat());
            x = radius * (float)System.Math.Cos(angle);
            y = radius * (float)System.Math.Sin(angle);
        }

        /// <summary>Standard normal, via Box-Muller. Used where a bell curve reads better
        /// than a flat one — bot aim error, for instance, where a uniform distribution makes
        /// a bot's misses look mechanical.</summary>
        public float NextGaussian()
        {
            // u1 is pulled away from zero because log(0) is negative infinity, and one
            // infinity reaching a player's aim angle ruins the match.
            float u1 = SalvoMath.Clamp(NextFloat(), 1e-7f, 1f);
            float u2 = NextFloat();
            return (float)(System.Math.Sqrt(-2.0 * System.Math.Log(u1))
                           * System.Math.Cos(SalvoMath.TwoPi * u2));
        }
    }
}
