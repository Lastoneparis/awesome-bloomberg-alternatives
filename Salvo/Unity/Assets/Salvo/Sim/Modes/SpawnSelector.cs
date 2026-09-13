using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>
    /// Decides where a player comes back.
    /// </summary>
    /// <remarks>
    /// Spawn selection is one of the few systems that is invisible when it works and ruinous
    /// when it does not. The failure everyone has experienced is spawning inside an enemy's
    /// crosshair and dying before the screen has finished fading in; the failure nobody
    /// notices is spawning so far from the fight that the player spends the match walking.
    ///
    /// <para>So spawns are scored rather than picked at random or in rotation. The score is
    /// deliberately readable — distance to the nearest enemy, whether an enemy can actually see
    /// the spot, distance to friends, and how recently it was used — because a scoring function
    /// nobody can reason about is one nobody can fix.</para>
    /// </remarks>
    public static class SpawnSelector
    {
        /// <summary>Enemies nearer than this make a spawn nearly unusable.</summary>
        public const float DangerRadius = 14f;
        /// <summary>Seconds during which a spawn stays "recently used".</summary>
        public const float ReuseCooldown = 5f;

        [System.ThreadStatic] private static List<SpawnPoint> _candidates;

        /// <summary>
        /// Picks the best spawn for a player, or fails if the map has none they may use.
        /// </summary>
        public static bool TryChoose(MatchSimulation match, PlayerRuntime player,
                                     out SpawnPoint chosen)
        {
            chosen = default;
            MapDefinition map = match.Map;
            if (map == null || map.Spawns.Count == 0) return false;

            _candidates ??= new List<SpawnPoint>(32);
            _candidates.Clear();
            foreach (SpawnPoint spawn in map.SpawnsFor(player.Team)) _candidates.Add(spawn);
            // A map with no spawns for this team is a content error, but failing to spawn the
            // player is worse than using a neutral one, so fall back to the whole set.
            if (_candidates.Count == 0) _candidates.AddRange(map.Spawns);
            if (_candidates.Count == 0) return false;

            float bestScore = float.NegativeInfinity;
            int bestIndex = -1;

            for (int i = 0; i < _candidates.Count; i++)
            {
                float score = Score(match, player, _candidates[i]);
                // Ties broken by the deterministic RNG rather than by list order, so a map's
                // first spawn does not become everybody's spawn.
                if (score > bestScore)
                {
                    bestScore = score;
                    bestIndex = i;
                }
            }

            if (bestIndex < 0) return false;
            chosen = _candidates[bestIndex];
            match.NoteSpawnUsed(chosen);
            return true;
        }

        /// <summary>
        /// Scores one spawn for one player. Higher is better. Exposed so it can be tested
        /// directly — the interesting failures here are about ordering, not about the pick.
        /// </summary>
        public static float Score(MatchSimulation match, PlayerRuntime player, SpawnPoint spawn)
        {
            // A spawn embedded in geometry is not a spawn. This is checked first and fatally,
            // because every other consideration is irrelevant if the player arrives inside a
            // wall — and because a map can pass validation and still drift into this.
            var box = new Aabb(
                spawn.Position - new Vec3(CharacterDefinition.Radius, 0f, CharacterDefinition.Radius),
                spawn.Position + new Vec3(CharacterDefinition.Radius,
                                          CharacterDefinition.StandingHeight,
                                          CharacterDefinition.Radius));
            if (match.World.Overlaps(box)) return float.NegativeInfinity;

            float score = spawn.Priority * 5f;

            float nearestEnemy = float.MaxValue;
            bool seenByEnemy = false;
            float nearestFriend = float.MaxValue;

            Vec3 spawnEye = spawn.Position + new Vec3(0f, CharacterDefinition.StandingHeight - 0.12f, 0f);

            IReadOnlyList<PlayerRuntime> players = match.Players;
            for (int i = 0; i < players.Count; i++)
            {
                PlayerRuntime other = players[i];
                if (other == player || !other.IsAlive || !other.IsConnected) continue;

                float distance = Vec3.Distance(other.Movement.Position, spawn.Position);
                bool hostile = other.Team.IsHostileTo(player.Team) || player.Team == Team.None;

                if (hostile)
                {
                    if (distance < nearestEnemy) nearestEnemy = distance;
                    // Line of sight is what separates "an enemy is near" from "an enemy is
                    // aiming at this spot". A spawn twenty metres away through a wall is safe;
                    // one thirty metres away down a sightline is not.
                    if (!seenByEnemy && distance < 60f
                        && match.World.HasLineOfSight(other.EyePosition, spawnEye))
                        seenByEnemy = true;
                }
                else if (distance < nearestFriend)
                {
                    nearestFriend = distance;
                }
            }

            if (nearestEnemy < float.MaxValue)
            {
                // Ramps up to DangerRadius and then stops mattering: the difference between 40 m
                // and 60 m from an enemy is not worth walking for.
                score += SalvoMath.Clamp01(nearestEnemy / DangerRadius) * 40f;
                if (nearestEnemy < CharacterDefinition.Radius * 4f) score -= 1000f;
            }
            else
            {
                score += 40f;   // no live enemies at all
            }

            if (seenByEnemy) score -= 60f;

            // Mild pull toward team-mates, so a team does not scatter across the map. Small,
            // because a large one would stack the whole team on one spawn and make them a
            // grenade's worth of free kills.
            if (nearestFriend < float.MaxValue)
                score += SalvoMath.Clamp01(1f - nearestFriend / 30f) * 8f;

            float sinceUsed = match.SecondsSinceSpawnUsed(spawn);
            if (sinceUsed < ReuseCooldown)
                score -= (1f - sinceUsed / ReuseCooldown) * 25f;

            return score;
        }
    }
}
