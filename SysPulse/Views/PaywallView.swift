import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    private let benefits = [
        ("Unlimited servers", "server.rack"),
        ("Docker, services and logs", "shippingbox"),
        ("Premium terminal themes", "terminal"),
        ("Widgets and Live Activities", "rectangle.stack.badge.play"),
        ("Secure iCloud sync", "icloud"),
        ("One app for all your Linux machines", "sparkles")
    ]

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
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
                                }
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        PlanCard(title: "Pro Monthly", price: "$3.99 / month", subtitle: "Flexible monitoring for all servers.", isBestValue: false) {
                            unlock(.proMonthly)
                        }
                        PlanCard(title: "Pro Yearly", price: "$29.99 / year", subtitle: "Best Value", isBestValue: true) {
                            unlock(.proYearly)
                        }
                        PlanCard(title: "Lifetime Pro", price: "$79.99 one-time", subtitle: "Unlock all local premium features.", isBestValue: false) {
                            unlock(.lifetime)
                        }
                    }

                    Button("Restore purchases") {
                        appState.subscription.lastStoreKitMessage = "Restore uses StoreKit 2 when products are configured."
                    }
                    .font(.callout.weight(.semibold))

                    Text("Mock StoreKit is enabled for development. Configure product IDs in App Store Connect before TestFlight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 24)
                }
                .padding(20)
            }
        }
    }

    private func unlock(_ plan: SubscriptionPlan) {
        appState.subscription.plan = plan
        appState.subscription.isActive = true
        dismiss()
    }
}

private struct PlanCard: View {
    var title: LocalizedStringKey
    var price: String
    var subtitle: LocalizedStringKey
    var isBestValue: Bool
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
                    Text(price)
                        .font(.subheadline.weight(.bold))
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
