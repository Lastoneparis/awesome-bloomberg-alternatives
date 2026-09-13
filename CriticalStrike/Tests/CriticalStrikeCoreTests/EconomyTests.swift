import XCTest
@testable import CriticalStrikeCore

final class WalletTests: XCTestCase {
    func testDebitFailsWhenShort() {
        var wallet = Wallet(coins: 100)
        XCTAssertFalse(wallet.debit(500, .coins))
        XCTAssertEqual(wallet.coins, 100, "A failed debit changed the balance")
    }

    func testBalancesCanNeverGoNegative() {
        var wallet = Wallet(coins: 10, gems: 5)
        for _ in 0..<100 {
            _ = wallet.debit(3, .coins)
            _ = wallet.debit(4, .gems)
        }
        XCTAssertGreaterThanOrEqual(wallet.coins, 0)
        XCTAssertGreaterThanOrEqual(wallet.gems, 0)
    }

    func testCreditIgnoresNonPositiveAmounts() {
        var wallet = Wallet(coins: 100)
        wallet.credit(-50, .coins)
        wallet.credit(0, .coins)
        XCTAssertEqual(wallet.coins, 100)
    }
}

final class LootCrateTests: XCTestCase {
    private func crate() -> LootCrate {
        LootCrateDatabase.crate("crate_supply")!
    }

    func testPublishedOddsSumTo100() {
        for crate in LootCrateDatabase.all {
            let total = crate.publishedOdds().reduce(0) { $0 + $1.percent }
            XCTAssertEqual(total, 100, accuracy: 0.01,
                           "\(crate.name) odds do not sum to 100%")
        }
    }

    func testObservedRatesMatchPublishedOdds() {
        // The odds shown to the player must be the odds the code actually uses.
        let crate = crate()
        let service = LootBoxService(seed: 1234)
        let sampleCount = 40_000
        var counts: [Rarity: Int] = [:]
        for _ in 0..<sampleCount {
            for reward in service.open(crate, owned: []) {
                counts[reward.rarity, default: 0] += 1
            }
        }
        for (rarity, published) in crate.publishedOdds() {
            let observed = Double(counts[rarity] ?? 0) / Double(sampleCount) * 100
            // The pity timer legitimately pushes epic+ above the base rate, so only the
            // common tiers are checked tightly.
            if rarity < .epic {
                XCTAssertEqual(observed, published, accuracy: max(1.5, published * 0.12),
                               "\(rarity.displayName): published \(published)%, observed \(observed)%")
            }
        }
    }

    func testPityTimerGuaranteesAnEpic() {
        let crate = crate()
        let service = LootBoxService(seed: 777)
        var sawEpicWithinPity = false
        for index in 0..<(crate.pityThreshold + 1) {
            let rewards = service.open(crate, owned: [])
            if rewards.contains(where: { $0.rarity >= .epic }) {
                sawEpicWithinPity = true
                break
            }
            XCTAssertLessThanOrEqual(index, crate.pityThreshold)
        }
        XCTAssertTrue(sawEpicWithinPity,
                      "The pity timer did not deliver an epic within its threshold")
    }

    func testDuplicatesPayCompensation() {
        let crate = crate()
        let service = LootBoxService(seed: 55)
        let everything = Set(CosmeticDatabase.all.map(\.id))
        let rewards = service.open(crate, owned: everything)
        for reward in rewards {
            XCTAssertTrue(reward.isDuplicate)
            XCTAssertGreaterThan(reward.compensationCoins, 0)
        }
    }
}

final class ProgressionTests: XCTestCase {
    func testLevelCurveIsMonotonicAndTerminates() {
        var previous = 0
        for level in 2...XPCurve.maxLevel {
            let required = XPCurve.xpRequired(forLevel: level)
            XCTAssertGreaterThan(required, previous, "Level \(level) costs less than \(level - 1)")
            previous = required
        }
        let totalForMax = XPCurve.totalXP(forLevel: XPCurve.maxLevel)
        XCTAssertEqual(XPCurve.level(forTotalXP: totalForMax), XPCurve.maxLevel)
        XCTAssertEqual(XPCurve.level(forTotalXP: totalForMax * 10), XPCurve.maxLevel,
                       "Level exceeded the cap")
    }

