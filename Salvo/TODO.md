# SALVO — TODO

Updated at the end of every phase. `[x]` means done **and verified**; anything verified only
by reading is marked `[~]` with what is missing.

---

## Phase 1 — Architecture + simulation core  *(in progress)*

### Done
- [x] Inspect repository; confirm no Unity project exists
- [x] Confirm toolchain: .NET SDK 8.0.131, NuGet reachable, `dotnet test` works
- [x] Confirm `netstandard2.1` + C# 9 compiles (Unity 6's profile)
- [x] `ARCHITECTURE.md`, `PROJECT_PLAN.md`, `TODO.md`
- [x] Folder structure
- [x] Decide multiplayer architecture (NGO for session, own tick sim for gameplay)
- [x] Decide Unity version and package set

### In progress
- [ ] Core value types (`Vec3`, angles, fixed clock, ids)
- [ ] Data definitions: Weapon, Character, Map, World, Faction, GameMode, BotDifficulty,
      Attachment, Cosmetic — as POCOs with catalog interfaces
- [ ] Collision world (AABB brushes) and spawn selection
- [ ] Movement simulation
- [ ] Weapon state machine, ballistics, damage model with hitboxes
- [ ] `IGameMode` + Team Deathmatch
- [ ] Minimal bots
- [ ] `MatchSimulation` tying it together
- [ ] xUnit tests for all of the above
- [ ] `Salvo.Headless` — plays a full bot match and prints a scoreboard
- [ ] CI workflow running build + tests

### Not started, Phase 1
- [ ] Unity `Packages/manifest.json` and `ProjectSettings`
- [ ] Assembly definitions (`Salvo.Sim`, `Salvo.Runtime`, `Salvo.Editor`)
- [ ] ScriptableObject wrappers over the definitions
- [ ] Editor menu item that builds the prototype scene from code

---

## Known issues / decisions deferred

- [ ] **Trademark search for "SALVO"** before any public use. Codename only.
- [ ] Ranked needs dedicated servers; Relay is host-authoritative and cheatable by the host
- [ ] Input-based matchmaking pools (touch vs mouse) — decide before ranked
- [ ] Localisation tables exist from the first UI string, not retrofitted
- [ ] Nothing under `Unity/Assets/Salvo/Runtime/` has been compiled (no Unity here)

---

## Repository note

`/CriticalStrike` in this repository is a **separate, earlier Swift/SceneKit project**, not
part of SALVO. It is untouched. Two things about it are worth flagging:

1. Its name is one the brief explicitly says not to reuse. If anything from it is ever
   carried forward, it needs renaming first.
2. Its test suite currently has failures unrelated to SALVO (spawns inside geometry,
   ballistics registration, attachment balance). They are recorded in that project, not
   here.
