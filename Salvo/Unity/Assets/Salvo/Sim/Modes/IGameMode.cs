using System.Collections.Generic;

namespace Salvo.Sim
{
    public enum MatchPhase : byte
    {
        Warmup,
        /// <summary>Round-based modes only: players are frozen at spawn.</summary>
        Freeze,
        Live,
        /// <summary>A round has ended but the match has not.</summary>
        RoundEnd,
        MatchEnd,
    }

    /// <summary>Who won, once the match is over.</summary>
    public struct MatchOutcome
    {
        public bool IsDecided;
        public Team WinningTeam;
        public PlayerId WinningPlayer;     // free-for-all modes
        public string ReasonKey;           // localisation key, never a sentence

        public static readonly MatchOutcome Undecided = default;

        public static MatchOutcome TeamWins(Team team, string reasonKey) => new MatchOutcome
        {
            IsDecided = true, WinningTeam = team, WinningPlayer = PlayerId.None, ReasonKey = reasonKey,
        };

        public static MatchOutcome PlayerWins(PlayerId player, string reasonKey) => new MatchOutcome
        {
            IsDecided = true, WinningTeam = Team.None, WinningPlayer = player, ReasonKey = reasonKey,
        };

        public static MatchOutcome Draw(string reasonKey) => new MatchOutcome
        {
            IsDecided = true, WinningTeam = Team.None, WinningPlayer = PlayerId.None,
            ReasonKey = reasonKey,
        };
    }

    /// <summary>
    /// The rules of one game mode.
    /// </summary>
    /// <remarks>
    /// This interface is what keeps <see cref="MatchSimulation"/> from becoming the one giant
    /// manager the brief warns against. The match loop owns movement, weapons, damage and
    /// networking — things every mode does identically — and delegates every decision that
    /// differs between modes to here. A new mode is a new implementation plus a data asset; it
    /// does not touch the loop.
    ///
    /// <para>Modes are told what happened; they do not make it happen. A mode does not move
    /// players, apply damage or write to another player's state — it reads the match, updates
    /// its own score, and answers questions. That restriction is what makes modes composable
    /// and, more practically, what stops two modes from fighting over the same player.</para>
    /// </remarks>
    public interface IGameMode
    {
        GameModeDefinition Definition { get; }

        /// <summary>Called once, after every player has been added but before the first tick.</summary>
        void OnMatchStart(MatchSimulation match);

        /// <summary>Called at the start of each round in a round-based mode. Never called for
        /// modes where <see cref="GameModeDefinition.IsRoundBased"/> is false.</summary>
        void OnRoundStart(MatchSimulation match, int roundNumber);

        /// <summary>Called every tick while the match is live, after movement and combat.</summary>
        void OnTick(MatchSimulation match, float dt);

        /// <summary>Called after a kill has already been credited. Use it to award objective
        /// score or to end a round; do not re-credit the kill.</summary>
        void OnPlayerKilled(MatchSimulation match, PlayerRuntime victim, PlayerRuntime killer,
                            DamageEvent damage);

        /// <summary>
        /// Whether a dead player may come back yet, and where.
        /// </summary>
        /// <returns>False to leave them dead — which is what a round-based mode does for the
        /// rest of the round.</returns>
        bool TryChooseRespawn(MatchSimulation match, PlayerRuntime player, out SpawnPoint spawn);

        /// <summary>Has the round ended? Returns the winner of the round, not of the match.</summary>
        MatchOutcome CheckRoundEnd(MatchSimulation match);

        /// <summary>Has the whole match ended?</summary>
        MatchOutcome CheckMatchEnd(MatchSimulation match);

        /// <summary>Team score, for the scoreboard. Modes define what a point means.</summary>
        int TeamScore(Team team);
    }

    /// <summary>
    /// Shared implementation for the parts almost every mode does the same way.
    /// </summary>
    /// <remarks>
    /// A base class rather than a utility the modes call, because the default answers are the
    /// right ones often enough that a mode overriding nothing should still be playable. A mode
    /// that wants different behaviour overrides one method; it does not reimplement the rest.
    /// </remarks>
    public abstract class GameModeBase : IGameMode
    {
        protected GameModeBase(GameModeDefinition definition)
        {
            Definition = definition ?? throw new System.ArgumentNullException(nameof(definition));
        }

        public GameModeDefinition Definition { get; }

        protected readonly Dictionary<Team, int> Scores = new Dictionary<Team, int>
        {
            { Team.Alpha, 0 }, { Team.Bravo, 0 },
        };

        public virtual void OnMatchStart(MatchSimulation match)
        {
            Scores[Team.Alpha] = 0;
            Scores[Team.Bravo] = 0;
        }

        public virtual void OnRoundStart(MatchSimulation match, int roundNumber) { }

        public virtual void OnTick(MatchSimulation match, float dt) { }

        public virtual void OnPlayerKilled(MatchSimulation match, PlayerRuntime victim,
                                           PlayerRuntime killer, DamageEvent damage) { }

        public virtual bool TryChooseRespawn(MatchSimulation match, PlayerRuntime player,
                                             out SpawnPoint spawn)
        {
            spawn = default;
            if (!Definition.AllowsRespawn) return false;
            if (player.RespawnRemaining > 0f) return false;
            return SpawnSelector.TryChoose(match, player, out spawn);
        }

        public virtual MatchOutcome CheckRoundEnd(MatchSimulation match) => MatchOutcome.Undecided;

        public virtual MatchOutcome CheckMatchEnd(MatchSimulation match)
        {
            if (Definition.TimeLimitSeconds > 0f && match.ElapsedSeconds >= Definition.TimeLimitSeconds)
                return DecideOnScore("match.end.time_limit");

            if (Definition.ScoreLimit > 0)
            {
                foreach (KeyValuePair<Team, int> entry in Scores)
                    if (entry.Value >= Definition.ScoreLimit)
                        return MatchOutcome.TeamWins(entry.Key, "match.end.score_limit");
            }
            return MatchOutcome.Undecided;
        }

        protected MatchOutcome DecideOnScore(string reasonKey)
        {
            int alpha = Scores[Team.Alpha];
            int bravo = Scores[Team.Bravo];
            if (alpha == bravo) return MatchOutcome.Draw("match.end.draw");
            return MatchOutcome.TeamWins(alpha > bravo ? Team.Alpha : Team.Bravo, reasonKey);
        }

        public int TeamScore(Team team) => Scores.TryGetValue(team, out int score) ? score : 0;

        protected void AddScore(Team team, int amount)
        {
            if (team == Team.None) return;
            Scores[team] = TeamScore(team) + amount;
        }
    }
}
