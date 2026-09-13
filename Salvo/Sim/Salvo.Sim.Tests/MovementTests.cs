using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    public class MovementTests
    {
        private static MovementTuning Tuning() => new MovementTuning();

        [Fact]
        public void TuningDefaultsAreSelfConsistent()
        {
            var problems = new System.Collections.Generic.List<string>();
            Tuning().Validate(problems);
            Assert.Empty(problems);
        }

        [Fact]
        public void StandingStillOnTheFloorStaysOnTheFloor()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            var state = MovementState.AtSpawn(new SpawnPoint(new Vec3(0f, 0f, 0f), 0f));
            state = TestWorlds.Simulate(state, TestWorlds.Command(0f, 0f), world, Tuning(), 128);

            Assert.True(state.IsGrounded);
            // Not "close to zero": exactly on the floor, within the skin width the collision
            // code deliberately leaves. A player who sinks a millimetre per second is a player
            // who falls through the map after ten minutes.
            Assert.InRange(state.Position.Y, -0.01f, 0.01f);
            Assert.InRange(state.HorizontalSpeed, 0f, 0.001f);
        }

        [Fact]
        public void PlayerAcceleratesToRunSpeedAndNoFurther()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            MovementTuning tuning = Tuning();
            var state = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            // Yaw 0 looks down +Z; full forward stick.
            state = TestWorlds.Simulate(state, TestWorlds.Command(0f, 1f), world, tuning, 64);

            Assert.True(state.HorizontalSpeed > tuning.RunSpeed * 0.97f,
                        $"expected to reach run speed, got {state.HorizontalSpeed:F3}");
            Assert.True(state.HorizontalSpeed <= tuning.RunSpeed + 0.01f,
                        $"exceeded run speed: {state.HorizontalSpeed:F3}");
            Assert.True(state.Position.Z > 4f, $"barely moved: z={state.Position.Z:F3}");
        }

        [Fact]
        public void DiagonalMovementIsNotFasterThanStraight()
        {
            // The classic bug: normalising per-axis lets a diagonal run at sqrt(2) times speed.
            CollisionWorld world = TestWorlds.FlatWorld();
            MovementTuning tuning = Tuning();

            var straight = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));
            straight = TestWorlds.Simulate(straight, TestWorlds.Command(0f, 1f), world, tuning, 64);

            var diagonal = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));
            diagonal = TestWorlds.Simulate(diagonal, TestWorlds.Command(1f, 1f), world, tuning, 64);

            // The diagonal is allowed to be slower (strafing is penalised) but never faster.
            Assert.True(diagonal.HorizontalSpeed <= straight.HorizontalSpeed + 0.01f,
                        $"diagonal {diagonal.HorizontalSpeed:F3} > straight {straight.HorizontalSpeed:F3}");
        }

        [Fact]
        public void WalkingIsSlowerThanRunningAndCrouchingSlowerStill()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            MovementTuning tuning = Tuning();

            float Run(InputButtons buttons)
            {
                var state = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));
                // Long enough for the crouch transition to complete before measuring.
                state = TestWorlds.Simulate(state, TestWorlds.Command(0f, 1f, 0f, buttons),
                                            world, tuning, 96);
                return state.HorizontalSpeed;
            }

            float running = Run(InputButtons.None);
            float walking = Run(InputButtons.Walk);
            float crouching = Run(InputButtons.Crouch);

            Assert.True(walking < running, $"walk {walking:F3} not slower than run {running:F3}");
            Assert.True(crouching < walking, $"crouch {crouching:F3} not slower than walk {walking:F3}");
        }

        [Fact]
        public void BackwardsIsSlowerThanForwards()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            MovementTuning tuning = Tuning();

            var forward = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));
            forward = TestWorlds.Simulate(forward, TestWorlds.Command(0f, 1f), world, tuning, 64);

            var back = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));
            back = TestWorlds.Simulate(back, TestWorlds.Command(0f, -1f), world, tuning, 64);

            Assert.True(back.HorizontalSpeed < forward.HorizontalSpeed,
                        $"retreating at {back.HorizontalSpeed:F3} vs advancing {forward.HorizontalSpeed:F3}");
        }

        [Fact]
        public void JumpLeavesTheGroundAndComesBackDown()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            MovementTuning tuning = Tuning();
            var state = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            PlayerInput jump = TestWorlds.Command(0f, 0f, 0f, InputButtons.Jump);
            float peak = 0f;
            bool leftGround = false;
            for (int i = 0; i < 128; i++)
            {
                jump.Tick = i;
                // Release the key after the first tick, so this also proves the jump is not
                // re-triggered by a held button.
                PlayerInput command = i == 0 ? jump : TestWorlds.Command(0f, 0f);
                command.Tick = i;
                MovementSimulation.Step(ref state, command, world, tuning, 1f, FixedClock.TickInterval);
                if (!state.IsGrounded) leftGround = true;
                peak = System.Math.Max(peak, state.Position.Y);
            }

            Assert.True(leftGround, "the jump never left the ground");
            Assert.True(peak > 0.8f, $"jump apex only {peak:F3} m");
            Assert.True(peak < 1.6f, $"jump apex {peak:F3} m is higher than the tuning implies");
            Assert.True(state.IsGrounded, "never landed again");
            Assert.InRange(state.Position.Y, -0.01f, 0.01f);
        }

        [Fact]
        public void FallingPlayerLandsOnTheFloorAndRecordsTheImpact()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            MovementTuning tuning = Tuning();
            var state = MovementState.AtSpawn(new SpawnPoint(new Vec3(0f, 12f, 0f), 0f));
            state.IsGrounded = false;

            float recordedImpact = 0f;
            PlayerInput idle = TestWorlds.Command(0f, 0f);
            for (int i = 0; i < 256 && !state.IsGrounded; i++)
            {
                idle.Tick = i;
                MovementSimulation.Step(ref state, idle, world, tuning, 1f, FixedClock.TickInterval);
                if (state.LandingImpactSpeed > 0f) recordedImpact = state.LandingImpactSpeed;
            }

            Assert.True(state.IsGrounded, "never landed");
            Assert.InRange(state.Position.Y, -0.01f, 0.01f);
            // v = sqrt(2gh) = sqrt(2 * 19.6 * 12) ~= 21.7 m/s, less whatever the last tick
            // clipped. Asserting a band rather than a value keeps this a physics check, not a
            // transcription of the implementation.
            Assert.InRange(recordedImpact, 18f, 23f);
        }

        [Fact]
        public void WallStopsForwardMotionButAllowsSlidingAlongIt()
        {
            CollisionWorld world = TestWorlds.ObstacleWorld();
            MovementTuning tuning = Tuning();

            // Facing +X, straight into the wall at x = 4.
            var head_on = MovementState.AtSpawn(new SpawnPoint(new Vec3(0f, 0f, 0f), 90f));
            head_on = TestWorlds.Simulate(head_on, TestWorlds.Command(0f, 1f, 90f), world, tuning, 128);

            float expectedStop = 4f - CharacterDefinition.Radius;
            Assert.True(head_on.Position.X < expectedStop + 0.05f,
                        $"walked into the wall: x={head_on.Position.X:F3}");
            Assert.True(head_on.Position.X > expectedStop - 0.2f,
                        $"stopped well short of the wall: x={head_on.Position.X:F3}");

            // Now at 45 degrees to it: should be stopped in X but still travelling in Z.
            var glancing = MovementState.AtSpawn(new SpawnPoint(new Vec3(0f, 0f, 0f), 45f));
            glancing = TestWorlds.Simulate(glancing, TestWorlds.Command(0f, 1f, 45f), world, tuning, 128);

            Assert.True(glancing.Position.X < expectedStop + 0.05f, "slid through the wall");
            Assert.True(glancing.Position.Z > 3f,
                        $"stopped dead against the wall instead of sliding: z={glancing.Position.Z:F3}");
        }

        [Fact]
        public void LowStepIsWalkedOverAndTallBlockIsNot()
        {
            CollisionWorld world = TestWorlds.ObstacleWorld();
            MovementTuning tuning = Tuning();

            // The 0.3 m step spans z in [6,8] at x in [-10,0]. Approach from z = 2 facing +Z.
            var onStep = MovementState.AtSpawn(new SpawnPoint(new Vec3(-5f, 0f, 2f), 0f));
            onStep = TestWorlds.Simulate(onStep, TestWorlds.Command(0f, 1f, 0f), world, tuning, 160);

            Assert.True(onStep.Position.Z > 6.5f,
                        $"never climbed the 0.3 m step: z={onStep.Position.Z:F3}");
            Assert.InRange(onStep.Position.Y, 0.28f, 0.34f);

            // The 1.5 m block spans z in [-8,-6]. Approach from z = -2 facing -Z.
            var atBlock = MovementState.AtSpawn(new SpawnPoint(new Vec3(-5f, 0f, -2f), 180f));
            atBlock = TestWorlds.Simulate(atBlock, TestWorlds.Command(0f, 1f, 180f), world, tuning, 160);

            Assert.True(atBlock.Position.Z > -6f - CharacterDefinition.Radius - 0.05f,
                        $"walked through the 1.5 m block: z={atBlock.Position.Z:F3}");
            Assert.InRange(atBlock.Position.Y, -0.01f, 0.05f);
        }

        [Fact]
        public void PlayerCannotStandUpUnderALowCeiling()
        {
            CollisionWorld world = TestWorlds.ObstacleWorld();
            MovementTuning tuning = Tuning();

            // The ceiling covers x in [-18,-12], z in [-3,3], from y = 1.4 up.
            var state = MovementState.AtSpawn(new SpawnPoint(new Vec3(-15f, 0f, 0f), 0f));

            // Crouch first...
            state = TestWorlds.Simulate(state, TestWorlds.Command(0f, 0f, 0f, InputButtons.Crouch),
                                        world, tuning, 64);
            Assert.True(state.CrouchAmount > 0.99f, "did not finish crouching");

            // ...then release. There is no headroom, so the stance must not recover.
            state = TestWorlds.Simulate(state, TestWorlds.Command(0f, 0f), world, tuning, 64);
            Assert.True(state.CrouchAmount > 0.99f,
                        $"stood up into the ceiling: crouch={state.CrouchAmount:F3}");
            Assert.True(state.Position.Y < 0.05f, "was pushed up through the ceiling");
        }

        [Fact]
        public void SimulationIsDeterministic()
        {
            // The property the whole prediction/reconciliation design rests on. If this ever
            // fails, client and server have quietly stopped agreeing and nothing else matters.
            CollisionWorld world = TestWorlds.ObstacleWorld();
            MovementTuning tuning = Tuning();

            MovementState Run()
            {
                var state = MovementState.AtSpawn(new SpawnPoint(new Vec3(-2f, 0f, 0f), 30f));
                var random = new DeterministicRandom(12345);
                for (int i = 0; i < 400; i++)
                {
                    var buttons = InputButtons.None;
                    if (random.NextFloat() < 0.05f) buttons |= InputButtons.Jump;
                    if (random.NextFloat() < 0.15f) buttons |= InputButtons.Crouch;
                    if (random.NextFloat() < 0.10f) buttons |= InputButtons.Walk;
                    PlayerInput command = PlayerInput.Quantised(
                        i,
                        random.NextFloat() * 2f - 1f,
                        random.NextFloat() * 2f - 1f,
                        new ViewAngles(random.NextFloat() - 0.5f, random.NextFloat() * SalvoMath.TwoPi),
                        buttons);
                    MovementSimulation.Step(ref state, command, world, tuning, 1f,
                                            FixedClock.TickInterval);
                }
                return state;
            }

            MovementState a = Run();
            MovementState b = Run();
            Assert.Equal(a.Position, b.Position);
            Assert.Equal(a.Velocity, b.Velocity);
            Assert.Equal(a.CrouchAmount, b.CrouchAmount);
        }

        [Fact]
        public void PlayerNeverEscapesTheLevelUnderRandomInput()
        {
            // A fuzz test, because every "player fell out of the map" bug I have ever seen
            // was found by a player, not by a unit test that checked one scripted path.
            CollisionWorld world = TestWorlds.ObstacleWorld();
            MovementTuning tuning = Tuning();

            for (int seed = 0; seed < 40; seed++)
            {
                var random = new DeterministicRandom((uint)(seed * 7919 + 1));
                var state = MovementState.AtSpawn(new SpawnPoint(new Vec3(0f, 0.2f, 0f), 0f));

                for (int i = 0; i < 600; i++)
                {
                    var buttons = InputButtons.None;
                    if (random.NextFloat() < 0.25f) buttons |= InputButtons.Jump;
                    if (random.NextFloat() < 0.20f) buttons |= InputButtons.Crouch;
                    PlayerInput command = PlayerInput.Quantised(
                        i,
                        random.NextFloat() * 2f - 1f,
                        random.NextFloat() * 2f - 1f,
                        new ViewAngles(0f, random.NextFloat() * SalvoMath.TwoPi),
                        buttons);
                    MovementSimulation.Step(ref state, command, world, tuning, 1f,
                                            FixedClock.TickInterval);

                    Assert.True(IsFinite(state.Position),
                                $"seed {seed} tick {i}: position went non-finite ({state.Position})");
                    Assert.True(state.Position.Y > -2f,
                                $"seed {seed} tick {i}: fell through the floor to y={state.Position.Y:F3}");
                    Assert.True(state.Position.Y < 8f,
                                $"seed {seed} tick {i}: launched to y={state.Position.Y:F3}");
                    // The floor is 40 m across; nothing should reach the edge at these speeds
                    // in ten seconds, let alone pass it.
                    Assert.True(System.Math.Abs(state.Position.X) < 21f
                                && System.Math.Abs(state.Position.Z) < 21f,
                                $"seed {seed} tick {i}: left the arena at {state.Position}");
                }
            }
        }

        private static bool IsFinite(Vec3 v) =>
            !float.IsNaN(v.X) && !float.IsInfinity(v.X)
            && !float.IsNaN(v.Y) && !float.IsInfinity(v.Y)
            && !float.IsNaN(v.Z) && !float.IsInfinity(v.Z);
    }
}