    func testLevelRoundTripsThroughTotalXP() {
        for level in 1...XPCurve.maxLevel {
            let total = XPCurve.totalXP(forLevel: level)
            XCTAssertEqual(XPCurve.level(forTotalXP: total), level, "Round trip failed at \(level)")
        }
    }

    func testAwardingXPGrantsLevelsAndUnlocks() {
        var profile = PlayerProfile()
        let startingWeapons = profile.unlocks.weapons.count
        let gained = profile.awardXP(XPCurve.totalXP(forLevel: 20))
        XCTAssertFalse(gained.isEmpty)
        XCTAssertEqual(profile.level, 20)
        XCTAssertGreaterThan(profile.unlocks.weapons.count, startingWeapons,
                             "Levelling granted no weapons")
    }

    func testWeaponKillsUnlockAttachments() {
        var unlocks = UnlockState()
        let unlocked = unlocks.recordKills(120, with: "ar_vanguard")
        XCTAssertFalse(unlocked.isEmpty, "120 kills unlocked no attachments")
        for attachment in unlocked {
            XCTAssertTrue(unlocks.hasAttachment(attachment.id, on: "ar_vanguard"))
            // Attachments are per-weapon.
            XCTAssertFalse(unlocks.hasAttachment(attachment.id, on: "smg_wasp"))
        }
    }

    func testRankThresholdsAreOrdered() {
        var previous = -1
        for rank in CompetitiveRank.allCases {
            XCTAssertGreaterThan(rank.threshold, previous)
            previous = rank.threshold
        }
        XCTAssertEqual(CompetitiveRank.rank(forRating: 0), .bronze)
        XCTAssertEqual(CompetitiveRank.rank(forRating: 99_999), .legend)
    }

    func testRatingRewardsWinsAndPunishesLosses() {
        let base = 1500
        let afterWin = RatingCalculator.update(rating: base, opponentRating: base, won: true,
                                               performanceScore: 0.5)
        let afterLoss = RatingCalculator.update(rating: base, opponentRating: base, won: false,
                                                performanceScore: 0.5)
        XCTAssertGreaterThan(afterWin, base)
        XCTAssertLessThan(afterLoss, base)
        XCTAssertGreaterThanOrEqual(afterLoss, 0)
    }

    func testCarryingALossStillPaysSomething() {
        let base = 1500
        let quietLoss = RatingCalculator.update(rating: base, opponentRating: base, won: false,
                                                performanceScore: 0.1)
        let carriedLoss = RatingCalculator.update(rating: base, opponentRating: base, won: false,
                                                  performanceScore: 0.95)
        XCTAssertGreaterThan(carriedLoss, quietLoss)
    }

    func testLoadoutValidationStripsUnownedGear() {
        let unlocks = UnlockState()   // starter unlocks only
        var loadout = Loadout.starter()
        loadout.primary = WeaponBuild(weapon: "snp_specter",     // level 34, not unlocked
                                      attachments: ["opt_thermal"])
        loadout.character = "chr_nocturne"
        let validated = loadout.validated(against: unlocks, level: 1)
        XCTAssertEqual(validated.primary.weapon, WeaponDatabase.defaultPrimary)
        XCTAssertTrue(validated.primary.attachments.isEmpty)
        XCTAssertEqual(validated.character, "chr_recruit_strike")
    }

    func testPerkEffectsAggregateAndCapAtThree() {
        var loadout = Loadout.starter()
        loadout.perks = ["perk_lightfoot", "perk_juggernaut", "perk_quickhands", "perk_ghost"]
        let effects = loadout.perkEffects
        // Only the first three should apply, so Ghost must not be active.
        XCTAssertFalse(effects.silentOnMinimap)
        XCTAssertGreaterThan(effects.armorBonus, 0)
        XCTAssertLessThan(effects.reloadScale, 1)
    }
}

