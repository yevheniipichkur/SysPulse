import SwiftUI
import UIKit

struct ServersView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("serversCompactMode") private var isCompactMode = false
    @State private var isAddingServer = false
    @State private var editingServer: ServerProfile?
    @State private var selectedGroupName: String?
    @State private var isShowingDetail = false
    @State private var isShowingCompare = false

    private var allGroups: [String] {
        Array(Set(appState.serverProfiles.compactMap(\.groupName)))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var filteredProfiles: [ServerProfile] {
        guard let group = selectedGroupName else { return appState.serverProfiles }
        return appState.serverProfiles.filter { $0.groupName == group }
    }

    var body: some View {
        Group {
            if appState.isScreenshotMode {
                screenshotServersBody
            } else {
                serversListBody
            }
        }
        .accessibilityIdentifier(AppTab.servers.screenAccessibilityIdentifier)
        .sheet(isPresented: $isAddingServer) {
            AddServerView()
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .sheet(item: $editingServer) { server in
            AddServerView(editingServer: server)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .onChange(of: appState.shouldOpenSelectedServerMonitor) { _, shouldOpen in
            if shouldOpen {
                isShowingDetail = true
                appState.shouldOpenSelectedServerMonitor = false
            }
        }
    }

    private var serversListBody: some View {
        NavigationStack {
            serversScrollContent
                .navigationDestination(isPresented: $isShowingDetail) {
                    ServerDetailView()
                        .environmentObject(appState)
                }
                .navigationDestination(isPresented: $isShowingCompare) {
                    ServersCompareView()
                        .environmentObject(appState)
                }
        }
    }

    private var serversScrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                PageHeader(
                    title: "Servers",
                    subtitle: LocalizedStringKey("Monitor · SSH · Files"),
                    leadingActionSymbol: "list.bullet",
                    leadingActionActive: isCompactMode,
                    leadingAction: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            isCompactMode.toggle()
                        }
                        appState.haptic(.light)
                    },
                    secondaryActionSymbol: appState.serverProfiles.count > 1 ? "chart.bar" : nil,
                    secondaryAction: appState.serverProfiles.count > 1 ? {
                        isShowingCompare = true
                    } : nil,
                    actionSymbol: "plus"
                ) {
                    isAddingServer = true
                }
                .padding(.top, 8)

                if !appState.isProUnlocked {
                    FreePlanBanner()
                }

                if !allGroups.isEmpty && appState.isProUnlocked {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "All", isSelected: selectedGroupName == nil) {
                                selectedGroupName = nil
                            }
                            ForEach(allGroups, id: \.self) { group in
                                FilterChip(label: group, isSelected: selectedGroupName == group) {
                                    selectedGroupName = selectedGroupName == group ? nil : group
                                }
                            }
                        }
                    }
                }

                if filteredProfiles.isEmpty {
                    if appState.serverProfiles.isEmpty {
                        ActionEmptyStateView(
                            title: "No saved servers",
                            message: "Add your first SSH profile to start monitoring, terminal sessions and SFTP.",
                            symbol: "server.rack",
                            actionTitle: "Add Server",
                            actionSymbol: "plus"
                        ) { isAddingServer = true }
                        .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)
                    } else {
                        ActionEmptyStateView(
                            title: "No servers in this group",
                            message: "Add servers to this group in the server profile editor.",
                            symbol: "server.rack",
                            actionTitle: "Clear Filter",
                            actionSymbol: "xmark"
                        ) { selectedGroupName = nil }
                        .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)
                    }
                } else {
                    ForEach(Array(filteredProfiles.enumerated()), id: \.element.id) { index, server in
                        ServerCardView(
                            server: server,
                            metrics: appState.metric(for: server),
                            isRefreshing: appState.isRefreshingMetrics(for: server),
                            metricError: appState.metricError(for: server),
                            isCompact: isCompactMode
                        )
                            .listItemEntrance(index: index, disabled: appState.shouldReduceMotion)
                            .onTapGesture {
                                appState.selectedServer = server
                                appState.haptic(.light)
                                isShowingDetail = true
                            }
                            .contextMenu {
                                Button {
                                    appState.select(server, tab: .terminal)
                                } label: {
                                    Label("Open Terminal", systemImage: "terminal")
                                }
                                Button {
                                    appState.selectedServer = server
                                    appState.haptic(.light)
                                    isShowingDetail = true
                                } label: {
                                    Label("Open Detail", systemImage: "waveform.path.ecg")
                                }
                                Button {
                                    editingServer = server
                                } label: {
                                    Label("Edit Server", systemImage: "pencil")
                                }
                                Button {
                                    appState.selectedServer = server
                                    appState.selectedTab = .sftp
                                } label: {
                                    Label("Browse Files", systemImage: "folder")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    appState.deleteServer(server)
                                } label: {
                                    Label("Delete Server", systemImage: "trash")
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, SysPulseDesign.pagePadding)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            appState.refreshAllServers()
        }
    }

    private var screenshotServersBody: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                AppBackground()

                VStack(spacing: 18) {
                    PageHeader(
                        title: "Servers",
                        subtitle: LocalizedStringKey("Monitor · SSH · Files"),
                        actionSymbol: "plus"
                    ) {
                        isAddingServer = true
                    }

                    if let server = appState.serverProfiles.first {
                        ServerCardView(
                            server: server,
                            metrics: appState.metric(for: server),
                            isRefreshing: false,
                            metricError: appState.metricError(for: server)
                        )
                    }
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, max(proxy.safeAreaInsets.top + 8, 62))
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct FreePlanBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GlassCard(cornerRadius: 22, padding: 15) {
            HStack(spacing: 14) {
                Image(systemName: "lock.open.display")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 44, height: 44)
                    .background(.cyan.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Free plan")
                        .font(.headline)
                    Text("One real server, basic dashboard and basic terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.presentPaywall(
                        feature: "Unlimited servers",
                        message: "One real server, basic dashboard and basic terminal."
                    )
                } label: {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ServerCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    var server: ServerProfile
    var metrics: ServerMetrics
    var isRefreshing = false
    var metricError: String?
    var isCompact: Bool = false

    private var accent: Color { Color(hex: server.accentHex) }
    private var healthRating: HealthRating { .rating(for: metrics.healthScore) }
    private var primaryRisk: ServerPrimaryRisk {
        ServerPrimaryRisk.evaluate(
            server: server,
            metrics: metrics,
            alertCount: appState.activeAlertCount(for: server)
        )
    }
    private var isMetricsStale: Bool { Date().timeIntervalSince(metrics.timestamp) > 900 }
    private var needsAttention: Bool {
        isMetricsStale || server.status == .offline || server.status == .warning || metrics.healthScore < 70 || metrics.failedServices > 0
    }
    private var attentionColor: Color {
        if isMetricsStale { return .orange }
        if server.status == .offline { return .red }
        if server.status == .warning { return .orange }
        if metrics.healthScore < 70 { return healthRating.color }
        if metrics.failedServices > 0 { return .orange }
        return .clear
    }

    private func localizedMetricText(_ value: String) -> String {
        switch value {
        case "Unknown", "Unknown Linux":
            return appState.localized(value)
        default:
            return value
        }
    }

    var body: some View {
        if isCompact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: Compact layout

    private var compactBody: some View {
        GlassCard(cornerRadius: 24, padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent.opacity(0.16))
                            .frame(width: 48, height: 48)
                            .shadow(color: accent.opacity(0.18), radius: 10)
                        Image(systemName: server.displayIcon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(server.name)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)

                        HStack(spacing: 0) {
                            Text(server.serverType.titleKey)
                            Text(" • \(server.host)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                        Text(localizedMetricText(metrics.osName))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 6)

                    VStack(alignment: .trailing, spacing: 7) {
                        StatusPill(status: server.status)
                        if appState.activeAlertCount(for: server) > 0 {
                            Text("\(appState.activeAlertCount(for: server))")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.orange, in: Capsule())
                        }
                        MetricFreshnessBadge(date: metrics.timestamp, isStale: isMetricsStale)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }

                if let metricError, !metricError.isEmpty {
                    ServerConnectionIssueBanner(message: metricError)
                }

                primaryRiskLine(compact: true)

                if appState.isProUnlocked, !metrics.cpuHistory.isEmpty {
                    HStack(spacing: 8) {
                        Sparkline(values: metrics.cpuHistory, color: .cyan)
                            .frame(height: 26)
                        Sparkline(values: metrics.ramHistory, color: .green)
                            .frame(height: 26)
                    }
                }

                HStack(spacing: 10) {
                    CompactMetric(title: "CPU", value: metrics.cpuUsage, color: MetricThresholdColor.forPercent(metrics.cpuUsage))
                    CompactMetric(title: "RAM", value: metrics.ramUsage, color: MetricThresholdColor.forPercent(metrics.ramUsage))
                    CompactMetric(title: "Disk", value: metrics.diskUsage, color: MetricThresholdColor.forPercent(metrics.diskUsage))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(attentionColor.opacity(needsAttention ? (colorScheme == .dark ? 0.42 : 0.34) : 0), lineWidth: needsAttention ? 1.5 : 0)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isRefreshing)
    }

    // MARK: Full layout

    private var fullBody: some View {
        GlassCard(cornerRadius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent.opacity(0.16))
                            .frame(width: 52, height: 52)
                            .shadow(color: accent.opacity(0.25), radius: 16)
                        Image(systemName: server.displayIcon)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(server.name)
                                .font(.headline.weight(.bold))
                                .lineLimit(1)
                        }
                        HStack(spacing: 0) {
                            Text(server.serverType.titleKey)
                            Text(" • \(server.host)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        Text(localizedMetricText(metrics.osName))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    VStack(alignment: .trailing, spacing: 7) {
                        StatusPill(status: server.status)
                        MetricFreshnessBadge(date: metrics.timestamp, isStale: isMetricsStale)
                    }
                }

                ServerHealthSummary(
                    score: metrics.healthScore,
                    rating: healthRating,
                    failedServices: metrics.failedServices,
                    colorScheme: colorScheme
                )

                primaryRiskLine(compact: false)

                if let metricError, !metricError.isEmpty {
                    ServerConnectionIssueBanner(message: metricError)
                }

                HStack(spacing: 10) {
                    CompactMetric(title: "CPU", value: metrics.cpuUsage, color: MetricThresholdColor.forPercent(metrics.cpuUsage))
                    CompactMetric(title: "RAM", value: metrics.ramUsage, color: MetricThresholdColor.forPercent(metrics.ramUsage))
                    CompactMetric(title: "Disk", value: metrics.diskUsage, color: MetricThresholdColor.forPercent(metrics.diskUsage))
                }

                if appState.isProUnlocked, !metrics.cpuHistory.isEmpty {
                    Sparkline(values: metrics.cpuHistory, color: accent)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        Label(localizedMetricText(metrics.uptime), systemImage: "clock")
                        Label("\(Int(metrics.temperatureCelsius ?? 0))°C", systemImage: "thermometer.medium")
                        Label("\(metrics.dockerRunning)/\(metrics.dockerTotal)", systemImage: "shippingbox")
                        if metrics.failedServices > 0 {
                            Label("\(metrics.failedServices)", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .scrollIndicators(.hidden)

                HStack(spacing: 8) {
                    ServerQuickActionButton(title: "Terminal", symbol: "terminal", tint: .green) {
                        appState.select(server, tab: .terminal)
                    }
                    ServerQuickActionButton(title: "Files", symbol: "folder", tint: .blue) {
                        appState.select(server, tab: .sftp)
                    }
                    ServerQuickActionButton(title: "Refresh", symbol: "arrow.clockwise", tint: .cyan, isLoading: isRefreshing) {
                        appState.refreshMetrics(for: server)
                    }
                }
            }
        }
        .scaleEffect(isRefreshing ? 0.995 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(attentionColor.opacity(needsAttention ? (colorScheme == .dark ? 0.42 : 0.34) : 0), lineWidth: needsAttention ? 1.5 : 0)
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isRefreshing)
    }

    private func primaryRiskLine(compact: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: primaryRisk.symbol)
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.semibold))
                .foregroundStyle(primaryRisk.color)
            Text(riskText)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(primaryRisk.color)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !compact {
                Text("\(metrics.healthScore)")
                    .font(.caption.weight(.black))
                    .monospacedDigit()
                    .foregroundStyle(healthRating.color)
            }
        }
        .padding(.horizontal, compact ? 10 : 11)
        .padding(.vertical, compact ? 7 : 9)
        .background(primaryRisk.color.opacity(colorScheme == .dark ? 0.10 : 0.12), in: RoundedRectangle(cornerRadius: compact ? 14 : 16, style: .continuous))
    }

    private var riskText: String {
        if primaryRisk.messageArgs.isEmpty {
            return appState.localized(primaryRisk.messageKey)
        }
        if primaryRisk.messageArgs.count == 1, let value = primaryRisk.messageArgs[0] as? Int {
            return appState.localized(primaryRisk.messageKey, value)
        }
        return appState.localized(primaryRisk.messageKey)
    }
}

