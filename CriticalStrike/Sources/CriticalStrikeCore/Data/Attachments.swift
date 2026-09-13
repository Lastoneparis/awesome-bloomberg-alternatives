import Foundation

public enum AttachmentSlot: String, Codable, CaseIterable, Sendable {
    case optic, barrel, magazine, grip, stock, laser

    public var displayName: String {
        switch self {
        case .optic: return "Optic"
        case .barrel: return "Barrel"
        case .magazine: return "Magazine"
        case .grip: return "Grip"
        case .stock: return "Stock"
        case .laser: return "Laser"
        }
    }
}

/// Attachments are pure multiplicative/additive modifiers applied on top of `WeaponData`.
/// Every attachment has a real downside — no strictly-better parts.
public struct AttachmentData: Codable, Identifiable, Sendable {
    public var id: AttachmentID
    public var name: String
    public var slot: AttachmentSlot
    public var rarity: Rarity
    public var unlockKills: Int          // weapon-specific kills required
    public var storeCostCoins: Int

    // Multipliers (1.0 = no change)
    public var damageScale: Float = 1
    public var rangeScale: Float = 1
    public var fireRateScale: Float = 1
    public var reloadScale: Float = 1
    public var adsTimeScale: Float = 1
    public var adsZoomScale: Float = 1
    public var hipSpreadScale: Float = 1
    public var adsSpreadScale: Float = 1
    public var recoilVerticalScale: Float = 1
    public var recoilHorizontalScale: Float = 1
    public var moveSpeedScale: Float = 1
    public var magazineScale: Float = 1
    public var penetrationScale: Float = 1
    public var loudnessScale: Float = 1  // < 1 hides the shot from enemy minimaps

    public var description: String

    public init(id: AttachmentID, name: String, slot: AttachmentSlot, rarity: Rarity = .common,
                unlockKills: Int = 0, storeCostCoins: Int = 0, description: String = "",
                damageScale: Float = 1, rangeScale: Float = 1, fireRateScale: Float = 1,
                reloadScale: Float = 1, adsTimeScale: Float = 1, adsZoomScale: Float = 1,
                hipSpreadScale: Float = 1, adsSpreadScale: Float = 1, recoilVerticalScale: Float = 1,
                recoilHorizontalScale: Float = 1, moveSpeedScale: Float = 1, magazineScale: Float = 1,
                penetrationScale: Float = 1, loudnessScale: Float = 1) {
        self.id = id; self.name = name; self.slot = slot; self.rarity = rarity
        self.unlockKills = unlockKills; self.storeCostCoins = storeCostCoins; self.description = description
        self.damageScale = damageScale; self.rangeScale = rangeScale; self.fireRateScale = fireRateScale
        self.reloadScale = reloadScale; self.adsTimeScale = adsTimeScale; self.adsZoomScale = adsZoomScale
        self.hipSpreadScale = hipSpreadScale; self.adsSpreadScale = adsSpreadScale
        self.recoilVerticalScale = recoilVerticalScale; self.recoilHorizontalScale = recoilHorizontalScale
        self.moveSpeedScale = moveSpeedScale; self.magazineScale = magazineScale
        self.penetrationScale = penetrationScale; self.loudnessScale = loudnessScale
    }
}

