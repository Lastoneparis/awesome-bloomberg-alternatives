namespace Salvo.Sim
{
    /// <summary>
    /// Kill the other team more times than they kill you.
    /// </summary>
    /// <remarks>
    /// The first mode, and the reference implementation of <see cref="IGameMode"/>: it is short
    /// because everything it does not override is already handled by the match loop. If a second
    /// mode turns out to need changes in <see cref="MatchSimulation"/> rather than here, that is
    /// a sign the split between loop and rules is in the wrong place.
    /// </remarks>
    public sealed class TeamDeathmatchMode : GameModeBase
    {
        public TeamDeathmatchMode(GameModeDefinition definition) : base(definition) { }

        public override void OnPlayerKilled(MatchSimulation match, PlayerRuntime victim,
                                            PlayerRuntime killer, DamageEvent damage)
        {
            if (killer == null || killer == victim)
            {
                // A suicide or a world death feeds the other team. Otherwise stepping off a
                // ledge would be a free way to deny the enemy a point.
                AddScore(victim.Team.Opponent(), 1);
                return;
            }
            if (killer.Team == victim.Team)
            {
                // Team kills cost the killer's team, rather than rewarding the victim's. Same
                // scoreline, but it puts the penalty where the behaviour was.
                AddScore(killer.Team, -1);
                return;
            }
            AddScore(killer.Team, 1);
        }
    }

    /// <summary>
    /// Everyone for themselves. Included from the start because it is what proves the mode
    /// abstraction is not secretly team-shaped: it scores per player, has no teams, and still
    /// needs no change to the match loop.
    /// </summary>
    public sealed class FreeForAllMode : GameModeBase
    {
        public FreeForAllMode(GameModeDefinition definition) : base(definition) { }

        public override MatchOutcome CheckMatchEnd(MatchSimulation match)
        {
            PlayerRuntime leader = null;
            bool tied = false;
            foreach (PlayerRuntime player in match.Players)
            {
                if (!player.IsConnected) continue;
                if (leader == null || player.Score.Kills > leader.Score.Kills)
                {
                    leader = player;
                    tied = false;
                }
                else if (player != leader && player.Score.Kills == leader.Score.Kills)
                {
                    tied = true;
                }
            }

            if (leader != null && Definition.ScoreLimit > 0
                && leader.Score.Kills >= Definition.ScoreLimit)
                return MatchOutcome.PlayerWins(leader.Id, "match.end.score_limit");

            if (Definition.TimeLimitSeconds > 0f && match.ElapsedSeconds >= Definition.TimeLimitSeconds)
            {
                if (leader == null) return MatchOutcome.Draw("match.end.draw");
                return tied ? MatchOutcome.Draw("match.end.draw")
                            : MatchOutcome.PlayerWins(leader.Id, "match.end.time_limit");
            }
            return MatchOutcome.Undecided;
        }
    }
}
