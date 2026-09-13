using System.Collections.Generic;
using Xunit;
using Salvo.Sim;

namespace Salvo.Sim.Tests
{
    /// <summary>
    /// Whether a second era can exist without the engine knowing about it.
    /// </summary>
    /// <remarks>
    /// PROJECT_PLAN.md states the bar: if adding a world requires touching the player
    /// controller, the design failed. These tests are the mechanical half of checking that —
    /// the other half is the diff, which for the wartime era touched no file under Movement/,
    /// Combat/, Modes/, AI/, Net/ or Match/.
    /// </remarks>
    public class WorldTests
    {
        private static GameContent Content() => StarterContent.Build();

        [Fact]
        public void BothWorldsLoadAndCrossReferenceCleanly()
        {
            List<string> problems = Content().Validate();
            Assert.True(problems.Count == 0,
                        "content has problems:\n  " + string.Join("\n  ", problems));
        }

        [Fact]
        public void EachWorldStandsUpOnItsOwn()
        {
            // A world that only validates alongside another is not modular — it is leaning on
            // something it does not declare. Downloadable eras make this a shipping concern
            // rather than a tidiness one.
            List<string> problems = StarterContent.BuildModernOnly().Validate();
            Assert.True(problems.Count == 0,
                        "the modern world cannot stand alone:\n  " + string.Join("\n  ", problems));
        }

        [Fact]
        public void EveryWeaponInEveryWorldIsInternallyConsistent()
        {
            var problems = new List<string>();
            foreach (WeaponDefinition weapon in Content().Weapons.All) weapon.Validate(problems);
            Assert.True(problems.Count == 0, string.Join("\n", problems));
        }

        [Fact]
        public void NoWeaponOrMapIdCollidesBetweenWorlds()
        {
            // Two eras each adding "wpn.rifle" would silently overwrite one another, and the
            // loser would simply never appear in game.
            var seen = new HashSet<string>();
            foreach (IWorldContent world in StarterContent.AllWorlds())
            {
                foreach (WeaponDefinition weapon in world.Weapons())
                    Assert.True(seen.Add(weapon.Id.ToString()),
                                $"weapon id {weapon.Id} is used by more than one world");
                foreach (MapDefinition map in world.Maps())
                    Assert.True(seen.Add(map.Id.ToString()),
                                $"map id {map.Id} is used by more than one world");
            }
        }

        [Fact]
        public void EveryWeaponBelongsToTheWorldThatShipsIt()
        {
            foreach (IWorldContent world in StarterContent.AllWorlds())
                foreach (WeaponDefinition weapon in world.Weapons())
                    Assert.Equal(world.World.Id, weapon.WorldId);
        }

        [Fact]
        public void TheTwoErasActuallyPlayDifferently()
        {
            // If a second era is a reskin, the data model has not really been exercised. The
            // wartime era is meant to be slower and heavier: fewer rounds a minute, more damage
            // a round, less accurate from the hip.
            GameContent content = Content();

            double AverageRpm(ContentId worldId)
            {
                double total = 0; int count = 0;
                foreach (WeaponDefinition weapon in content.Weapons.All)
                {
                    if (weapon.WorldId != worldId || weapon.Class == WeaponClass.Melee) continue;
                    total += weapon.RoundsPerMinute; count++;
                }
                return count == 0 ? 0 : total / count;
            }

            double AverageDamage(ContentId worldId)
            {
                double total = 0; int count = 0;
                foreach (WeaponDefinition weapon in content.Weapons.All)
                {
                    if (weapon.WorldId != worldId || weapon.Class == WeaponClass.Melee) continue;
                    total += weapon.BaseDamage; count++;
                }
                return count == 0 ? 0 : total / count;
            }

            double modernRpm = AverageRpm(StarterContent.WorldModern);
            double wartimeRpm = AverageRpm(WartimeWorld.Id);
            Assert.True(wartimeRpm < modernRpm * 0.8,
                        $"wartime fires at {wartimeRpm:F0} rpm vs modern {modernRpm:F0} — "
                        + "the eras are not mechanically distinct");
            Assert.True(AverageDamage(WartimeWorld.Id) > AverageDamage(StarterContent.WorldModern),
                        "wartime weapons do not hit harder despite firing slower");
        }

