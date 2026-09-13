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

## Phase 6 — Networking  *(simulation side complete)*

### Done and verified
- [x] Bit-level wire format with explicit field widths and quantisation
- [x] Snapshots with delta encoding against a client-acknowledged baseline
- [x] `SimulatedLink` — deterministic latency, jitter, loss and reordering
- [x] Client prediction with server reconciliation and input replay
- [x] Entity interpolation, short-way-round angles, insertion of late snapshots
- [x] Server-side input queue: one command simulated per tick, with a 2-tick jitter buffer
- [x] `salvo-headless --net` — a real server and real clients over a lossy link, in process

Measured over a 120 s, 10-client team deathmatch:

| Link | Mean error | Worst | Corrections | Downstream |
| --- | --- | --- | --- | --- |
| perfect | 0.001 m | 0.02 m | 0.3% | 22 kbit/s |
| mobile (60 ms, 1% loss) | 0.008 m | 0.49 m | 9.3% | 22 kbit/s |
| poor (150 ms, 5% loss) | 0.045 m | 1.36 m | 45% | 23 kbit/s |

Error is the client's prediction against the server's result *for the same input tick* —
not the gap between their current positions, which is latency times speed and is prediction
working rather than failing. The budget is 64 kbit/s downstream at 10v10.

### Not done
- [ ] No real transport. `SimulatedLink` is in-process; NGO is not wired up.
- [ ] No connection lifecycle: joining mid-match, dropping, rejoining, timing out.
- [ ] Shots are resolved server-side with lag compensation but are **not** predicted on the
      client, so a hit marker will lag by a round trip.
- [ ] Snapshots carry no events. Kills, impacts and sounds are computed but never sent.
- [ ] Nothing is encrypted or authenticated. The wire format trusts its peer entirely.

---

## 5v5 round objective  *(playable)*

- [x] `OverloadMode` — rounds, freeze time, no respawn, arm/disarm with a fuse, elimination,
      sides swapped at half time
- [x] `IGameMode.TryGetObjectiveOrder` — bots play the objective without knowing which mode
      they are in, so a new mode does not mean a new branch inside the AI
- [x] `GameModes.Create` — one place that maps a mode kind to an implementation, and throws
      for a kind with none rather than quietly substituting deathmatch
- [x] Two relay sites on the starter map, with a test that a player can stand in each
- [x] 13 tests for the round lifecycle, which had never run before this mode existed

Measured over a full 13-round match, 10 bots:

| Difficulty | Result | Charges armed | Attacker time on site |
| --- | --- | --- | --- |
| easy | 7-5 attackers | 7 | 122 s |
| normal | 5-7 defenders | 8 | 97 s |
| hard | 5-7 defenders | 9 | 91 s |
| expert | 4-7 defenders | 5 | 85 s |

The first site placement was 14 m from the defenders' spawn and 50 m from the attackers'.
Every test still passed and average bots armed seven times a match, but at higher skill the
defenders simply arrived first: attackers took one round in eight. The format is meant to
favour defenders; a 36 m head start decides it rather than favouring it. Moved to the flanks
near the midpoint, which is what the table above measures.

### Known gaps
- [ ] No buy phase or economy. Everyone starts each round with the same loadout.
- [ ] Bots do not coordinate a push, hold angles, or rotate between sites — they walk to the
      ordered position and fight whatever they meet.
- [ ] No carried-charge model: any attacker can arm, rather than one carrying it.

---

## Second era  *(the architecture test)*

PROJECT_PLAN.md set the bar: if adding an era requires touching the player controller, the
design failed. It did not.

- [x] `IWorldContent` — an era declares its weapons, attachments, factions, characters and
      maps; it does not declare modes or bot difficulties, which are rules and are shared
- [x] `WartimeWorld` — a 1940s era: five weapons, two attachments, two factions, one map
- [x] `Loadouts.TryBuildDefault` — a loadout drawn from the map's own world
- [x] 16 tests, including that each world validates standing alone

**The diff for the whole era touched no file under `Movement/`, `Combat/`, `Modes/`, `AI/`,
`Net/`, `Match/`, `World/`, `Math/` or `Core/`.** Only `Content/` and a new test file.

It is not a reskin, and that is testable rather than asserted. The era pushes on parts of the
data model the modern one never used:

| | Modern | Wartime |
| --- | --- | --- |
| Mean rate of fire | 618 rpm | 305 rpm |
| Mean damage | 27 | 43 |
| Optics available | yes | none — the slot is simply not listed |
| Bolt action | no | yes, with round-by-round reloading |
| Map shape | flat, symmetric, raised centre | a pit with terraced rim |
| Bot hit rate, same difficulty | 56% | 31% |

The hit-rate gap is the data model working: iron sights and higher spread make the same bots
measurably less accurate, with no code aware of which era it is running.

### Known gaps
- [ ] `Loadouts` picks by weapon class round-robin. There is no loadout UI, no saved
      preference, and no per-faction restriction yet.
- [ ] The quarry favours attackers in the objective mode (7-3) where Junction favours
      defenders (4-7 to 5-7). Both are playable; neither has been tuned.
- [ ] Era is content, but there is still only one `MovementTuning`. A heavier era would want
      its own, and the type is ready for it — nothing reads it per world yet.

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
- [ ] No real network transport. Prediction, reconciliation, interpolation and the wire
      format are built and measured against a simulated lossy link, but nothing has crossed
      a socket. NGO integration is the remaining half of Phase 6.

---

## Repository note

`/CriticalStrike` in this repository is a **separate, earlier Swift/SceneKit project**, not
part of SALVO. It is untouched. Two things about it are worth flagging:

1. Its name is one the brief explicitly says not to reuse. If anything from it is ever
   carried forward, it needs renaming first.
2. Its test suite currently has failures unrelated to SALVO (spawns inside geometry,
   ballistics registration, attachment balance). They are recorded in that project, not
   here.
