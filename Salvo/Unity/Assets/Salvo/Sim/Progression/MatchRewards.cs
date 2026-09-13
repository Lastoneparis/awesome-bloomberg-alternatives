namespace Salvo.Sim
{
    /// <summary>
    /// What one player earned from one finished match.
    /// </summary>
    /// <remarks>
    /// Computed on the server from the server's own match record, and from nothing a client
    /// said. The rule about never trusting the client is usually discussed in terms of damage
    /// and hit registration, but experience is the more tempting target: it is persistent,
    /// whereas a stolen kill lasts one round.
    /// </remarks>
    public struct MatchRewards
    {
        public PlayerId Player;
        public bool Won;

        public int Kills;
        public int Deaths;
        public int Assists;
        public int Headshots;
        public int ObjectiveActions;
        public float DamageDealt;
        public int BestStreak;
        public long SecondsPlayed;

        public long KillXp;
        public long AssistXp;
        public long ObjectiveXp;
        public long ParticipationXp;
        public long WinBonusXp;

        public long TotalXp => KillXp + AssistXp + ObjectiveXp + ParticipationXp + WinBonusXp;
    }

    /// <summary>
    /// Turns a finished match into experience.
    /// </summary>
    /// <remarks>
    /// <b>Participation is the largest single component, and that is deliberate.</b> A curve
    /// weighted mostly toward kills rewards the player who was already winning and punishes the
    /// one who needed the encouragement — and, worse, it makes playing the objective cost the
    /// player something, which is how a team game teaches people not to play it. Time in the
    /// match and objective work together outweigh raw kills for anyone who is not dominating.
    ///
    /// <para>There is no loss penalty. Losing already costs the win bonus; taking experience
    /// away as well turns a bad match into a reason to stop playing, and rewards quitting early
    /// over finishing a losing game.</para>
    /// </remarks>
    public static class RewardRules
    {
        public const int XpPerKill = 100;
        public const int XpPerAssist = 40;
        public const int XpPerHeadshot = 25;          // on top of the kill
        public const int XpPerObjectiveAction = 150;  // arming, disarming, capturing
        public const int XpPerMinutePlayed = 120;
        public const int WinBonus = 500;

        /// <summary>
        /// Experience below which a match is treated as not played. Stops a player from farming
        /// the participation award by joining and immediately leaving.
        /// </summary>
        public const int MinimumSecondsForReward = 30;

        public static MatchRewards Compute(MatchSimulation match, PlayerRuntime player)
        {
            if (match == null) throw new System.ArgumentNullException(nameof(match));
            if (player == null) throw new System.ArgumentNullException(nameof(player));

            long seconds = (long)match.ElapsedSeconds;
            bool won = match.Outcome.IsDecided
                       && (match.Outcome.WinningPlayer == player.Id
                           || (match.Outcome.WinningTeam != Team.None
                               && match.Outcome.WinningTeam == player.Team));

            var rewards = new MatchRewards
            {
                Player = player.Id,
                Won = won,
                Kills = player.Score.Kills,
                Deaths = player.Score.Deaths,
                Assists = player.Score.Assists,
                Headshots = player.Score.Headshots,
                DamageDealt = player.Score.DamageDealt,
                BestStreak = player.Score.BestStreak,
                SecondsPlayed = seconds,
                // ObjectiveScore is awarded by the mode in fixed lumps; dividing recovers the
                // count without the mode having to report it separately.
                ObjectiveActions = player.Score.ObjectiveScore / 50,
            };

            if (seconds < MinimumSecondsForReward) return rewards;

            rewards.KillXp = (long)player.Score.Kills * XpPerKill
                             + (long)player.Score.Headshots * XpPerHeadshot;
            rewards.AssistXp = (long)player.Score.Assists * XpPerAssist;
            rewards.ObjectiveXp = (long)rewards.ObjectiveActions * XpPerObjectiveAction;
            rewards.ParticipationXp = seconds * XpPerMinutePlayed / 60;
            rewards.WinBonusXp = won ? WinBonus : 0;
            return rewards;
        }

        /// <summary>
        /// Folds a match's per-weapon shooting into a player's career record.
        /// </summary>
        /// <remarks>
        /// Driven from the match's event stream rather than from the players, because shots
        /// fired and shots landed are events; nothing accumulates them on the player, and adding
        /// counters there would mean the simulation carrying statistics it never reads.
        ///
        /// <para><paramref name="content"/> is needed to know how many projectiles a weapon puts
        /// out per trigger pull, which is what makes the accuracy figure mean the same thing for
        /// a rifle and for a shotgun.</para>
        /// </remarks>
        public static void RecordEvents(PlayerProgress progress, PlayerId player,
                                        System.Collections.Generic.IReadOnlyList<MatchEvent> events,
                                        GameContent content)
        {
            if (progress == null) return;
            for (int i = 0; i < events.Count; i++)
            {
                MatchEvent e = events[i];
                switch (e.Kind)
                {
                    case MatchEventKind.Fired when e.Player == player:
                        // Counted in pellets, not trigger pulls. A shotgun emits one Fired event
                        // and up to eight Damaged ones, so counting hits against pulls would
                        // show it as 800% accurate — a wrong number on a stats screen that
                        // nothing else would ever flag.
                        int pellets = content != null
                                      && content.Weapons.TryGet(e.ContentId, out WeaponDefinition w)
                            ? System.Math.Max(1, w.PelletsPerShot) : 1;
                        progress.RecordWeapon(e.ContentId, s => { s.ShotsFired += pellets; return s; });
                        break;
                    case MatchEventKind.Damaged when e.OtherPlayer == player && e.Player != player:
                        progress.RecordWeapon(e.ContentId, s =>
                        {
                            s.ShotsHit++;
                            s.DamageDealt += (long)e.Value;
                            return s;
                        });
                        break;
                    case MatchEventKind.Died when e.OtherPlayer == player:
                        progress.RecordWeapon(e.ContentId, s =>
                        {
                            s.Kills++;
                            if (e.Region == HitRegion.Head) s.Headshots++;
                            return s;
                        });
                        break;
                }
            }
        }
    }
}
