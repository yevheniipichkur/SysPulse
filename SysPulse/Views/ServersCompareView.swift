import SwiftUI

private enum CompareSort: String, CaseIterable, Identifiable {
    case health
    case cpu
    case ram
    case disk
    case name

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .health: "Health"
        case .cpu: "CPU"
        case .ram: "RAM"
        case .disk: "Disk"
        case .name: "Name"
        }
    }

    var label: String {
        switch self {
        case .health: "Health"
        case .cpu: "CPU"
        case .ram: "RAM"
        case .disk: "Disk"
        case .name: "Name"
        }
    }
}

struct ServersCompareView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sortBy: CompareSort = .health

    private var rows: [(ServerProfile, ServerMetrics)] {
        let pairs = appState.serverProfiles.map { ($0, appState.metric(for: $0)) }
        switch sortBy {
        case .health:
            return pairs.sorted { $0.1.healthScore < $1.1.healthScore }
        case .cpu:
            return pairs.sorted { $0.1.cpuUsage > $1.1.cpuUsage }
        case .ram:
            return pairs.sorted { $0.1.ramUsage > $1.1.ramUsage }
        case .disk:
            return pairs.sorted { $0.1.diskUsage > $1.1.diskUsage }
        case .name:
            return pairs.sorted { $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending }
        }
    }

    private var visibleRows: [(ServerProfile, ServerMetrics)] {
        appState.isProUnlocked ? rows : Array(rows.prefix(1))
    }

    private var lockedCount: Int {
        appState.isProUnlocked ? 0 : max(0, rows.count - 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(cornerRadius: 22, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(LocalizedStringKey("Compare servers"), systemImage: "chart.bar")
                            .font(.headline)
                        Text(LocalizedStringKey("Sorted view of CPU, RAM, disk and health across all saved servers."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(CompareSort.allCases) { option in
                                    FilterChip(label: option.label, isSelected: sortBy == option) {
                                        sortBy = option
                                    }
                                }
                            }
                        }
                    }
                }

                if rows.isEmpty {
                    ActionEmptyStateView(
                        title: "No servers",
                        message: "Add servers to compare their metrics side by side.",
                        symbol: "server.rack",
                        actionTitle: "Add Server",
                        actionSymbol: "plus"
                    ) {}
                } else {
                    ForEach(visibleRows, id: \.0.id) { server, metrics in
                        CompareServerRow(
                            server: server,
                            metrics: metrics,
                            alertCount: appState.activeAlertCount(for: server)
                        ) {
                            openMonitor(for: server)
                        }
                    }

                    if lockedCount > 0 {
                        CompareLockedTeaser(lockedCount: lockedCount)
                    }
                }
            }
            .padding(.horizontal, SysPulseDesign.pagePadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(LocalizedStringKey("Compare"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { appState.refreshAllServers() }
    }

    private func openMonitor(for server: ServerProfile) {
        appState.selectedServer = server
        appState.shouldOpenSelectedServerMonitor = true
        dismiss()
    }
}

private struct CompareLockedTeaser: View {
    @EnvironmentObject private var appState: AppState
    var lockedCount: Int

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                ForEach(0..<min(lockedCount, 2), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(height: 120)
                        .overlay {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.secondary.opacity(0.2))
                                    .frame(width: 80, height: 14)
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.secondary.opacity(0.15))
                                    .frame(maxWidth: .infinity, maxHeight: 14)
                            }
                            .padding(20)
                        }
                }
            }
            .blur(radius: 6)
            .allowsHitTesting(false)

            PremiumLockedCard(
                feature: "Compare servers",
                title: "Full compare is Pro",
                message: "Unlock side-by-side metrics for all remaining servers.",
                paywallMessage: "Unlock side-by-side metrics for all remaining servers."
            )
        }
    }
}

private struct CompareServerRow: View {
    @EnvironmentObject private var appState: AppState
    var server: ServerProfile
    var metrics: ServerMetrics
    var alertCount: Int
    var onOpen: () -> Void

    private var accent: Color { Color(hex: server.accentHex) }

    var body: some View {
        Button(action: onOpen) {
            GlassCard(cornerRadius: 22, padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Label(server.name, systemImage: server.displayIcon)
                            .font(.headline)
                            .foregroundStyle(accent)
                        Spacer()
                        StatusPill(status: server.status)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    Text("\(server.username)@\(server.host)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        compareMetric("CPU", metrics.cpuUsage)
                        compareMetric("RAM", metrics.ramUsage)
                        compareMetric("Disk", metrics.diskUsage)
                        VStack(spacing: 4) {
                            Text("Health")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(metrics.healthScore)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(HealthRating.rating(for: metrics.healthScore).color)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if alertCount > 0 {
                        Label(appState.localized("%lld active alert(s)", Int64(alertCount)), systemImage: "bell.badge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func compareMetric(_ title: LocalizedStringKey, _ value: Double) -> some View {
        let color = MetricThresholdColor.forPercent(value)
        return VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value))%")
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity)
    }
}
