import Foundation

extension MatchSimulation {
    // MARK: - Weapon outcomes

    func applyOutcomes(_ outcomes: [WeaponOutcome], from shooter: PlayerID) {
        for outcome in outcomes {
            switch outcome {
            case let .hit(shooterID, weaponID, hit, damage, headshot):
                let weapon = WeaponDatabase.weaponOrDefault(weaponID)
                recordHit(shooterID)
                applyBulletDamage(to: hit.victim, from: shooterID, weapon: weapon,
                                  base: damage, hit: hit, headshot: headshot)

            case let .meleeHit(shooterID, hit, damage, backstab):
                let knife = WeaponDatabase.weaponOrDefault(players[shooterID]?.loadout.melee.weapon
                                                           ?? WeaponDatabase.defaultMelee)
                recordHit(shooterID)
                applyBulletDamage(to: hit.victim, from: shooterID, weapon: knife,
                                  base: damage, hit: hit, headshot: backstab)

            case let .throwGrenade(player, kind, id, origin, velocity):
                let team = players[player]?.team ?? .none
                projectiles.spawn(owner: player, team: team, grenadeID: id, kind: kind,
                                  origin: origin, velocity: velocity, events: events)
            }
        }
        _ = shooter
    }

    private func applyBulletDamage(to victimID: PlayerID, from attackerID: PlayerID,
                                   weapon: WeaponData, base: Float, hit: ShotHit, headshot: Bool) {
        guard let victim = players[victimID], victim.isAlive else { return }
        guard !victim.isInvulnerable(now: time) else { return }

        let resistance: Float = victim.hasOvershield(now: time) ? 0.4 : 0
        let result = DamageModel.resolve(base: base, distance: hit.distance, weapon: weapon,
                                         hitbox: hit.hitbox, armor: victim.armor,
                                         penetratedSurfaces: hit.penetratedSurfaces,
                                         hasHelmet: victim.hasHelmet, resistance: resistance)
        guard result.total > 0 else { return }

        var died = false
        mutatePlayer(victimID) { p in
            died = p.applyDamage(result, from: attackerID, now: self.time)
            if hit.hitbox.appliesSlow { p.slowUntil = max(p.slowUntil, self.time + 0.8) }
        }
        mutatePlayer(attackerID) { p in
            p.damageDealt += result.total
            if headshot { p.headshots += 1 }
        }

        events.emit(.playerDamaged(victim: victimID, attacker: attackerID, amount: result.total,
                                   hitbox: hit.hitbox, position: hit.position))
        events.emit(.hitConfirmed(attacker: attackerID, lethal: died, headshot: headshot,
                                  damage: result.total))

        if died {
            killPlayer(victimID, killer: attackerID, weapon: weapon.id,
                       headshot: headshot, wallbang: hit.penetratedSurfaces > 0)
        }
    }

    /// Generic damage entry point (fire, explosions, fall damage, scripted sources).
    public func applyDamage(to victimID: PlayerID, from attackerID: PlayerID, amount: Float,
                            hitbox: HitboxKind, weapon: WeaponID, isExplosive: Bool,
                            position: Vec3) {
        guard let victim = players[victimID], victim.isAlive, amount > 0 else { return }
        if attackerID != victimID && victim.isInvulnerable(now: time) { return }

        // Explosives mostly bypass armor; they are stopped by resistance perks instead.
        let result = isExplosive
            ? DamageResult(health: amount * (1 - victim.perks.explosiveResistance),
                           armor: min(victim.armor, amount * 0.25))
            : DamageResult(health: amount, armor: 0)

        var died = false
        mutatePlayer(victimID) { p in
            died = p.applyDamage(result, from: attackerID, now: self.time)
        }
        if attackerID != victimID {
            mutatePlayer(attackerID) { $0.damageDealt += result.total }
        }
        events.emit(.playerDamaged(victim: victimID, attacker: attackerID, amount: result.total,
                                   hitbox: hitbox, position: position))
        if died {
            killPlayer(victimID, killer: attackerID, weapon: weapon, headshot: false, wallbang: false)
        }
    }

    // MARK: - Death

