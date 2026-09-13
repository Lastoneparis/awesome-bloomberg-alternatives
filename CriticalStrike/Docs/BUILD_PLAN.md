# Critical Strike — Build Plan / Progress Tracker

This file is the checklist the build loop works through. Anything unchecked is not done yet.

## Phase 1 — Core foundations
- [x] SPM manifest, folder layout
- [x] Math (Vec3, ViewAngles, MathUtil, deterministic RNG, AABB/Ray/Sphere)
- [x] Core (EntityID/PlayerID/Team, GameClock+Timer, EventBus, Log)

## Phase 2 — Content data
- [x] WeaponData + 18-weapon roster + spray patterns
- [x] Attachments (6 slots, 20 parts) + WeaponBuild resolution
- [x] Surfaces + hitbox layout
- [x] Grenades / equipment
- [x] Characters (operators) + cosmetics/skins
- [x] Game mode definitions
- [x] Maps (geometry, spawns, objectives, navigation, cover)

## Phase 3 — Simulation
- [ ] Damage model (falloff, armor, penetration, hitboxes)
- [ ] Movement (accel/friction, crouch, slide, jump, air control, ladders)
- [ ] Weapon runtime state machine (fire/reload/ADS/switch/burst)
- [ ] Recoil + spread model
- [ ] Ballistics (hitscan, projectile, wallbang, ricochet)
- [ ] Grenade physics + effects (frag/flash/smoke/molotov)
- [ ] Collision world + spatial hash
- [ ] Player state, spawn selection, pickups
- [ ] Match/round state machine + all game modes
- [ ] Scoring, killfeed, streaks, economy (buy menu)

## Phase 4 — AI
- [ ] Bot perception (vision cones, hearing, memory)
- [ ] Bot combat (aim model per difficulty, burst discipline, strafing)
- [ ] Bot navigation (nav graph, A*, waypoint following)
- [ ] Bot objective behaviour per mode + difficulty tuning

## Phase 5 — Netcode
- [ ] Binary packet codec (bit-packing, quantization, delta compression)
- [ ] Protocol messages (handshake, input, snapshot, events, chat)
- [ ] Server simulation host (authoritative)
- [ ] Client prediction + reconciliation + entity interpolation
- [ ] Lag compensation (hit rewind)
- [ ] Matchmaking / lobby / party types
- [ ] Anti-cheat sanity validation

## Phase 6 — Economy & progression
- [ ] Currencies, store catalog, bundles
- [ ] Loot crates with published odds + pity timer
- [ ] Battle pass (free/premium tracks, tiers, rewards)
- [ ] Missions (daily/weekly/career)
- [ ] XP curve, ranks, unlocks, prestige
- [ ] Player stats tracking

## Phase 7 — Persistence
- [ ] Player profile model + atomic save store
- [ ] Settings model (graphics, audio, controls, HUD layout)

## Phase 8 — iOS app layer
- [ ] App entry, routing, coordinator, lifecycle
- [ ] SceneKit renderer: map building, materials, lighting, post-process
- [ ] Weapon viewmodel rig (sway, bob, ADS, recoil animation)
- [ ] Character rendering + animation + ragdoll
- [ ] Effects: muzzle flash, tracers, impacts, decals, blood, explosions, smoke
- [ ] Minimap, quality tiers, dynamic resolution
- [ ] Touch controls (joystick, look, fire, ADS, jump, crouch, grenades, aim assist)
- [ ] HUD (health/ammo/crosshair/hitmarker/killfeed/scoreboard/objectives)
- [ ] Menus: main, play/modes, loadout, armory, store, battle pass, missions, settings, profile, leaderboards, clan
- [ ] Audio engine (spatial, mixer, music, voice lines)
- [ ] StoreKit 2 IAP (consumables, non-consumables, subscription, restore)
- [ ] Game Center (auth, leaderboards, achievements, matchmaking)
- [ ] Network transport (WebSocket client, LAN host via Network.framework)
- [ ] Game session glue (sim + render + input + net)

## Phase 9 — Project & docs
- [ ] XcodeGen project.yml, Info.plist, entitlements, StoreKit config
- [ ] Unit tests for core systems
- [ ] README, ARCHITECTURE, GAMEPLAY, MONETIZATION, NETCODE docs
- [ ] Validation tooling + CI workflow
