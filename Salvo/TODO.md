# SALVO — TODO

Updated at the end of every phase. `[x]` means done **and verified**; anything verified only
by reading is marked `[~]` with what is missing.

---

## Phase 1 — Architecture + simulation core  *(complete)*

### Done and verified
- [x] Inspect repository; confirm no Unity project exists
- [x] Confirm toolchain: .NET SDK 8.0.131, NuGet reachable, `dotnet test` works
- [x] Confirm `netstandard2.1` + C# 9 compiles (Unity 6's profile)
- [x] `ARCHITECTURE.md`, `PROJECT_PLAN.md`, `TODO.md`, `ORIGINALITY.md`
- [x] Folder structure
- [x] Decide multiplayer architecture (NGO for session, own tick sim for gameplay)
- [x] Decide Unity version and package set
- [x] Core value types (`Vec3`, `ViewAngles`, `FixedClock`, `ContentId`, `DeterministicRandom`)
- [x] Data definitions: Weapon, Character, Map, World, Faction, GameMode, BotDifficulty,
      Attachment — POCOs behind `IContentCatalog<T>`, each with its own `Validate`
- [x] Collision world (uniform grid over AABB brushes), box sweep, depenetration
- [x] Movement simulation — collide-and-slide, step-up, stances, coyote time, fall damage
- [x] Spawn selection, scored on enemy proximity, line of sight, friends and recent use
- [x] Weapon state machine, ballistics, damage model with hitboxes, lag compensation
- [x] `IGameMode` + Team Deathmatch + Free-For-All
- [x] Bots at four difficulties, constrained to the same input interface as a player
- [x] `MatchSimulation` tying it together
- [x] 63 xUnit tests covering all of the above
- [x] `Salvo.Headless` — plays a full bot match and prints a scoreboard, and **fails** if
      nobody moved, shot, hit, died, or if anyone left the map
- [x] CI workflow: build, tests, bridge compile, four playable-match runs, determinism check
- [x] Unity `Packages/manifest.json` and `ProjectSettings/ProjectVersion.txt`
- [x] Assembly definitions — `Salvo.Sim` has `noEngineReferences: true`, which is the
      architecture's guardrail rather than a comment about it
- [x] `Salvo.Bridge.Check` — compiles the Unity layer against a stub UnityEngine. Verified to
      catch a Sim-side rename by deliberately renaming one.

### Written but NOT verified — no Unity in this environment
- [~] ScriptableObject wrappers over the definitions — compile against the shim only
- [~] `PrototypeHost`, `LocalPlayerInput`, `MapGeometryBuilder`, `SalvoConvert` — compile
      against the shim only; none has run a frame
- [~] Editor menu item that builds the prototype scene from code — never executed. The scene
      it writes has never existed.

The shim is honest about its limits: see `Sim/Salvo.UnityShim/README.md`. A green bridge
build means the code is consistent with itself and with the simulation, **not** that it
matches real Unity 6. Expect to fix something on first open.

---

## Known issues / decisions deferred

- [ ] **Trademark search for "SALVO"** before any public use. Codename only.
- [ ] Ranked needs dedicated servers; Relay is host-authoritative and cheatable by the host
- [ ] Input-based matchmaking pools (touch vs mouse) — decide before ranked
- [ ] Localisation tables exist from the first UI string, not retrofitted
- [ ] Nothing under `Unity/Assets/Salvo/Runtime/` or `Editor/` has run inside Unity
- [ ] Ballistics is hitscan only. `WeaponDefinition.Validate` rejects a weapon with a muzzle
      velocity rather than silently firing it as hitscan — projectiles wait for a phase where
      their interaction with lag compensation can be built and tested properly.
- [ ] Bot navigation is direct steering with local avoidance, not pathfinding. Fine on the
      open arena that ships; a map with a dead end would trap a bot in it. No such map should
      be added before Phase 9.
- [ ] `MapGeometryBuilder` emits every face, including ones buried inside neighbouring
      brushes. Correct, and wasteful; face culling belongs with the rest of the map pipeline.
- [ ] No network transport is wired up at all. `MatchSimulation` is authoritative by
      construction and `LagCompensation` is tested, but nothing has crossed a socket.

---

## Repository note

`/CriticalStrike` in this repository is a **separate, earlier Swift/SceneKit project**, not
part of SALVO. It is untouched. Two things about it are worth flagging:

1. Its name is one the brief explicitly says not to reuse. If anything from it is ever
   carried forward, it needs renaming first.
2. Its test suite currently has failures unrelated to SALVO (spawns inside geometry,
   ballistics registration, attachment balance). They are recorded in that project, not
   here.
