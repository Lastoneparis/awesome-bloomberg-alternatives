import Foundation

/// Something the weapon system decided happened this tick, for the match to apply.
/// Keeping it declarative means the weapon state machine never needs write access to
/// other players — which is what makes prediction and rollback tractable.
public enum WeaponOutcome: Sendable {
    case hit(shooter: PlayerID, weapon: WeaponID, hit: ShotHit, damage: Float, headshot: Bool)
    case throwGrenade(player: PlayerID, kind: GrenadeKind, id: ContentID, origin: Vec3, velocity: Vec3)
    case meleeHit(shooter: PlayerID, hit: ShotHit, damage: Float, backstab: Bool)
}

public struct WeaponStepContext {
    public var world: CollisionWorld
    public var targets: [HitVolume]
    public var now: Float
    public var friendlyFire: Bool
    public var events: EventBus
    public var mode: GameModeKind

    public init(world: CollisionWorld, targets: [HitVolume], now: Float,
                friendlyFire: Bool, events: EventBus, mode: GameModeKind) {
        self.world = world; self.targets = targets; self.now = now
        self.friendlyFire = friendlyFire; self.events = events; self.mode = mode
    }
}

/// The weapon state machine: ADS, fire timing, burst, reload (including shell-by-shell),
/// weapon switching, melee and grenade throws.
public enum WeaponSystem {
    public static func step(player: inout PlayerState, input: InputCommand,
                            ctx: WeaponStepContext, rng: inout DeterministicRandom) -> [WeaponOutcome] {
        guard player.isAlive else { return [] }
        var outcomes: [WeaponOutcome] = []
        let dt = input.deltaTime
        let weapon = player.activeWeapon

        updateAiming(&player, input: input, weapon: weapon, dt: dt, ctx: ctx)
        RecoilSystem.decay(player: &player, weapon: weapon, dt: dt)
        player.fireCooldown = max(0, player.fireCooldown - dt)

        // Timed actions (reload, draw, holster, grenade wind-up) resolve first.
        if player.action != .ready && player.action != .firing {
            if player.actionTimer.tick(dt) {
                outcomes.append(contentsOf: completeAction(&player, ctx: ctx, rng: &rng))
            } else {
                return outcomes
            }
        }

        // Weapon switching.
        if let requested = input.requestedSlot, requested != player.activeSlot,
           player.slots[requested] != nil || requested == .lethal || requested == .tactical {
            beginSwitch(&player, to: requested, ctx: ctx)
            return outcomes
        }
        if input.buttons.contains(.swapWeapon) {
            let next: LoadoutSlot = player.activeSlot == .primary ? .secondary : .primary
            if player.slots[next] != nil {
                beginSwitch(&player, to: next, ctx: ctx)
                return outcomes
            }
        }

        // Grenades.
        if input.buttons.contains(.lethal), player.lethalCount > 0 {
            beginGrenade(&player, id: player.lethalID, ctx: ctx)
            return outcomes
        }
        if input.buttons.contains(.tactical), player.tacticalCount > 0 {
            beginGrenade(&player, id: player.tacticalID, ctx: ctx)
            return outcomes
        }

        // Quick melee.
        if input.buttons.contains(.melee), player.activeSlot != .melee {
            outcomes.append(contentsOf: quickMelee(&player, ctx: ctx))
            return outcomes
        }

        // Reload.
        if input.buttons.contains(.reload), let slot = player.slots[player.activeSlot], slot.canReload {
            beginReload(&player, ctx: ctx)
            return outcomes
        }

        // Fire.
        let wantsFire = input.buttons.contains(.fire)
        if player.slots[player.activeSlot]?.burstRemaining ?? 0 > 0 {
            outcomes.append(contentsOf: tryFire(&player, ctx: ctx, rng: &rng, forced: true))
        } else if wantsFire {
            outcomes.append(contentsOf: tryFire(&player, ctx: ctx, rng: &rng, forced: false))
        } else {
            player.action = .ready
            // Releasing the trigger re-arms semi-automatic weapons.
            if var slot = player.slots[player.activeSlot] {
                slot.burstRemaining = 0
                player.slots[player.activeSlot] = slot
            }
            player.semiTriggerReady = true
        }

        // Auto-reload when the magazine runs dry and the player keeps holding fire.
        if let slot = player.slots[player.activeSlot], slot.isEmpty, slot.canReload,
           player.action == .ready, wantsFire {
            beginReload(&player, ctx: ctx)
        }

        return outcomes
    }