    public func killPlayer(_ victimID: PlayerID, killer killerID: PlayerID, weapon: WeaponID,
                           headshot: Bool, wallbang: Bool) {
        guard var victim = players[victimID], victim.isAlive else { return }
        victim.isAlive = false
        victim.health = 0
        victim.stance = .dead
        victim.velocity = .zero
        victim.deaths += 1
        victim.currentStreak = 0
        victim.respawnTimer.start(state.mode.respawnDelay)
        let dropPosition = victim.position
        let carriedBomb = victim.hasBomb
        victim.hasBomb = false
        let credits = victim.pendingDamageCredits
        victim.pendingDamageCredits.removeAll()
        players[victimID] = victim

        let suicide = killerID == victimID || !killerID.isValid
        let killerName = suicide ? victim.name : (players[killerID]?.name ?? "—")
        let killerTeam = suicide ? victim.team : (players[killerID]?.team ?? .none)
        let teamKill = !suicide && killerTeam == victim.team && victim.team != .none

        // Scoring.
        if !suicide, var killer = players[killerID] {
            if teamKill {
                killer.score -= 50
                killer.kills -= 1
            } else {
                killer.kills += 1
                killer.currentStreak += 1
                killer.bestStreak = max(killer.bestStreak, killer.currentStreak)
                killer.score += headshot ? 125 : 100
                if wallbang { killer.score += 25 }
                killer.health = min(killer.maxHealth, killer.health + (state.mode.kind == .freeForAll ? 25 : 0))
                if state.mode.kind == .oneInTheChamber, var slot = killer.slots[killer.activeSlot] {
                    slot.ammoInMagazine += 1
                    killer.slots[killer.activeSlot] = slot
                }
            }
            players[killerID] = killer

            if !teamKill {
                let weaponData = WeaponDatabase.weaponOrDefault(weapon)
                giveMoney(killerID, state.mode.killReward > 0 ? weaponData.killReward : 0)
                awardXP(killerID, headshot ? 150 : 100, reason: headshot ? "Headshot Kill" : "Kill")
                if wallbang { awardXP(killerID, 50, reason: "Wallbang") }
                if killer.currentStreak >= 3 {
                    events.emit(.killStreak(player: killerID, count: killer.currentStreak))
                    awardXP(killerID, killer.currentStreak * 25, reason: "\(killer.currentStreak) Streak")
                }
                if !state.firstBloodTaken {
                    state.firstBloodTaken = true
                    events.emit(.firstBlood(player: killerID))
                    awardXP(killerID, 100, reason: "First Blood")
                }
                if killer.perks.revealsOnKill { revealEnemies(around: dropPosition, for: killerTeam) }
            }
        }

        // Assists: anyone who did meaningful damage in the last few seconds.
        for (assister, damage) in credits where assister != killerID && damage >= 25 {
            mutatePlayer(assister) { p in
                p.assists += 1
                p.score += 50
            }
            awardXP(assister, 50, reason: "Assist")
            events.emit(.assist(player: assister, victim: victimID))
        }

        events.emit(.playerDied(victim: victimID, killer: killerID, weapon: weapon,
                                headshot: headshot, wallbang: wallbang))
        pushKillFeed(KillFeedEntry(killerName: killerName, victimName: victim.name,
                                   killerTeam: killerTeam, victimTeam: victim.team,
                                   weapon: weapon, headshot: headshot, wallbang: wallbang,
                                   timestamp: time))

        // Drop what the player was carrying.
        if carriedBomb {
            spawnPickup(kind: .bomb, at: dropPosition + Vec3(0, 0.3, 0))
            events.emit(.bombDropped(position: dropPosition))
        }
        if let slot = victim.slots[victim.activeSlot], slot.resolvedWeapon.weaponClass != .melee,
           state.mode.kind.usesBuyMenu {
            spawnPickup(kind: .weapon, at: dropPosition + Vec3(0, 0.3, 0),
                        weapon: slot.build.weapon, ammo: slot.ammoInMagazine)
            events.emit(.weaponDropped(entity: EntityID(rawValue: 0), weapon: slot.build.weapon,
                                       position: dropPosition, ammo: slot.ammoInMagazine))
        }

        currentRules.playerKilled(sim: self, victim: victimID, killer: killerID,
                                  weapon: weapon, headshot: headshot, position: dropPosition)
    }

