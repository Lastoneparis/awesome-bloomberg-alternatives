using System.Collections.Generic;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    /// <summary>
    /// Small hand-built levels the tests assert against.
    /// </summary>
    /// <remarks>
    /// Built in code rather than loaded from a fixture file so that a test failure points at a
    /// line you can read, and so the geometry cannot drift away from the assertions that
    /// depend on it.
    /// </remarks>
    public static class TestWorlds
    {
        /// <summary>A 40 x 40 m floor at y = 0 with nothing on it.</summary>
        public static MapDefinition FlatArena()
        {
            var map = new MapDefinition
            {
                Id = "test_flat",
                DisplayNameKey = "map.test_flat",
                WorldId = "test_world",
                Bounds = new Aabb(new Vec3(-24f, -4f, -24f), new Vec3(24f, 20f, 24f)),
            };
            map.Brushes.Add(new MapBrush(new Aabb(new Vec3(-20f, -1f, -20f), new Vec3(20f, 0f, 20f)),
                                         SurfaceKind.Concrete));
            map.Spawns.Add(new SpawnPoint(new Vec3(-8f, 0f, 0f), 90f, Team.Alpha));
            map.Spawns.Add(new SpawnPoint(new Vec3(8f, 0f, 0f), 270f, Team.Bravo));
            return map;
        }

        /// <summary>
        /// The flat arena plus the shapes movement has to get right: a wall to slide along, a
        /// low step to walk over, a tall block to be stopped by, and a ceiling to crouch under.
        /// </summary>
        public static MapDefinition ObstacleCourse()
        {
            MapDefinition map = FlatArena();
            map.Id = "test_obstacles";

            // A wall running along Z at x = 4.
            map.Brushes.Add(new MapBrush(new Aabb(new Vec3(4f, 0f, -10f), new Vec3(4.5f, 3f, 10f))));
            // A 0.3 m platform from z = 6 outwards — under StepHeight, so walkable. It runs to
            // the far side of the arena on purpose: a short step would let a test "pass" by
            // sprinting straight over the top and landing back on the floor beyond it, which
            // proves nothing about whether the player ever stepped up.
            map.Brushes.Add(new MapBrush(new Aabb(new Vec3(-10f, 0f, 6f), new Vec3(0f, 0.3f, 18f))));
            // A 1.5 m block from z = -6 outwards — over StepHeight, so a wall.
            map.Brushes.Add(new MapBrush(new Aabb(new Vec3(-10f, 0f, -18f), new Vec3(0f, 1.5f, -6f))));
            // A ceiling 1.4 m above the floor: too low to stand, high enough to crouch.
            map.Brushes.Add(new MapBrush(new Aabb(new Vec3(-18f, 1.4f, -3f), new Vec3(-12f, 2.4f, 3f))));
            return map;
        }

        public static CollisionWorld FlatWorld() => new CollisionWorld(FlatArena());
        public static CollisionWorld ObstacleWorld() => new CollisionWorld(ObstacleCourse());

        /// <summary>Runs the movement model for a number of ticks with one held command.</summary>
        public static MovementState Simulate(MovementState state, PlayerInput input,
                                             CollisionWorld world, MovementTuning tuning,
                                             int ticks, float speedMultiplier = 1f)
        {
            for (int i = 0; i < ticks; i++)
            {
                input.Tick = i;
                MovementSimulation.Step(ref state, input, world, tuning, speedMultiplier,
                                        FixedClock.TickInterval);
            }
            return state;
        }

        public static PlayerInput Command(float right, float forward, float yawDegrees = 0f,
                                          InputButtons buttons = InputButtons.None) =>
            PlayerInput.Quantised(0, right, forward,
                                  new ViewAngles(0f, yawDegrees * SalvoMath.DegToRad), buttons);
    }
}