    // MARK: - Aiming

    private static func updateAiming(_ player: inout PlayerState, input: InputCommand,
                                     weapon: WeaponData, dt: Float, ctx: WeaponStepContext) {
        let wantsAim = input.buttons.contains(.aim) && weapon.weaponClass != .melee
            && player.action != .reloading && player.action != .throwingGrenade
        player.isAiming = wantsAim
        let adsTime = max(0.05, weapon.adsTime * player.perks.adsTimeScale)
        let target: Float = wantsAim ? 1 : 0
        let rate = dt / adsTime
        player.adsProgress = MathUtil.clamp(player.adsProgress + (target > player.adsProgress ? rate : -rate), 0, 1)
        if !wantsAim { player.scopeLevel = 0 }
        if input.buttons.contains(.scopeToggle), wantsAim, !weapon.scopeLevels.isEmpty {
            player.scopeLevel = (player.scopeLevel + 1) % weapon.scopeLevels.count
        }
    }

    // MARK: - Firing

    private static func tryFire(_ player: inout PlayerState, ctx: WeaponStepContext,
                                rng: inout DeterministicRandom, forced: Bool) -> [WeaponOutcome] {
        guard var slot = player.slots[player.activeSlot] else { return [] }
        let weapon = slot.resolvedWeapon
        guard player.fireCooldown <= 0 else { return [] }

        // Semi/bolt/pump weapons need a fresh trigger pull per shot.
        if !forced && !weapon.fireMode.isAutomatic && !player.semiTriggerReady { return [] }

        if weapon.weaponClass == .melee {
            player.semiTriggerReady = false
            return meleeAttack(&player, weapon: weapon, ctx: ctx)
        }

        guard slot.ammoInMagazine > 0 else {
            if player.fireCooldown <= 0 {
                ctx.events.emit(.weaponDryFire(player: player.id))
                player.fireCooldown = 0.25
                player.semiTriggerReady = false
            }
            return []
        }

        // Sliding and sprinting block fire briefly, which is what gives sprint a cost.
        if player.stance == .sliding && weapon.weaponClass != .pistol { return [] }

        slot.ammoInMagazine -= 1
        let shotIndex = slot.shotsFiredInSpray
        slot.shotsFiredInSpray += 1
        if weapon.fireMode == .burst {
            if slot.burstRemaining <= 0 {
                slot.burstRemaining = weapon.burstCount - 1
            } else {
                slot.burstRemaining -= 1
            }
        }
        player.slots[player.activeSlot] = slot
        player.semiTriggerReady = false
        player.action = .firing
        player.lastFireTime = ctx.now
        player.fireCooldown = (weapon.fireMode == .burst && slot.burstRemaining == 0)
            ? weapon.burstDelay : weapon.fireInterval

        let spread = RecoilSystem.effectiveSpread(player: player, weapon: weapon)
        let origin = player.eyePosition
        let aim = RecoilSystem.aimDirection(for: player)
        let damageScale: Float = player.hasDoubleDamage(now: ctx.now) ? 2 : 1

        var outcomes: [WeaponOutcome] = []
        let result: ShotResult
        if weapon.pelletsPerShot > 1 {
            result = BallisticsSystem.fireSpread(origin: origin, direction: aim, spread: spread,
                                                 weapon: weapon, shooter: player.id,
                                                 shooterTeam: player.team, friendlyFire: ctx.friendlyFire,
                                                 world: ctx.world, targets: ctx.targets, rng: &rng)
        } else {
            let dir = RecoilSystem.spreadDirection(aim, spread: spread, rng: &rng)
            result = BallisticsSystem.fireBullet(origin: origin, direction: dir, weapon: weapon,
                                                 shooter: player.id, shooterTeam: player.team,
                                                 friendlyFire: ctx.friendlyFire, world: ctx.world,
                                                 targets: ctx.targets)
        }

        for hit in result.hits {
            let base = weapon.baseDamage * damageScale
            outcomes.append(.hit(shooter: player.id, weapon: weapon.id, hit: hit,
                                 damage: base, headshot: hit.hitbox.isHead))
        }
        for impact in result.impacts where impact.surface != .flesh {
            ctx.events.emit(.bulletImpact(position: impact.position, normal: impact.normal,
                                          surface: impact.surface, penetrated: impact.penetrated))
        }
        ctx.events.emit(.bulletTracer(from: origin, to: result.tracerEnd, weapon: weapon.id))
        ctx.events.emit(.weaponFired(player: player.id, weapon: weapon.id, origin: origin,
                                     direction: aim, ammoLeft: slot.ammoInMagazine))

        RecoilSystem.applyShot(player: &player, weapon: weapon, shotIndex: shotIndex, rng: &rng)
        return outcomes
    }

