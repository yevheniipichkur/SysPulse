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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(cornerRadius: 22, padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Compare servers", systemImage: "chart.bar")
                            .font(.headline)
                        Text("Sorted view of CPU, RAM, disk and health across all saved servers.")
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
                    ForEach(rows, id: \.0.id) { server, metrics in
                        CompareServerRow(
                            server: server,
                            metrics: metrics,
                            alertCount: appState.activeAlertCount(for: server)
                        )
                    }
                }
            }
            .padding(.horizontal, SysPulseDesign.pagePadding)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { appState.refreshAllServers() }
    }
}

private struct CompareServerRow: View {
    var server: ServerProfile
    var metrics: ServerMetrics
    var alertCount: Int

    private var accent: Color { Color(hex: server.accentHex) }

    var body: some View {
        GlassCard(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Label(server.name, systemImage: server.displayIcon)
                        .font(.headline)
                        .foregroundStyle(accent)
                    Spacer()
                    StatusPill(status: server.status)
                }

                Text("\(server.username)@\(server.host)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    compareMetric("CPU", metrics.cpuUsage, .cyan)
                    compareMetric("RAM", metrics.ramUsage, .green)
                    compareMetric("Disk", metrics.diskUsage, metrics.diskUsage > 80 ? .orange : .blue)
                    VStack(spacing: 4) {
                        Text("Health")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(metrics.healthScore)")
                            .font(.headline.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                }

                if alertCount > 0 {
                    Label("\(alertCount) active alert(s)", systemImage: "bell.badge")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func compareMetric(_ title: LocalizedStringKey, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value))%")
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
}
