import Foundation
import UIKit
import CriticalStrikeCore

/// Rewarded-video and interstitial placement.
///
/// Deliberately built around an `AdNetworkAdapter` protocol rather than a concrete SDK:
/// the game never depends on a particular mediation vendor, and the simulator/unit-test
/// builds use `NoAdsAdapter`, which reports every ad as completed without showing one.
/// Rewarded ads are always optional and never gate progression — only bonuses.
@MainActor
protocol AdNetworkAdapter: AnyObject {
    var isRewardedReady: Bool { get }
    var isInterstitialReady: Bool { get }
    func preload()
    func showRewarded(from viewController: UIViewController, completion: @escaping (Bool) -> Void)
    func showInterstitial(from viewController: UIViewController, completion: @escaping () -> Void)
}

/// Used in debug builds, the simulator, and whenever the player has removed ads.
@MainActor
final class NoAdsAdapter: AdNetworkAdapter {
    var isRewardedReady: Bool { true }
    var isInterstitialReady: Bool { true }
    func preload() {}
    func showRewarded(from viewController: UIViewController, completion: @escaping (Bool) -> Void) {
        completion(true)
    }
    func showInterstitial(from viewController: UIViewController, completion: @escaping () -> Void) {
        completion()
    }
}

@MainActor
final class AdService {
    /// Placements, so analytics can tell which ones actually earn.
    enum Placement: String {
        case doubleMatchRewards, freeCrate, extraLoadoutSlot, reviveToken, dailyBonus
    }

    var adapter: AdNetworkAdapter = NoAdsAdapter()
    /// Interstitials never interrupt a match; they only appear between them, and at most
    /// this often.
    var minimumInterstitialInterval: TimeInterval = 300
    private var lastInterstitialAt: Date = .distantPast
    private(set) var rewardedWatchedToday = 0
    private var rewardedDayStamp: Date = .distantPast
    let dailyRewardedCap = 8

    func preload() { adapter.preload() }

    var canWatchRewarded: Bool {
        resetDailyCountIfNeeded()
        return adapter.isRewardedReady && rewardedWatchedToday < dailyRewardedCap
    }

    func presentRewarded(reason: String, completion: @escaping (Bool) -> Void) {
        resetDailyCountIfNeeded()
        guard canWatchRewarded, let viewController = Self.topViewController() else {
            completion(false)
            return
        }
        adapter.showRewarded(from: viewController) { [weak self] completed in
            if completed { self?.rewardedWatchedToday += 1 }
            Log.info("Rewarded ad for \(reason): completed=\(completed)", category: "ads")
            completion(completed)
        }
    }

    func presentInterstitialIfAppropriate(completion: @escaping () -> Void) {
        guard adapter.isInterstitialReady,
              Date().timeIntervalSince(lastInterstitialAt) > minimumInterstitialInterval,
              let viewController = Self.topViewController() else {
            completion()
            return
        }
        lastInterstitialAt = Date()
        adapter.showInterstitial(from: viewController, completion: completion)
    }

    private func resetDailyCountIfNeeded() {
        if !Calendar.current.isDate(rewardedDayStamp, inSameDayAs: Date()) {
            rewardedDayStamp = Date()
            rewardedWatchedToday = 0
        }
    }

    static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
