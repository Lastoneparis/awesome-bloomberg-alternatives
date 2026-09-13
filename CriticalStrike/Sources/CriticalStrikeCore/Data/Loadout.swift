import Foundation

/// A saved class. Players get five slots and can rename them.
public struct Loadout: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var character: CharacterID
    public var primary: WeaponBuild
    public var secondary: WeaponBuild
    public var melee: WeaponBuild
    public var lethal: ContentID
    public var tactical: ContentID
    public var perks: [ContentID]
    public var bannerID: SkinID?
    public var titleID: SkinID?

    public init(id: UUID = UUID(), name: String, character: CharacterID,
                primary: WeaponBuild, secondary: WeaponBuild, melee: WeaponBuild,
                lethal: ContentID = GrenadeDatabase.defaultLethal,
                tactical: ContentID = GrenadeDatabase.defaultTactical,
                perks: [ContentID] = [], bannerID: SkinID? = nil, titleID: SkinID? = nil) {
        self.id = id; self.name = name; self.character = character
        self.primary = primary; self.secondary = secondary; self.melee = melee
        self.lethal = lethal; self.tactical = tactical; self.perks = perks
        self.bannerID = bannerID; self.titleID = titleID
    }

    public static func starter(name: String = "Assault") -> Loadout {
        Loadout(name: name,
                character: "chr_recruit_strike",
                primary: WeaponBuild(weapon: WeaponDatabase.defaultPrimary),
                secondary: WeaponBuild(weapon: WeaponDatabase.defaultSecondary),
                melee: WeaponBuild(weapon: WeaponDatabase.defaultMelee),
                perks: ["perk_lightfoot", "perk_scavenger", "perk_quickhands"])
    }

    public static func defaultSet() -> [Loadout] {
        var assault = Loadout.starter(name: "Assault")
        assault.primary = WeaponBuild(weapon: "ar_vanguard", attachments: ["opt_reddot", "grp_vertical"])

        var rusher = Loadout.starter(name: "Rusher")
        rusher.primary = WeaponBuild(weapon: "smg_wasp", attachments: ["las_tactical", "stk_light"])
        rusher.lethal = "nade_impact"
        rusher.tactical = "nade_flash"
        rusher.perks = ["perk_lightfoot", "perk_scavenger", "perk_quickhands"]

        var marksman = Loadout.starter(name: "Marksman")
        marksman.primary = WeaponBuild(weapon: "snp_longbow", attachments: ["bar_longbarrel", "stk_heavy"])
        marksman.secondary = WeaponBuild(weapon: "pst_magnum")
        marksman.tactical = "nade_smoke"
        marksman.perks = ["perk_ghost", "perk_resilience", "perk_regen"]

        var support = Loadout.starter(name: "Support")
        support.primary = WeaponBuild(weapon: "lmg_bulwark", attachments: ["opt_holo", "grp_bipod"])
        support.lethal = "nade_frag"
        support.tactical = "nade_smoke"
        support.perks = ["perk_juggernaut", "perk_demolition", "perk_regen"]

        var breacher = Loadout.starter(name: "Breacher")
        breacher.primary = WeaponBuild(weapon: "sg_breaker", attachments: ["las_tactical"])
        breacher.lethal = "nade_molotov"
        breacher.tactical = "nade_stun"
        breacher.perks = ["perk_juggernaut", "perk_demolition", "perk_quickhands"]

        return [assault, rusher, marksman, support, breacher]
    }

    /// Aggregated perk effects, applied once at spawn.
    public var perkEffects: PerkEffects {
        var e = PerkEffects()
        for id in perks.prefix(3) {
            guard let p = PerkDatabase.perk(id) else { continue }
            e.moveSpeedScale *= p.moveSpeedScale
            e.healthBonus += p.healthBonus
            e.armorBonus += p.armorBonus
            e.reloadScale *= p.reloadScale
            e.adsTimeScale *= p.adsTimeScale
            e.explosiveResistance = max(e.explosiveResistance, p.explosiveResistance)
            e.flashResistance = max(e.flashResistance, p.flashResistance)
            e.footstepVolumeScale *= p.footstepVolumeScale
            e.extraMagazines += p.extraMagazines
            e.extraGrenades += p.extraGrenades
            e.regenDelayScale *= p.regenDelayScale
            e.fallDamageScale *= p.fallDamageScale
            e.revealsOnKill = e.revealsOnKill || p.revealsOnKill
            e.silentOnMinimap = e.silentOnMinimap || p.silentOnMinimap
        }
        if let c = CharacterDatabase.character(character) {
            e.moveSpeedScale *= c.moveSpeedScale
            e.healthBonus += c.healthBonus
            e.reloadScale *= c.reloadScale
        }
        return e
    }

    public func build(for slot: LoadoutSlot) -> WeaponBuild? {
        switch slot {
        case .primary: return primary
        case .secondary: return secondary
        case .melee: return melee
        default: return nil
        }
    }

    /// Rejects a loadout the player hasn't actually unlocked (also re-checked server-side).
    public func validated(against unlocks: UnlockState, level: Int) -> Loadout {
        var out = self
        func fixWeapon(_ b: WeaponBuild, fallback: WeaponID) -> WeaponBuild {
            var build = b
            let w = WeaponDatabase.weapon(b.weapon)
            if w == nil || w!.unlockLevel > level || !unlocks.hasWeapon(b.weapon) {
                build = WeaponBuild(weapon: fallback)
            }
            build.attachments = build.attachments.filter { unlocks.hasAttachment($0, on: build.weapon) }
            if let s = build.skin, !unlocks.hasCosmetic(s) { build.skin = nil }
            return build
        }
        out.primary = fixWeapon(primary, fallback: WeaponDatabase.defaultPrimary)
        out.secondary = fixWeapon(secondary, fallback: WeaponDatabase.defaultSecondary)
        out.melee = fixWeapon(melee, fallback: WeaponDatabase.defaultMelee)
        if !unlocks.hasCharacter(character) { out.character = "chr_recruit_strike" }
        out.perks = perks.filter { id in
            guard let p = PerkDatabase.perk(id) else { return false }
            return p.unlockLevel <= level && unlocks.hasPerk(id)
        }
        if (GrenadeDatabase.grenade(lethal)?.unlockLevel ?? 99) > level { out.lethal = GrenadeDatabase.defaultLethal }
        if (GrenadeDatabase.grenade(tactical)?.unlockLevel ?? 99) > level { out.tactical = GrenadeDatabase.defaultTactical }
        return out
    }
}

public struct PerkEffects: Codable, Equatable, Sendable {
    public var moveSpeedScale: Float = 1
    public var healthBonus: Float = 0
    public var armorBonus: Float = 0
    public var reloadScale: Float = 1
    public var adsTimeScale: Float = 1
    public var explosiveResistance: Float = 0
    public var flashResistance: Float = 0
    public var footstepVolumeScale: Float = 1
    public var extraMagazines: Int = 0
    public var extraGrenades: Int = 0
    public var regenDelayScale: Float = 1
    public var fallDamageScale: Float = 1
    public var revealsOnKill: Bool = false
    public var silentOnMinimap: Bool = false
    public init() {}
}
