using System.Collections.Generic;

namespace Salvo.Sim
{
    /// <summary>A player as the ballistics code sees them: an id, a side, and some boxes.</summary>
    public struct ShootableTarget
    {
        public PlayerId Id;
        public Team Team;
        public PlayerHitboxes Hitboxes;
        public bool IsAlive;
    }

    /// <summary>The outcome of one pellet or bullet.</summary>
    public struct ShotResult
    {
        public bool HitPlayer;
        public PlayerId Victim;
        public HitRegion Region;

        public bool HitWorld;
        public SurfaceKind Surface;

        /// <summary>Where the shot stopped — a player, a wall, or the end of its range.</summary>
        public Vec3 End;
        public Vec3 Normal;
        public float DistanceMetres;
    }

    /// <summary>
    /// Where bullets go and what they hit.
    /// </summary>
    /// <remarks>
    /// Hitscan only, for now, and that is a decision rather than an omission. Projectile
    /// travel time is supported by the data model (<see cref="WeaponDefinition.MuzzleVelocity"/>)
    /// but not yet by this code, because travel time interacts badly with lag compensation:
    /// rewinding the world by a client's latency is well defined for an instantaneous trace and
    /// genuinely ambiguous for a projectile that exists across several ticks. Getting that wrong
    /// produces the worst bug in a shooter — shots that visibly connect and do nothing — so it
    /// waits for a phase where it can be built and tested properly.
    ///
    /// <para>A weapon that sets a muzzle velocity would be fired as hitscan here, so
    /// <see cref="WeaponDefinition.Validate"/> rejects one. Content validation is the right
    /// place for that: it fails when the catalogue loads, where an author can act on it, rather
    /// than throwing in the middle of a match.</para>
    /// </remarks>
    public static class Ballistics
    {
        /// <summary>
        /// Fires one shot and appends a result per pellet.
        /// </summary>
        /// <param name="shooter">Excluded from the trace; nobody shoots themselves.</param>
        /// <param name="origin">Eye position, not the muzzle. The muzzle is where the effect is
        /// drawn; the eye is where the shot is computed, because that is what the player aimed
        /// with. Tracing from a muzzle offset means a player flush against a corner shoots the
        /// corner they can plainly see past.</param>
        /// <param name="random">
        /// Passed by reference and advanced. The caller owns the seed, because the client has
        /// to reproduce exactly this sequence to predict where its own shots went.
        /// </param>
        public static void Fire(WeaponDefinition weapon, PlayerId shooter, Team shooterTeam,
                                Vec3 origin, ViewAngles aim, float spreadRadians,
                                CollisionWorld world, IReadOnlyList<ShootableTarget> targets,
                                ref DeterministicRandom random, bool friendlyFire,
                                List<ShotResult> results)
        {
            int pellets = System.Math.Max(1, weapon.PelletsPerShot);
            float range = weapon.MaxRangeMetres > 0f ? weapon.MaxRangeMetres : 120f;

            for (int pellet = 0; pellet < pellets; pellet++)
            {
                Vec3 direction = ApplySpread(aim, spreadRadians, ref random);
                results.Add(TraceOne(shooter, shooterTeam, origin, direction, range,
                                     world, targets, friendlyFire));
            }
        }

        /// <summary>
        /// Perturbs an aim direction by a cone of the given half-angle.
        /// </summary>
        public static Vec3 ApplySpread(ViewAngles aim, float spreadRadians,
                                       ref DeterministicRandom random)
        {
            Vec3 forward = aim.Forward;
            if (spreadRadians <= 0f) return forward;

            random.NextPointInDisc(out float dx, out float dy);

            // A basis around the aim direction. Using the view's own right vector would tilt
            // the spread cone with the player's pitch; deriving it from world up keeps the
            // cone circular however the player is looking.
            Vec3 right = Vec3.Cross(Vec3.Up, forward);
            if (right.LengthSquared < 1e-6f) right = Vec3.Right;   // looking straight up or down
            right = right.Normalized;
            Vec3 up = Vec3.Cross(forward, right).Normalized;

            float tangent = (float)System.Math.Tan(spreadRadians);
            return (forward + right * (dx * tangent) + up * (dy * tangent)).Normalized;
        }

        /// <summary>
        /// Traces one ray against the world and every target, and returns whichever it reached
        /// first.
        /// </summary>
        /// <remarks>
        /// The world is traced first and its distance used to bound the player traces, so a
        /// player standing behind a wall cannot be hit through it. Getting that order wrong is
        /// how wallbangs appear in games that do not have them.
        /// </remarks>
        public static ShotResult TraceOne(PlayerId shooter, Team shooterTeam, Vec3 origin,
                                          Vec3 direction, float range, CollisionWorld world,
                                          IReadOnlyList<ShootableTarget> targets,
                                          bool friendlyFire)
        {
            TraceHit worldHit = world.Trace(origin, origin + direction * range, TraceMask.Bullets);
            float limit = worldHit.Hit ? worldHit.Fraction * range : range;

            PlayerId victim = PlayerId.None;
            var region = HitRegion.None;
            float best = limit;

            for (int i = 0; i < targets.Count; i++)
            {
                ShootableTarget target = targets[i];
                if (!target.IsAlive) continue;
                if (target.Id == shooter) continue;
                if (!friendlyFire && target.Team == shooterTeam && target.Team != Team.None) continue;

                if (!target.Hitboxes.Raycast(origin, direction, best,
                                             out float distance, out HitRegion hitRegion)) continue;
                if (distance >= best) continue;

                best = distance;
                victim = target.Id;
                region = hitRegion;
            }

            if (victim.IsValid)
            {
                return new ShotResult
                {
                    HitPlayer = true,
                    Victim = victim,
                    Region = region,
                    End = origin + direction * best,
                    Normal = -direction,
                    DistanceMetres = best,
                };
            }

            if (worldHit.Hit)
            {
                return new ShotResult
                {
                    HitWorld = true,
                    Surface = worldHit.Surface,
                    End = worldHit.Point,
                    Normal = worldHit.Normal,
                    DistanceMetres = worldHit.Fraction * range,
                };
            }

            return new ShotResult
            {
                End = origin + direction * range,
                Normal = -direction,
                DistanceMetres = range,
            };
        }
    }
}