        [Fact]
        public void TheDataModelCanExpressABoltAction()
        {
            // The wartime rifle is the feature test for FireMode.Bolt plus round-by-round
            // reloading, neither of which the modern era exercised on a rifle.
            WeaponDefinition warden = Content().Weapons.Get(WartimeWorld.Weapons.Warden);
            Assert.Equal(FireMode.Bolt, warden.FireMode);
            Assert.True(warden.ReloadsOneRoundAtATime);

            var state = WeaponState.Fresh(warden);
            int shots = 0;
            // Holding the trigger for two seconds must not empty a five-round magazine: a bolt
            // action needs the trigger released between shots.
            for (int i = 0; i < FixedClock.TicksPerSecond * 2; i++)
            {
                if (state.CanFire(warden)) { state.ConsumeShot(warden); shots++; }
                state.Tick(warden, triggerDown: true, FixedClock.TickInterval);
            }
            Assert.Equal(1, shots);
        }

        [Fact]
        public void AnEraCanSimplyNotOfferAnAttachmentCategory()
        {
            // Iron sights only. An era that has not invented a red dot should not need a flag to
            // disable optics — it should just not list the slot.
            WeaponDefinition warden = Content().Weapons.Get(WartimeWorld.Weapons.Warden);
            Assert.DoesNotContain(AttachmentSlot.Optic, warden.SupportedAttachments);

            WeaponDefinition kestrel = Content().Weapons.Get(StarterContent.Weapons.Kestrel);
            Assert.Contains(AttachmentSlot.Optic, kestrel.SupportedAttachments);
        }

        [Fact]
        public void TheQuarryIsWellFormedAndItsSpawnsAreStandable()
        {
            MapDefinition map = Content().Maps.Get(WartimeWorld.MapQuarry);
            var problems = new List<string>();
            map.Validate(problems);
            Assert.True(problems.Count == 0, string.Join("\n", problems));

            var world = new CollisionWorld(map);
            foreach (SpawnPoint spawn in map.Spawns)
            {
                var box = new Aabb(
                    spawn.Position - new Vec3(CharacterDefinition.Radius, 0f, CharacterDefinition.Radius),
                    spawn.Position + new Vec3(CharacterDefinition.Radius,
                                              CharacterDefinition.StandingHeight,
                                              CharacterDefinition.Radius));
                Assert.False(world.Overlaps(box), $"spawn at {spawn.Position} is inside geometry");
            }

            foreach (ObjectiveZone zone in map.Objectives)
            {
                Vec3 feet = new Vec3(zone.Centre.X, zone.Volume.Min.Y, zone.Centre.Z);
                var box = new Aabb(
                    feet - new Vec3(CharacterDefinition.Radius, 0f, CharacterDefinition.Radius),
                    feet + new Vec3(CharacterDefinition.Radius,
                                    CharacterDefinition.StandingHeight,
                                    CharacterDefinition.Radius));
                Assert.False(world.Overlaps(box), $"{zone.NameKey} is inside geometry");
                Assert.True(zone.Contains(feet), $"{zone.NameKey} excludes its own centre");
            }
        }

        [Fact]
        public void TheQuarryHasVerticalityTheModernMapDoesNot()
        {
            // A reskin would be flat too. The quarry is a bowl, so the spread of walkable
            // heights should be substantially larger.
            GameContent content = Content();
            float Spread(ContentId mapId)
            {
                MapDefinition map = content.Maps.Get(mapId);
                float low = float.MaxValue, high = float.MinValue;
                foreach (MapBrush brush in map.Brushes)
                {
                    if (brush.IsClip) continue;
                    low = System.Math.Min(low, brush.Box.Max.Y);
                    high = System.Math.Max(high, brush.Box.Max.Y);
                }
                return high - low;
            }
            Assert.True(Spread(WartimeWorld.MapQuarry) > 4f,
                        "the quarry is as flat as the modern arena");
        }

