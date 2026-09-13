# SALVO — Architecture

> **Working title.** `SALVO` is a codename. It is a generic artillery term that spans every
> era the game targets, which suits a multi-world shooter — but it has **not** had a
> trademark search. Do that before any public announcement. Renaming is a namespace and a
> folder: the name appears in no gameplay logic.

---

## 1. The decision everything else follows from

**The simulation does not reference UnityEngine.**

```
Salvo/
├── Unity/Assets/Salvo/Sim/        ← the game. Pure C#. No UnityEngine. netstandard2.1.
├── Unity/Assets/Salvo/Runtime/    ← Unity presentation: rendering, input, audio, NGO glue.
└── Sim/                           ← .NET projects that compile the SAME Sim/ source files
    ├── Salvo.Sim.csproj           ← library, for tests and the server
    ├── Salvo.Sim.Tests/           ← xUnit
    └── Salvo.Headless/            ← runs a whole match with no engine at all
```

There is **one copy of the source**. The `.csproj` reaches into `Unity/Assets/Salvo/Sim/`
with a glob; Unity compiles the same folder through an assembly definition. Neither is a
copy of the other, so they cannot drift.

### Why

1. **The brief requires an authoritative server that is not the player's phone** (§5, §15,
   §36). A server that shares the client's gameplay code is the only way to guarantee the
   two agree. If the gameplay code needs Unity, every server instance needs a Unity
   runtime — expensive, and a licence question. Unity-free, the server is a plain .NET
   console app that costs almost nothing to host.
2. **Tests run in seconds, here and in CI, with no Unity licence.** Unity Test Framework in
   CI needs a licensed Editor in a multi-gigabyte image. `dotnet test` needs neither. This
   is not hypothetical convenience: it is the difference between tests that run on every
   commit and tests that run never.
3. **netstandard2.1 is Unity 6's own profile.** Targeting it means the compiler refuses
   anything Unity could not compile. The restriction is the point.
4. It keeps gameplay honest. Code that cannot call `GameObject.Find` or `Time.deltaTime`
   has to take its inputs explicitly, which is what makes it testable and deterministic.

### What lives where

| Belongs in `Sim/` | Belongs in `Runtime/` |
| --- | --- |
| movement, recoil, ballistics, damage | animation, VFX, audio playback |
| weapon state machine, reloads | weapon models, muzzle flashes |
| game-mode rules, scoring, spawn choice | HUD, menus, scoreboard rendering |
| bot decisions | bot animation |
| hit registration, lag compensation | camera, look-at, interpolation smoothing |
| data definitions (POCOs) | ScriptableObject wrappers around them |

The rule when in doubt: **if a dedicated server needs to know it, it goes in `Sim`.**

---

## 2. Multiplayer architecture

The brief says to evaluate rather than choose blindly. Four candidates:

| Option | Verdict |
| --- | --- |
| **Netcode for GameObjects (NGO) 2.x** | Official, integrates with Unity Auth/Lobby/Relay/Multiplay, right scale for 5v5. Its `NetworkTransform` is *not* adequate for competitive hit registration — no rollback, no lag compensation. |
| **Netcode for Entities (DOTS)** | Has prediction and lag compensation built in, and scales to hundreds. Requires an ECS rewrite of all gameplay, has heavier mobile tooling, and 5v5 does not need it. Rejected as overkill. |
| **Photon Fusion 2** | Excellent prediction/rollback and genuinely mature. Third-party licence cost per CCU, and pulls the session stack away from the Unity services the brief names. Keep as a fallback. |
| **Mirror / FishNet** | Free and capable; FishNet's prediction is good. Weaker story for managed Lobby/Relay/matchmaking on Apple platforms. |

### Chosen: NGO for *transport and session*, our own tick simulation for *gameplay*

```
Unity Authentication ─┐
Unity Lobby / Party  ─┼─→ session setup, invites, matchmaking
Unity Relay          ─┘
        │
        ▼
   NGO + Unity Transport  ← moves bytes, manages connections
        │
        ▼
   Salvo.Sim tick loop    ← 64 Hz authoritative simulation, snapshots at 20 Hz
```

Clients send `InputCommand`s. The server simulates and returns snapshots. Client-side
prediction, reconciliation, entity interpolation and server-side lag compensation are ours,
in `Sim/Net`, because that is exactly the part NGO does not provide and exactly the part
that decides whether the gunplay feels good.

An `ITransport` interface sits between the simulation and NGO so the headless server can
use plain sockets and the tests can use an in-memory loopback.

### Honest note on "authoritative" for the MVP

Unity **Relay is peer-hosted**: one player is the host, and that host *is* the authority. It
is genuinely server-authoritative with respect to the other nine players, and it is wrong
for ranked, because the host can cheat. This is a real limitation, not a detail:

- **MVP / private matches / friends:** Relay-hosted. Cheap, no infrastructure, fine.
- **Ranked:** dedicated servers (Unity Multiplay, or our own .NET host). Because the
  simulation is engine-free, that server is the *same code* with a different transport.

The architecture supports both from day one; only ranked requires the second.

---

## 3. Data-driven content

Adding a weapon must not mean editing weapon code (§2).

```
WeaponDefinition (POCO, in Sim)   ←  the thing the simulation reads
        ▲                    ▲
        │                    │
WeaponAsset : ScriptableObject   weapons.json
   (Unity authoring)              (dedicated server, no Unity)
```

