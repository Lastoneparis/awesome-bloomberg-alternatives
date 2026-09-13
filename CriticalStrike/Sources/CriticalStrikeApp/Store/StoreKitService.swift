import Foundation
import StoreKit
import CriticalStrikeCore

/// StoreKit 2 wrapper.
///
/// Everything is verified through `VerificationResult` — an unverified transaction is
/// never granted. Consumables are finished as soon as the grant is applied and saved;
/// non-consumables and the subscription are re-read from `Transaction.currentEntitlements`
/// on every launch so entitlements survive a reinstall without a custom server.
@MainActor
final class StoreKitService: ObservableObject {
    struct EntitlementSnapshot {
        var ownedProductIDs: Set<String> = []
        var subscriptionExpiry: Date?
        var isSubscriptionActive: Bool { (subscriptionExpiry ?? .distantPast) > Date() }
    }

    enum PurchaseOutcome {
        case success
        case userCancelled
        case pending
    }

    enum StoreError: Error, LocalizedError {
        case productNotFound(String)
        case verificationFailed
        case unknown

        var errorDescription: String? {
            switch self {
            case let .productNotFound(id): return "Product \(id) is unavailable."
            case .verificationFailed: return "The purchase could not be verified."
            case .unknown: return "Something went wrong with the purchase."
            }
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published private(set) var entitlements = EntitlementSnapshot()

    var onEntitlementsChanged: ((EntitlementSnapshot) -> Void)?
    var onPurchaseCompleted: ((IAPProduct) -> Void)?

    private var updateListener: Task<Void, Never>?

    init() {
        // Transactions can arrive at any time (Ask to Buy approvals, family sharing,
        // purchases made on another device), so the listener starts with the service and
        // outlives any particular screen.
        updateListener = Task.detached { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionResult: update)
            }
        }
    }

    deinit { updateListener?.cancel() }

    // MARK: - Catalogue

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: StoreCatalog.allStoreKitIdentifiers)
            products = fetched.sorted { a, b in
                let orderA = StoreCatalog.product(storeKitID: a.id)?.sortOrder ?? 999
                let orderB = StoreCatalog.product(storeKitID: b.id)?.sortOrder ?? 999
                return orderA < orderB
            }
            Log.info("Loaded \(products.count) StoreKit products", category: "store")
        } catch {
            Log.error("Failed to load products: \(error)", category: "store")
        }
    }

    func product(for catalogProduct: IAPProduct) -> Product? {
        products.first { $0.id == catalogProduct.productID }
    }

    /// Localized price, falling back to the catalogue's USD figure before StoreKit answers.
    func displayPrice(for catalogProduct: IAPProduct) -> String {
        if let product = product(for: catalogProduct) { return product.displayPrice }
        return String(format: "$%.2f", catalogProduct.displayPriceUSD)
    }

    func subscriptionPeriodText(for catalogProduct: IAPProduct) -> String {
        guard let product = product(for: catalogProduct),
              let subscription = product.subscription else { return "" }
        let unit: String
        switch subscription.subscriptionPeriod.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        let value = subscription.subscriptionPeriod.value
        return value == 1 ? "per \(unit)" : "per \(value) \(unit)s"
    }

    // MARK: - Purchase

    func purchase(productID: String) async throws -> PurchaseOutcome {
        guard let product = products.first(where: { $0.id == productID }) else {
            throw StoreError.productNotFound(productID)
        }
        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification)
            await grant(transaction: transaction)
            await transaction.finish()
            await refreshEntitlements()
            return .success
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            throw StoreError.unknown
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            Log.warn("AppStore.sync failed: \(error)", category: "store")
        }
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var snapshot = EntitlementSnapshot()
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.revocationDate != nil { continue }
            snapshot.ownedProductIDs.insert(transaction.productID)
            if StoreCatalog.subscriptionIdentifiers.contains(transaction.productID) {
                if let expiry = transaction.expirationDate {
                    snapshot.subscriptionExpiry = max(snapshot.subscriptionExpiry ?? .distantPast, expiry)
                }
            }
        }
        entitlements = snapshot
        onEntitlementsChanged?(snapshot)
    }

    /// True when the user is eligible for the subscription's introductory offer.
    func isEligibleForIntroOffer(_ catalogProduct: IAPProduct) async -> Bool {
        guard let product = product(for: catalogProduct),
              let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    // MARK: - Internals

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(transactionResult) else { return }
        await grant(transaction: transaction)
        await transaction.finish()
        await refreshEntitlements()
    }

    private func grant(transaction: Transaction) async {
        guard let catalogProduct = StoreCatalog.product(storeKitID: transaction.productID) else {
            Log.warn("Unknown product purchased: \(transaction.productID)", category: "store")
            return
        }
        onPurchaseCompleted?(catalogProduct)
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case let .verified(safe):
            return safe
        }
    }
}