final class BattlePassTests: XCTestCase {
    func testSeasonHasAHundredTiersWithRewards() {
        let season = BattlePassDatabase.currentSeason
        XCTAssertEqual(season.totalTiers, 100)
        for tier in season.tiers {
            XCTAssertNotNil(tier.premiumReward, "Premium tier \(tier.tier) is empty")
        }
        let freeRewards = season.tiers.compactMap(\.freeReward).count
        XCTAssertGreaterThan(freeRewards, 40, "The free track is too sparse")
    }

    func testTierProgressionTracksXP() {
        let season = BattlePassDatabase.currentSeason
        var progress = BattlePassProgress(seasonID: season.seasonID)
        XCTAssertEqual(progress.currentTier(in: season), 1)
        progress.xp = season.xpPerTier * 9
        XCTAssertEqual(progress.currentTier(in: season), 10)
        progress.xp = season.xpPerTier * 10_000
        XCTAssertEqual(progress.currentTier(in: season), season.totalTiers)
    }

    func testUnclaimedRewardsRespectThePremiumGate() {
        let season = BattlePassDatabase.currentSeason
        var free = BattlePassProgress(seasonID: season.seasonID, xp: season.xpPerTier * 5,
                                      isPremium: false)
        let freeRewards = free.unclaimedRewards(in: season)
        XCTAssertTrue(freeRewards.allSatisfy { !$0.premium })

        free.isPremium = true
        let premiumRewards = free.unclaimedRewards(in: season)
        XCTAssertGreaterThan(premiumRewards.count, freeRewards.count)
    }
}

final class MissionTests: XCTestCase {
    func testDailyAssignmentIsStableForTheSameDay() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = MissionDatabase.dailyAssignment(for: date, level: 20)
        let second = MissionDatabase.dailyAssignment(for: date, level: 20)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func testDailyAssignmentChangesBetweenDays() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let tomorrow = today.addingTimeInterval(86_400)
        let a = MissionDatabase.dailyAssignment(for: today, level: 20).map(\.id)
        let b = MissionDatabase.dailyAssignment(for: tomorrow, level: 20).map(\.id)
        XCTAssertNotEqual(a, b)
    }

    func testAssignmentsRespectLevelGates() {
        let missions = MissionDatabase.dailyAssignment(for: Date(), level: 1, count: 12)
        XCTAssertTrue(missions.allSatisfy { $0.unlockLevel <= 1 })
    }

    func testTrackerAdvancesAndCompletes() {
        let tracker = MissionTracker()
        let mission = Mission(id: "test_kills", title: "Test", scope: .daily,
                              objective: .kills(count: 3), xpReward: 100)
        var completed: Mission?
        tracker.onMissionCompleted = { completed = $0 }
        tracker.setActiveMissions([mission], existing: [:])

        for _ in 0..<3 {
            tracker.handle(.playerDied(victim: PlayerID(1), killer: PlayerID(0),
                                       weapon: "ar_vanguard", headshot: false, wallbang: false),
                           localPlayer: PlayerID(0))
        }
        XCTAssertEqual(completed?.id, "test_kills")
        XCTAssertEqual(tracker.claimable().count, 1)
        XCTAssertNotNil(tracker.claim("test_kills"))
        XCTAssertNil(tracker.claim("test_kills"), "A mission was claimed twice")
    }

    func testTrackerIgnoresOtherPlayersKills() {
        let tracker = MissionTracker()
        let mission = Mission(id: "test_kills", title: "Test", scope: .daily,
                              objective: .kills(count: 1), xpReward: 100)
        tracker.setActiveMissions([mission], existing: [:])
        tracker.handle(.playerDied(victim: PlayerID(1), killer: PlayerID(2),
                                   weapon: "ar_vanguard", headshot: false, wallbang: false),
                       localPlayer: PlayerID(0))
        XCTAssertTrue(tracker.claimable().isEmpty)
    }
}

