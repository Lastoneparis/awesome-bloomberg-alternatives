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
- [x] Damage model (falloff, armor, penetration, hitboxes)
- [x] Movement (accel/friction, crouch, slide, jump, air control, ladders)
- [x] Weapon runtime state machine (fire/reload/ADS/switch/burst)
- [x] Recoil + spread model
- [x] Ballistics (hitscan, projectile, wallbang, ricochet)
- [x] Grenade physics + effects (frag/flash/smoke/molotov)
- [x] Collision world + spatial hash
- [x] Player state, spawn selection, pickups
- [x] Match/round state machine + all game modes
- [x] Scoring, killfeed, streaks, economy (buy menu)

## Phase 4 — AI
- [x] Bot perception (vision cones, hearing, memory)
- [x] Bot combat (aim model per difficulty, burst discipline, strafing)
- [x] Bot navigation (nav graph, A*, waypoint following)
- [x] Bot objective behaviour per mode + difficulty tuning

## Phase 5 — Netcode
- [x] Binary packet codec (bit-packing, quantization, delta compression)
- [x] Protocol messages (handshake, input, snapshot, events, chat)
- [x] Server simulation host (authoritative)
- [x] Client prediction + reconciliation + entity interpolation
- [x] Lag compensation (hit rewind)
- [x] Matchmaking / lobby / party types
- [x] Anti-cheat sanity validation

## Phase 6 — Economy & progression
- [x] Currencies, store catalog, bundles
- [x] Loot crates with published odds + pity timer
- [x] Battle pass (free/premium tracks, tiers, rewards)
- [x] Missions (daily/weekly/career)
- [x] XP curve, ranks, unlocks, prestige
- [x] Player stats tracking

## Phase 7 — Persistence
- [x] Player profile model + atomic save store
- [x] Settings model (graphics, audio, controls, HUD layout)

## Phase 8 — iOS app layer
- [x] App entry, routing, coordinator, lifecycle
- [x] SceneKit renderer: map building, materials, lighting, post-process
- [x] Weapon viewmodel rig (sway, bob, ADS, recoil animation)
- [x] Character rendering + animation + ragdoll
- [x] Effects: muzzle flash, tracers, impacts, decals, blood, explosions, smoke
- [x] Minimap, quality tiers, dynamic resolution
- [x] Touch controls (joystick, look, fire, ADS, jump, crouch, grenades, aim assist)
- [x] HUD (health/ammo/crosshair/hitmarker/killfeed/scoreboard/objectives)
- [x] Menus: main, play/modes, loadout, armory, store, battle pass, missions, settings, profile, leaderboards, clan
- [x] Audio engine (spatial, mixer, music, voice lines)
- [x] StoreKit 2 IAP (consumables, non-consumables, subscription, restore)
- [x] Game Center (auth, leaderboards, achievements, matchmaking)
- [x] Network transport (WebSocket client, LAN host via Network.framework)
- [x] Game session glue (sim + render + input + net)

## Phase 9 — Project & docs
- [x] XcodeGen project.yml, Info.plist, entitlements, StoreKit config
- [x] Unit tests for core systems
- [x] README, ARCHITECTURE, GAMEPLAY, MONETIZATION, NETCODE docs
- [x] Validation tooling + CI workflow
