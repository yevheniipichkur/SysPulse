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
    @State private var purchaseStatusMessage: String?

    private let benefits: [(String, String)] = [
        ("Unlimited servers",                   "server.rack"),
        ("Auto-refresh and metric history",    "clock.arrow.circlepath"),
        ("Docker and systemd actions",         "shippingbox"),
        ("Health timeline and alerts",         "bell.badge"),
        ("Widgets and Live Activities",          "rectangle.stack.badge.play"),
        ("Shortcuts and iCloud sync",            "icloud"),
        ("Premium terminal themes",              "terminal")
    ]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    proofStrip
                    benefitsCard
                    planCards
                    footer
                }
                .padding(20)
                .padding(.top, 18)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .padding(.top, 14)
            .padding(.trailing, 14)
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

            Text(appState.paywallFeatureTitle.map { appState.localized("Unlock %@", $0) } ?? appState.localized("Unlock Pro Monitoring"))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text(appState.localized(
                appState.paywallFeatureMessage
                    ?? "Everything you need to monitor Linux servers from your iPhone."
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey("SSH, SFTP, alerts and widgets in one secure workspace."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(SysPulseDesign.actionStart)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(SysPulseDesign.actionStart.opacity(0.12), in: Capsule())
        }
        .padding(.top, 30)
    }

    private var proofStrip: some View {
        HStack(spacing: 10) {
            PaywallProofTile(value: "All", title: "Servers", symbol: "server.rack", tint: .cyan)
            PaywallProofTile(value: "24/7", title: "Widgets", symbol: "rectangle.stack.badge.play", tint: .purple)
            PaywallProofTile(value: "SSH", title: "Secure", symbol: "lock.shield", tint: .green)
        }
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
                productUnavailableCard
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

    private var productUnavailableCard: some View {
        GlassCard(cornerRadius: 22, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "icloud.slash")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 38, height: 38)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Plans unavailable")
                            .font(.headline)
                        Text("Check your connection and try again. Purchases are handled securely by App Store.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    purchaseStatusMessage = nil
                    Task {
                        await storeKit.loadProducts()
                        if storeKit.products.isEmpty {
                            purchaseStatusMessage = storeKit.statusMessage.isEmpty
                                ? appState.localized("No StoreKit products were returned.")
                                : storeKit.statusMessage
                        }
                    }
                } label: {
                    Label("Retry loading products", systemImage: "arrow.clockwise")
                        .font(.callout.weight(.bold))
                }
                .buttonStyle(PressableGlassButtonStyle(tint: .orange))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 16) {
            if let statusMessage {
                StoreKitStatusBanner(message: statusMessage, isPositive: appState.isProUnlocked)
            }

            Button {
                restore()
            } label: {
                if isRestoring {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Restoring purchases...")
                            .font(.callout.weight(.semibold))
                    }
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

    private var statusMessage: String? {
        if let purchaseStatusMessage {
            return purchaseStatusMessage
        }
        if storeKit.products.isEmpty && !storeKit.statusMessage.isEmpty {
            return storeKit.statusMessage
        }
        return nil
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
            } catch StoreKitServiceError.pendingApproval {
                purchaseStatusMessage = appState.localized("Purchase is pending approval.")
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
                purchaseStatusMessage = appState.subscription.lastStoreKitMessage
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

private struct PaywallProofTile: View {
    var value: LocalizedStringKey
    var title: LocalizedStringKey
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.black))
                .monospacedDigit()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct StoreKitStatusBanner: View {
    var message: String
    var isPositive: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isPositive ? "checkmark.seal.fill" : "info.circle.fill")
                .foregroundStyle(isPositive ? .green : .cyan)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

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
                                    .foregroundStyle(.primary)
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