The definitions are plain C# structs/classes in `Sim/Data`. Unity wraps each in a
`ScriptableObject` so designers author them in the Inspector; the server loads the same
definitions from JSON exported from those assets. One schema, two loaders, and the
simulation never knows which it got.

Catalogs are interfaces (`IWeaponCatalog`, `IMapCatalog`, …) so content can come from
Addressables, a remote manifest, or a test fixture.

**Worlds** (§10) are the top of the content tree: a `WorldDefinition` owns its factions,
weapon pool, map list and presentation theme. Adding *WWII Europe* is a new `WorldAsset`
plus its content — no gameplay code changes, because the player controller never asks what
century it is.

---

## 4. Unity version and packages

**Unity 6.2 LTS (6000.2 LTS)**, URP, Apple silicon Editor.

| Package | Why |
| --- | --- |
| `com.unity.render-pipelines.universal` | URP — required by the brief, right choice for mobile |
| `com.unity.inputsystem` | touch + KBM + gamepad from one action map |
| `com.unity.netcode.gameobjects` | transport/session layer |
| `com.unity.transport` | UTP, under NGO |
| `com.unity.services.authentication` | accounts + guest, Sign in with Apple later |
| `com.unity.services.lobby` | party, private match, invites |
| `com.unity.services.relay` | NAT traversal for host-authoritative sessions |
| `com.unity.services.matchmaker` | public matchmaking (later phase) |
| `com.unity.addressables` | content scale, remote worlds |
| `com.unity.ai.navigation` | bot navmesh baking |
| `com.unity.test-framework` | Unity-side play-mode tests |
| `com.unity.ide.rider` / `.visualstudio` | IDE integration |

Deliberately **not** included yet: Cinemachine (not needed for an FPS view model),
Analytics (privacy — add only when there is something to measure), IAP (§24: after the game
is fun), Burst/Collections (only if profiling demands it).

---

## 5. Determinism and anti-cheat posture

The simulation is **float-based and server-authoritative**, not lockstep-deterministic.
Chosen deliberately: lockstep determinism across ARM and x86 is expensive to maintain and
buys nothing when a server is already the authority.

The server never trusts a client for damage, health, ammunition, score, kills, or match
result. Clients send *intent* (`InputCommand`: movement axes, view angles, buttons) and the
server validates it — magnitude, view-rate, timestep plausibility, fire cadence — before
simulating. That validation lives in `Sim/Net` so the tests can attack it directly.

---

## 6. What is verified, and what is not

This environment has the .NET SDK but **cannot install Unity** (the download host is
blocked by the network policy, and the Editor needs a licence). So the honest split is:

### Verified by running it

- ✅ Everything in `Sim/` compiles under `netstandard2.1` with warnings as errors, and its
  63 tests pass — here and in CI.
- ✅ `Salvo.Headless` plays a full team deathmatch to its own 50-kill limit with no engine,
  in about 3.7 s of wall clock for 370 s of match time. It exits non-zero if nobody moved,
  nobody fired, nothing was hit, nobody died, or anyone left the map, so CI fails on a
  regression that leaves bots standing in their spawn rather than passing quietly.
- ✅ The same match replays identically from its seed. Client-side prediction depends on
  this absolutely, and CI diffs two runs to prove it.
- ✅ Bot difficulty differentiates: measured hit rates of 33% / 47% / 55% / 79% across
  Easy → Expert, with damage per landed hit flat. A test asserts both halves.

### Verified only as far as "it is valid C# that agrees with the simulation"

- ⚠️ `Unity/Assets/Salvo/Runtime/` and `Editor/` compile via `Sim/Salvo.Bridge.Check`,
  which builds those exact source files against a stub `UnityEngine` in
  `Sim/Salvo.UnityShim`.

  This catches the failure that will actually happen — a rename in `Sim` silently breaking
  the bridge — and it was confirmed to catch it by deliberately renaming
  `MatchSimulation.Start` and watching the build fail with a file and line. It found two
  real bugs when first run: a generic call whose type arguments could not be inferred, and
  a static method referring to an instance member.

  It does **not** prove the code matches real Unity. The shim was written from memory of
  Unity's API; where that memory is wrong, the shim is wrong the same way and the build
  passes regardless. Expect to fix something on first open. It will be smaller than it
  would have been.

### Not verified at all

- ❌ Nothing has run inside Unity. Not one frame, not one `Start()`.
- ❌ No scene or prefab exists. Hand-written `.unity` YAML rots, conflicts on every parallel
  edit, and hides mistakes behind GUIDs; the prototype scene is **built by code** from an
  Editor menu item instead, so it is reviewable as source. That menu item has never run.
- ❌ No network transport is wired up. `MatchSimulation` is authoritative by construction —
  the only way intent enters it is `SubmitInput`, which accepts a command and nothing else —
  and `LagCompensation` is tested against synthetic history. But nothing has crossed a
  socket, and "authoritative by construction" is a claim about the shape of the code, not a
  measurement.
- ❌ No performance number in `PROJECT_PLAN.md` has been measured on a device. They are
  budgets, not results.

Anything in this repository that falls below the first heading is marked as untested
wherever it appears. `TODO.md` uses `[~]` for exactly this.