    private static func meleeAttack(_ player: inout PlayerState, weapon: WeaponData,
                                    ctx: WeaponStepContext) -> [WeaponOutcome] {
        player.fireCooldown = weapon.fireInterval
        player.action = .meleeSwing
        player.actionTimer.start(weapon.fireInterval * 0.5)
        ctx.events.emit(.weaponFired(player: player.id, weapon: weapon.id,
                                     origin: player.eyePosition, direction: player.angles.forward,
                                     ammoLeft: 0))
        guard let hit = BallisticsSystem.meleeSwing(origin: player.eyePosition,
                                                    direction: player.angles.forward,
                                                    weapon: weapon, shooter: player.id,
                                                    shooterTeam: player.team,
                                                    friendlyFire: ctx.friendlyFire,
                                                    world: ctx.world, targets: ctx.targets) else { return [] }
        let victim = ctx.targets.first { $0.player == hit.victim }
        let backstab = victim.map {
            BallisticsSystem.isBackstab(attackerPosition: player.position,
                                        victimPosition: $0.position, victimYaw: player.angles.yaw)
        } ?? false
        let damage = backstab ? 200 : weapon.baseDamage
        return [.meleeHit(shooter: player.id, hit: hit, damage: damage, backstab: backstab)]
    }

    private static func quickMelee(_ player: inout PlayerState, ctx: WeaponStepContext) -> [WeaponOutcome] {
        guard player.fireCooldown <= 0 else { return [] }
        let knife = WeaponDatabase.weaponOrDefault(player.loadout.melee.weapon)
        return meleeAttack(&player, weapon: knife, ctx: ctx)
    }

    // MARK: - Reload / switch / grenade

    private static func beginReload(_ player: inout PlayerState, ctx: WeaponStepContext) {
        guard let slot = player.slots[player.activeSlot], slot.canReload else { return }
        let weapon = slot.resolvedWeapon
        let base = slot.isEmpty ? weapon.emptyReloadTime : weapon.reloadTime
        let duration = max(0.15, base * player.perks.reloadScale)
        player.action = .reloading
        player.isAiming = false
        player.actionTimer.start(weapon.shellByShellReload ? duration : duration)
        ctx.events.emit(.weaponReloadStarted(player: player.id, weapon: weapon.id, duration: duration))
    }

    private static func beginSwitch(_ player: inout PlayerState, to slot: LoadoutSlot,
                                    ctx: WeaponStepContext) {
        let current = player.activeWeapon
        player.pendingSlot = slot
        player.action = .holstering
        player.isAiming = false
        player.adsProgress = 0
        player.actionTimer.start(max(0.08, current.holsterTime))
    }

    private static func beginGrenade(_ player: inout PlayerState, id: ContentID,
                                     ctx: WeaponStepContext) {
        guard let data = GrenadeDatabase.grenade(id) else { return }
        player.pendingGrenade = id
        player.action = .throwingGrenade
        player.isAiming = false
        player.actionTimer.start(0.45)
        _ = data
    }

