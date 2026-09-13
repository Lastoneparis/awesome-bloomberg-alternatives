using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Round-based 5v5. Attackers carry a charge to one of two relays and arm it; defenders
    /// stop them, or disarm it before it fires.
    /// </summary>
    /// <remarks>
    /// The shape is a genre convention — an attacking side, a defending side, two objective
    /// sites, no respawning within a round, sides swapped at half time. ORIGINALITY.md is
    /// explicit that conventions are the vocabulary of the genre rather than anyone's property;
    /// what may not be copied is a specific game's maps, callouts, timings, names or assets, and
    /// none of those are here.
    ///
    /// <para>This mode is also the first real test of <see cref="IGameMode"/>. Team deathmatch
    /// and free-for-all are both "shoot people, count it", so neither exercises rounds, freeze
    /// time, elimination, a carried objective, or a side swap. If any of that had required
    /// changes to <see cref="MatchSimulation"/>, the split between loop and rules would have
    /// been in the wrong place.</para>
    ///
    /// <para>One consequence worth stating: the mode holds its own objective state and reads
    /// player positions and buttons through the match, but never writes to a player. Arming is
    /// expressed as "this player stood in this zone holding Use for long enough", which the mode
    /// can observe; it does not reach into the player to set a flag.</para>
    /// </remarks>
    public sealed class OverloadMode : GameModeBase
    {
        /// <summary>Seconds of continuous contact to arm the charge.</summary>
        public const float ArmSeconds = 3.5f;
        /// <summary>Seconds to disarm. Longer than arming, so a defender cannot casually undo
        /// an attacker's committed push.</summary>
        public const float DisarmSeconds = 5f;
        /// <summary>Seconds from arming to detonation.</summary>
        public const float FuseSeconds = 40f;

        /// <summary>The side that attacks in the first half. Swapped at half time.</summary>
        public Team FirstHalfAttackers { get; }

        public Team Attackers { get; private set; }
        public Team Defenders => Attackers.Opponent();

        public bool IsArmed { get; private set; }
        public int ArmedSite { get; private set; } = -1;
        public float FuseRemaining { get; private set; }
        public float ArmProgress { get; private set; }
        public float DisarmProgress { get; private set; }
        /// <summary>Who is currently making progress, for the UI to show a bar over.</summary>
        public PlayerId Interactor { get; private set; } = PlayerId.None;

        private float _roundElapsed;
        private bool _roundDecided;
        private MatchOutcome _roundOutcome;

        public OverloadMode(GameModeDefinition definition, Team firstHalfAttackers = Team.Alpha)
            : base(definition)
        {
            FirstHalfAttackers = firstHalfAttackers;
            Attackers = firstHalfAttackers;
        }

        public override void OnMatchStart(MatchSimulation match)
        {
            base.OnMatchStart(match);
            Attackers = FirstHalfAttackers;
            ResetRoundState();
        }

        public override void OnRoundStart(MatchSimulation match, int roundNumber)
        {
            // Sides swap once, at the midpoint of the maximum possible rounds. Doing it by round
            // number rather than by score keeps it predictable: a team knows in advance which
            // half they are in, which matters because attacking and defending are bought
            // differently.
            int halfTime = Definition.RoundsToWin;
            Attackers = roundNumber > halfTime ? FirstHalfAttackers.Opponent() : FirstHalfAttackers;
            ResetRoundState();
        }

        private void ResetRoundState()
        {
            IsArmed = false;
            ArmedSite = -1;
            FuseRemaining = 0f;
            ArmProgress = 0f;
            DisarmProgress = 0f;
            Interactor = PlayerId.None;
            _roundElapsed = 0f;
            _roundDecided = false;
            _roundOutcome = MatchOutcome.Undecided;
        }

        public override void OnTick(MatchSimulation match, float dt)
        {
            if (_roundDecided) return;
            _roundElapsed += dt;

            if (IsArmed) TickArmed(match, dt);
            else TickUnarmed(match, dt);

            if (_roundDecided) return;
            CheckElimination(match);
            if (_roundDecided) return;

            // Time runs out only while the charge is unarmed. Once it is armed the fuse is the
            // clock, which is the whole point of arming: the attackers have converted a time
            // limit that favours the defenders into one that favours them.
            if (!IsArmed && Definition.RoundSeconds > 0f && _roundElapsed >= Definition.RoundSeconds)
                Decide(MatchOutcome.TeamWins(Defenders, "round.end.time_expired"));
        }

        private void TickUnarmed(MatchSimulation match, float dt)
        {
            PlayerRuntime armer = FindInteractor(match, Attackers, out int site);
            if (armer == null)
            {
                // Progress is lost, not paused. A half-arm that survives the player dying and
                // being replaced by a team-mate would make the commitment meaningless.
                ArmProgress = 0f;
                Interactor = PlayerId.None;
                return;
            }

            Interactor = armer.Id;
            ArmProgress += dt;
            if (ArmProgress < ArmSeconds) return;

            IsArmed = true;
            ArmedSite = site;
            FuseRemaining = FuseSeconds;
            ArmProgress = 0f;
            Interactor = PlayerId.None;
            armer.Score.ObjectiveScore += 50;
            match.Emit(new MatchEvent
            {
                Kind = MatchEventKind.ObjectiveChanged, Tick = match.Tick, Player = armer.Id,
                ContentId = "objective.armed", Value = site,
                Position = match.Map.Objectives[site].Centre,
            });
        }

        private void TickArmed(MatchSimulation match, float dt)
        {
            FuseRemaining -= dt;

            PlayerRuntime defuser = FindInteractor(match, Defenders, out int site);
            if (defuser == null || site != ArmedSite)
            {
                DisarmProgress = 0f;
                Interactor = PlayerId.None;
            }
            else
            {
                Interactor = defuser.Id;
                DisarmProgress += dt;
                if (DisarmProgress >= DisarmSeconds)
                {
                    defuser.Score.ObjectiveScore += 50;
                    match.Emit(new MatchEvent
                    {
                        Kind = MatchEventKind.ObjectiveChanged, Tick = match.Tick,
                        Player = defuser.Id, ContentId = "objective.disarmed", Value = ArmedSite,
                        Position = match.Map.Objectives[ArmedSite].Centre,
                    });
                    Decide(MatchOutcome.TeamWins(Defenders, "round.end.disarmed"));
                    return;
                }
            }

            // The fuse is checked after the disarm, so a disarm completing on the same tick the
            // fuse expires goes to the defenders. Someone wins that tick either way; giving it
            // to the player who was actively doing something is the defensible choice.
            if (FuseRemaining <= 0f)
                Decide(MatchOutcome.TeamWins(Attackers, "round.end.detonated"));
        }

        /// <summary>
        /// The player currently interacting with a site, if exactly one is eligible.
        /// </summary>
        /// <remarks>
        /// "Eligible" means alive, on the right side, holding Use, inside the zone and on the
        /// ground. The grounded check is not fussiness: without it a player can arm mid-jump,
        /// which is both absurd to watch and a way to arm from on top of geometry the site was
        /// not meant to be reachable from.
        /// </remarks>
        private static PlayerRuntime FindInteractor(MatchSimulation match, Team side, out int site)
        {
            site = -1;
            List<ObjectiveZone> zones = match.Map.Objectives;
            if (zones.Count == 0) return null;

            IReadOnlyList<PlayerRuntime> players = match.Players;
            for (int i = 0; i < players.Count; i++)
            {
                PlayerRuntime player = players[i];
                if (!player.IsConnected || !player.IsAlive || player.Team != side) continue;
                if (!player.Input.Held(InputButtons.Use)) continue;
                if (!player.Movement.IsGrounded) continue;

                for (int z = 0; z < zones.Count; z++)
                {
                    if (!zones[z].Contains(player.Movement.Position)) continue;
                    site = z;
                    return player;
                }
            }
            return null;
        }

        private void CheckElimination(MatchSimulation match)
        {
            int attackersAlive = match.LivingCount(Attackers);
            int defendersAlive = match.LivingCount(Defenders);

            if (attackersAlive == 0)
            {
                // An armed charge outlives its planter. Wiping the attacking team after they
                // have armed does not win the round — the defenders still have to disarm it,
                // which is what makes the arm worth committing to.
                if (!IsArmed) Decide(MatchOutcome.TeamWins(Defenders, "round.end.eliminated"));
                return;
            }
            if (defendersAlive == 0) Decide(MatchOutcome.TeamWins(Attackers, "round.end.eliminated"));
        }

        private void Decide(MatchOutcome outcome)
        {
            if (_roundDecided) return;
            _roundDecided = true;
            _roundOutcome = outcome;
            AddScore(outcome.WinningTeam, 1);
        }

        public override MatchOutcome CheckRoundEnd(MatchSimulation match) => _roundOutcome;

        public override MatchOutcome CheckMatchEnd(MatchSimulation match)
        {
            // Rounds won, not kills. The base implementation's score limit and time limit are
            // both meaningless here, which is exactly why this is overridable.
            if (Definition.RoundsToWin <= 0) return MatchOutcome.Undecided;

            int alpha = TeamScore(Team.Alpha);
            int bravo = TeamScore(Team.Bravo);
            if (alpha >= Definition.RoundsToWin)
                return MatchOutcome.TeamWins(Team.Alpha, "match.end.rounds_won");
            if (bravo >= Definition.RoundsToWin)
                return MatchOutcome.TeamWins(Team.Bravo, "match.end.rounds_won");

            // Every possible round played without either side reaching the target.
            if (alpha + bravo >= Definition.RoundsToWin * 2 - 1)
                return DecideOnScore("match.end.rounds_exhausted");

            return MatchOutcome.Undecided;
        }

        public override bool TryGetObjectiveOrder(MatchSimulation match, PlayerRuntime player,
                                                  out Vec3 position, out bool holdUse)
        {
            position = Vec3.Zero;
            holdUse = false;

            List<ObjectiveZone> zones = match.Map.Objectives;
            if (zones.Count == 0) return false;

            bool attacking = player.Team == Attackers;

            if (IsArmed)
            {
                // Both sides converge on the armed site. The attackers are defending it now,
                // which is the role reversal that makes the second half of a round interesting.
                position = zones[SalvoMath.Clamp(ArmedSite, 0, zones.Count - 1)].Centre;
                holdUse = !attacking;
                return true;
            }

            if (!attacking)
            {
                // Defenders spread across the sites rather than stacking on one. Splitting by
                // player id is crude but stable: a bot does not change its mind about which site
                // it is holding halfway through a round.
                position = zones[player.Id.Raw % zones.Count].Centre;
                return true;
            }

            // Attackers all commit to the same site, chosen by the match seed so it varies
            // between matches but not within a round. A team that split would never assemble
            // enough force to arm anything.
            int target = (int)(match.MatchSeed % (uint)zones.Count);
            position = zones[target].Centre;
            holdUse = true;
            return true;
        }

        public override bool TryChooseRespawn(MatchSimulation match, PlayerRuntime player,
                                              out SpawnPoint spawn)
        {
            // Nobody comes back inside a round. The match loop respawns everyone at the start of
            // the next one, which is the whole tension of the format.
            spawn = default;
            return false;
        }
    }
}