private struct ServerConnectionIssueBanner: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.orange.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct MetricFreshnessBadge: View {
    var date: Date
    var isStale: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isStale ? "clock.badge.exclamationmark" : "clock")
            if isStale {
                Text("Stale")
            }
            Text(date, style: .relative)
                .monospacedDigit()
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(isStale ? .orange : .secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}

private struct ServerHealthSummary: View {
    var score: Int
    var rating: HealthRating
    var failedServices: Int
    var colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(rating.color)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Health")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(score)")
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                    Text(rating.titleKey)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(rating.color)
                }
            }

            Spacer(minLength: 8)

            if failedServices > 0 {
                Label("\(failedServices)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(rating.color.opacity(colorScheme == .dark ? 0.10 : 0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(rating.color.opacity(colorScheme == .dark ? 0.18 : 0.24), lineWidth: 1)
        }
    }
}

private struct ServerQuickActionButton: View {
    var title: LocalizedStringKey
    var symbol: String
    var tint: Color
    var isLoading = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct CompactMetric: View {
    var title: LocalizedStringKey
    var value: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("\(Int(value))%")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            GeometryReader { proxy in
                Capsule()
                    .fill(color.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * min(value / 100, 1))
                    }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthScoreView: View {
    var score: Int
    private var rating: HealthRating { .rating(for: score) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Health")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            HStack(spacing: 5) {
                Image(systemName: "heart.text.square")
                Text("\(score)")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.bold))
            Text(rating.titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(rating.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    private let editingServer: ServerProfile?

    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authType: SSHAuthenticationType = .password
    @State private var secret = ""
    @State private var passphrase = ""
    @State private var tags = ""
    @State private var group = ""
    @State private var icon = "server.rack"
    @State private var accentHex = "#33C2EA"
    @State private var serverType: ServerType = .vps
    @State private var statusMessage = ""
    @State private var jumpServerID: UUID?
    @State private var shouldPresentProTour = false

    init(editingServer: ServerProfile? = nil) {
        self.editingServer = editingServer
        _name = State(initialValue: editingServer?.name ?? "")
        _host = State(initialValue: editingServer?.host ?? "")
        _port = State(initialValue: editingServer.map { String($0.port) } ?? "22")
        _username = State(initialValue: editingServer?.username ?? "")
        _authType = State(initialValue: editingServer?.authenticationType ?? .password)
        _tags = State(initialValue: editingServer?.tags.joined(separator: ", ") ?? "")
        _group = State(initialValue: editingServer?.groupName ?? "")
        _icon = State(initialValue: editingServer?.icon ?? "server.rack")
        _accentHex = State(initialValue: editingServer?.accentHex ?? "#33C2EA")
        _serverType = State(initialValue: editingServer?.serverType ?? .vps)
        _jumpServerID = State(initialValue: editingServer?.jumpServerID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        AddServerPreviewCard(
                            name: previewName,
                            endpoint: previewEndpoint,
                            type: serverType,
                            icon: icon,
                            accent: accent
                        )
                        .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)

                        if editingServer == nil {
                            AddServerGuideStrip()
                                .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)
                        }

                        ServerFormSection(title: "Connection", symbol: "network") {
                            ServerFormTextField(
                                title: "Name",
                                placeholder: "Production API",
                                text: $name,
                                symbol: "server.rack"
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Host",
                                placeholder: "192.168.1.10",
                                text: $host,
                                symbol: "globe",
                                keyboardType: .URL,
                                autocapitalization: .never
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Port",
                                placeholder: "22",
                                text: $port,
                                symbol: "number",
                                keyboardType: .numberPad
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "User",
                                placeholder: "root",
                                text: $username,
                                symbol: "person",
                                autocapitalization: .never
                            )
                        }
                        .listItemEntrance(index: 1, disabled: appState.shouldReduceMotion)

                        ServerFormSection(title: "Security", symbol: "lock.shield") {
                            ServerPickerRow(title: "Authentication", symbol: authType.symbol) {
                                Picker("Authentication", selection: $authType) {
                                    ForEach(SSHAuthenticationType.allCases) { type in
                                        Text(type.titleKey).tag(type)
                                    }
                                }
                            }
                            ServerFormDivider()
                            credentialInput
                            ServerFormDivider()
                            jumpHostPicker
                        }
                        .listItemEntrance(index: 2, disabled: appState.shouldReduceMotion)

                        ServerFormSection(title: "Profile", symbol: "slider.horizontal.3") {
                            ServerPickerRow(title: "Type", symbol: serverType.symbol) {
                                Picker("Server type", selection: $serverType) {
                                    ForEach(ServerType.allCases) { type in
                                        Label(type.titleKey, systemImage: type.symbol).tag(type)
                                    }
                                }
                            }
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Group",
                                placeholder: "Home lab",
                                text: $group,
                                symbol: "folder"
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Tags",
                                placeholder: "docker, backup",
                                text: $tags,
                                symbol: "tag"
                            )
                            ServerFormDivider()
                            ServerIconPicker(selection: $icon, serverType: serverType, accent: accent)
                            ServerFormDivider()
                            ServerAccentPicker(selection: $accentHex)
                        }
                        .listItemEntrance(index: 3, disabled: appState.shouldReduceMotion)

                        if !statusMessage.isEmpty {
                            ServerStatusMessage(message: statusMessage)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                testConnectionButton
                                saveAndConnectButton
                            }

                            VStack(spacing: 10) {
                                testConnectionButton
                                saveAndConnectButton
                            }
                        }
                    }
                    .padding(20)
                    .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: authType)
                    .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: serverType)
                    .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: accentHex)
                    .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: statusMessage.isEmpty)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(editingServer == nil ? LocalizedStringKey("Add Server") : LocalizedStringKey("Edit Server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        save(connectAfterSave: false)
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $shouldPresentProTour) {
                ProFeatureTourView()
                    .environmentObject(appState)
                    .onDisappear { dismiss() }
            }
        }
    }

    private var accent: Color {
        Color(hex: accentHex)
    }

    private var previewName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.localized("New Server") : trimmed
    }

    private var previewEndpoint: String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointHost = trimmedHost.isEmpty ? "host.local" : trimmedHost
        return "\(usernamePrefix)\(endpointHost):\(trimmedPort.isEmpty ? "22" : trimmedPort)"
    }

    private var usernamePrefix: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "\(trimmed)@"
    }

    private var testConnectionButton: some View {
        Button {
            testConnection()
        } label: {
            Label("Test Connection", systemImage: "checkmark.shield")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var saveAndConnectButton: some View {
        Button {
            save(connectAfterSave: true)
        } label: {
            Label("Save & Connect", systemImage: "terminal")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .background(
                    LinearGradient(colors: [SysPulseDesign.actionStart, SysPulseDesign.actionEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.55)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var credentialInput: some View {
        switch authType {
        case .password:
            ServerFormSecureField(
                title: editingServer == nil ? "Password" : "Password",
                placeholder: editingServer == nil ? "Required for password login" : "Keep current password",
                text: $secret,
                symbol: "key"
            )
        case .privateKey, .privateKeyWithPassphrase:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.horizontal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 28, height: 28)
                        .background(.cyan.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private Key")
                            .font(.subheadline.weight(.semibold))
                        Text(editingServer == nil ? LocalizedStringKey("OpenSSH RSA or ED25519") : LocalizedStringKey("Leave empty to keep current key"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $secret)
                    .font(.caption.monospaced())
                    .frame(minHeight: 132)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                if authType == .privateKeyWithPassphrase {
                    ServerFormSecureField(
                        title: "Passphrase",
                        placeholder: "Optional",
                        text: $passphrase,
                        symbol: "ellipsis.rectangle"
                    )
                }
            }
        }
    }

    private var jumpHostPicker: some View {
        let candidates = appState.serverProfiles.filter { $0.id != editingServer?.id }
        return Group {
            if !candidates.isEmpty {
                ServerPickerRow(title: "Jump host", symbol: "arrowshape.turn.up.right") {
                    Picker("Jump host", selection: $jumpServerID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(candidates) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                }
                Text(LocalizedStringKey("Metrics and commands proxy through the bastion. Terminal opens an SSH session via jump host; SFTP lists and downloads work through the bridge."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var keychainSecretValue: String {
        switch authType {
        case .password, .privateKey:
            secret
        case .privateKeyWithPassphrase:
            SSHPrivateKeyCredentialPayload(
                privateKey: secret,
                passphrase: passphrase.isEmpty ? nil : passphrase
            ).keychainValue
        }
    }

    private func save(connectAfterSave: Bool) {
        let serverID = UUID()
        let targetID = editingServer?.id ?? serverID
        let credentialID = editingServer?.credentialIdentifier ?? "server-\(targetID.uuidString)"
        if !secret.isEmpty {
            do {
                try KeychainService.shared.saveSecret(keychainSecretValue, account: credentialID)
            } catch {
                statusMessage = error.localizedDescription
                return
            }
        }

        if let editingServer {
            editingServer.name = name
            editingServer.host = host
            editingServer.port = Int(port) ?? 22
            editingServer.username = username
            editingServer.authenticationType = authType
            editingServer.credentialIdentifier = secret.isEmpty ? editingServer.credentialIdentifier : credentialID
            editingServer.tagsCSV = tags
            editingServer.groupName = group.isEmpty ? nil : group
            editingServer.icon = icon
            editingServer.accentHex = accentHex
            editingServer.serverType = serverType
            editingServer.jumpServerID = jumpServerID
            appState.updateServer(editingServer)
            if connectAfterSave {
                appState.select(editingServer, tab: .terminal)
                appState.refreshMetrics(for: editingServer)
            }
            dismiss()
            return
        }

        let server = ServerProfile(
            id: targetID,
            name: name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authenticationType: authType,
            credentialIdentifier: secret.isEmpty ? nil : credentialID,
            tags: tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) },
            groupName: group.isEmpty ? nil : group,
            icon: icon,
            accentHex: accentHex,
            serverType: serverType,
            status: .unknown,
            jumpServerID: jumpServerID
        )
        guard appState.addServer(server) else {
            return
        }
        if appState.serverProfiles.count == 1, !appState.hasSeenProFeatureTour {
            shouldPresentProTour = true
        }
        if connectAfterSave {
            appState.select(server, tab: .terminal)
            appState.refreshMetrics(for: server)
        }
        if shouldPresentProTour {
            return
        }
        dismiss()
    }

    private func testConnection() {
        guard canSave else {
            statusMessage = appState.localized("Enter server name, host and username first.")
            return
        }

        let targetID = editingServer?.id ?? UUID()
        let temporaryCredentialID = "server-test-\(targetID.uuidString)"
        let credentialID = editingServer?.credentialIdentifier ?? temporaryCredentialID

        if !secret.isEmpty {
            do {
                try KeychainService.shared.saveSecret(keychainSecretValue, account: credentialID)
            } catch {
                statusMessage = error.localizedDescription
                return
            }
        }

        let server = ServerProfile(
            id: targetID,
            name: name.isEmpty ? appState.localized("Connection Test") : name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authenticationType: authType,
            credentialIdentifier: credentialID,
            icon: icon,
            accentHex: accentHex,
            serverType: serverType,
            status: .unknown,
            jumpServerID: jumpServerID
        )

        statusMessage = appState.localized("Connecting to %@...", host)
        Task {
            do {
                let output = try await appState.testConnection(to: server)
                await MainActor.run {
                    let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? appState.localized("SSH is ready.")
                    statusMessage = appState.localized("Connected. %@", firstLine)
                }
            } catch {
                await MainActor.run {
                    statusMessage = appState.connectionErrorMessage(error, server: server)
                }
            }
            if editingServer == nil {
                try? KeychainService.shared.deleteSecret(account: temporaryCredentialID)
            }
        }
    }
}

private extension SSHAuthenticationType {
    var symbol: String {
        switch self {
        case .password:
            "key"
        case .privateKey:
            "key.horizontal"
        case .privateKeyWithPassphrase:
            "lock.rectangle.stack"
        }
    }
}

private struct AddServerPreviewCard: View {
    var name: String
    var endpoint: String
    var type: ServerType
    var icon: String
    var accent: Color

    var body: some View {
        GlassCard(cornerRadius: 28, padding: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(accent.opacity(0.16))
                        .frame(width: 58, height: 58)
                        .shadow(color: accent.opacity(0.22), radius: 18)

                    Image(systemName: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? type.symbol : icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 7) {
                        Image(systemName: type.symbol)
                        Text(type.titleKey)
                        Text(endpoint)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct ServerFormSection<Content: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard(cornerRadius: 24, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ServerFormTextField: View {
    var title: LocalizedStringKey
    var placeholder: LocalizedStringKey
    @Binding var text: String
    var symbol: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(.cyan.opacity(0.12), in: Circle())

            Text(title)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 8)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(minHeight: 46)
    }
}

private struct ServerFormSecureField: View {
    var title: LocalizedStringKey
    var placeholder: LocalizedStringKey
    @Binding var text: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(.cyan.opacity(0.12), in: Circle())

            Text(title)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 8)

            SecureField(placeholder, text: $text)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .frame(minHeight: 46)
    }
}

private struct ServerPickerRow<Content: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(.cyan.opacity(0.12), in: Circle())

            Text(title)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 8)

            content
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.callout.weight(.semibold))
                .tint(.primary)
        }
        .frame(minHeight: 46)
    }
}

private struct ServerIconPicker: View {
    @Binding var selection: String
    var serverType: ServerType
    var accent: Color

    private static let choices = [
        "server.rack",
        "desktopcomputer",
        "externaldrive.connected.to.line.below",
        "cpu",
        "network",
        "terminal",
        "folder",
        "cloud",
        "shippingbox",
        "lock.shield",
        "house",
        "building.2",
        "antenna.radiowaves.left.and.right",
        "bolt.horizontal.circle",
        "memorychip"
    ]

    private var selectedSymbol: String {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? serverType.symbol : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: selectedSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.12), in: Circle())

                Text("Icon")
                    .font(.callout.weight(.semibold))

                Spacer()

                TextField(LocalizedStringKey(serverType.symbol), text: $selection)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced().weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 160)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 42), spacing: 9)], spacing: 9) {
                ForEach(Self.choices, id: \.self) { symbol in
                    iconButton(symbol)
                }
            }
        }
        .frame(minHeight: 112)
        .accessibilityElement(children: .contain)
    }

    private func iconButton(_ symbol: String) -> some View {
        let isSelected = selectedSymbol == symbol

        return Button {
            selection = symbol
        } label: {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(isSelected ? accent : .secondary)
                .frame(width: 42, height: 42)
                .background(
                    (isSelected ? accent.opacity(0.16) : Color.primary.opacity(0.055)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? accent.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Server icon"))
        .accessibilityValue(Text(isSelected ? "Selected" : symbol))
    }
}

private struct ServerAccentPicker: View {
    @Binding var selection: String

    private static let choices = [
        "#33C2EA",
        "#34C759",
        "#FF9F0A",
        "#FF453A",
        "#AF52DE",
        "#5E5CE6"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 28, height: 28)
                    .background(.cyan.opacity(0.12), in: Circle())

                Text("Accent")
                    .font(.callout.weight(.semibold))

                Spacer()

                TextField("#33C2EA", text: $selection)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced().weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
            }

            HStack(spacing: 11) {
                ForEach(Self.choices, id: \.self) { hex in
                    swatch(hex)
                }
            }
        }
        .frame(minHeight: 74)
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = selection.caseInsensitiveCompare(hex) == .orderedSame

        return Button {
            selection = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.white.opacity(0.45), lineWidth: isSelected ? 2.5 : 1)
                }
                .shadow(color: Color(hex: hex).opacity(isSelected ? 0.35 : 0.12), radius: isSelected ? 10 : 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Accent"))
        .accessibilityValue(Text(hex))
    }
}

private struct AddServerGuideStrip: View {
    var body: some View {
        GlassCard(cornerRadius: 20, padding: 14) {
            HStack(spacing: 10) {
                guidePill(number: 1, title: "Connection")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                guidePill(number: 2, title: "Security")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                guidePill(number: 3, title: "Save")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func guidePill(number: Int, title: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.cyan, in: Circle())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ServerFormDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 38)
            .padding(.vertical, 4)
    }
}

private struct ServerStatusMessage: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
