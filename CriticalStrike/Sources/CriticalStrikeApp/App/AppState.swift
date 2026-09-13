import Foundation
import SwiftUI
import Combine
import CriticalStrikeCore

/// The application's single source of truth outside a match. Owns the player profile,
/// every long-lived service, and the route. Deliberately `@MainActor`: everything here is
/// UI-facing, and the simulation runs behind `GameSession` on the render loop.
@MainActor
final class AppState: ObservableObject {
    // MARK: Navigation
    @Published private(set) var route: AppRoute = .splash
    @Published var toast: Toast?
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var pendingMapID: MapID = "map_sandstorm"

    // MARK: Player
    @Published private(set) var profile: PlayerProfile
    @Published private(set) var matchRewards: MatchRewards?
    @Published private(set) var lastResult: MatchResult?

    // MARK: Match setup
    @Published var selectedMode: GameModeKind = .teamDeathmatch
    @Published var selectedMapID: MapID = "map_sandstorm"
    @Published var lobby = Lobby()
    @Published var matchmakingState: MatchmakingState = .idle
    @Published private(set) var session: GameSession?

    // MARK: Store
    @Published private(set) var shopRotation = ShopRotation.current()
    @Published var showCrateOpening = false
    @Published private(set) var pendingCrateRewards: [CrateReward]?
    @Published private(set) var isPurchasing = false

    // MARK: Services
    let saveStore = SaveStore()
    let storeKit = StoreKitService()
    let gameCenter = GameCenterService()
    let audio = AudioEngine()
    let haptics = HapticsService()
    let ads = AdService()
    let missionTracker = MissionTracker()
    let lootService = LootBoxService()
    let matchmaker = Matchmaker()

    private var cancellables = Set<AnyCancellable>()
    private var toastTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?

    init() {
        profile = PlayerProfile()
    }

    // MARK: - Lifecycle