final class PersistenceTests: XCTestCase {
    private func temporaryStore() -> SaveStore {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        return SaveStore(directory: directory)
    }

    func testProfileRoundTrips() {
        let store = temporaryStore()
        var profile = PlayerProfile(displayName: "Vector")
        profile.awardXP(50_000)
        profile.wallet.credit(1234, .gems)
        profile.unlocks.unlockWeapon("snp_longbow")
        XCTAssertTrue(store.save(profile))

        let loaded = store.load()
        XCTAssertEqual(loaded.displayName, "Vector")
        XCTAssertEqual(loaded.totalXP, profile.totalXP)
        XCTAssertEqual(loaded.wallet.gems, profile.wallet.gems)
        XCTAssertTrue(loaded.unlocks.hasWeapon("snp_longbow"))
        store.deleteAll()
    }

    func testCorruptedSaveFallsBackToTheBackup() {
        let store = temporaryStore()
        var profile = PlayerProfile(displayName: "Backup")
        profile.awardXP(9_000)
        XCTAssertTrue(store.save(profile))
        // A second save moves the first one to the backup slot.
        profile.awardXP(1_000)
        XCTAssertTrue(store.save(profile))

        try? Data("not json".utf8).write(to: store.profileURL)
        let recovered = store.load()
        XCTAssertGreaterThan(recovered.totalXP, 0, "Backup recovery failed")
        store.deleteAll()
    }

    func testMissingSaveProducesAFreshProfile() {
        let store = temporaryStore()
        let profile = store.load()
        XCTAssertEqual(profile.level, 1)
        XCTAssertEqual(profile.version, PlayerProfile.currentVersion)
        XCTAssertFalse(profile.loadouts.isEmpty)
    }

    func testCloudMergeTakesMaximaAndNeverDuplicatesCurrency() {
        let store = temporaryStore()
        var local = PlayerProfile(displayName: "Local")
        local.wallet.credit(1000, .gems)
        local.unlocks.unlockWeapon("ar_krait")
        local.awardXP(5_000)

        var cloud = PlayerProfile(displayName: "Cloud")
        cloud.wallet.credit(1500, .gems)
        cloud.unlocks.unlockWeapon("smg_viper")
        cloud.awardXP(9_000)

        let merged = store.merge(local: local, cloud: cloud)
        XCTAssertEqual(merged.wallet.gems, 1500, "Merging summed currencies instead of taking the max")
        XCTAssertEqual(merged.totalXP, 9_000)
        XCTAssertTrue(merged.unlocks.hasWeapon("ar_krait"))
        XCTAssertTrue(merged.unlocks.hasWeapon("smg_viper"))
    }

    func testMatchResultsApplyOnce() {
        var profile = PlayerProfile()
        let result = PlayerResult(player: PlayerID(0), name: "P", team: .strike, isBot: false,
                                  kills: 12, deaths: 6, assists: 3, score: 1500, damage: 2400,
                                  headshots: 4, bestStreak: 5, xpEarned: 900)
        let rewards = profile.applyMatchResults(result: result,
                                                mode: GameModeDatabase.mode(.teamDeathmatch),
                                                won: true, durationSeconds: 600,
                                                shotsFired: 200, shotsHit: 70,
                                                killsByWeapon: ["ar_vanguard": 12])
        XCTAssertGreaterThan(rewards.xp, 0)
        XCTAssertGreaterThan(rewards.coins, 0)
        XCTAssertEqual(profile.stats.kills, 12)
        XCTAssertEqual(profile.stats.matchesWon, 1)
        XCTAssertEqual(profile.unlocks.kills(with: "ar_vanguard"), 12)
        XCTAssertEqual(profile.stats.accuracy, 0.35, accuracy: 0.001)
    }

    func testSettingsLayoutLookupAlwaysReturnsSomething() {
        var settings = GameSettings()
        XCTAssertEqual(settings.layout(for: "fireButton").id, "fireButton")
        XCTAssertEqual(settings.layout(for: "does_not_exist").id, "does_not_exist")
        var updated = settings.layout(for: "fireButton")
        updated.x = 0.42
        settings.updateLayout(updated)
        XCTAssertEqual(settings.layout(for: "fireButton").x, 0.42)
        settings.resetHUDLayout()
        XCTAssertNotEqual(settings.layout(for: "fireButton").x, 0.42)
    }
}

