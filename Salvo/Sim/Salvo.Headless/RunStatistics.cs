using System;
using System.Collections.Generic;
using Salvo.Sim;

namespace Salvo.Headless
{
    /// <summary>
    /// Watches a headless run and decides whether it looked like a game.
    /// </summary>
    /// <remarks>
    /// The checks in <see cref="Problems"/> are the point of this class. A match that runs for
    /// three minutes without crashing proves very little — bots standing still in their spawn
    /// would do that. What proves the simulation works is that players moved, found each other,
    /// hit each other, died and came back. Each of those is a separate check because each fails
    /// for a different reason, and a single "did anything happen" check would pass on a game
    /// where the bots only ever shot the floor.
    /// </remarks>
    public sealed class RunStatistics
    {
        public int Spawns;
        public int ShotsFired;
        public int Hits;
        public int Deaths;
        public int Footsteps;
        public double DistanceMoved;
        public int HeadshotHits;

        /// <summary>How long the run was allowed to last. Needed to tell "this match cannot
        /// end" from "this run was stopped early", which look identical from the outside.</summary>
        private readonly float _allowedSeconds;

        public RunStatistics(float allowedSeconds) { _allowedSeconds = allowedSeconds; }

        private readonly Dictionary<int, Vec3> _lastPosition = new Dictionary<int, Vec3>();
        private readonly HashSet<int> _playersWhoFired = new HashSet<int>();
        private readonly HashSet<int> _playersWhoMoved = new HashSet<int>();
        private float _maxAbsY;

        public double HitRate => ShotsFired == 0 ? 0 : (double)Hits / ShotsFired;

        public void Observe(MatchSimulation match, bool verbose)
        {
            foreach (MatchEvent matchEvent in match.Events)
            {
                switch (matchEvent.Kind)
                {
                    case MatchEventKind.Spawned: Spawns++; break;
                    case MatchEventKind.Footstep: Footsteps++; break;
                    case MatchEventKind.Fired:
                        ShotsFired++;
                        _playersWhoFired.Add(matchEvent.Player.Raw);
                        break;
                    case MatchEventKind.Damaged:
                        if (matchEvent.OtherPlayer != matchEvent.Player)
                        {
                            Hits++;
                            if (matchEvent.Region == HitRegion.Head) HeadshotHits++;
                        }
                        break;
                    case MatchEventKind.Died:
                        Deaths++;
                        if (verbose)
                        {
                            PlayerRuntime victim = match.Find(matchEvent.Player);
                            PlayerRuntime killer = match.Find(matchEvent.OtherPlayer);
                            Console.WriteLine($"  [{match.ElapsedSeconds,6:F1}s] "
                                              + $"{killer?.Name ?? "the world"} killed "
                                              + $"{victim?.Name} ({matchEvent.Region})");
                        }
                        break;
                }
            }

            foreach (PlayerRuntime player in match.Players)
            {
                if (!player.IsAlive) { _lastPosition.Remove(player.Id.Raw); continue; }
                Vec3 position = player.Movement.Position;
                _maxAbsY = Math.Max(_maxAbsY, Math.Abs(position.Y));

                if (_lastPosition.TryGetValue(player.Id.Raw, out Vec3 previous))
                {
                    float step = Vec3.Distance(previous, position);
                    // A jump larger than any tick could produce is a teleport — a respawn we
                    // already skipped, or a bug. Not counted either way.
                    if (step < 2f)
                    {
                        DistanceMoved += step;
                        if (step > 0.01f) _playersWhoMoved.Add(player.Id.Raw);
                    }
                }
                _lastPosition[player.Id.Raw] = position;
            }
        }

        public IEnumerable<string> Problems(MatchSimulation match)
        {
            int connected = 0;
            foreach (PlayerRuntime player in match.Players) if (player.IsConnected) connected++;

            if (Spawns < connected)
                yield return $"only {Spawns} spawns for {connected} players — someone never "
                             + "entered the match (spawn selection rejected every point?)";

            if (_playersWhoMoved.Count < connected)
                yield return $"{connected - _playersWhoMoved.Count} of {connected} players never "
                             + "moved — navigation or movement input is not reaching them";

            if (_playersWhoFired.Count < connected)
                yield return $"{connected - _playersWhoFired.Count} of {connected} players never "
                             + "fired a shot — perception or the fire decision is broken for them";

            if (ShotsFired == 0) yield return "no shots were fired at all";
            else if (Hits == 0)
                yield return "shots were fired but nothing was ever hit — ballistics, hitboxes "
                             + "or aiming is wrong";

            if (Deaths == 0 && Hits > 0)
                yield return "players were hit but nobody ever died — the damage model is not "
                             + "reducing health to zero";

            if (HitRate > 0.9)
                yield return $"hit rate of {HitRate:P0} is implausibly high — spread or bot aim "
                             + "error is not being applied";

            if (_maxAbsY > 40f)
                yield return $"a player reached y={_maxAbsY:F1}, far outside the map — the "
                             + "collision or movement model let someone escape";

            // Only a problem when the run was actually given long enough for the mode's own
            // limits to bite. A 4-minute run of a 10-minute mode stopping early is the run
            // being cut short, not the match failing to end — and reporting it as a failure
            // would train everyone to ignore the one message that would matter.
            if (match.Phase != MatchPhase.MatchEnd
                && _allowedSeconds >= match.Mode.Definition.TimeLimitSeconds)
                yield return "the match never reached an ending, despite being given longer "
                             + $"than its own {match.Mode.Definition.TimeLimitSeconds:F0}s time limit";
        }

        /// <summary>True when the run found nothing wrong.</summary>
        public bool Verdict(MatchSimulation match)
        {
            foreach (string _ in Problems(match)) return false;
            return true;
        }
    }
}
