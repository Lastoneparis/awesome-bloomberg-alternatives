using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>One party waiting for a match. A solo player is a party of one.</summary>
    /// <remarks>
    /// Solos are not a special case, and that is deliberate: every rule about keeping a party
    /// together, respecting blocks and balancing teams applies identically, so there is one code
    /// path rather than two that can disagree about a player queueing alone.
    /// </remarks>
    public sealed class MatchmakingTicket
    {
        /// <summary>Accounts in this party, all of whom must land on the same team.</summary>
        public readonly List<string> Accounts = new List<string>();

        public ContentId ModeId;
        /// <summary>Preferred worlds, empty meaning no preference. Advisory: a player who will
        /// only play one era waits longer, and the matchmaker says so rather than ignoring it.</summary>
        public ContentId[] PreferredWorlds = System.Array.Empty<ContentId>();

        /// <summary>Mean skill of the party. Teams are balanced on the sum of these.</summary>
        public int SkillRating = SkillRatings.Default;

        /// <summary>Seconds this ticket has been waiting. Drives both fairness and how far the
        /// skill tolerance has widened.</summary>
        public float WaitSeconds;

        public int Size => Accounts.Count;

        public static MatchmakingTicket ForParty(Party party, ContentId modeId, int skill)
        {
            var ticket = new MatchmakingTicket { ModeId = modeId, SkillRating = skill };
            ticket.Accounts.AddRange(party.Members);
            return ticket;
        }

        public static MatchmakingTicket ForSolo(string account, ContentId modeId,
                                                int skill = SkillRatings.Default)
        {
            var ticket = new MatchmakingTicket { ModeId = modeId, SkillRating = skill };
            ticket.Accounts.Add(account);
            return ticket;
        }
    }

    /// <summary>
    /// Skill numbers, kept deliberately crude.
    /// </summary>
    /// <remarks>
    /// A real rating system is a project of its own and needs live data to tune. What matters
    /// now is that team balancing has <em>something</em> to balance on and that the matchmaker's
    /// shape is right; swapping in a proper rating later changes one number per ticket and
    /// nothing else.
    /// </remarks>
    public static class SkillRatings
    {
        public const int Minimum = 0;
        public const int Default = 1000;
        public const int Maximum = 5000;

        /// <summary>How far apart two tickets may be at zero wait.</summary>
        public const int BaseTolerance = 150;
        /// <summary>How much the tolerance widens per second waited.</summary>
        public const int ToleranceGrowthPerSecond = 25;
        /// <summary>Past this, skill is ignored entirely — a match is better than none.</summary>
        public const int MaxTolerance = 2500;

        public static int ToleranceAfter(float waitSeconds) =>
            SalvoMath.Clamp((int)(BaseTolerance + waitSeconds * ToleranceGrowthPerSecond),
                            BaseTolerance, MaxTolerance);

        /// <summary>A placeholder rating derived from career record, so testing has a spread to
        /// work with. Not a rating system, and named so nobody mistakes it for one.</summary>
        public static int PlaceholderFromCareer(PlayerProgress progress)
        {
            if (progress == null) return Default;
            CareerStats career = progress.Career;
            if (career.MatchesPlayed < 3) return Default;

            float kd = SalvoMath.Clamp(career.KillDeathRatio, 0.2f, 3f);
            float winRate = SalvoMath.Clamp01(career.WinRate);
            return SalvoMath.Clamp((int)(Default * (0.6f + kd * 0.25f + winRate * 0.4f)),
                                   Minimum, Maximum);
        }
    }
}
