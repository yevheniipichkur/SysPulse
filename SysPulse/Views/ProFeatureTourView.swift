import SwiftUI

struct ProFeatureTourView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GlassCard(cornerRadius: 22, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(LocalizedStringKey("Pro unlocks deeper ops"), systemImage: "sparkles")
                                .font(.title3.bold())
                            Text(LocalizedStringKey("Compare every server side-by-side and run a full diagnostic pack from Monitor."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    tourRow(
                        symbol: "chart.bar",
                        title: "Compare servers",
                        detail: "Sort by health, CPU, RAM or disk and jump into Monitor with one tap."
                    )
                    tourRow(
                        symbol: "stethoscope",
                        title: "Diagnostic pack",
                        detail: "Collect logs, services, disk and network signals in one Pro runbook."
                    )
                    tourRow(
                        symbol: "bell.badge",
                        title: "Alerts & automation",
                        detail: "Webhook alerts, scheduled commands, and metric history across the fleet."
                    )

                    Button {
                        appState.hasSeenProFeatureTour = true
                        dismiss()
                    } label: {
                        Text(LocalizedStringKey("Continue"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(LocalizedStringKey("See Pro plans")) {
                        appState.presentPaywall(feature: appState.localized("SysPulse Pro"))
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(SysPulseDesign.pagePadding)
            }
            .background { AppBackground() }
            .navigationTitle(LocalizedStringKey("Pro features"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("Later")) {
                        appState.hasSeenProFeatureTour = true
                        dismiss()
                    }
                }
            }
        }
    }

    private func tourRow(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