public enum AttachmentDatabase {
    public static let all: [AttachmentData] = [
        // Optics
        AttachmentData(id: "opt_reddot", name: "Red Dot", slot: .optic, rarity: .common,
                       unlockKills: 10, storeCostCoins: 2500,
                       description: "Cleaner sight picture, slightly slower ADS.",
                       adsTimeScale: 1.04, adsZoomScale: 1.1, adsSpreadScale: 0.9),
        AttachmentData(id: "opt_holo", name: "Holographic", slot: .optic, rarity: .uncommon,
                       unlockKills: 40, storeCostCoins: 5000,
                       description: "Wide field of view, better target tracking.",
                       adsTimeScale: 1.07, adsZoomScale: 1.15, adsSpreadScale: 0.85),
        AttachmentData(id: "opt_acog", name: "4x Tactical", slot: .optic, rarity: .rare,
                       unlockKills: 90, storeCostCoins: 9000,
                       description: "Long-range magnification at the cost of handling.",
                       adsTimeScale: 1.22, adsZoomScale: 2.1, adsSpreadScale: 0.7, moveSpeedScale: 0.97),
        AttachmentData(id: "opt_thermal", name: "Thermal Scope", slot: .optic, rarity: .epic,
                       unlockKills: 150, storeCostCoins: 18000,
                       description: "Highlights warm bodies through smoke.",
                       adsTimeScale: 1.3, adsZoomScale: 2.4, adsSpreadScale: 0.68, moveSpeedScale: 0.95),

        // Barrels
        AttachmentData(id: "bar_suppressor", name: "Suppressor", slot: .barrel, rarity: .uncommon,
                       unlockKills: 25, storeCostCoins: 6000,
                       description: "Hides you from the enemy minimap. Costs muzzle velocity.",
                       damageScale: 0.94, rangeScale: 0.9, loudnessScale: 0.25),
        AttachmentData(id: "bar_compensator", name: "Compensator", slot: .barrel, rarity: .common,
                       unlockKills: 15, storeCostCoins: 3500,
                       description: "Tames vertical climb, widens horizontal drift.",
                       recoilVerticalScale: 0.78, recoilHorizontalScale: 1.15),
        AttachmentData(id: "bar_longbarrel", name: "Long Barrel", slot: .barrel, rarity: .rare,
                       unlockKills: 70, storeCostCoins: 8500,
                       description: "More range and punch, heavier to swing around.",
                       damageScale: 1.06, rangeScale: 1.25, adsTimeScale: 1.12, moveSpeedScale: 0.96,
                       penetrationScale: 1.2),
        AttachmentData(id: "bar_muzzlebrake", name: "Muzzle Brake", slot: .barrel, rarity: .uncommon,
                       unlockKills: 35, storeCostCoins: 5500,
                       description: "Cuts horizontal recoil, louder report.",
                       recoilHorizontalScale: 0.7, loudnessScale: 1.3),

        // Magazines
        AttachmentData(id: "mag_extended", name: "Extended Mag", slot: .magazine, rarity: .common,
                       unlockKills: 20, storeCostCoins: 4000,
                       description: "+40% capacity, slower reloads.",
                       reloadScale: 1.18, magazineScale: 1.4),
        AttachmentData(id: "mag_fastmag", name: "Fast Mag", slot: .magazine, rarity: .uncommon,
                       unlockKills: 45, storeCostCoins: 6500,
                       description: "Much quicker reloads, no extra rounds.",
                       reloadScale: 0.72),
        AttachmentData(id: "mag_ap", name: "AP Rounds", slot: .magazine, rarity: .rare,
                       unlockKills: 110, storeCostCoins: 12000,
                       description: "Punches through cover and armor. Smaller magazine.",
                       damageScale: 1.04, magazineScale: 0.85, penetrationScale: 1.6),
        AttachmentData(id: "mag_hollowpoint", name: "Hollow Point", slot: .magazine, rarity: .rare,
                       unlockKills: 120, storeCostCoins: 12000,
                       description: "Devastating up close, stopped by hard cover.",
                       damageScale: 1.12, rangeScale: 0.85, penetrationScale: 0.4),

        // Grips
        AttachmentData(id: "grp_vertical", name: "Vertical Grip", slot: .grip, rarity: .common,
                       unlockKills: 12, storeCostCoins: 3000,
                       description: "Steadier vertical recoil while aiming.",
                       adsTimeScale: 1.03, recoilVerticalScale: 0.85),
        AttachmentData(id: "grp_angled", name: "Angled Grip", slot: .grip, rarity: .uncommon,
                       unlockKills: 50, storeCostCoins: 6000,
                       description: "Snap to target faster, slightly looser spray.",
                       adsTimeScale: 0.85, recoilHorizontalScale: 1.12),
        AttachmentData(id: "grp_bipod", name: "Bipod", slot: .grip, rarity: .rare,
                       unlockKills: 80, storeCostCoins: 8000,
                       description: "Near-zero recoil when crouched, clumsy on the move.",
                       recoilVerticalScale: 0.6, recoilHorizontalScale: 0.6, moveSpeedScale: 0.93),

        // Stocks
        AttachmentData(id: "stk_tactical", name: "Tactical Stock", slot: .stock, rarity: .common,
                       unlockKills: 18, storeCostCoins: 3500,
                       description: "Faster recoil recovery and steadier aim.",
                       adsSpreadScale: 0.92, recoilVerticalScale: 0.9),
        AttachmentData(id: "stk_light", name: "Skeleton Stock", slot: .stock, rarity: .uncommon,
                       unlockKills: 55, storeCostCoins: 6000,
                       description: "Move faster, aim less steadily.",
                       adsTimeScale: 0.9, recoilVerticalScale: 1.08, moveSpeedScale: 1.06),
        AttachmentData(id: "stk_heavy", name: "Heavy Stock", slot: .stock, rarity: .rare,
                       unlockKills: 85, storeCostCoins: 8000,
                       description: "Rock steady, but you are slower.",
                       recoilVerticalScale: 0.72, recoilHorizontalScale: 0.8, moveSpeedScale: 0.93),

        // Lasers
        AttachmentData(id: "las_tactical", name: "Tac Laser", slot: .laser, rarity: .common,
                       unlockKills: 22, storeCostCoins: 3000,
                       description: "Tighter hip fire. Visible to enemies when aiming.",
                       hipSpreadScale: 0.7),
        AttachmentData(id: "las_ir", name: "IR Illuminator", slot: .laser, rarity: .epic,
                       unlockKills: 130, storeCostCoins: 14000,
                       description: "Invisible beam: hip fire accuracy with no tell.",
                       adsTimeScale: 0.96, hipSpreadScale: 0.78)
    ]

