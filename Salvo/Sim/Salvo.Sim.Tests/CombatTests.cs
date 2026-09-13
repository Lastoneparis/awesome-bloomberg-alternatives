using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    public class CombatTests
    {
        private static WeaponDefinition Rifle() => new WeaponDefinition
        {
            Id = "test_rifle",
            DisplayNameKey = "weapon.test_rifle",
            Class = WeaponClass.AssaultRifle,
            FireMode = FireMode.Automatic,
            BaseDamage = 26f,
            HeadshotMultiplier = 3f,
            FalloffStartMetres = 25f,
            FalloffEndMetres = 60f,
            FalloffFloor = 0.6f,
            ArmourPiercing = 0.3f,
            RoundsPerMinute = 600f,
            MagazineSize = 30,
            ReserveAmmo = 120,
            ReloadSeconds = 2.0f,
            EmptyReloadSeconds = 2.6f,
            HipSpreadRadians = 0.02f,
            AdsSpreadRadians = 0.002f,
            SpreadPerShot = 0.004f,
            MaxSpreadRadians = 0.09f,
            SpreadRecoveryPerSecond = 0.14f,
            SpreadRecoveryDelaySeconds = 0.22f,
            MaxRangeMetres = 120f,
        };

        // ---- hitboxes ----------------------------------------------------------------

        [Fact]
        public void EveryRegionIsReachableOnAStandingPlayer()
        {
            // The bug this exists to catch: a head hitbox that no ray can ever reach because
            // another box encloses it. It is invisible in play — headshots simply never happen
            // — and it is the sort of thing only an explicit test finds.
            var target = PlayerHitboxes.For(Vec3.Zero, CharacterDefinition.StandingHeight,
                                            new ViewAngles(0f, 0f));
            var seen = new HashSet<HitRegion>();

            // Sweep a wall of rays from 6 m away, straight along +X at the player at origin.
            for (int step = 0; step <= 400; step++)
            {
                float height = step / 400f * (CharacterDefinition.StandingHeight + 0.2f);
                Vec3 origin = new Vec3(-6f, height, 0f);
                if (target.Raycast(origin, Vec3.Right, 20f, out _, out HitRegion region))
                    seen.Add(region);
            }

            Assert.Contains(HitRegion.Head, seen);
            Assert.Contains(HitRegion.Torso, seen);
            Assert.Contains(HitRegion.Legs, seen);
        }

        [Fact]
        public void CrouchingShrinksTheTargetAndLowersTheHead()
        {
            var standing = PlayerHitboxes.For(Vec3.Zero, CharacterDefinition.StandingHeight,
                                              new ViewAngles(0f, 0f));
            var crouched = PlayerHitboxes.For(Vec3.Zero, CharacterDefinition.CrouchingHeight,
                                              new ViewAngles(0f, 0f));

            Assert.True(crouched.Head.Centre.Y < standing.Head.Centre.Y,
                        "crouching did not lower the head");
            Assert.True(crouched.Whole.Max.Y < standing.Whole.Max.Y,
                        "crouching did not shrink the silhouette");
        }

        [Fact]
        public void NoHitboxEnclosesAnother()
        {
            // The invariant that keeps every region reachable. A nested box is always the
            // nearer one, so whichever box encloses another makes the enclosed region
            // impossible to hit — silently, and from every angle.
            var t = PlayerHitboxes.For(Vec3.Zero, CharacterDefinition.StandingHeight,
                                       new ViewAngles(0f, 0f));

            Assert.False(Encloses(t.Legs, t.Torso), "legs enclose the torso");
            Assert.False(Encloses(t.Torso, t.Legs), "torso encloses the legs");
            Assert.False(Encloses(t.Torso, t.Head), "torso encloses the head");
            Assert.False(Encloses(t.Legs, t.Head), "legs enclose the head");

            // Stacked, so a frontal ray at a given height finds exactly one region.
            Vec3 chest = new Vec3(-6f, CharacterDefinition.StandingHeight * 0.7f, 0f);
            Assert.True(t.Raycast(chest, Vec3.Right, 20f, out float distance, out HitRegion region));
            Assert.Equal(HitRegion.Torso, region);
            Assert.InRange(distance, 6f - CharacterDefinition.Radius - 0.01f,
                                     6f - CharacterDefinition.Radius + 0.01f);

            Vec3 shin = new Vec3(-6f, CharacterDefinition.StandingHeight * 0.2f, 0f);
            Assert.True(t.Raycast(shin, Vec3.Right, 20f, out _, out HitRegion shinRegion));
            Assert.Equal(HitRegion.Legs, shinRegion);
        }

        private static bool Encloses(Aabb outer, Aabb inner) =>
            outer.Min.X <= inner.Min.X && outer.Max.X >= inner.Max.X
            && outer.Min.Y <= inner.Min.Y && outer.Max.Y >= inner.Max.Y
            && outer.Min.Z <= inner.Min.Z && outer.Max.Z >= inner.Max.Z;

        // ---- damage ------------------------------------------------------------------

        [Fact]
        public void DamageFallsOffWithRangeButNeverBelowTheFloor()
        {
            WeaponDefinition rifle = Rifle();
            float close = rifle.DamageAtRange(5f);
            float mid = rifle.DamageAtRange(40f);
            float far = rifle.DamageAtRange(200f);

            Assert.Equal(rifle.BaseDamage, close, 3);
            Assert.True(mid < close && mid > far, $"falloff is not monotonic: {close}/{mid}/{far}");
            Assert.Equal(rifle.BaseDamage * rifle.FalloffFloor, far, 3);
        }

        [Fact]
        public void HeadshotsHurtMoreThanTorsoAndLimbsLess()
        {
            WeaponDefinition rifle = Rifle();
            var vitals = VitalsState.Spawn(new GameModeDefinition { StartingHealth = 1000f });

            float Damage(HitRegion region) => DamageModel
                .Resolve(new PlayerId(0), new PlayerId(1), rifle, region, 10f, vitals,
                         Vec3.Zero, Vec3.Right, 0).HealthDamage;

            Assert.True(Damage(HitRegion.Head) > Damage(HitRegion.Torso));
            Assert.True(Damage(HitRegion.Torso) > Damage(HitRegion.Legs));
        }

        [Fact]
        public void ArmourReducesDamageAndIsConsumedDoingIt()
        {
            DamageModel.SplitAcrossArmour(100f, armour: 50f, piercing: 0f,
                                          out float toHealth, out float toArmour);
            Assert.True(toHealth < 100f, "armour absorbed nothing");
            Assert.True(toArmour > 0f, "armour took no wear");
            // Nothing may be created or destroyed: what the armour absorbed is exactly what the
            // health was spared.
            Assert.Equal(100f, toHealth + toArmour, 3);
        }

        [Fact]
        public void ArmourPiercingIgnoresArmourInProportion()
        {
            DamageModel.SplitAcrossArmour(100f, armour: 100f, piercing: 0f,
                                          out float blockedHealth, out _);
            DamageModel.SplitAcrossArmour(100f, armour: 100f, piercing: 1f,
                                          out float piercedHealth, out float piercedArmour);

            Assert.Equal(100f, piercedHealth, 3);
            Assert.Equal(0f, piercedArmour, 3);
            Assert.True(piercedHealth > blockedHealth,
                        "full armour-piercing did no better than none");
        }

        [Fact]
        public void ExhaustedArmourStopsProtecting()
        {
            // The overflow path: 1 point of armour must not block 50 points of damage.
            DamageModel.SplitAcrossArmour(100f, armour: 1f, piercing: 0f,
                                          out float toHealth, out float toArmour);
            Assert.Equal(1f, toArmour, 3);
            Assert.Equal(99f, toHealth, 3);
        }

        [Fact]
        public void DamageEventNeverClaimsMoreThanTheVictimHad()
        {
            WeaponDefinition rifle = Rifle();
            var vitals = new VitalsState { Health = 8f, MaxHealth = 100f, Armour = 0f, IsAlive = true };
            DamageEvent hit = DamageModel.Resolve(new PlayerId(0), new PlayerId(1), rifle,
                                                  HitRegion.Head, 2f, vitals, Vec3.Zero,
                                                  Vec3.Right, 0);

            Assert.True(hit.WasFatal);
            Assert.Equal(8f, hit.HealthDamage, 3);
        }

        [Fact]
        public void FallDamageIsFreeThenRampsThenKills()
        {
            var tuning = new MovementTuning();
            Assert.Equal(0f, DamageModel.FallDamage(tuning.SafeFallSpeed, tuning, 100f), 3);
            Assert.Equal(0f, DamageModel.FallDamage(3f, tuning, 100f), 3);

            float middling = DamageModel.FallDamage(
                (tuning.SafeFallSpeed + tuning.LethalFallSpeed) * 0.5f, tuning, 100f);
            Assert.InRange(middling, 1f, 99f);

            Assert.Equal(100f, DamageModel.FallDamage(tuning.LethalFallSpeed, tuning, 100f), 3);
            Assert.Equal(100f, DamageModel.FallDamage(999f, tuning, 100f), 3);
        }

        [Fact]
        public void ApplyKillsExactlyOnce()
        {
            var vitals = new VitalsState { Health = 10f, MaxHealth = 100f, IsAlive = true };
            var lethal = new DamageEvent { HealthDamage = 50f };

            Assert.True(DamageModel.Apply(ref vitals, lethal));
            Assert.False(vitals.IsAlive);
            Assert.Equal(0f, vitals.Health);
            // A second hit on a corpse must not register as another kill, or every kill in a
            // firefight gets credited two or three times.
            Assert.False(DamageModel.Apply(ref vitals, lethal));
        }

        // ---- weapon state ------------------------------------------------------------

        [Fact]
        public void SemiAutomaticNeedsTheTriggerReleasedBetweenShots()
        {
            WeaponDefinition pistol = Rifle();
            pistol.FireMode = FireMode.Semi;
            pistol.RoundsPerMinute = 1200f;   // cooldown shorter than a tick, so only the
                                              // trigger rule can limit the rate
            var state = WeaponState.Fresh(pistol);

            int shots = 0;
            for (int i = 0; i < 64; i++)
            {
                if (state.CanFire(pistol)) { state.ConsumeShot(pistol); shots++; }
                state.Tick(pistol, triggerDown: true, FixedClock.TickInterval);
            }
            Assert.Equal(1, shots);

            // Release and pull again: exactly one more.
            state.Tick(pistol, triggerDown: false, FixedClock.TickInterval);
            Assert.True(state.CanFire(pistol));
        }

        [Fact]
        public void AutomaticFiresAtItsStatedRate()
        {
            WeaponDefinition rifle = Rifle();   // 600 rpm = 10 rounds/second
            var state = WeaponState.Fresh(rifle);

            int shots = 0;
            for (int i = 0; i < FixedClock.TicksPerSecond; i++)
            {
                if (state.CanFire(rifle)) { state.ConsumeShot(rifle); shots++; }
                state.Tick(rifle, triggerDown: true, FixedClock.TickInterval);
            }
            // 10 per second, give or take the tick the cooldown lands on.
            Assert.InRange(shots, 9, 11);
        }

        [Fact]
        public void MagazineEmptiesAndReloadRefillsFromReserve()
        {
            WeaponDefinition rifle = Rifle();
            var state = WeaponState.Fresh(rifle);

            for (int i = 0; i < 600 && state.Magazine > 0; i++)
            {
                if (state.CanFire(rifle)) state.ConsumeShot(rifle);
                state.Tick(rifle, triggerDown: true, FixedClock.TickInterval);
            }
            Assert.Equal(0, state.Magazine);
            Assert.False(state.CanFire(rifle));

            Assert.True(state.CanReload(rifle));
            state.BeginReload(rifle);
            // An empty reload is the slow one.
            Assert.Equal(rifle.EmptyReloadSeconds, state.ActionRemaining, 3);

            for (int i = 0; i < 400 && state.IsReloading; i++)
                state.Tick(rifle, triggerDown: false, FixedClock.TickInterval);

            Assert.Equal(rifle.MagazineSize, state.Magazine);
            Assert.Equal(rifle.ReserveAmmo - rifle.MagazineSize, state.Reserve);
        }

        [Fact]
        public void ReloadNeverManufacturesAmmunition()
        {
            WeaponDefinition rifle = Rifle();
            rifle.ReserveAmmo = 7;   // less than a magazine
            var state = WeaponState.Fresh(rifle);
            state.Magazine = 0;

            state.BeginReload(rifle);
            for (int i = 0; i < 400 && state.IsReloading; i++)
                state.Tick(rifle, triggerDown: false, FixedClock.TickInterval);

            Assert.Equal(7, state.Magazine);
            Assert.Equal(0, state.Reserve);
            Assert.False(state.CanReload(rifle));
        }

        [Fact]
        public void SprayClimbsWhileHeldAndResetsOnRelease()
        {
            WeaponDefinition rifle = Rifle();
            var state = WeaponState.Fresh(rifle);
            var movement = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            float first = state.CurrentSpread(rifle, movement, aiming: true);
            for (int i = 0; i < 64; i++)
            {
                if (state.CanFire(rifle)) state.ConsumeShot(rifle);
                state.Tick(rifle, triggerDown: true, FixedClock.TickInterval);
            }
            float afterSpray = state.CurrentSpread(rifle, movement, aiming: true);
            Assert.True(afterSpray > first * 2f,
                        $"spread barely grew during a spray: {first:F4} -> {afterSpray:F4}");

            for (int i = 0; i < FixedClock.TicksPerSecond * 4; i++)
                state.Tick(rifle, triggerDown: false, FixedClock.TickInterval);
            float recovered = state.CurrentSpread(rifle, movement, aiming: true);
            Assert.True(recovered < afterSpray * 0.5f,
                        $"spread did not recover: {afterSpray:F4} -> {recovered:F4}");
            Assert.Equal(0, state.ShotsInBurst);
        }

        [Fact]
        public void MovingAndJumpingAreLessAccurateThanStandingStill()
        {
            WeaponDefinition rifle = Rifle();
            var state = WeaponState.Fresh(rifle);

            var still = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));
            var running = still; running.Velocity = new Vec3(0f, 0f, 5.6f);
            var airborne = still; airborne.IsGrounded = false;

            float stillSpread = state.CurrentSpread(rifle, still, aiming: false);
            float runSpread = state.CurrentSpread(rifle, running, aiming: false);
            float airSpread = state.CurrentSpread(rifle, airborne, aiming: false);

            Assert.True(runSpread > stillSpread, "running was as accurate as standing");
            Assert.True(airSpread > runSpread, "jumping was more accurate than running");
        }

        [Fact]
        public void AimingIsMoreAccurateThanHipFire()
        {
            WeaponDefinition rifle = Rifle();
            var state = WeaponState.Fresh(rifle);
            var still = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            Assert.True(state.CurrentSpread(rifle, still, aiming: true)
                        < state.CurrentSpread(rifle, still, aiming: false));
        }

        [Fact]
        public void BurstFireStopsAfterItsBurstCount()
        {
            WeaponDefinition burst = Rifle();
            burst.FireMode = FireMode.Burst;
            burst.BurstCount = 3;
            burst.BurstDelaySeconds = 0.4f;
            burst.RoundsPerMinute = 900f;
            var state = WeaponState.Fresh(burst);

            int shots = 0;
            // A fifth of a second: long enough for three rounds at 900 rpm, far too short for
            // the between-burst delay.
            for (int i = 0; i < 13; i++)
            {
                if (state.CanFire(burst)) { state.ConsumeShot(burst); shots++; }
                state.Tick(burst, triggerDown: true, FixedClock.TickInterval);
            }
            Assert.Equal(3, shots);
        }

        // ---- ballistics --------------------------------------------------------------

        private static List<ShootableTarget> OneTarget(Vec3 feet, Team team = Team.Bravo,
                                                       bool alive = true) =>
            new List<ShootableTarget>
            {
                new ShootableTarget
                {
                    Id = new PlayerId(1),
                    Team = team,
                    IsAlive = alive,
                    Hitboxes = PlayerHitboxes.For(feet, CharacterDefinition.StandingHeight,
                                                  new ViewAngles(0f, 0f)),
                }
            };

        [Fact]
        public void PerfectlyAimedShotAtAnExposedTargetConnects()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            var targets = OneTarget(new Vec3(10f, 0f, 0f));

            Vec3 eye = new Vec3(0f, 1.68f, 0f);
            // Aim at the target's chest, not at its feet.
            ViewAngles aim = ViewAngles.LookingAt(eye, new Vec3(10f, 1.2f, 0f));

            ShotResult shot = Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward,
                                                  120f, world, targets, friendlyFire: false);

            Assert.True(shot.HitPlayer, $"missed an exposed target 10 m away (hit world: {shot.HitWorld})");
            Assert.Equal(new PlayerId(1), shot.Victim);
        }

        [Fact]
        public void ShotAtAHeadHitsTheHead()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            var targets = OneTarget(new Vec3(10f, 0f, 0f));
            PlayerHitboxes boxes = targets[0].Hitboxes;

            Vec3 eye = new Vec3(0f, 1.68f, 0f);
            ViewAngles aim = ViewAngles.LookingAt(eye, boxes.Head.Centre);

            ShotResult shot = Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward,
                                                  120f, world, targets, friendlyFire: false);

            Assert.True(shot.HitPlayer, "a shot aimed at the centre of a head missed entirely");
            Assert.Equal(HitRegion.Head, shot.Region);
        }

        [Fact]
        public void WallsStopBullets()
        {
            CollisionWorld world = TestWorlds.ObstacleWorld();
            // The wall stands at x = 4. Put the target behind it.
            var targets = OneTarget(new Vec3(10f, 0f, 0f));

            Vec3 eye = new Vec3(0f, 1.68f, 0f);
            ViewAngles aim = ViewAngles.LookingAt(eye, new Vec3(10f, 1.2f, 0f));

            ShotResult shot = Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward,
                                                  120f, world, targets, friendlyFire: false);

            Assert.False(shot.HitPlayer, "shot straight through a solid wall");
            Assert.True(shot.HitWorld);
            Assert.InRange(shot.End.X, 3.9f, 4.6f);
        }

        [Fact]
        public void FriendlyFireIsOffByDefaultAndTheDeadAreNotTargets()
        {
            CollisionWorld world = TestWorlds.FlatWorld();
            Vec3 eye = new Vec3(0f, 1.68f, 0f);
            ViewAngles aim = ViewAngles.LookingAt(eye, new Vec3(10f, 1.2f, 0f));

            var friend = OneTarget(new Vec3(10f, 0f, 0f), Team.Alpha);
            Assert.False(Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward, 120f,
                                             world, friend, friendlyFire: false).HitPlayer);
            Assert.True(Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward, 120f,
                                            world, friend, friendlyFire: true).HitPlayer);

            var corpse = OneTarget(new Vec3(10f, 0f, 0f), Team.Bravo, alive: false);
            Assert.False(Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward, 120f,
                                             world, corpse, friendlyFire: false).HitPlayer);
        }

        [Fact]
        public void SpreadStaysInsideItsConeAndIsNotBiasedOffCentre()
        {
            var aim = new ViewAngles(0.3f, 1.1f);
            float spread = 0.05f;
            var random = new DeterministicRandom(4242);

            Vec3 sum = Vec3.Zero;
            for (int i = 0; i < 20000; i++)
            {
                Vec3 direction = Ballistics.ApplySpread(aim, spread, ref random);
                float angle = (float)System.Math.Acos(
                    SalvoMath.Clamp(Vec3.Dot(direction, aim.Forward), -1f, 1f));
                Assert.True(angle <= spread + 1e-3f,
                            $"pellet {i} left the cone: {angle:F5} > {spread:F5}");
                sum += direction;
            }

            // The mean direction of a symmetric cone is its axis. A biased spread — the classic
            // symptom of building the basis from the view's own right vector — shows up here
            // and nowhere else.
            Vec3 mean = (sum / 20000f).Normalized;
            float bias = (float)System.Math.Acos(
                SalvoMath.Clamp(Vec3.Dot(mean, aim.Forward), -1f, 1f));
            Assert.True(bias < 0.002f, $"spread is biased {bias:F5} rad off the aim direction");
        }

        [Fact]
        public void SpreadIsReproducibleFromTheSameSeed()
        {
            // The client predicts its own shots by re-rolling the server's spread. If this
            // fails, every shot lands somewhere other than where the shooter saw it go.
            var aim = new ViewAngles(0.1f, 2.0f);
            var a = new DeterministicRandom(99);
            var b = new DeterministicRandom(99);
            for (int i = 0; i < 256; i++)
                Assert.Equal(Ballistics.ApplySpread(aim, 0.03f, ref a),
                             Ballistics.ApplySpread(aim, 0.03f, ref b));
        }

        // ---- lag compensation ---------------------------------------------------------

        [Fact]
        public void RewindFindsWhereAPlayerWasNotWhereTheyAre()
        {
            var history = new LagCompensation();
            var player = new PlayerId(1);
            var movement = MovementState.AtSpawn(new SpawnPoint(Vec3.Zero, 0f));

            // Walk 10 m/s along +X for one second of ticks.
            for (int tick = 0; tick < FixedClock.TicksPerSecond; tick++)
            {
                movement.Position = new Vec3(tick * (10f / FixedClock.TicksPerSecond), 0f, 0f);
                history.Record(player, tick, movement, isAlive: true);
            }

            int now = FixedClock.TicksPerSecond - 1;
            int rewound = LagCompensation.RewindTarget(now, 0.1f);
            Assert.True(history.TryGetPose(player, rewound, out HistoricPose pose));

            // 100 ms ago they were about a metre back.
            Assert.InRange(movement.Position.X - pose.Position.X, 0.8f, 1.2f);
        }

        [Fact]
        public void RewindIsClampedSoLatencyCannotBeClaimedWithoutLimit()
        {
            int now = 1000;
            Assert.Equal(now, LagCompensation.RewindTarget(now, 0f));
            int clamped = LagCompensation.RewindTarget(now, 10f);
            int atLimit = LagCompensation.RewindTarget(now, LagCompensation.MaxRewindSeconds);
            Assert.Equal(atLimit, clamped);
            Assert.True(now - clamped <= LagCompensation.MaxRewindSeconds * FixedClock.TicksPerSecond + 1);
        }

        [Fact]
        public void HistoryIsLongEnoughForEveryRewindItWillBeAsked()
        {
            // The invariant the rewind relies on: RewindTarget clamps to MaxRewindSeconds, and
            // the ring must hold at least that much. If the ring were shorter, TryGetPose would
            // quietly hand back the oldest pose it still had and shots would register against
            // stale positions — a bug that looks exactly like bad luck.
            var history = new LagCompensation();
            int neededTicks = (int)System.Math.Ceiling(
                LagCompensation.MaxRewindSeconds * FixedClock.TicksPerSecond);
            Assert.True(history.Capacity > neededTicks,
                        $"ring holds {history.Capacity} ticks but rewinds reach back {neededTicks}");
        }

        [Fact]
        public void RewindingLetsALaggingShooterHitWhatTheySaw()
        {
            // The whole point of lag compensation, stated as a test: a target that has already
            // run out of the line of fire on the server is still hittable by a shot the client
            // took when they were in it.
            CollisionWorld world = TestWorlds.FlatWorld();
            var history = new LagCompensation();
            var victim = new PlayerId(1);

            var movement = MovementState.AtSpawn(new SpawnPoint(new Vec3(10f, 0f, 0f), 0f));
            // Fewer ticks than the ring retains, so tick 4 is still there to be asked for.
            // The production guarantee is the same one, stated differently: the ring is sized
            // to cover MaxRewindSeconds and RewindTarget clamps to it.
            const int shotTick = 16;
            for (int tick = 0; tick <= shotTick; tick++)
            {
                // Sprinting across the shooter's line of sight along +Z.
                movement.Position = new Vec3(10f, 0f, tick * 0.25f);
                history.Record(victim, tick, movement, isAlive: true);
            }

            Vec3 eye = new Vec3(0f, 1.68f, 0f);
            // Aim where the victim was at tick 4, which is well behind them by tick 16.
            ViewAngles aim = ViewAngles.LookingAt(eye, new Vec3(10f, 1.2f, 1.0f));

            var players = new List<PlayerId> { victim };
            var teams = new List<Team> { Team.Bravo };

            var liveTargets = new List<ShootableTarget>
            {
                new ShootableTarget
                {
                    Id = victim, Team = Team.Bravo, IsAlive = true,
                    Hitboxes = PlayerHitboxes.For(movement.Position,
                                                  CharacterDefinition.StandingHeight,
                                                  new ViewAngles(0f, 0f)),
                }
            };
            Assert.False(Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward, 120f,
                                             world, liveTargets, friendlyFire: false).HitPlayer,
                         "the target was somehow still there without rewinding");

            var rewound = history.RewindTargets(4, players, teams);
            Assert.True(Ballistics.TraceOne(new PlayerId(0), Team.Alpha, eye, aim.Forward, 120f,
                                            world, rewound, friendlyFire: false).HitPlayer,
                        "rewinding did not put the target back where the shooter saw it");
        }
    }
}
