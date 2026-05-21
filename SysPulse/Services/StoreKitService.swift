import Foundation
import StoreKit

enum StoreKitServiceError: LocalizedError {
    case failedVerification
    case purchaseFailed(String)

    var errorDescription: String? {
        switch self {
        case .failedVerification:      return "Purchase verification failed."
        case .purchaseFailed(let msg): return msg
        }
    }
}

@MainActor
final class StoreKitService: ObservableObject {
    static let productIDs = [
        "syspulse.pro.monthly",
        "syspulse.pro.yearly",
        "syspulse.pro.lifetime"
    ]

    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var statusMessage = ""

    // AppState sets this to sync subscription after any transaction
    var onSubscriptionChange: ((SubscriptionState) -> Void)?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { await listenForTransactions() }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            products = []
            statusMessage = "Could not load products: \(error.localizedDescription)"
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> SubscriptionState {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            return state(from: transaction)
        case .pending:
            throw StoreKitServiceError.purchaseFailed("Purchase is pending approval.")
        case .userCancelled:
            throw StoreKitServiceError.purchaseFailed("Purchase was cancelled.")
        @unknown default:
            throw StoreKitServiceError.purchaseFailed("Unknown purchase result.")
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()
        let restored = await verifyCurrentEntitlements()
        onSubscriptionChange?(restored)
        statusMessage = restored.isActive ? "Purchases restored." : "No active purchases found."
    }

    // MARK: - Entitlement check (called on launch)

    func verifyCurrentEntitlements() async -> SubscriptionState {
        var best = SubscriptionState()
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            let s = state(from: transaction)
            if s.isPro { best = s }
            await transaction.finish()
        }
        best.productsLoaded = !products.isEmpty
        return best
    }

    // MARK: - Background transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            let s = state(from: transaction)
            onSubscriptionChange?(s)
            await transaction.finish()
        }
    }

    // MARK: - Helpers

    private func state(from transaction: Transaction) -> SubscriptionState {
        var s = SubscriptionState()
        s.expiresAt = transaction.expirationDate

        let product = products.first { $0.id == transaction.productID }
        let isNonConsumable = product?.type == .nonConsumable

        if isNonConsumable {
            // Non-consumable (lifetime): never expires, only revocable
            s.plan = .lifetime
            s.isActive = transaction.revocationDate == nil
        } else if transaction.productID.contains("yearly") {
            s.plan = .proYearly
            s.isActive = transaction.revocationDate == nil &&
                (transaction.expirationDate.map { $0 > .now } ?? false)
        } else {
            s.plan = .proMonthly
            s.isActive = transaction.revocationDate == nil &&
                (transaction.expirationDate.map { $0 > .now } ?? false)
        }
        s.productsLoaded = true
        return s
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreKitServiceError.failedVerification
        case .verified(let value): return value
        }
    }
}
