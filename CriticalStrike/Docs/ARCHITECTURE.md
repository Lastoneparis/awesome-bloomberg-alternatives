# Architecture

## The one rule

`CriticalStrikeCore` imports nothing but `Foundation`. No UIKit, no SceneKit, no StoreKit,
no SwiftUI. Everything that decides what happens in a match — movement, ballistics, damage,
game modes, bots, netcode, economy — lives there.

This is not architectural purity for its own sake. It buys three concrete things:

1. **The simulation is testable.** `Tests/CriticalStrikeCoreTests` runs a full ten-minute
   bot match, a bomb defusal round and forty thousand loot crate openings without a device,
   a window or a run loop.
2. **The server can reuse it verbatim.** A dedicated server binary is `GameServer` plus a
   socket; there is no second implementation of the rules to drift out of sync.
3. **Rendering can never change the game.** A renderer that cannot reach the simulation
   cannot accidentally make a visual effect affect a hitbox.

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ SwiftUI screens          AppState (profile, services, route)  │
├──────────────────────────────────────────────────────────────┤
│ GameSession   ← the only object that touches both sides       │
├───────────────────────────────┬──────────────────────────────┤
│ GameRenderer / TouchControls  │ MatchSimulation / GameServer  │
│ EffectsSystem / AudioEngine   │ BotDirector / GameClientSession│
├───────────────────────────────┴──────────────────────────────┤
│ CriticalStrikeCore — Foundation only                          │
└──────────────────────────────────────────────────────────────┘
```

## Data flow for one frame

```
SCNSceneRendererDelegate fires
   │
   ├─ TouchControls.buildCommand()        input + aim assist → InputCommand
   ├─ MatchSimulation.setInput()
   ├─ GameClock.advance()                 real time → N fixed 64Hz steps
   │    └─ for each step:
   │         BotDirector.step()           bots produce InputCommands too
   │         MatchSimulation.step()       movement, weapons, projectiles, modes
   │              └─ EventBus.emit(...)   the simulation's only output besides state
   ├─ GameRenderer.updateCamera()         reads the predicted local player
   ├─ GameRenderer.syncPlayers()          reads an interpolated WorldSnapshot
   └─ GameSession.handle(event)           drains events → effects, audio, haptics, HUD
```

The simulation never calls into the renderer. It appends to an `EventBus`, and the
presentation layer decides what a `bulletImpact` looks like and sounds like. Swapping
SceneKit for Metal or RealityKit would touch `Sources/CriticalStrikeApp/Render` and nothing
else.

## Fixed timestep

The simulation runs at exactly 64Hz. `GameClock` converts variable frame time into whole
steps and clamps catch-up to 8 ticks, so a stall (an incoming call, the app backgrounding)
can never produce a death spiral of a thousand queued steps. Snapshots go out at 20Hz,
which is the mobile bandwidth compromise; the gap is covered by interpolation on the client.

## Value types

`PlayerState` is a struct. So are `MatchState`, `WorldSnapshot` and every piece of content
data. Prediction, rollback and lag compensation all need to copy and rewind state cheaply,
and reference semantics make each of those a source of aliasing bugs. The few classes in
the core (`MatchSimulation`, `ProjectileSystem`, `BotBrain`, `NavGraph`, `EventBus`) are the
ones that genuinely own mutable identity.

## Determinism

`DeterministicRandom` (xoshiro128**) is used everywhere the outcome must be reproducible:
spray patterns, bot decisions, loot rolls, daily mission assignment, shop rotation. Seeding
the simulation the same way twice and feeding it the same inputs produces the same match,
which is what makes replay, server validation and the "same shop for everyone" behaviour
possible without a server round trip.

## Content as data

Weapons, attachments, perks, grenades, maps, modes, cosmetics, crates and the battle pass
are all plain `Codable` structs in `Sources/CriticalStrikeCore/Data`. Nothing about balance
is hardcoded in a system. That means a live-ops build can fetch a new `WeaponData` array as
JSON and ship a balance patch without an App Store review, and it means the balance tests in
`ContentIntegrityTests` can assert invariants across the whole roster at once.

## Maps

Maps are brush-based: arrays of axis-aligned boxes with a surface type. `MapAuthor` is a
small DSL (`room`, `wall`, `wallWithDoor`, `window`, `stairs`, `crate`) so a layout reads as
level design rather than coordinates. Collision is a uniform grid over those boxes, which is
fast enough that bots can raycast constantly. The navigation graph is baked at load time by
sampling the floor and linking walkable neighbours — no hand-placed waypoints, so a map
edit can never leave stale nav data behind.

## Concurrency

`AppState`, `GameSession`, `StoreKitService` and `GameCenterService` are `@MainActor`.
Everything in the core is main-actor-agnostic and free of shared mutable global state, with
the exception of `Log`'s configuration. The render-loop callback hops to the main actor
before touching the session, so there is exactly one thread mutating the simulation.