final class ContentIntegrityTests: XCTestCase {
    func testEveryContentIDIsUnique() {
        func assertUnique<T>(_ items: [T], id: (T) -> String, label: String) {
            var seen = Set<String>()
            for item in items {
                let key = id(item)
                XCTAssertTrue(seen.insert(key).inserted, "Duplicate \(label): \(key)")
            }
        }
        assertUnique(WeaponDatabase.all, id: { $0.id.value }, label: "weapon")
        assertUnique(AttachmentDatabase.all, id: { $0.id.value }, label: "attachment")
        assertUnique(PerkDatabase.all, id: { $0.id.value }, label: "perk")
        assertUnique(GrenadeDatabase.all, id: { $0.id.value }, label: "grenade")
        assertUnique(CharacterDatabase.all, id: { $0.id.value }, label: "character")
        assertUnique(CosmeticDatabase.all, id: { $0.id.value }, label: "cosmetic")
        assertUnique(MapDatabase.all, id: { $0.id.value }, label: "map")
        assertUnique(StoreCatalog.products, id: { $0.productID }, label: "product")
        assertUnique(MissionDatabase.all, id: { $0.id.value }, label: "mission")
    }

    func testEveryDefaultReferenceResolves() {
        XCTAssertNotNil(WeaponDatabase.weapon(WeaponDatabase.defaultPrimary))
        XCTAssertNotNil(WeaponDatabase.weapon(WeaponDatabase.defaultSecondary))
        XCTAssertNotNil(WeaponDatabase.weapon(WeaponDatabase.defaultMelee))
        XCTAssertNotNil(GrenadeDatabase.grenade(GrenadeDatabase.defaultLethal))
        XCTAssertNotNil(GrenadeDatabase.grenade(GrenadeDatabase.defaultTactical))
        for weaponID in GameModeDatabase.gunGameLadder {
            XCTAssertNotNil(WeaponDatabase.weapon(weaponID), "Gun game ladder references \(weaponID)")
        }
        for loadout in Loadout.defaultSet() {
            XCTAssertNotNil(WeaponDatabase.weapon(loadout.primary.weapon))
            XCTAssertNotNil(WeaponDatabase.weapon(loadout.secondary.weapon))
            XCTAssertNotNil(WeaponDatabase.weapon(loadout.melee.weapon))
            XCTAssertNotNil(CharacterDatabase.character(loadout.character))
            for perk in loadout.perks { XCTAssertNotNil(PerkDatabase.perk(perk)) }
        }
    }

    func testBattlePassRewardsReferenceRealContent() {
        for tier in BattlePassDatabase.currentSeason.tiers {
            for reward in [tier.freeReward, tier.premiumReward].compactMap({ $0 }) {
                switch reward {
                case let .cosmetic(id):
                    XCTAssertNotNil(CosmeticDatabase.cosmetic(id), "Tier \(tier.tier): \(id)")
                case let .character(id):
                    XCTAssertNotNil(CharacterDatabase.character(id), "Tier \(tier.tier): \(id)")
                case let .weapon(id):
                    XCTAssertNotNil(WeaponDatabase.weapon(id), "Tier \(tier.tier): \(id)")
                case let .crate(id):
                    XCTAssertNotNil(LootCrateDatabase.crate(id), "Tier \(tier.tier): \(id)")
                default:
                    break
                }
            }
        }
    }

