import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject var storeKit: StoreKitService
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var showError = false

    private let benefits: [(String, String)] = [
        ("Unlimited servers",                   "server.rack"),
        ("Docker, services and logs",            "shippingbox"),
        ("Premium terminal themes",              "terminal"),
        ("Widgets and Live Activities",          "rectangle.stack.badge.play"),
        ("Secure iCloud sync",                   "icloud"),
        ("One app for all your Linux machines",  "sparkles")
    ]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    benefitsCard
                    planCards
                    footer
                }
                .padding(20)
            }
        }
        .alert("Purchase failed", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 112, height: 112)
                .background(.ultraThinMaterial, in: Circle())

            Text("Unlock Pro Monitoring")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text("Everything you need to monitor Linux servers from your iPhone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 30)
    }

    private var benefitsCard: some View {
        GlassCard {
            VStack(spacing: 14) {
                ForEach(benefits, id: \.0) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.1)
                            .foregroundStyle(.cyan)
                            .frame(width: 28)
                        Text(LocalizedStringKey(item.0))
                            .font(.headline)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    private var planCards: some View {
        VStack(spacing: 12) {
            if storeKit.isLoading {
                ProgressView("Loading products...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if storeKit.products.isEmpty {
                fallbackPlanCards
            } else {
                ForEach(storeKit.products, id: \.id) { product in
                    PlanCard(
                        title: product.displayName,
                        price: product.displayPrice,
                        subtitle: subtitle(for: product),
                        isBestValue: product.id.contains("yearly"),
                        isLoading: isPurchasing
                    ) {
                        buy(product)
                    }
                }
            }
        }
    }

    private var fallbackPlanCards: some View {
        Group {
            PlanCard(
                title: appState.localized("Pro Monthly"),
                price: "$3.99 / month",
                subtitle: appState.localized("Flexible monitoring for all servers."),
                isBestValue: false,
                isLoading: false
            ) {}
            PlanCard(
                title: appState.localized("Pro Yearly"),
                price: "$29.99 / year",
                subtitle: appState.localized("Best Value - save 37%."),
                isBestValue: true,
                isLoading: false
            ) {}
            PlanCard(
                title: appState.localized("Lifetime Pro"),
                price: "$79.99 one-time",
                subtitle: appState.localized("All future features included."),
                isBestValue: false,
                isLoading: false
            ) {}
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            Button {
                restore()
            } label: {
                if isRestoring {
                    ProgressView()
                } else {
                    Text("Restore purchases")
                        .font(.callout.weight(.semibold))
                }
            }
            .disabled(isRestoring || isPurchasing)

            Text("Subscriptions auto-renew unless cancelled. Manage in Settings > Apple ID > Subscriptions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Actions

    private func buy(_ product: Product) {
        guard !isPurchasing else { return }
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await appState.purchaseProduct(product)
                dismiss()
            } catch StoreKitServiceError.userCancelled {
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func restore() {
        guard !isRestoring else { return }
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                try await appState.restorePurchases()
                if appState.subscription.isPro { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func subtitle(for product: Product) -> String {
        if product.id.contains("lifetime") { return appState.localized("All future features included.") }
        if product.id.contains("yearly") { return appState.localized("Best Value - save 37%.") }
        return appState.localized("Flexible monitoring for all servers.")
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    var title: String
    var price: String
    var subtitle: String
    var isBestValue: Bool
    var isLoading: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard(cornerRadius: 22, padding: 16) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(title)
                                .font(.headline)
                            if isBestValue {
                                Text("Best Value")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.green.opacity(0.16), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(price)
                            .font(.subheadline.weight(.bold))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}
