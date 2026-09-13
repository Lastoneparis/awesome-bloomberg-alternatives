namespace Salvo.Sim
{
    /// <summary>
    /// Turns experience into a level, and back.
    /// </summary>
    /// <remarks>
    /// Integer arithmetic throughout, and that is not fussiness. A player's level is compared,
    /// displayed, gated on and persisted; if it is derived from a float it can differ between a
    /// client's display and a server's record by one, on exactly the boundary where it matters
    /// most — the moment the player levels up. The forward curve is a closed-form quadratic and
    /// the inverse is that quadratic solved and then <em>corrected against the forward
    /// function</em>, so the two can never disagree even if the square root rounds badly.
    ///
    /// <para>The curve is quadratic rather than exponential. Exponential curves make the first
    /// twenty levels meaningless and the last twenty unreachable; a quadratic keeps each level a
    /// visibly longer commitment than the last without the gap running away.</para>
    /// </remarks>
    public static class XpCurve
    {
        /// <summary>Extra experience each level costs over the previous one.</summary>
        public const int Step = 100;
        /// <summary>Experience for the first level-up.</summary>
        public const int FirstLevel = 1000;
        /// <summary>Levels stop here. Beyond it, experience still accrues and is still shown.</summary>
        public const int MaxLevel = 100;

        /// <summary>
        /// Total experience needed to have reached <paramref name="level"/>. Level 1 costs zero:
        /// everyone starts there.
        /// </summary>
        public static long TotalXpForLevel(int level)
        {
            if (level <= 1) return 0;
            int capped = level > MaxLevel ? MaxLevel : level;
            long n = capped - 1;
            // Sum over n levels of (FirstLevel + Step * (i - 1)), in closed form.
            return n * FirstLevel + Step * (n * (n - 1) / 2);
        }

        /// <summary>Experience needed to go from <paramref name="level"/> to the next.</summary>
        public static long XpForNextLevel(int level)
        {
            if (level >= MaxLevel) return 0;
            return TotalXpForLevel(level + 1) - TotalXpForLevel(level);
        }

        /// <summary>
        /// The level a total experience figure corresponds to.
        /// </summary>
        /// <remarks>
        /// Solved directly, then walked to the exact answer. The closed-form inverse of a
        /// quadratic needs a square root, and a square root that lands a hair under an integer
        /// boundary would report a player as one level lower than the forward function says they
        /// are. The correction loop runs at most a step or two and makes the two functions
        /// consistent by construction rather than by hope.
        /// </remarks>
        public static int LevelForTotalXp(long totalXp)
        {
            if (totalXp <= 0) return 1;

            // 100/2 * n^2 + (1000 - 100/2) * n = xp, solved for n.
            double a = Step / 2.0;
            double b = FirstLevel - Step / 2.0;
            double n = (-b + System.Math.Sqrt(b * b + 4.0 * a * totalXp)) / (2.0 * a);
            int level = (int)n + 1;

            if (level < 1) level = 1;
            if (level > MaxLevel) level = MaxLevel;

            while (level < MaxLevel && TotalXpForLevel(level + 1) <= totalXp) level++;
            while (level > 1 && TotalXpForLevel(level) > totalXp) level--;
            return level;
        }

        /// <summary>Progress through the current level, 0 to 1. Returns 1 at the cap.</summary>
        public static float ProgressThroughLevel(long totalXp)
        {
            int level = LevelForTotalXp(totalXp);
            if (level >= MaxLevel) return 1f;

            long start = TotalXpForLevel(level);
            long span = TotalXpForLevel(level + 1) - start;
            if (span <= 0) return 1f;
            return SalvoMath.Clamp01((float)((totalXp - start) / (double)span));
        }
    }
}
