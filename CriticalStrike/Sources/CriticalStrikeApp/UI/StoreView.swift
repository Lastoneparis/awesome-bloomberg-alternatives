import SwiftUI
import CriticalStrikeCore

struct StoreView: View {
    @EnvironmentObject private var app: AppState
    @State private var tab: Tab = .featured

    enum Tab: String, CaseIterable {
        case featured = "Featured"
        case gems = "Gems"
        case crates = "Crates"
        case cosmetics = "Cosmetics"
    }

    private var profile: PlayerProfile { app.profile }

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "Store",
                         subtitle: "Daily shop resets in \(app.shopRotation.expiresIn.compactDuration)",
                         onBack: { app.goBack() },
                         trailing: AnyView(CurrencyBar(wallet: profile.wallet)))

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView {
                switch tab {
                case .featured: featuredSection
                case .gems: gemsSection
                case .crates: cratesSection
                case .cosmetics: cosmeticsSection
                }
            }

            HStack {
                Button("Restore Purchases") { app.restorePurchases() }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Text("Prices shown in your local currency at checkout.")
                    .font(Theme.caption(9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .overlay {
            if app.isPurchasing {
                ZStack {
                    Color.black.opacity(0.5).ignoresSafeArea()
                    ProgressView().tint(Theme.accent)
                }
            }
        }
    }

    // MARK: Sections

    private var featuredSection: some View {
        VStack(spacing: 10) {
            ForEach(StoreCatalog.products(in: .starterPack)
                + StoreCatalog.products(in: .battlePass)
                + StoreCatalog.products(in: .subscription)
                + StoreCatalog.products(in: .bundle)) { product in
                featuredCard(product)
            }
            if !profile.entitlements.adsRemoved {
                ForEach(StoreCatalog.products(in: .removeAds)) { product in
                    featuredCard(product)
                }
            }

            Text("SHOP ROTATION")
                .font(Theme.caption(10))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(app.shopRotation.featured + app.shopRotation.offers) { offer in
                    offerCard(offer)
                }
            }
        }
    }

    private var gemsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 10) {
            ForEach(StoreCatalog.products(in: .currency)) { product in
                Button {
                    app.purchase(product)
                } label: {
                    VStack(spacing: 5) {
                        if product.bestValue {
                            Text("BEST VALUE")
                                .font(Theme.caption(8))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent))
                        }
                        Text("\(product.gems)")
                            .font(Theme.display(24))
                            .foregroundStyle(Color(hex: CurrencyKind.gems.colorHex))
                        Text("Gems")
                            .font(Theme.caption(10))
                            .foregroundStyle(Theme.textSecondary)
                        if product.bonusPercent > 0 {
                            Text("+\(product.bonusPercent)% bonus")
                                .font(Theme.caption(9))
                                .foregroundStyle(Theme.success)
                        }
                        Text(app.storeKit.displayPrice(for: product))
                            .font(Theme.title(15))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.top, 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .panel(elevated: true)
                }
            }
        }
    }

    private var cratesSection: some View {
        VStack(spacing: 10) {
            ForEach(LootCrateDatabase.all) { crate in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(crate.name).font(Theme.title(16)).foregroundStyle(Theme.textPrimary)
                            Text(crate.description)
                                .font(Theme.caption(10)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button {
                            app.openCrate(crate)
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(hex: crate.priceCoins > 0
                                                ? CurrencyKind.coins.colorHex : CurrencyKind.gems.colorHex))
                                    .frame(width: 8, height: 8)
                                Text("\(crate.priceCoins > 0 ? crate.priceCoins : crate.priceGems)")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(wide: false))
                    }

                    // Published odds, exactly as implemented.
                    HStack(spacing: 10) {
                        ForEach(crate.publishedOdds()) { entry in
                            VStack(spacing: 1) {
                                Text(String(format: "%.2f%%", entry.percent))
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.rarity(entry.rarity))
                                Text(entry.rarity.displayName)
                                    .font(Theme.caption(8))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    let remaining = app.lootService.opensUntilGuarantee(crate)
                    Text(remaining == 0
                         ? "Next open is a guaranteed Epic or better"
                         : "\(remaining) opens until a guaranteed Epic or better")
                        .font(Theme.caption(9))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(12)
                .panel(elevated: true)
            }
        }
    }

    private var cosmeticsSection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(CosmeticDatabase.all.filter { !$0.crateOnly }) { cosmetic in
                let owned = profile.unlocks.hasCosmetic(cosmetic.id)
                Button {
                    guard !owned else { return }
                    app.buyCosmetic(cosmetic.id, priceCoins: cosmetic.storeCostCoins,
                                    priceGems: cosmetic.storeCostGems)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Theme.rarityGradient(cosmetic.rarity))
                            .frame(height: 58)
                            .overlay(
                                Image(systemName: iconName(for: cosmetic.kind))
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(.white.opacity(0.9)))
                        Text(cosmetic.name)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        HStack {
                            RarityBadge(rarity: cosmetic.rarity)
                            Spacer()
                            if owned {
                                Text("OWNED").font(Theme.caption(9)).foregroundStyle(Theme.success)
                            } else {
                                Text(cosmetic.storeCostCoins > 0
                                     ? "\(cosmetic.storeCostCoins)" : "\(cosmetic.storeCostGems)")
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Color(hex: cosmetic.storeCostCoins > 0
                                                           ? CurrencyKind.coins.colorHex
                                                           : CurrencyKind.gems.colorHex))
                            }
                        }
                    }
                    .padding(9)
                    .panel(elevated: true)
                    .opacity(owned ? 0.65 : 1)
                }
            }
        }
    }

    // MARK: Cards

    private func featuredCard(_ product: IAPProduct) -> some View {
        Button {
            app.purchase(product)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Theme.accentGradient)
                    .frame(width: 70, height: 70)
                    .overlay(Image(systemName: productIcon(product))
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.name).font(Theme.title(16)).foregroundStyle(Theme.textPrimary)
                        if product.limitedTime {
                            Text("LIMITED")
                                .font(Theme.caption(8))
                                .foregroundStyle(Theme.warning)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Theme.warning.opacity(0.18)))
                        }
                    }
                    Text(product.subtitle)
                        .font(Theme.caption(11))
                        .foregroundStyle(Theme.textSecondary)
                    if product.isSubscription {
                        Text("Auto-renews. Cancel anytime in Settings.")
                            .font(Theme.caption(9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(app.storeKit.displayPrice(for: product))
                        .font(Theme.title(16))
                        .foregroundStyle(Theme.accent)
                    if product.isSubscription {
                        Text(app.storeKit.subscriptionPeriodText(for: product))
                            .font(Theme.caption(9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(12)
            .panel(elevated: true)
        }
        .disabled(alreadyOwned(product))
        .opacity(alreadyOwned(product) ? 0.55 : 1)
    }

    private func alreadyOwned(_ product: IAPProduct) -> Bool {
        guard !product.isConsumable || product.isSubscription else { return false }
        if product.category == .removeAds { return profile.entitlements.adsRemoved }
        if product.isSubscription { return profile.entitlements.hasActiveVIP }
        return profile.entitlements.owns(product.productID)
    }

    private func offerCard(_ offer: ShopRotation.Offer) -> some View {
        let cosmetic = CosmeticDatabase.cosmetic(offer.item)
        return Button {
            app.buyCosmetic(offer.item, priceCoins: offer.priceCoins, priceGems: offer.priceGems)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Theme.rarityGradient(cosmetic?.rarity ?? .common))
                    .frame(height: 62)
                    .overlay(alignment: .topTrailing) {
                        if offer.discountPercent > 0 {
                            Text("-\(offer.discountPercent)%")
                                .font(Theme.caption(9))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.danger))
                                .padding(5)
                        }
                    }
                Text(cosmetic?.name ?? offer.item.value)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(offer.priceCoins > 0 ? "\(offer.priceCoins) Credits" : "\(offer.priceGems) Gems")
                    .font(Theme.caption(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(9)
            .panel(elevated: true)
        }
    }

    private func productIcon(_ product: IAPProduct) -> String {
        switch product.category {
        case .currency: return "diamond.fill"
        case .bundle, .starterPack: return "shippingbox.fill"
        case .subscription: return "crown.fill"
        case .removeAds: return "nosign"
        case .battlePass: return "rosette"
        }
    }

    private func iconName(for kind: CosmeticKind) -> String {
        switch kind {
        case .weaponSkin: return "paintbrush.fill"
        case .characterSkin: return "person.fill"
        case .charm: return "key.fill"
        case .sticker, .sprayTag: return "tag.fill"
        case .emote: return "figure.wave"
        case .banner: return "flag.fill"
        case .title: return "textformat"
        case .killEffect: return "sparkles"
        case .tracerColor: return "line.diagonal"
        }
    }
}

/// The crate reveal. Deliberately short and skippable — a long forced animation on a
/// paid box is exactly the pattern that gets a game a bad reputation.
struct CrateOpeningView: View {
    let rewards: [CrateReward]
    let onDismiss: () -> Void
    @State private var revealed = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(revealed ? "UNLOCKED" : "OPENING")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.textPrimary)

                HStack(spacing: 12) {
                    ForEach(rewards.indices, id: \.self) { index in
                        let reward = rewards[index]
                        let cosmetic = CosmeticDatabase.cosmetic(reward.cosmetic)
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Theme.rarityGradient(reward.rarity))
                                .frame(width: 128, height: 128)
                                .overlay(
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 34, weight: .light))
                                        .foregroundStyle(.white.opacity(0.9)))
                                .shadow(color: Theme.rarity(reward.rarity).opacity(0.6), radius: 18)
                                .scaleEffect(revealed ? 1 : 0.4)
                                .opacity(revealed ? 1 : 0)
                                .animation(.spring(response: 0.45, dampingFraction: 0.65)
                                    .delay(Double(index) * 0.12), value: revealed)
                            Text(cosmetic?.name ?? reward.cosmetic.value)
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.textPrimary)
                            RarityBadge(rarity: reward.rarity)
                            if reward.isDuplicate {
                                Text("Duplicate → +\(reward.compensationCoins) Credits")
                                    .font(Theme.caption(9))
                                    .foregroundStyle(Theme.warning)
                            }
                        }
                    }
                }

                Button("Continue", action: onDismiss)
                    .buttonStyle(PrimaryButtonStyle(wide: false))
            }
        }
        .onAppear { revealed = true }
        .onTapGesture { if revealed { onDismiss() } }
    }
}