    func testEveryMapSupportsItsObjectiveModes() {
        for map in MapDatabase.all {
            if map.supports(.bombDefusal) {
                XCTAssertGreaterThanOrEqual(map.bombSites.count, 2,
                                            "\(map.name) supports bomb defusal without two sites")
            }
            if map.supports(.domination) {
                XCTAssertGreaterThanOrEqual(map.capturePoints.count, 3,
                                            "\(map.name) supports domination without three points")
            }
            if map.supports(.hardpoint) {
                XCTAssertGreaterThanOrEqual(map.hardpoints.count, 2,
                                            "\(map.name) supports hardpoint without rotation points")
            }
            XCTAssertGreaterThanOrEqual(map.spawns(for: .strike).count, 4, "\(map.name) spawns")
            XCTAssertGreaterThanOrEqual(map.spawns(for: .shield).count, 4, "\(map.name) spawns")
        }
    }

    func testStoreProductsAreCoherent() {
        for product in StoreCatalog.products {
            XCTAssertGreaterThan(product.displayPriceUSD, 0, "\(product.name) is free")
            XCTAssertTrue(product.productID.hasPrefix(StoreCatalog.bundleIdentifier),
                          "\(product.name) has a foreign bundle prefix")
            for cosmetic in product.grantsCosmetics {
                XCTAssertNotNil(CosmeticDatabase.cosmetic(cosmetic))
            }
            for character in product.grantsCharacters {
                XCTAssertNotNil(CharacterDatabase.character(character))
            }
        }
        // Bigger packs must always be better value, or the pricing is misleading.
        let packs = StoreCatalog.products(in: .currency).sorted { $0.displayPriceUSD < $1.displayPriceUSD }
        for index in 1..<packs.count {
            XCTAssertGreaterThanOrEqual(packs[index].gemsPerDollar, packs[index - 1].gemsPerDollar,
                                        "\(packs[index].name) is worse value than a cheaper pack")
        }
    }
}

final class SocialTests: XCTestCase {
    func testFriendCodesAreStableAndReadable() {
        let account = "8B1C-DEADBEEF"
        let code = FriendCode.make(from: account)
        XCTAssertEqual(code, FriendCode.make(from: account), "Friend codes are not stable")
        XCTAssertTrue(FriendCode.isValid(code))
        XCTAssertEqual(code.count, 9, "Expected XXXX-XXXX")
        // The alphabet excludes characters that are ambiguous when read aloud.
        XCTAssertFalse(code.contains("O"))
        XCTAssertFalse(code.contains("0"))
        XCTAssertFalse(code.contains("I"))
        XCTAssertFalse(code.contains("1"))
    }

    func testDifferentAccountsGetDifferentCodes() {
        var seen = Set<String>()
        for index in 0..<500 {
            seen.insert(FriendCode.make(from: "account-\(index)"))
        }
        XCTAssertGreaterThan(seen.count, 490, "Friend codes collide too often")
    }

    func testFriendCodeNormalisation() {
        let code = FriendCode.make(from: "abc")
        let stripped = code.replacingOccurrences(of: "-", with: "").lowercased()
        XCTAssertEqual(FriendCode.normalize(stripped), code)
        XCTAssertFalse(FriendCode.isValid("NOPE"))
    }

    func testClanTagsAreNormalised() {
        XCTAssertEqual(Clan.normalize(tag: "a-b c!de"), "ABCD")
        XCTAssertTrue(Clan.isValid(tag: "cs"))
        XCTAssertFalse(Clan.isValid(tag: "x"))
        XCTAssertFalse(Clan.isValid(name: "no"))
        XCTAssertTrue(Clan.isValid(name: "Strike Force"))
    }

    func testClanBonusIsCappedAtFivePercent() {
        for level in 1...50 {
            let clan = Clan(name: "Test", tag: "TEST", level: level, leaderID: "a")
            XCTAssertLessThanOrEqual(clan.xpBonus, 1.05,
                                     "Clan level \(level) grants more than a 5% bonus")
        }
    }

    func testTaggedNameIncludesTheClanTag() {
        var profile = PlayerProfile(displayName: "Vector")
        XCTAssertEqual(profile.taggedName, "Vector")
        profile.clan = Clan(name: "Strike Force", tag: "STRK", leaderID: profile.accountID)
        XCTAssertEqual(profile.taggedName, "[STRK] Vector")
    }
}