    private static func completeAction(_ player: inout PlayerState, ctx: WeaponStepContext,
                                       rng: inout DeterministicRandom) -> [WeaponOutcome] {
        switch player.action {
        case .reloading:
            finishReload(&player, ctx: ctx)
        case .holstering:
            if let pending = player.pendingSlot {
                player.activeSlot = pending
                player.pendingSlot = nil
                let weapon = player.activeWeapon
                player.action = .drawing
                player.actionTimer.start(max(0.08, weapon.drawTime))
                ctx.events.emit(.weaponSwitched(player: player.id, weapon: weapon.id, slot: pending))
                return []
            }
            player.action = .ready
        case .drawing, .meleeSwing:
            player.action = .ready
            if var slot = player.slots[player.activeSlot] {
                slot.shotsFiredInSpray = 0
                player.slots[player.activeSlot] = slot
            }
        case .throwingGrenade:
            let outcomes = releaseGrenade(&player, ctx: ctx)
            player.action = .drawing
            player.actionTimer.start(0.3)
            return outcomes
        default:
            player.action = .ready
        }
        return []
    }

    private static func finishReload(_ player: inout PlayerState, ctx: WeaponStepContext) {
        guard var slot = player.slots[player.activeSlot] else { return }
        let weapon = slot.resolvedWeapon
        if weapon.shellByShellReload {
            // One shell at a time: keep looping while the trigger stays off.
            let needed = min(1, weapon.magazineSize - slot.ammoInMagazine)
            let loaded = min(needed, slot.reserveAmmo)
            slot.ammoInMagazine += loaded
            slot.reserveAmmo -= loaded
            slot.shotsFiredInSpray = 0
            player.slots[player.activeSlot] = slot
            if slot.canReload {
                player.actionTimer.start(max(0.15, weapon.reloadTime * player.perks.reloadScale))
                player.action = .reloading
                return
            }
        } else {
            let needed = weapon.magazineSize - slot.ammoInMagazine
            let loaded = min(needed, slot.reserveAmmo)
            slot.ammoInMagazine += loaded
            slot.reserveAmmo -= loaded
            slot.shotsFiredInSpray = 0
            player.slots[player.activeSlot] = slot
        }
        player.action = .ready
        ctx.events.emit(.weaponReloadFinished(player: player.id, weapon: weapon.id))
    }

    private static func releaseGrenade(_ player: inout PlayerState, ctx: WeaponStepContext) -> [WeaponOutcome] {
        guard let id = player.pendingGrenade, let data = GrenadeDatabase.grenade(id) else { return [] }
        player.pendingGrenade = nil
        if data.kind.slot == .lethal {
            guard player.lethalCount > 0 else { return [] }
            player.lethalCount -= 1
        } else {
            guard player.tacticalCount > 0 else { return [] }
            player.tacticalCount -= 1
        }
        let origin = player.eyePosition + player.angles.forward * 0.5
        // Looking down = short underhand lob; looking up = full overhand throw.
        let pitchFactor = MathUtil.unlerp(-0.5, 0.6, player.angles.pitch)
        let speed = MathUtil.lerp(data.lobSpeed, data.throwSpeed, pitchFactor)
        let velocity = player.angles.forward * speed + Vec3(0, 1.2, 0) + player.velocity * 0.5
        return [.throwGrenade(player: player.id, kind: data.kind, id: id,
                              origin: origin, velocity: velocity)]
    }

    /// Gun Game and pickups replace a slot wholesale.
    public static func giveWeapon(_ player: inout PlayerState, build: WeaponBuild,
                                  slot: LoadoutSlot, equip: Bool, ctx: WeaponStepContext) {
        player.slots[slot] = WeaponSlotState(build: build, extraMagazines: player.perks.extraMagazines)
        if equip {
            player.activeSlot = slot
            player.action = .drawing
            player.actionTimer.start(max(0.1, build.resolved().drawTime))
            ctx.events.emit(.weaponSwitched(player: player.id, weapon: build.weapon, slot: slot))
        }
    }
}
