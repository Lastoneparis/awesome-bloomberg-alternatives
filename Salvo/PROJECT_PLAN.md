# SALVO — Project Plan

A cross-platform (iPhone / iPad / Mac) team-based FPS built as a **platform**, not a game:
multiple eras, worlds, weapons, maps and modes added as data, on one shared engine.

Original IP. No asset, name, map, weapon, sound or mechanic is taken from an existing
product. See `ORIGINALITY.md` for the rules this project holds itself to.

---

## Scope discipline

The brief lists enough features for several years. The plan below is ordered so that **the
game is playable at the end of every phase**, and so that the expensive, hard-to-change
decisions (netcode shape, data model, server authority) are made first — before content
volume makes them expensive to revisit.

What is explicitly *not* being built now: battle royale, vehicles, extraction, zombies,
ranked ladders, a store. The architecture leaves room for each; none is implemented.

---

## Phases

| # | Phase | Definition of done | Status |
| --- | --- | --- | --- |
| 1 | **Architecture + simulation core** | Sim compiles, tests pass, a full bot match runs headless | **done** — 63 tests, TDM reaches its 50-kill limit headless |
| 2 | Unity project + player controller | Walk/run/crouch/jump/ADS on Mac and touch, 60 fps | **next** — bridge code written and shim-compiled, never opened in Unity |
| 3 | Weapon framework | 3 weapons from data assets, no weapon-specific code | **done in simulation** — 5 weapons, 3 attachments, no weapon-specific code |
| 4 | First map (Modern world) | Greybox with routes, cover, spawns, validated by tooling | not started |
| 5 | Bots | 4 difficulties, navigation, cover, objectives | partly — 4 difficulties done and measured; navigation is steering, not pathfinding |
| 6 | Networking | Server-authoritative, prediction, reconciliation, lag comp | **simulation side done** — measured over a lossy link; no real transport yet |
| 7 | Lobby / matchmaking / private match | Create, invite, join, ready, start | not started |
| 8 | Friends / parties | Add, accept, invite, block, report | **rules done** — graph and party enforced and tested; no service, no reporting |
| 9 | Mobile controls | Customisable HUD, haptics, safe areas | not started |
| 10 | Mac controls | KBM, remapping, sensitivity, FOV, windowed/fullscreen | not started |
| 11 | UI | Menus, loadout, scoreboard, results | not started |
| 12 | Audio / VFX | Surface-aware footsteps, weapon audio, impacts | not started |
| 13 | Performance | Quality tiers, device detection, thermal handling | not started |
| 14 | Second world (WWII) | Proves the world system with zero engine changes | **done in simulation** — the era's diff touched only Content/ |
| 15 | More maps and weapons | Content velocity test | partly — 10 weapons, 2 maps, 2 eras |
| 16 | Progression | XP, levels, stats, challenges | **simulation side done** — no persistence, no challenges |
| 17 | Cosmetics | Data-driven, no gameplay effect | structure done — UnlockTable rejects anything that touches gameplay; no content yet |
| 18 | Ranked | Dedicated servers, input-based pools | not started |
| 19 | Store submission | Privacy, account deletion, ratings, metadata | not started |

Phase 14 is the real test of the architecture. If adding WWII requires touching the player
controller, the design failed and it is cheaper to learn that at phase 14 than at phase 30.

---

## MVP (the vertical slice)

One modern map, one mode (Team Deathmatch), 5v5 architecture, three weapons, one character,
bots, private match, touch + Mac controls, HUD, respawn, scoreboard, basic audio and VFX.

The MVP is **playable or it is not done**. No phase is "complete" with the game unlaunchable.

---

## Player counts

Configurable per game mode, never global.

| | Players |
| --- | --- |
| MVP | 2–10 |
| Standard | 5v5 |
| Ceiling (if netcode and perf allow) | 10v10 |

Snapshot bandwidth is budgeted against 10v10 at 20 Hz from the start so the ceiling is a
measurement, not a hope.

---

## Performance budgets (from day one, §26)

| Target | Budget |
| --- | --- |
| iPhone 12 and later | 60 fps sustained, 120 where the display allows |
| iPhone X-era | 60 fps at LOW preset |
| Mac (Apple silicon) | 120 fps+ |
| Frame time | ≤ 16.6 ms, with ≤ 6 ms on the main thread |
| Draw calls | ≤ 400 on mobile |
| Memory | ≤ 1.2 GB on mobile |
| Snapshot bandwidth | ≤ 64 kbit/s down per client at 10v10 |
| Cold start to main menu | ≤ 4 s |
| Match load | ≤ 3 s |

These are tracked by a developer overlay, and regressions are treated as bugs.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| Relay is host-authoritative, so ranked is cheatable | Dedicated-server path designed in from phase 1; same code, different transport |
| Touch vs mouse fairness | Separate ranked pools by input type; decided before ranked ships |
| Content volume outpacing the data model | Phase 14 adds a whole era early, as a deliberate stress test |
| Unity cannot be run in this environment | Simulation is engine-free and fully tested; Unity layer is reviewed in the Editor |
| Scope | Everything above is ordered, and nothing later is started before the MVP is fun |