    private func revealEnemies(around position: Vec3, for team: Team) {
        for id in playerOrder {
            guard let p = players[id], p.isAlive, p.team != team else { continue }
            guard p.position.distance(to: position) < 20 else { continue }
            mutatePlayer(id) { $0.lastNoiseTime = self.time; $0.lastNoisePosition = $0.position }
        }
    }

    // MARK: - Explosions

    func resolveExplosion(_ explosion: ExplosionEvent) {
        switch explosion.kind {
        case .flash:
            applyFlash(explosion)
        case .stun:
            applyStun(explosion)
            applyBlastDamage(explosion)
        case .smoke, .decoy:
            break
        default:
            applyBlastDamage(explosion)
        }
    }

    private func applyBlastDamage(_ explosion: ExplosionEvent) {
        let data = explosion.data
        guard data.damage > 0 else { return }
        for id in playerOrder {
            guard let p = players[id], p.isAlive else { continue }
            let centre = p.position + Vec3(0, 0.9, 0)
            let distance = centre.distance(to: explosion.position)
            guard distance <= data.outerRadius else { continue }
            let occluded = !world.hasLineOfSight(from: explosion.position + Vec3(0, 0.2, 0), to: centre)
            var damage = DamageModel.explosion(damage: data.damage, innerRadius: data.innerRadius,
                                               outerRadius: data.outerRadius, distance: distance,
                                               occluded: occluded,
                                               resistance: p.perks.explosiveResistance)
            if id == explosion.owner {
                damage *= data.selfDamageScale
            } else if p.team == explosion.team && p.team != .none {
                guard state.mode.friendlyFire else { continue }
                damage *= data.teamDamageScale
            }
            guard damage > 0.5 else { continue }
            applyDamage(to: id, from: explosion.owner, amount: damage, hitbox: .chest,
                        weapon: WeaponID(explosion.data.id.value), isExplosive: true, position: centre)
        }
    }

    private func applyFlash(_ explosion: ExplosionEvent) {
        let data = explosion.data
        for id in playerOrder {
            guard let p = players[id], p.isAlive else { continue }
            let eye = p.eyePosition
            let occluded = !world.hasLineOfSight(from: explosion.position, to: eye)
            let intensity = DamageModel.flashIntensity(eye: eye, viewForward: p.angles.forward,
                                                       flashPosition: explosion.position,
                                                       radius: data.effectRadius, occluded: occluded,
                                                       resistance: p.perks.flashResistance)
            guard intensity > 0.05 else { continue }
            let duration = data.effectDuration * intensity
            mutatePlayer(id) {
                $0.flashAmount = max($0.flashAmount, intensity)
                $0.flashDecayRate = 1 / max(0.3, duration)
            }
            events.emit(.flashed(player: id, intensity: intensity, duration: duration))
        }
        applyBlastDamage(explosion)
    }

    private func applyStun(_ explosion: ExplosionEvent) {
        let data = explosion.data
        for id in playerOrder {
            guard let p = players[id], p.isAlive else { continue }
            let distance = p.position.distance(to: explosion.position)
            guard distance <= data.effectRadius else { continue }
            let occluded = !world.hasLineOfSight(from: explosion.position, to: p.eyePosition)
            guard !occluded else { continue }
            let strength = (1 - MathUtil.unlerp(0, data.effectRadius, distance))
                * (1 - p.perks.flashResistance * 0.5)
            mutatePlayer(id) { $0.stunAmount = max($0.stunAmount, strength) }
        }
    }

    /// The bomb going off — a much bigger, non-negotiable blast.
    func detonateBomb(at position: Vec3) {
        for id in playerOrder {
            guard let p = players[id], p.isAlive else { continue }
            let distance = p.position.distance(to: position)
            let damage = DamageModel.explosion(damage: BombState.explosionDamage,
                                               innerRadius: BombState.explosionInnerRadius,
                                               outerRadius: BombState.explosionOuterRadius,
                                               distance: distance, occluded: false,
                                               resistance: p.perks.explosiveResistance * 0.5)
            guard damage > 0 else { continue }
            applyDamage(to: id, from: .none, amount: damage, hitbox: .chest,
                        weapon: "bomb", isExplosive: true, position: p.position)
        }
        events.emit(.bombExploded(position: position))
    }
}
