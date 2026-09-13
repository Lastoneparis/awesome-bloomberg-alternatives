using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    public class NetworkTests
    {
        // ---- bit buffer ----------------------------------------------------------------

        [Fact]
        public void BitsRoundTripAtEveryWidth()
        {
            var writer = new BitWriter();
            var expected = new List<(uint value, int bits)>();
            var random = new DeterministicRandom(7);

            for (int i = 0; i < 2000; i++)
            {
                int bits = random.NextInt(1, 33);
                uint value = random.NextUInt();
                if (bits < 32) value &= (1u << bits) - 1u;
                writer.WriteBits(value, bits);
                expected.Add((value, bits));
            }

            var reader = new BitReader(writer.ToArray());
            for (int i = 0; i < expected.Count; i++)
                Assert.Equal(expected[i].value, reader.ReadBits(expected[i].bits));
        }

        [Fact]
        public void OversizedValuesAreMaskedNotLeakedIntoTheNextField()
        {
            // The failure this prevents is nasty: a value too wide for its field corrupts the
            // *following* field, so the symptom appears somewhere unrelated to the cause.
            var writer = new BitWriter();
            writer.WriteBits(0xFFFFFFFF, 4);
            writer.WriteBits(0xA, 4);

            var reader = new BitReader(writer.ToArray());
            Assert.Equal(0xFu, reader.ReadBits(4));
            Assert.Equal(0xAu, reader.ReadBits(4));
        }

        [Fact]
        public void QuantisedFloatsComeBackWithinTheirResolution()
        {
            var writer = new BitWriter();
            var random = new DeterministicRandom(11);
            var values = new List<float>();
            for (int i = 0; i < 500; i++)
            {
                float value = random.NextFloat(-128f, 128f);
                values.Add(value);
                writer.WriteQuantised(value, -128f, 128f, 16);
            }

            var reader = new BitReader(writer.ToArray());
            // 256 m across 65535 steps is about 3.9 mm; allow one step of rounding.
            const float resolution = 256f / 65535f;
            for (int i = 0; i < values.Count; i++)
            {
                float decoded = reader.ReadQuantised(-128f, 128f, 16);
                Assert.True(System.Math.Abs(decoded - values[i]) <= resolution,
                            $"{values[i]} came back as {decoded}");
            }
        }

        [Fact]
        public void AnglesRoundTripAndStayInRange()
        {
            var writer = new BitWriter();
            var random = new DeterministicRandom(13);
            var angles = new List<float>();
            for (int i = 0; i < 500; i++)
            {
                float angle = random.NextFloat(-SalvoMath.Pi, SalvoMath.Pi);
                angles.Add(angle);
                writer.WriteAngle(angle, 12);
            }

            var reader = new BitReader(writer.ToArray());
            float resolution = SalvoMath.TwoPi / 4095f;
            for (int i = 0; i < angles.Count; i++)
            {
                float decoded = reader.ReadAngle(12);
                // Compared with AngleDelta, not by value: which side of the wrap boundary a
                // value lands on is a rounding question, and -pi and +pi are the same angle.
                Assert.True(System.Math.Abs(SalvoMath.AngleDelta(angles[i], decoded)) <= resolution,
                            $"{angles[i]} came back as {decoded}");
            }
        }

        [Fact]
        public void ReadingPastTheEndThrowsRatherThanReturningRubbish()
        {
            var writer = new BitWriter();
            writer.WriteBits(1, 8);
            var reader = new BitReader(writer.ToArray());
            reader.ReadBits(8);
            Assert.Throws<System.InvalidOperationException>(() => reader.ReadBits(8));
        }

        // ---- snapshots -----------------------------------------------------------------

        private static WorldSnapshot MakeSnapshot(int tick, int players, uint seed)
        {
            var random = new DeterministicRandom(seed);
            var snapshot = new WorldSnapshot { Tick = tick, Phase = MatchPhase.Live };
            for (int i = 0; i < players; i++)
            {
                snapshot.Players.Add(new PlayerSnapshot
                {
                    Id = new PlayerId(i),
                    Team = i % 2 == 0 ? Team.Alpha : Team.Bravo,
                    Position = new Vec3(random.NextFloat(-40f, 40f), random.NextFloat(0f, 4f),
                                        random.NextFloat(-40f, 40f)),
                    View = new ViewAngles(random.NextFloat(-1.5f, 1.5f),
                                          random.NextFloat(-3.1f, 3.1f)),
                    CrouchAmount = random.NextFloat(),
                    IsAlive = random.NextBool(0.8f),
                    IsGrounded = random.NextBool(0.7f),
                    HeldSlot = (WeaponSlot)random.NextInt(3),
                    Health = (byte)random.NextInt(256),
                    Armour = (byte)random.NextInt(256),
                    Magazine = (ushort)random.NextInt(1024),
                });
            }
            return snapshot;
        }

        private static void AssertSnapshotsAgree(WorldSnapshot expected, WorldSnapshot actual)
        {
            Assert.Equal(expected.Tick, actual.Tick);
            Assert.Equal(expected.Phase, actual.Phase);
            Assert.Equal(expected.Players.Count, actual.Players.Count);
            for (int i = 0; i < expected.Players.Count; i++)
            {
                PlayerSnapshot a = expected.Players[i];
                Assert.True(actual.TryGet(a.Id, out PlayerSnapshot b), $"player {a.Id} went missing");
                Assert.True(Vec3.Distance(a.Position, b.Position) < 0.02f,
                            $"{a.Id} position {a.Position} -> {b.Position}");
                Assert.True(System.Math.Abs(SalvoMath.AngleDelta(a.View.Yaw, b.View.Yaw)) < 0.01f);
                Assert.Equal(a.IsAlive, b.IsAlive);
                Assert.Equal(a.Health, b.Health);
                Assert.Equal(a.Armour, b.Armour);
                Assert.Equal(a.HeldSlot, b.HeldSlot);
                Assert.Equal(a.Magazine, b.Magazine);
                Assert.Equal(a.Team, b.Team);
            }
        }

        [Fact]
        public void FullSnapshotRoundTrips()
        {
            WorldSnapshot original = MakeSnapshot(100, 10, 3);
            var writer = new BitWriter();
            SnapshotCodec.Encode(writer, original, null);

            var decoded = new WorldSnapshot();
            Assert.True(SnapshotCodec.Decode(new BitReader(writer.ToArray()), decoded, _ => null));
            AssertSnapshotsAgree(original, decoded);
        }

        [Fact]
        public void DeltaSnapshotRoundTrips()
        {
            WorldSnapshot baseline = MakeSnapshot(100, 10, 3);
            WorldSnapshot next = MakeSnapshot(101, 10, 9);

            var writer = new BitWriter();
            SnapshotCodec.Encode(writer, next, baseline);

            var decoded = new WorldSnapshot();
            Assert.True(SnapshotCodec.Decode(new BitReader(writer.ToArray()), decoded,
                                             tick => tick == baseline.Tick ? baseline : null));
            AssertSnapshotsAgree(next, decoded);
        }

        [Fact]
        public void AnUnchangedWorldCostsAlmostNothing()
        {
            // The claim delta encoding is making. If this ever stops being true the bandwidth
            // budget is gone and the cause will not be obvious.
            WorldSnapshot baseline = MakeSnapshot(100, 10, 3);
            var identical = new WorldSnapshot().CopyFrom(baseline);
            identical.Tick = 101;

            var full = new BitWriter();
            SnapshotCodec.Encode(full, identical, null);

            var delta = new BitWriter();
            SnapshotCodec.Encode(delta, identical, baseline);

            Assert.True(delta.BytesWritten * 4 < full.BytesWritten,
                        $"delta {delta.BytesWritten}B vs full {full.BytesWritten}B — "
                        + "delta encoding is not paying for itself");
        }

        [Fact]
        public void ADeltaWithoutItsBaselineIsRejectedRatherThanMisread()
        {
            // Decoding against the wrong baseline produces plausible, wrong positions. Silent
            // corruption is far worse than a dropped packet, so this must fail loudly.
            WorldSnapshot baseline = MakeSnapshot(100, 10, 3);
            WorldSnapshot next = MakeSnapshot(101, 10, 9);
            var writer = new BitWriter();
            SnapshotCodec.Encode(writer, next, baseline);

            var decoded = new WorldSnapshot();
            Assert.False(SnapshotCodec.Decode(new BitReader(writer.ToArray()), decoded, _ => null));
        }

        [Fact]
        public void ATenPlayerSnapshotFitsTheBandwidthBudget()
        {
            // PROJECT_PLAN.md budgets 64 kbit/s downstream at 10v10. At 20 snapshots a second
            // that is 400 bytes per snapshot, and this is the worst case: every player moving,
            // nothing shared with the baseline.
            WorldSnapshot baseline = MakeSnapshot(100, 10, 3);
            WorldSnapshot moving = MakeSnapshot(101, 10, 4);
            var writer = new BitWriter();
            SnapshotCodec.Encode(writer, moving, baseline);

            Assert.True(writer.BytesWritten <= 400,
                        $"a 10-player snapshot is {writer.BytesWritten} bytes; "
                        + "the budget is 400 at 20 Hz for 64 kbit/s");
        }

        // ---- the simulated link ---------------------------------------------------------

        [Fact]
        public void PerfectLinkDeliversEverythingInOrder()
        {
            var link = SimulatedLink.Perfect();
            for (int i = 0; i < 100; i++) link.Send(i, new byte[] { (byte)i });

            var delivered = new List<byte>();
            for (int tick = 0; tick <= 120; tick++)
                foreach (byte[] packet in link.Receive(tick)) delivered.Add(packet[0]);

            Assert.Equal(100, delivered.Count);
            for (int i = 0; i < 100; i++) Assert.Equal((byte)i, delivered[i]);
        }

        [Fact]
        public void LatencyActuallyDelaysDelivery()
        {
            var link = new SimulatedLink(1, latencySeconds: 0.1f);
            link.Send(0, new byte[] { 42 });

            // 100 ms at 64 Hz is about 6 ticks. Nothing before then.
            for (int tick = 0; tick < 5; tick++)
                Assert.Empty(link.Receive(tick));

            var arrived = new List<byte[]>();
            for (int tick = 5; tick < 20; tick++) arrived.AddRange(link.Receive(tick));
            Assert.Single(arrived);
        }

        [Fact]
        public void LossDropsRoughlyTheConfiguredShare()
        {
            var link = new SimulatedLink(99, lossChance: 0.2f);
            for (int i = 0; i < 5000; i++) link.Send(0, new byte[] { 1 });
            double dropped = link.PacketsDropped / 5000.0;
            Assert.InRange(dropped, 0.17, 0.23);
        }

        [Fact]
        public void TheLinkIsDeterministic()
        {
            int Run()
            {
                var link = SimulatedLink.Poor(seed: 555);
                for (int i = 0; i < 1000; i++) link.Send(i, new byte[] { (byte)i });
                return link.PacketsDropped;
            }
            Assert.Equal(Run(), Run());
        }

        // ---- prediction and reconciliation ----------------------------------------------

        [Fact]
        public void PredictionThatMatchesTheServerCausesNoCorrection()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            var tuning = new MovementTuning();
            var initial = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            var client = new ClientPrediction(world, tuning, initial);
            MovementState server = initial;

            for (int tick = 0; tick < 64; tick++)
            {
                PlayerInput input = PlayerInput.Quantised(tick, 0.3f, 1f,
                                                          new ViewAngles(0f, 0.4f), InputButtons.None);
                client.Predict(input, 1f);
                MovementSimulation.Step(ref server, input, world, tuning, 1f, FixedClock.TickInterval);
                client.Reconcile(tick, server, _ => 1f);
            }

            Assert.Equal(0, client.Reconciliations);
            Assert.True(Vec3.Distance(client.State.Position, server.Position) < 0.001f);
        }

        [Fact]
        public void AWrongPredictionIsCorrectedAndTheReplayCatchesUp()
        {
            // The behaviour that makes a correction invisible: after reconciling to a server
            // state from several ticks ago, replaying the unacknowledged inputs must land the
            // client where it would have been, not a round trip behind.
            CollisionWorld world = TestWorlds.FlatWorld();
            var tuning = new MovementTuning();
            var initial = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            var client = new ClientPrediction(world, tuning, initial);
            MovementState server = initial;
            var inputs = new List<PlayerInput>();

            for (int tick = 0; tick < 40; tick++)
            {
                PlayerInput input = PlayerInput.Quantised(tick, 0f, 1f, new ViewAngles(0f, 0f),
                                                          InputButtons.None);
                inputs.Add(input);
                client.Predict(input, 1f);
                MovementSimulation.Step(ref server, input, world, tuning, 1f, FixedClock.TickInterval);
            }

            // Shove the client sideways so its prediction is definitely wrong.
            MovementState wrong = client.State;
            wrong.Position += new Vec3(3f, 0f, 0f);
            client.Reset(wrong);
            for (int tick = 0; tick < 40; tick++) client.Predict(inputs[tick], 1f);

            Assert.True(client.Reconcile(20, ServerStateAt(world, tuning, initial, inputs, 20), _ => 1f));
            Assert.True(client.Reconciliations > 0);

            // After replaying ticks 21..39 the client must agree with the server's tick-39 state.
            MovementState expected = ServerStateAt(world, tuning, initial, inputs, 39);
            Assert.True(Vec3.Distance(client.State.Position, expected.Position) < 0.01f,
                        $"replay landed at {client.State.Position}, server says {expected.Position}");
        }

        private static MovementState ServerStateAt(CollisionWorld world, MovementTuning tuning,
                                                   MovementState initial,
                                                   List<PlayerInput> inputs, int throughTick)
        {
            MovementState state = initial;
            for (int i = 0; i <= throughTick; i++)
                MovementSimulation.Step(ref state, inputs[i], world, tuning, 1f,
                                        FixedClock.TickInterval);
            return state;
        }

        // ---- interpolation ---------------------------------------------------------------

        [Fact]
        public void InterpolationSmoothsBetweenSnapshots()
        {
            var interpolator = new SnapshotInterpolator { DelaySeconds = 0.1f };
            var id = new PlayerId(0);

            for (int i = 0; i <= 10; i++)
            {
                var snapshot = new WorldSnapshot { Tick = i * 3 };
                snapshot.Players.Add(new PlayerSnapshot
                {
                    Id = id, Position = new Vec3(i * 3f, 0f, 0f), IsAlive = true,
                });
                interpolator.Add(snapshot);
            }

            // Render moment sits 0.1 s (about 6 ticks) behind tick 24, so around tick 18.
            Assert.True(interpolator.TryGet(id, 24, out PlayerSnapshot result));
            Assert.InRange(result.Position.X, 16f, 20f);
        }

        [Fact]
        public void InterpolationTakesTheShortWayRoundTheWrap()
        {
            // Lerping raw yaw sends a player spinning 350 degrees when they turn 10, and it
            // happens every time someone faces roughly north.
            var interpolator = new SnapshotInterpolator { DelaySeconds = 0f };
            var id = new PlayerId(0);

            var first = new WorldSnapshot { Tick = 0 };
            first.Players.Add(new PlayerSnapshot
            {
                Id = id, View = new ViewAngles(0f, SalvoMath.Pi - 0.1f), IsAlive = true,
            });
            var second = new WorldSnapshot { Tick = 10 };
            second.Players.Add(new PlayerSnapshot
            {
                Id = id, View = new ViewAngles(0f, -SalvoMath.Pi + 0.1f), IsAlive = true,
            });
            interpolator.Add(first);
            interpolator.Add(second);

            Assert.True(interpolator.TryGet(id, 5, out PlayerSnapshot midpoint));
            // Halfway across a 0.2 rad gap through the wrap is near pi, not near zero.
            Assert.True(System.Math.Abs(midpoint.View.Yaw) > 3.0f,
                        $"interpolated the long way round: yaw={midpoint.View.Yaw:F3}");
        }

        // ---- the local player's authoritative state ------------------------------------

        [Fact]
        public void OwnStateRoundTripsIncludingVelocity()
        {
            // Velocity is the field reconciliation cannot work without. Its absence turned 1%
            // packet loss into a 40% correction rate, because every replay started from the
            // client's current momentum instead of the server's momentum at the acknowledged
            // tick — so each correction produced a fresh error rather than removing one.
            var original = new MovementState
            {
                Position = new Vec3(12.25f, 3.5f, -7.125f),
                Velocity = new Vec3(-4.5f, 6.25f, 2.75f),
                CrouchAmount = 0.5f,
                IsGrounded = true,
                TimeSinceGrounded = 0.25f,
                JumpBufferRemaining = 0.0625f,
                JumpConsumed = true,
                StrideDistance = 1.5f,
                View = new ViewAngles(0.2f, 1.1f),
            };

            var writer = new BitWriter();
            var player = new PlayerRuntime { Movement = original };
            NetServer.WriteOwnState(writer, player);

            MovementState decoded = default;
            Assert.True(NetServer.ReadOwnState(new BitReader(writer.ToArray()), ref decoded));

            Assert.True(Vec3.Distance(original.Position, decoded.Position) < 0.002f);
            Assert.True(Vec3.Distance(original.Velocity, decoded.Velocity) < 0.005f,
                        $"velocity {original.Velocity} came back as {decoded.Velocity}");
            Assert.Equal(original.IsGrounded, decoded.IsGrounded);
            Assert.Equal(original.JumpConsumed, decoded.JumpConsumed);
            Assert.True(System.Math.Abs(original.CrouchAmount - decoded.CrouchAmount) < 0.01f);
            Assert.True(System.Math.Abs(original.TimeSinceGrounded - decoded.TimeSinceGrounded) < 0.01f);
        }

        [Fact]
        public void AbsentOwnStateIsReportedRatherThanDecodedAsZero()
        {
            var writer = new BitWriter();
            NetServer.WriteOwnState(writer, null);
            MovementState decoded = default;
            Assert.False(NetServer.ReadOwnState(new BitReader(writer.ToArray()), ref decoded));
        }

        [Fact]
        public void ReplayingWithTheWrongSpeedMultiplierDivergesFromTheServer()
        {
            // Aiming halves movement speed. A client that replays a past command using its
            // current aim state rather than the command's own will disagree with the server
            // over any stretch where the two differ — which is most of a firefight.
            CollisionWorld world = TestWorlds.FlatWorld();
            var tuning = new MovementTuning();
            var initial = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            MovementState aiming = initial, notAiming = initial;
            for (int tick = 0; tick < 64; tick++)
            {
                PlayerInput input = PlayerInput.Quantised(tick, 0f, 1f, new ViewAngles(0f, 0f),
                                                          InputButtons.Aim);
                MovementSimulation.Step(ref aiming, input, world, tuning, 0.5f,
                                        FixedClock.TickInterval);
                MovementSimulation.Step(ref notAiming, input, world, tuning, 1f,
                                        FixedClock.TickInterval);
            }

            Assert.True(Vec3.Distance(aiming.Position, notAiming.Position) > 1f,
                        "the speed multiplier made no difference, so this test proves nothing");
        }

        [Fact]
        public void TheSpeedMultiplierComesFromTheCommandNotThePlayersCurrentState()
        {
            var weapon = new WeaponDefinition
            {
                Id = "w", DisplayNameKey = "w", MoveSpeedMultiplier = 1f,
                AdsMoveSpeedMultiplier = 0.5f,
            };
            Assert.Equal(1f, PlayerRuntime.SpeedMultiplierFor(weapon, aiming: false), 4);
            Assert.Equal(0.5f, PlayerRuntime.SpeedMultiplierFor(weapon, aiming: true), 4);
            // A missing weapon must not stop the player moving.
            Assert.Equal(1f, PlayerRuntime.SpeedMultiplierFor(null, aiming: true), 4);
        }

        [Fact]
        public void OutOfOrderSnapshotsAreInsertedNotAppended()
        {
            var interpolator = new SnapshotInterpolator { DelaySeconds = 0f };
            var id = new PlayerId(0);

            void Add(int tick, float x)
            {
                var snapshot = new WorldSnapshot { Tick = tick };
                snapshot.Players.Add(new PlayerSnapshot { Id = id, Position = new Vec3(x, 0f, 0f) });
                interpolator.Add(snapshot);
            }

            Add(0, 0f);
            Add(20, 20f);
            Add(10, 10f);   // arrives late

            Assert.True(interpolator.TryGet(id, 5, out PlayerSnapshot result));
            // If the buffer were left unsorted, the pair straddling tick 5 would be wrong and
            // the player would appear to jump backwards.
            Assert.InRange(result.Position.X, 4f, 6f);
        }
    }
}