    private static let index: [AttachmentID: AttachmentData] = {
        var m = [AttachmentID: AttachmentData](); for a in all { m[a.id] = a }; return m
    }()

    public static func attachment(_ id: AttachmentID) -> AttachmentData? { index[id] }
    public static func attachments(for slot: AttachmentSlot) -> [AttachmentData] {
        all.filter { $0.slot == slot }
    }
}

/// A weapon plus its fitted parts. Resolving produces a new `WeaponData` the sim can use
/// without ever knowing attachments exist.
public struct WeaponBuild: Codable, Equatable, Sendable {
    public var weapon: WeaponID
    public var attachments: [AttachmentID]
    public var skin: SkinID?
    public var charmID: ContentID?

    public init(weapon: WeaponID, attachments: [AttachmentID] = [], skin: SkinID? = nil, charmID: ContentID? = nil) {
        self.weapon = weapon; self.attachments = attachments; self.skin = skin; self.charmID = charmID
    }

    /// At most one attachment per slot; later entries win.
    public var normalizedAttachments: [AttachmentID] {
        var bySlot = [AttachmentSlot: AttachmentID]()
        for id in attachments {
            if let a = AttachmentDatabase.attachment(id) { bySlot[a.slot] = a.id }
        }
        return AttachmentSlot.allCases.compactMap { bySlot[$0] }
    }

    public func resolved() -> WeaponData {
        var w = WeaponDatabase.weaponOrDefault(weapon)
        for id in normalizedAttachments {
            guard let a = AttachmentDatabase.attachment(id) else { continue }
            w.baseDamage *= a.damageScale
            w.falloffStart *= a.rangeScale
            w.falloffEnd *= a.rangeScale
            w.range *= a.rangeScale
            w.roundsPerMinute *= a.fireRateScale
            w.reloadTime *= a.reloadScale
            w.emptyReloadTime *= a.reloadScale
            w.adsTime *= a.adsTimeScale
            w.adsZoom *= a.adsZoomScale
            w.scopeLevels = w.scopeLevels.map { $0 * a.adsZoomScale }
            w.baseSpread *= a.hipSpreadScale
            w.adsSpread *= a.adsSpreadScale
            w.recoilVertical *= a.recoilVerticalScale
            w.recoilHorizontal *= a.recoilHorizontalScale
            w.movementSpeedScale *= a.moveSpeedScale
            w.magazineSize = Int((Float(w.magazineSize) * a.magazineScale).rounded())
            w.penetrationPower *= a.penetrationScale
        }
        return w
    }

    /// Combined suppression factor — 1 means a normal, minimap-revealing gunshot.
    public var loudness: Float {
        normalizedAttachments.reduce(Float(1)) { acc, id in
            acc * (AttachmentDatabase.attachment(id)?.loudnessScale ?? 1)
        }
    }
}