        [Fact]
        public void ALoadoutBuiltForAWorldOnlyContainsThatWorldsWeapons()
        {
            // The failure this prevents is silent: handing out the modern carbine on a 1940s map
            // works perfectly, because the simulation has no opinion about anachronism. Nothing
            // errors, nothing looks wrong in a log, and players simply carry the wrong era's guns.
            GameContent content = Content();

            foreach (IWorldContent world in StarterContent.AllWorlds())
            {
                for (int variant = 0; variant < 6; variant++)
                {
                    Assert.True(Loadouts.TryBuildDefault(content, world.World.Id, variant,
                                                         out Loadout loadout),
                                $"{world.World.Id} produced no loadout");

                    foreach (WeaponSlot slot in new[] { WeaponSlot.Primary, WeaponSlot.Secondary,
                                                        WeaponSlot.Melee })
                    {
                        ContentId id = loadout[slot].WeaponId;
                        if (id.IsEmpty) continue;
                        Assert.True(content.Weapons.TryGet(id, out WeaponDefinition weapon),
                                    $"{id} is not in the catalogue");
                        Assert.Equal(world.World.Id, weapon.WorldId);
                    }
                }
            }
        }

        [Fact]
        public void SuccessiveVariantsCycleThroughAWorldsPrimaries()
        {
            // A team where every bot carries the same weapon exercises one weapon's state
            // machine and hides bugs in the rest.
            GameContent content = Content();
            var seen = new HashSet<string>();
            for (int variant = 0; variant < 8; variant++)
            {
                Assert.True(Loadouts.TryBuildDefault(content, StarterContent.WorldModern,
                                                     variant, out Loadout loadout));
                seen.Add(loadout.Primary.WeaponId.ToString());
            }
            Assert.True(seen.Count >= 3,
                        $"eight variants produced only {seen.Count} distinct primaries");
        }

        [Fact]
        public void ANegativeVariantStillProducesAValidLoadout()
        {
            // Callers pass player ids and indices; a negative one must not throw on the modulo.
            Assert.True(Loadouts.TryBuildDefault(Content(), StarterContent.WorldModern, -3,
                                                 out Loadout loadout));
            Assert.False(loadout.Primary.WeaponId.IsEmpty);
        }

        [Fact]
        public void AWorldWithNoWeaponsFailsRatherThanSubstituting()
        {
            Assert.False(Loadouts.TryBuildDefault(Content(), "world.does_not_exist", 0, out _));
        }

        [Fact]
        public void AMatchPlaysOnTheWartimeMapWithWartimeWeapons()
        {
            // The end of the argument: the engine runs an era it was not written for, using a
            // map shape it has never seen, with no code that knows either exists.
            GameContent content = Content();
            GameModeDefinition definition = content.GameModes.Get(StarterContent.Modes.TeamDeathmatch);
            MapDefinition map = content.Maps.Get(WartimeWorld.MapQuarry);

            var match = new MatchSimulation(content, map, GameModes.Create(definition), 7);
            var loadout = Loadout.Default(WartimeWorld.Weapons.Warden,
                                          WartimeWorld.Weapons.Kettle,
                                          WartimeWorld.Weapons.Spade);
            for (int i = 0; i < 6; i++)
                match.AddPlayer($"P{i}", i % 2 == 0 ? Team.Alpha : Team.Bravo, loadout,
                                isBot: true, botDifficulty: StarterContent.Difficulties.Normal);

            var director = new BotDirector(content, 7);
            match.Start();

            foreach (PlayerRuntime player in match.Players)
                Assert.True(player.IsAlive, $"{player.Name} never spawned on the quarry");

            int shots = 0, hits = 0;
            int ticks = 120 * FixedClock.TicksPerSecond;
            for (int i = 0; i < ticks && match.Phase != MatchPhase.MatchEnd; i++)
            {
                director.Think(match, FixedClock.TickInterval);
                match.Step();
                foreach (MatchEvent e in match.Events)
                {
                    if (e.Kind == MatchEventKind.Fired) shots++;
                    else if (e.Kind == MatchEventKind.Damaged && e.OtherPlayer != e.Player) hits++;
                }
                foreach (PlayerRuntime player in match.Players)
                    Assert.True(map.Bounds.Contains(player.Movement.Position),
                                $"{player.Name} left the quarry at {player.Movement.Position}");
            }

            Assert.True(shots > 10, $"only {shots} shots fired on the quarry");
            Assert.True(hits > 0, "nothing was ever hit on the quarry");
        }
    }
}