    func start() {
        guard route == .splash else { return }
        profile = saveStore.load()
        applySettings()
        refreshMissions()
        lootService.restore(pity: profile.lootPity)

        matchmaker.onStateChanged = { [weak self] state in
            Task { @MainActor in self?.handleMatchmaking(state) }
        }
        storeKit.onEntitlementsChanged = { [weak self] entitlements in
            Task { @MainActor in self?.applyEntitlements(entitlements) }
        }
        storeKit.onPurchaseCompleted = { [weak self] product in
            Task { @MainActor in self?.applyPurchase(product) }
        }

        Task {
            await storeKit.loadProducts()
            await storeKit.refreshEntitlements()
        }
        Task { await gameCenter.authenticate() }

        audio.start()
        audio.playMusic("mus_menu")
        startAutosave()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            route = profile.hasSeenTutorial ? .mainMenu : .mainMenu
            grantDailyRewardIfDue()
        }
    }

    func didBecomeActive() {
        audio.setSuspended(false)
        shopRotation = ShopRotation.current()
        refreshMissions()
        session?.resume()
    }

    func willResignActive() {
        session?.pause()
        save()
    }

    func didEnterBackground() {
        audio.setSuspended(true)
        session?.pause()
        save()
    }

    private func startAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await MainActor.run { self?.save() }
            }
        }
    }

    // MARK: - Navigation

    func go(to route: AppRoute) {
        guard route != self.route else { return }
        haptics.selection()
        if route.isMenu && !self.route.isMenu { audio.playMusic("mus_menu") }
        self.route = route
    }

    func goBack() {
        switch route {
        case .play, .loadout, .store, .battlePass, .missions, .profile, .leaderboard, .settings:
            go(to: .mainMenu)
        case .armory:
            go(to: .loadout)
        case .hudEditor:
            go(to: .settings)
        case .lobby, .matchmaking:
            matchmaker.cancel()
            go(to: .play)
        case .results:
            go(to: .mainMenu)
        default:
            go(to: .mainMenu)
        }
    }

    func showToast(_ message: String, style: Toast.Style = .info, icon: String? = nil) {
        toast = Toast(message: message, style: style, icon: icon)
        switch style {
        case .success, .reward: haptics.success()
        case .error: haptics.error()
        case .warning: haptics.warning()
        case .info: haptics.selection()
        }
        toastTask?.cancel()
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            self?.toast = nil
        }
    }

    // MARK: - Profile mutations

    func save() {
        profile.lootPity = lootService.pityCounters
        profile.missionProgress = missionTracker.progress
        _ = saveStore.save(profile)
    }

    func update(_ body: (inout PlayerProfile) -> Void) {
        body(&profile)
        save()
    }

    func applySettings() {
        audio.apply(settings: profile.settings)
        haptics.isEnabled = profile.settings.hapticsEnabled
        session?.applySettings(profile.settings)
    }

    func updateSettings(_ body: (inout GameSettings) -> Void) {
        body(&profile.settings)
        applySettings()
        save()
    }

    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed.count <= 16 else {
            showToast("Name must be 3-16 characters", style: .warning)
            return
        }
        update { $0.displayName = ChatFilter.sanitize(trimmed) }
        showToast("Name updated", style: .success)
    }

    // MARK: - Loadouts

    func selectLoadout(_ index: Int) {
        guard profile.loadouts.indices.contains(index) else { return }
        update { $0.selectedLoadoutIndex = index }
        haptics.selection()
    }

    func updateSelectedLoadout(_ body: (inout Loadout) -> Void) {
        guard profile.loadouts.indices.contains(profile.selectedLoadoutIndex) else { return }
        update { body(&$0.loadouts[$0.selectedLoadoutIndex]) }
    }

    func equipWeapon(_ weaponID: WeaponID, slot: LoadoutSlot) {
        guard profile.unlocks.hasWeapon(weaponID) else {
            showToast("Not unlocked yet", style: .warning)
            return
        }
        updateSelectedLoadout { loadout in
            switch slot {
            case .primary: loadout.primary = WeaponBuild(weapon: weaponID)
            case .secondary: loadout.secondary = WeaponBuild(weapon: weaponID)
            case .melee: loadout.melee = WeaponBuild(weapon: weaponID)
            default: break
            }
        }
        audio.playUI("ui_equip")
    }

    func toggleAttachment(_ attachmentID: AttachmentID, slot: LoadoutSlot) {
        updateSelectedLoadout { loadout in
            guard var build = loadout.build(for: slot) else { return }
            if build.attachments.contains(attachmentID) {
                build.attachments.removeAll { $0 == attachmentID }
            } else {
                build.attachments.append(attachmentID)
                build.attachments = build.normalizedAttachments
            }
            switch slot {
            case .primary: loadout.primary = build
            case .secondary: loadout.secondary = build
            case .melee: loadout.melee = build
            default: break
            }
        }
        audio.playUI("ui_attach")
    }

    // MARK: - Purchases with in-game currency

    @discardableResult
    func purchaseWithCurrency(cost: Int, kind: CurrencyKind, grant: (inout PlayerProfile) -> Void) -> Bool {
        guard profile.wallet.canAfford(cost, kind) else {
            showToast("Not enough \(kind.displayName)", style: .warning)
            if kind.isPremium { go(to: .store) }
            return false
        }
        update {
            _ = $0.wallet.debit(cost, kind)
            grant(&$0)
        }
        audio.playUI("ui_purchase")
        showToast("Purchased", style: .success)
        return true
    }

    func buyWeapon(_ weaponID: WeaponID) {
        guard let weapon = WeaponDatabase.weapon(weaponID) else { return }
        guard weapon.unlockLevel <= profile.level else {
            showToast("Unlocks at level \(weapon.unlockLevel)", style: .warning)
            return
        }
        let useGems = weapon.storeCostCoins == 0 && weapon.storeCostGems > 0
        let cost = useGems ? weapon.storeCostGems : weapon.storeCostCoins
        purchaseWithCurrency(cost: cost, kind: useGems ? .gems : .coins) { profile in
            profile.unlocks.unlockWeapon(weaponID)
        }
    }

    func buyCosmetic(_ cosmeticID: SkinID, priceCoins: Int, priceGems: Int) {
        guard !profile.unlocks.hasCosmetic(cosmeticID) else {
            showToast("Already owned", style: .info)
            return
        }
        let useGems = priceCoins == 0 && priceGems > 0
        purchaseWithCurrency(cost: useGems ? priceGems : priceCoins,
                             kind: useGems ? .gems : .coins) { profile in
            profile.unlocks.unlockCosmetic(cosmeticID)
        }
    }

    func openCrate(_ crate: LootCrate) {
        let useGems = crate.priceCoins == 0
        let cost = useGems ? crate.priceGems : crate.priceCoins
        guard profile.wallet.canAfford(cost, useGems ? .gems : .coins) else {
            showToast("Not enough \(useGems ? "Gems" : "Credits")", style: .warning)
            return
        }
        let owned = Set(profile.unlocks.cosmetics.map { SkinID($0) })
        let rewards = lootService.open(crate, owned: owned)
        update { profile in
            _ = profile.wallet.debit(cost, useGems ? .gems : .coins)
            for reward in rewards {
                if reward.isDuplicate {
                    profile.wallet.credit(reward.compensationCoins, .coins)
                } else {
                    profile.unlocks.unlockCosmetic(reward.cosmetic)
                }
            }
            profile.lootPity = lootService.pityCounters
        }
        pendingCrateRewards = rewards
        showCrateOpening = true
        haptics.success()
        audio.playUI("ui_crate_open")
    }

    func dismissCrateOpening() {
        showCrateOpening = false
        pendingCrateRewards = nil
    }

    // MARK: - StoreKit

    func purchase(_ product: IAPProduct) {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            do {
                let outcome = try await storeKit.purchase(productID: product.productID)
                switch outcome {
                case .success:
                    applyPurchase(product)
                case .userCancelled:
                    break
                case .pending:
                    showToast("Purchase pending approval", style: .info)
                }
            } catch {
                showToast("Purchase failed", style: .error)
                Log.error("Purchase error: \(error)", category: "store")
            }
        }
    }

    func restorePurchases() {
        Task { @MainActor in
            await storeKit.restore()
            showToast("Purchases restored", style: .success)
        }
    }

    private func applyPurchase(_ product: IAPProduct) {
        update { profile in
            profile.wallet.credit(product.gems, .gems)
            profile.wallet.credit(product.coins, .coins)
            for cosmetic in product.grantsCosmetics { profile.unlocks.unlockCosmetic(cosmetic) }
            for character in product.grantsCharacters { profile.unlocks.unlockCharacter(character) }
            if product.grantsBattlePassPremium { profile.battlePass.isPremium = true }
            if product.category == .removeAds { profile.entitlements.adsRemoved = true }
            if product.isSubscription {
                profile.entitlements.activateVIP(days: max(1, product.subscriptionPeriodDays))
            }
            if !product.isConsumable { profile.entitlements.ownedProductIDs.insert(product.productID) }
            profile.entitlements.lifetimeSpendUSD += product.displayPriceUSD
        }
        showToast("\(product.name) unlocked", style: .reward)
    }

    private func applyEntitlements(_ entitlements: StoreKitService.EntitlementSnapshot) {
        update { profile in
            profile.entitlements.ownedProductIDs = entitlements.ownedProductIDs
            profile.entitlements.adsRemoved = entitlements.ownedProductIDs
                .contains(StoreCatalog.product("iap_removeads")?.productID ?? "")
            profile.entitlements.vipExpiresAt = entitlements.subscriptionExpiry
        }
    }

    // MARK: - Battle pass & missions

    func claimBattlePassTier(_ tier: Int, premium: Bool) {
        let season = BattlePassDatabase.currentSeason
        guard let tierData = season.tiers.first(where: { $0.tier == tier }) else { return }
        guard profile.battlePass.currentTier(in: season) >= tier else {
            showToast("Tier \(tier) not reached", style: .warning)
            return
        }
        if premium && !profile.battlePass.isPremium {
            showToast("Requires the Season Pass", style: .warning)
            go(to: .store)
            return
        }
        guard let reward = premium ? tierData.premiumReward : tierData.freeReward else { return }
        update { profile in
            profile.grant(reward)
            if premium {
                profile.battlePass.claimedPremiumTiers.insert(tier)
            } else {
                profile.battlePass.claimedFreeTiers.insert(tier)
            }
        }
        showToast("Claimed \(reward.displayName)", style: .reward)
    }

    func claimAllBattlePassRewards() {
        let season = BattlePassDatabase.currentSeason
        let pending = profile.battlePass.unclaimedRewards(in: season)
        guard !pending.isEmpty else {
            showToast("Nothing to claim", style: .info)
            return
        }
        update { profile in
            for entry in pending {
                profile.grant(entry.reward)
                if entry.premium {
                    profile.battlePass.claimedPremiumTiers.insert(entry.tier)
                } else {
                    profile.battlePass.claimedFreeTiers.insert(entry.tier)
                }
            }
        }
        showToast("Claimed \(pending.count) rewards", style: .reward)
    }

    func refreshMissions() {
        let now = Date()
        let daily = MissionDatabase.dailyAssignment(for: now, level: profile.level)
        let weekly = MissionDatabase.weeklyAssignment(for: now, level: profile.level)
        let career = MissionDatabase.careerMissions

        // Reset daily progress when the day rolls over.
        var progress = profile.missionProgress
        if !Calendar.current.isDate(profile.missionsAssignedAt, inSameDayAs: now) {
            for mission in MissionDatabase.dailyPool { progress[mission.id] = nil }
            profile.missionsAssignedAt = now
        }
        missionTracker.setActiveMissions(daily + weekly + career, existing: progress)
        missionTracker.onMissionCompleted = { [weak self] mission in
            Task { @MainActor in
                self?.showToast("Mission complete: \(mission.title)", style: .reward)
            }
        }
    }

    func claimMission(_ missionID: MissionID) {
        guard let mission = missionTracker.claim(missionID) else { return }
        update { profile in
            profile.awardXP(mission.xpReward)
            if let (kind, amount) = mission.currencyReward { profile.wallet.credit(amount, kind) }
            if let cosmetic = mission.cosmeticReward { profile.unlocks.unlockCosmetic(cosmetic) }
        }
        showToast("+\(mission.xpReward) XP", style: .reward)
    }

    // MARK: - Daily reward

    private func grantDailyRewardIfDue() {
        let now = Date()
        if let last = profile.lastDailyRewardAt,
           Calendar.current.isDate(last, inSameDayAs: now) { return }
        let continuesStreak = profile.lastDailyRewardAt.map {
            now.timeIntervalSince($0) < 172_800   // within 48h
        } ?? false
        update { profile in
            profile.dailyRewardStreak = continuesStreak ? profile.dailyRewardStreak + 1 : 1
            let day = min(profile.dailyRewardStreak, 7)
            profile.wallet.credit(500 * day, .coins)
            if day >= 7 { profile.wallet.credit(100, .gems) }
            profile.lastDailyRewardAt = now
        }
        showToast("Daily reward: day \(profile.dailyRewardStreak)", style: .reward)

        // VIP members get their daily gems on top.
        if profile.entitlements.hasActiveVIP {
            update { $0.wallet.credit(StoreCatalog.vipDailyGems, .gems) }
        }
    }

    // MARK: - Match flow

    func startMatch(mode: GameModeKind, mapID: MapID?, offline: Bool) {
        let map = mapID ?? MapDatabase.maps(for: mode).first?.id ?? "map_sandstorm"
        pendingMapID = map
        loadingProgress = 0
        go(to: .loading)

        Task { @MainActor in
            let session = GameSession(profile: profile, mode: mode, mapID: map,
                                      offline: offline, audio: audio, haptics: haptics,
                                      missionTracker: missionTracker)
            session.onProgress = { [weak self] value in
                Task { @MainActor in self?.loadingProgress = value }
            }
            session.onMatchEnded = { [weak self] result in
                Task { @MainActor in self?.finishMatch(result) }
            }
            await session.prepare()
            session.applySettings(profile.settings)
            self.session = session
            self.loadingProgress = 1
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.audio.stopMusic()
            self.go(to: .inMatch)
            session.begin()
        }
    }

    func leaveMatch() {
        session?.end()
        session = nil
        go(to: .mainMenu)
        audio.playMusic("mus_menu")
    }

    private func finishMatch(_ result: MatchResult) {
        lastResult = result
        guard let session else { return }
        let localResult = result.results.first { $0.player == session.localPlayerID }
            ?? PlayerResult(player: .none, name: profile.displayName, team: .none, isBot: false,
                            kills: 0, deaths: 0, assists: 0, score: 0, damage: 0,
                            headshots: 0, bestStreak: 0)
        let won = result.localPlayerWon
        let mode = GameModeDatabase.mode(result.mode)

        var rewards: MatchRewards?
        update { profile in
            rewards = profile.applyMatchResults(result: localResult, mode: mode, won: won,
                                                durationSeconds: result.durationSeconds,
                                                shotsFired: session.shotsFired,
                                                shotsHit: session.shotsHit,
                                                killsByWeapon: session.killsByWeapon)
            if mode.kind.isRoundBased || mode.kind == .domination {
                let teamAverage = Float(result.results.filter { $0.team == localResult.team }
                    .map(\.score).reduce(0, +)) / Float(max(1, mode.teamSize))
                let performance = RatingCalculator.performanceScore(result: localResult,
                                                                    teamAverageScore: teamAverage)
                profile.competitiveRating = RatingCalculator.update(
                    rating: profile.competitiveRating,
                    opponentRating: profile.competitiveRating,
                    won: won, performanceScore: performance)
            }
        }
        matchRewards = rewards
        missionTracker.recordMatchFinished(won: won,
                                           durationMinutes: Int(result.durationSeconds / 60),
                                           level: profile.level)
        gameCenter.submit(score: profile.stats.kills, leaderboard: .totalKills)
        gameCenter.submit(score: Int(profile.stats.kdRatio * 100), leaderboard: .kdRatio)
        gameCenter.reportAchievements(stats: profile.stats, level: profile.level)

        self.session?.end()
        self.session = nil
        go(to: .results)
        audio.playMusic(won ? "mus_victory" : "mus_defeat")
    }

    // MARK: - Matchmaking

    func beginMatchmaking(mode: GameModeKind) {
        selectedMode = mode
        let ticket = MatchmakingTicket(mode: mode, region: profile.settings.preferredRegion,
                                       skillRating: profile.competitiveRating,
                                       allowBots: true)
        matchmaker.start(ticket)
        go(to: .matchmaking)
    }

    func cancelMatchmaking() {
        matchmaker.cancel()
        go(to: .play)
    }

    func tickMatchmaking(dt: Float) {
        matchmaker.update(deltaTime: dt)
    }

    private func handleMatchmaking(_ state: MatchmakingState) {
        matchmakingState = state
        if case let .found(endpoint) = state {
            startMatch(mode: selectedMode, mapID: nil, offline: endpoint == "local")
        }
    }

    // MARK: - Ads

    func watchRewardedAd(reason: String, reward: @escaping () -> Void) {
        guard profile.entitlements.showsAds else {
            reward()
            return
        }
        ads.presentRewarded(reason: reason) { [weak self] completed in
            Task { @MainActor in
                guard completed else {
                    self?.showToast("Ad not completed", style: .warning)
                    return
                }
                reward()
                self?.save()
            }
        }
    }
}
