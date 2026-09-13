# Critical Strike

A complete multiplayer first-person shooter for iOS — graphics, gameplay, multiplayer,
in-app purchases, progression and every supporting system — built in Swift with SceneKit
and SwiftUI.

```
CriticalStrike/
├── Package.swift                     SPM manifest (core library + tests)
├── project.yml                       XcodeGen project definition
├── Sources/
│   ├── CriticalStrikeCore/           Pure Swift. No UIKit, SceneKit or StoreKit.
│   │   ├── Math/                     Vectors, angles, deterministic RNG, geometry
│   │   ├── Core/                     Ids, clock, event bus, logging
│   │   ├── Data/                     Weapons, attachments, perks, maps, modes, cosmetics
│   │   ├── World/                    Collision world, navigation graph
│   │   ├── Combat/                   Damage, movement, weapons, recoil, ballistics
│   │   ├── Modes/                    Match simulation and the eleven game modes
│   │   ├── AI/                       Bot brains and the bot director
│   │   ├── Net/                      Bit streams, protocol, server, client, anti-cheat
│   │   ├── Economy/                  Currency, store, crates, battle pass, missions
│   │   ├── Progression/              XP, ranks, unlocks, stats
│   │   └── Persistence/              Profile, settings, atomic save store
│   └── CriticalStrikeApp/            The iOS app
│       ├── App/                      Entry point, routing, theme, app state
│       ├── Render/                   SceneKit renderer, materials, viewmodel, effects
│       ├── Input/                    Touch controls and aim assist
│       ├── Game/                     Session glue and HUD state
│       ├── UI/                       Every screen
│       ├── Store/                    StoreKit 2
│       ├── Net/                      WebSocket and LAN transports
│       ├── Audio/                    Spatial audio engine
│       └── Services/                 Game Center, haptics, ads, device tiers
├── Tests/CriticalStrikeCoreTests/    Unit and integration tests for the whole simulation
├── Support/                          Info.plist, entitlements, StoreKit config
├── Tools/validate.py                 Static checks that run without a Swift toolchain
└── Docs/                             Architecture, gameplay, netcode, monetisation
```

## Building

The project is generated rather than committed, so there is never a merge conflict in a
10,000-line `pbxproj`:

```sh
brew install xcodegen
cd CriticalStrike
xcodegen generate
open CriticalStrike.xcodeproj
```

Requires Xcode 15+, iOS 16+, and a device or simulator with Metal. Select the
`CriticalStrike` scheme and run. No accounts, servers or API keys are needed — the game
boots straight into a full match against bots.

The core library also builds standalone on any platform with a Swift toolchain:

```sh
swift build
swift test
python3 Tools/validate.py    # static checks with no toolchain at all
```

## What is implemented

**Gameplay** — Source-style movement (acceleration, friction, air control, crouch, slide,
step-up), a full weapon state machine, a two-part recoil model with learnable spray
patterns, hitscan ballistics with wall and body penetration, ten-part hitboxes with
distinct multipliers, armour with realistic throughput, grenades with real projectile
physics, and vision-blocking smoke.

**Content** — 18 weapons across 8 classes, 20 attachments that all carry a real downside,
9 perks, 7 grenade types, 8 operators, cosmetics, and five hand-built maps with spawns,
objectives, callouts, lighting and pickups.

**Modes** — Team Deathmatch, Free For All, Bomb Defusal, Domination, Gun Game, Search &
Rescue, Kill Confirmed, Hardpoint, One in the Chamber, Zombie Survival and a Training
Range, all behind one `GameModeRules` protocol.

**Bots** — Five difficulty profiles that scale reaction time and aim error rather than
damage. Bots see through view cones, hear footsteps and gunfire, path with A*, take cover,
push objectives, and produce the exact same `InputCommand` a human does.

**Multiplayer** — Authoritative server, client prediction with replay-based reconciliation,
entity interpolation, lag compensation, delta-compressed bit-packed snapshots, matchmaking,
LAN play over Bonjour, and anti-cheat input validation.

**Monetisation** — StoreKit 2 with consumables, non-consumables and an auto-renewing
subscription; a 100-tier battle pass; loot crates whose published odds are the odds the
code actually rolls; a daily shop; and rewarded ads that are always optional.

**Progression** — 55 levels with prestige, competitive ranks with Elo-style rating,
per-weapon attachment unlocks, lifetime stats, and daily/weekly/career missions.

**Presentation** — Procedurally generated materials (the app ships no bitmap textures), a
first-person viewmodel with sway, bob, ADS springs and recoil, pooled effects with budgets,
ragdolls, dynamic resolution driven by frame time and thermal state, spatial audio, and
Core Haptics feedback that distinguishes a body shot from a headshot.

**Accessibility** — Colour-blind palettes, a fully repositionable HUD, left-handed layout,
three fire modes including auto-fire, four aim-assist levels, and adjustable sensitivity
curves per aim state.

## Documentation

| Document | Contents |
| --- | --- |
| [ARCHITECTURE.md](Docs/ARCHITECTURE.md) | Layering, data flow, why the core is platform-free |
| [GAMEPLAY.md](Docs/GAMEPLAY.md) | Combat maths, movement, balance philosophy, mode rules |
| [NETCODE.md](Docs/NETCODE.md) | Prediction, reconciliation, interpolation, lag compensation |
| [MONETIZATION.md](Docs/MONETIZATION.md) | Every product, published crate odds, App Store compliance |
| [BUILD_PLAN.md](Docs/BUILD_PLAN.md) | The checklist this project was built against |

## Assets

The game ships with no bitmap textures, meshes or audio files. Materials and level geometry
are generated at runtime, and weapons and characters are assembled from primitives sized per
class. Sound effects are looked up by name and simply do not play if a file is absent, so
dropping real audio into the bundle is the only thing needed to complete the presentation.
