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
├── Tools/                            Static checks and asset generation, no toolchain needed
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
python3 Tools/validate.py     # delimiters, duplicate declarations, known mistakes
python3 Tools/symbolcheck.py  # every referenced type is declared somewhere
python3 Tools/argorder.py     # Swift requires arguments in declaration order
python3 Tools/conformance.py  # every type claiming a protocol implements it
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

**Audio** — A full procedural synthesis pipeline: oscillators, noise, envelopes, a
state-variable filter, saturation and a comb-filter room, composed into every gunshot,
footstep, impact, announcement, ambience bed and music track in the game. Weapon reports
are derived from the same `WeaponData` the damage model reads, so a heavier round really
does sound heavier and rebalancing a weapon rebalances how it sounds. Spatialised through
`AVAudioEnvironmentNode` with pooled voices. See [AUDIO.md](Docs/AUDIO.md).

**Presentation** — A full procedural PBR pipeline: tileable noise → height field → albedo,
normal, roughness, occlusion and metalness, generated in parallel during loading and cached
to disk. Generated skyboxes that also drive image-based lighting, world-space UVs so texel
density is constant across the level, a first-person viewmodel with sway, bob, ADS springs
and recoil, sprite-backed effects with budgets, ragdolls, dynamic resolution driven by frame
time and thermal state, spatial audio, and Core Haptics feedback that distinguishes a body
shot from a headshot.

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
| [TEXTURES.md](Docs/TEXTURES.md) | The procedural art pipeline, with preview sheets |
| [AUDIO.md](Docs/AUDIO.md) | The procedural audio pipeline, with waveform sheets |
| [BUILD_PLAN.md](Docs/BUILD_PLAN.md) | The checklist this project was built against |

## Assets

The game ships with no painted textures, no meshes and no baked lighting. Every material —
twelve world surfaces, ten weapon finishes, every particle sprite, every bullet hole, and
the skyboxes — is generated on the device at load time from tileable noise, with albedo,
normal, roughness, occlusion and metalness maps all derived from one shared height field so
the lighting agrees with the visible detail. See [TEXTURES.md](Docs/TEXTURES.md).

The only committed images are the App Store icon and the menu wordmark, which have to exist
before the app launches; both are produced by `Tools/generate_assets.py`, which includes its
own PNG encoder so there is nothing to install.

Sound is generated the same way. `AudioEngine` looks sounds up by name, as it always did,
and a bundled file of that name still wins — so real recordings can be dropped in later
without touching a line of the synthesis. Until then every sound in the game is built from
noise, sines and filters at load time.
