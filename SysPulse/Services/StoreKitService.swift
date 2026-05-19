import Foundation
import StoreKit

enum StoreKitServiceError: Error {
    case failedVerification
}

@MainActor
final class StoreKitService: ObservableObject {
    static let productIDs = [
        "syspulse.pro.monthly",
        "syspulse.pro.yearly",
        "syspulse.pro.lifetime"
    ]

    @Published var products: [Product] = []
    @Published var subscriptionState = SubscriptionState()

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
            subscriptionState.productsLoaded = true
            subscriptionState.lastStoreKitMessage = "Products loaded: \(products.count)"
        } catch {
            subscriptionState.productsLoaded = false
            subscriptionState.lastStoreKitMessage = "Using mock StoreKit products for development."
        }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            subscriptionState.isActive = true
            subscriptionState.plan = product.id.contains("lifetime") ? .lifetime : .proMonthly
            await transaction.finish()
        case .pending:
            subscriptionState.lastStoreKitMessage = "Purchase is pending approval."
        case .userCancelled:
            subscriptionState.lastStoreKitMessage = "Purchase cancelled."
        @unknown default:
            subscriptionState.lastStoreKitMessage = "Unknown purchase result."
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            subscriptionState.lastStoreKitMessage = "Restore completed."
        } catch {
            subscriptionState.lastStoreKitMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitServiceError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
