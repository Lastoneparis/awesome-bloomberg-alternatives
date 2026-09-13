import Foundation

/// Atomic, versioned profile storage.
///
/// Writes go to a temporary file and are then moved into place, so a crash or a kill
/// during save can never leave a half-written profile. A backup copy of the last good
/// save is kept and used automatically if the primary file fails to decode.
public final class SaveStore {
    public enum SaveError: Error, LocalizedError {
        case corrupted
        case migrationFailed(Int)

        public var errorDescription: String? {
            switch self {
            case .corrupted: return "The save file could not be read."
            case let .migrationFailed(version): return "Could not migrate save version \(version)."
            }
        }
    }

    private let directory: URL
    private let fileName: String
    private let backupName: String
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL? = nil, fileName: String = "profile.json") {
        let base = directory ?? SaveStore.defaultDirectory()
        self.directory = base
        self.fileName = fileName
        self.backupName = fileName.replacingOccurrences(of: ".json", with: ".backup.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("CriticalStrike", isDirectory: true)
    }

    public var profileURL: URL { directory.appendingPathComponent(fileName) }
    public var backupURL: URL { directory.appendingPathComponent(backupName) }

    public func load() -> PlayerProfile {
        if let profile = decodeProfile(at: profileURL) { return profile }
        if let profile = decodeProfile(at: backupURL) {
            Log.warn("Primary save unreadable; recovered from backup", category: "save")
            return profile
        }
        Log.info("No save found; creating a new profile", category: "save")
        return PlayerProfile()
    }

    private func decodeProfile(at url: URL) -> PlayerProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard var profile = try? decoder.decode(PlayerProfile.self, from: data) else {
            Log.error("Failed to decode \(url.lastPathComponent)", category: "save")
            return nil
        }
        if profile.version != PlayerProfile.currentVersion {
            profile.migrate()
        }
        return profile
    }

    @discardableResult
    public func save(_ profile: PlayerProfile) -> Bool {
        do {
            let data = try encoder.encode(profile)
            let temporary = directory.appendingPathComponent("\(fileName).tmp")
            try data.write(to: temporary, options: .atomic)

            // Keep the previous good save as a backup before replacing it.
            if fileManager.fileExists(atPath: profileURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: profileURL, to: backupURL)
                try fileManager.removeItem(at: profileURL)
            }
            try fileManager.moveItem(at: temporary, to: profileURL)
            return true
        } catch {
            Log.error("Save failed: \(error)", category: "save")
            return false
        }
    }

    public func deleteAll() {
        try? fileManager.removeItem(at: profileURL)
        try? fileManager.removeItem(at: backupURL)
    }

    /// Export/import for cloud sync. The payload is the same JSON the local save uses, so
    /// a cloud record can be dropped straight back in.
    public func exportData(_ profile: PlayerProfile) -> Data? {
        try? encoder.encode(profile)
    }

    public func importData(_ data: Data) -> PlayerProfile? {
        guard var profile = try? decoder.decode(PlayerProfile.self, from: data) else { return nil }
        if profile.version != PlayerProfile.currentVersion { profile.migrate() }
        return profile
    }

    /// Merges a cloud profile with the local one, preferring whichever has more progress.
    /// Currencies take the maximum rather than the sum so a conflict can never duplicate
    /// purchased gems.
    public func merge(local: PlayerProfile, cloud: PlayerProfile) -> PlayerProfile {
        var result = cloud.totalXP >= local.totalXP ? cloud : local
        let other = cloud.totalXP >= local.totalXP ? local : cloud

        result.totalXP = max(local.totalXP, cloud.totalXP)
        result.prestige = max(local.prestige, cloud.prestige)
        result.competitiveRating = max(local.competitiveRating, cloud.competitiveRating)
        result.wallet = Wallet(coins: max(local.wallet.coins, cloud.wallet.coins),
                               gems: max(local.wallet.gems, cloud.wallet.gems),
                               tokens: max(local.wallet.tokens, cloud.wallet.tokens))
        result.unlocks.weapons.formUnion(other.unlocks.weapons)
        result.unlocks.perks.formUnion(other.unlocks.perks)
        result.unlocks.characters.formUnion(other.unlocks.characters)
        result.unlocks.cosmetics.formUnion(other.unlocks.cosmetics)
        for (weapon, ids) in other.unlocks.attachments {
            result.unlocks.attachments[weapon, default: []].formUnion(ids)
        }
        for (weapon, kills) in other.unlocks.weaponKills {
            result.unlocks.weaponKills[weapon] = max(result.unlocks.weaponKills[weapon] ?? 0, kills)
        }
        result.entitlements.ownedProductIDs.formUnion(other.entitlements.ownedProductIDs)
        result.entitlements.adsRemoved = local.entitlements.adsRemoved || cloud.entitlements.adsRemoved
        if let a = local.entitlements.vipExpiresAt, let b = cloud.entitlements.vipExpiresAt {
            result.entitlements.vipExpiresAt = max(a, b)
        } else {
            result.entitlements.vipExpiresAt = local.entitlements.vipExpiresAt
                ?? cloud.entitlements.vipExpiresAt
        }
        result.battlePass.xp = max(local.battlePass.xp, cloud.battlePass.xp)
        result.battlePass.isPremium = local.battlePass.isPremium || cloud.battlePass.isPremium
        result.battlePass.claimedFreeTiers.formUnion(other.battlePass.claimedFreeTiers)
        result.battlePass.claimedPremiumTiers.formUnion(other.battlePass.claimedPremiumTiers)
        return result
    }
}
