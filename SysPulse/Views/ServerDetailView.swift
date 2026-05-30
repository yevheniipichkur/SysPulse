import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ServerDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: DetailTab = .overview
    @State private var showingMissingTools = false
    @State private var confirmationMessage = ""
    @State private var showingConfirmation = false
    @State private var pendingRemoteCommand: String?
    @State private var commandSearchText = ""
    @State private var diagnosticResult: DiagnosticPackResult?
    @State private var isRunningDiagnostics = false
    private let metricsExporter = MetricsExportService()

    private let dockerService = DockerService()
    private let systemdService = SystemdService()
    private let logsService = LogsService()

    private func localizedMetricText(_ value: String) -> String {
        switch value {
        case "Unknown", "Unknown Linux":
            return appState.localized(value)
        default:
            return value
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            if let server = appState.selectedServer {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        detailHeader(server: server)
                            .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)
                        MonitorNavigationHintBanner()
                            .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)
                        monitorQuickActions(server: server)
                            .listItemEntrance(index: 1, disabled: appState.shouldReduceMotion)
                        detailTabs
                            .listItemEntrance(index: 2, disabled: appState.shouldReduceMotion)

                        Group {
                            switch selectedTab {
                            case .overview:
                                overview(server: server, metrics: appState.metric(for: server))
                            case .processes:
                                processes(server: server)
                            case .disks:
                                disks(server: server)
                            case .docker:
                                docker(server: server)
                            case .services:
                                services(server: server)
                            case .logs:
                                logs(server: server)
                            case .logBrowser:
                                LogBrowserView(server: server)
                            case .tunnels:
                                SSHTunnelsView(server: server)
                            case .commands:
                                inlineCommands(server: server)
                            case .actions:
                                actions(server: server)
                            }
                        }
                        .transition(.opacity)
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.top, 8)
                    .animation(SysPulseMotion.fade(disabled: appState.shouldReduceMotion), value: selectedTab)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    appState.refreshMetrics(for: server, announceStatus: true)
                }
            } else {
                EmptyStateView(
                    title: "No server selected",
                    message: "Choose a server to open monitoring details.",
                    symbol: "server.rack"
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .accessibilityIdentifier("screen_monitor")
        .sheet(isPresented: $showingMissingTools) {
            MissingToolsView()
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .sheet(item: $diagnosticResult) { result in
            if let server = appState.selectedServer {
                DiagnosticPackView(server: server, result: result)
                    .environmentObject(appState)
            }
        }
        .alert("Confirmation required", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingRemoteCommand = nil
            }
            Button("Confirm", role: .destructive) {
                if let pendingRemoteCommand {
                    runRemote(pendingRemoteCommand)
                }
                pendingRemoteCommand = nil
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var remoteOutputCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Last Output", systemImage: "terminal")
                        .font(.headline)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = appState.remoteCommandOutput
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    Button {
                        appState.clearRemoteCommandOutput()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal) {
                    Text(appState.remoteCommandOutput)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func detailHeader(server: ServerProfile) -> some View {
        let metrics = appState.metric(for: server)
        return GlassCard(cornerRadius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(server.name)
                            .font(.largeTitle.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                        Text("\(server.username)@\(server.host):\(server.port)")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    StatusPill(status: server.status)
                }

                HStack(spacing: 12) {
                    HealthScoreView(score: metrics.healthScore)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Uptime")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(localizedMetricText(metrics.uptime))
                            .font(.headline.monospacedDigit())
                        Text(localizedMetricText(metrics.osName))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func monitorQuickActions(server: ServerProfile) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                MonitorActionChip(title: "Terminal", symbol: "terminal", tint: .green) {
                    appState.select(server, tab: .terminal)
                    dismiss()
                }
                MonitorActionChip(title: "Files", symbol: "folder", tint: .blue) {
                    appState.select(server, tab: .sftp)
                    dismiss()
                }
                MonitorActionChip(title: "Diagnostics", symbol: "stethoscope", tint: .purple) {
                    selectedTab = .actions
                    appState.refreshPackageStatuses(for: server)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var detailTabs: some View {
        GlassCard(cornerRadius: 22, padding: 12) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                spacing: 8
            ) {
                ForEach(DetailTab.allCases) { tab in
                    Button {
                        if appState.shouldReduceMotion {
                            selectedTab = tab
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                selectedTab = tab
                            }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .foregroundStyle(selectedTab == tab ? .cyan : .secondary)
                                .background(
                                    selectedTab == tab ? Color.cyan.opacity(0.15) : Color.primary.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(
                                            selectedTab == tab ? Color.cyan.opacity(0.42) : Color.clear,
                                            lineWidth: 1
                                        )
                                }
                            Text(LocalizedStringKey(tab.shortTitleKey))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(selectedTab == tab ? .cyan : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.titleKey)
                }
            }
        }
    }

    private func overview(server: ServerProfile, metrics: ServerMetrics) -> some View {
        VStack(spacing: 14) {
            healthOverview(server: server, metrics: metrics)

            resourceTrendCard(metrics: metrics)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "CPU", value: "\(Int(metrics.cpuUsage))%", symbol: "cpu", color: .cyan, progress: metrics.cpuUsage, usesGlass: false)
                MetricTile(title: "RAM", value: "\(Int(metrics.ramUsage))%", symbol: "memorychip", color: .green, progress: metrics.ramUsage, usesGlass: false)
                MetricTile(title: "Disk", value: "\(Int(metrics.diskUsage))%", symbol: "externaldrive", color: metrics.diskUsage > 80 ? .orange : .blue, progress: metrics.diskUsage, usesGlass: false)
                MetricTile(title: "Network", value: "\(Int(metrics.networkInMB + metrics.networkOutMB)) MB", symbol: "network", color: .purple, progress: nil, usesGlass: false)
                MetricTile(title: "Swap", value: "\(Int(metrics.swapUsage))%", symbol: "arrow.triangle.2.circlepath", color: .yellow, progress: metrics.swapUsage, usesGlass: false)
                MetricTile(title: "Temp", value: metrics.temperatureCelsius.map { "\(Int($0))°C" } ?? "N/A", symbol: "thermometer.medium", color: .red, progress: metrics.temperatureCelsius, usesGlass: false)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Smart Insights", systemImage: "sparkles")
                        .font(.headline)
                    ForEach(appState.insights(for: server)) { insight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: insight.symbol)
                                .foregroundStyle(insight.severity.color)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(LocalizedStringKey(insight.title))
                                    .font(.subheadline.weight(.semibold))
                                Text(LocalizedStringKey(insight.details))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("System Info")
                        .font(.headline)
                    DetailRow(title: "Kernel", value: metrics.kernel)
                    DetailRow(title: "Load average", value: metrics.loadAverage)
                    DetailRow(title: "IP addresses", value: metrics.ipAddresses.joined(separator: ", "))
                }
            }

            if appState.isProUnlocked {
                Button {
                    runDiagnostics(for: server)
                } label: {
                    Label(
                        isRunningDiagnostics ? "Running diagnostics..." : "Run diagnostic pack",
                        systemImage: "stethoscope"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PressableGlassButtonStyle(cornerRadius: 16))
                .disabled(isRunningDiagnostics)

                healthTimeline(server: server)

                ShareLink(
                    item: metricsExporter.csv(
                        server: server,
                        metrics: metrics,
                        events: appState.serverEvents(for: server)
                    ),
                    preview: SharePreview("SysPulse \(server.name).csv")
                ) {
                    Label("Export metrics CSV", systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(PressableGlassButtonStyle(cornerRadius: 16))
            }
        }
    }

    private func healthTimeline(server: ServerProfile) -> some View {
        let events = appState.serverEvents(for: server)
        return GlassCard(cornerRadius: 22, padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Health Timeline", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                if events.isEmpty {
                    Text("Events from metric refreshes and alerts will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(event.createdAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if event.id != events.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func healthOverview(server: ServerProfile, metrics: ServerMetrics) -> some View {
        GlassCard(cornerRadius: 24, padding: 15) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(server.status.color.opacity(0.18), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(max(metrics.healthScore, 0), 100)) / 100)
                            .stroke(server.status.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(metrics.healthScore)")
                            .font(.title3.weight(.black))
                            .monospacedDigit()
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            StatusDot(title: server.status.title, color: server.status.color)
                            Text(metrics.timestamp, style: .relative)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(localizedMetricText(metrics.osName))
                            .font(.headline)
                            .lineLimit(1)
                        Text(appState.localized("%@ · load %@", localizedMetricText(metrics.uptime), metrics.loadAverage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    if appState.isProUnlocked {
                        MonitorSummaryTile(title: "Docker", value: "\(metrics.dockerRunning)/\(metrics.dockerTotal)", symbol: "shippingbox", tint: .blue)
                        MonitorSummaryTile(title: "Services", value: "\(metrics.failedServices)", symbol: "exclamationmark.triangle", tint: metrics.failedServices > 0 ? .orange : .green)
                    } else {
                        MonitorSummaryTile(title: "Docker", value: "Pro", symbol: "shippingbox", tint: .cyan)
                        MonitorSummaryTile(title: "Services", value: "Pro", symbol: "exclamationmark.triangle", tint: .cyan)
                    }
                    MonitorSummaryTile(title: "Network", value: "\(Int(metrics.networkInMB + metrics.networkOutMB)) MB", symbol: "network", tint: .purple)
                    MonitorSummaryTile(title: "Temperature", value: metrics.temperatureCelsius.map { "\(Int($0))°C" } ?? "N/A", symbol: "thermometer.medium", tint: .red)
                }
            }
        }
    }

    private func resourceTrendCard(metrics: ServerMetrics) -> some View {
        GlassCard(cornerRadius: 24, padding: 15) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Resource Trends", systemImage: "chart.xyaxis.line")
                    .font(.headline)

                VStack(spacing: 12) {
                    trendRow(title: "CPU", value: metrics.cpuUsage, values: metrics.cpuHistory, color: .cyan)
                    trendRow(title: "RAM", value: metrics.ramUsage, values: metrics.ramHistory, color: .green)
                    trendRow(title: "Disk", value: metrics.diskUsage, values: metrics.diskHistory, color: metrics.diskUsage > 80 ? .orange : .blue)
                }
            }
        }
    }

    private func trendRow(title: LocalizedStringKey, value: Double, values: [Double], color: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(percent(value))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            }
            .frame(width: 58, alignment: .leading)

            Sparkline(values: values.isEmpty ? [value, value] : values, color: color)
                .frame(height: 34)
        }
    }

    private func processes(server: ServerProfile) -> some View {
        let items = appState.processes(for: server)
        return LazyVStack(spacing: 12) {
            monitorRefreshHeader(
                title: "Top Processes",
                message: "Live process snapshot from ps on the selected server.",
                primaryTitle: "Refresh CPU",
                primarySymbol: "cpu",
                primaryAction: { appState.refreshProcesses(for: server) },
                secondaryTitle: "Refresh RAM",
                secondarySymbol: "memorychip",
                secondaryAction: { appState.refreshProcesses(for: server, sortedByMemory: true) }
            )

            if items.isEmpty {
                EmptyStateView(
                    title: "No processes loaded",
                    message: "Refresh to fetch real process data.",
                    symbol: "list.bullet.rectangle"
                )
            } else {
                ForEach(items) { item in
                    processRow(item)
                }
            }

            commandPreview(
                title: "Interactive process viewer",
                command: "top -b -n 1 | head -n 30"
            )
        }
    }

    private func disks(server: ServerProfile) -> some View {
        let disks = appState.disks(for: server)
        return LazyVStack(spacing: 12) {
            monitorRefreshHeader(
                title: "Disk usage",
                message: "Mounted filesystems parsed from df with warning levels.",
                primaryTitle: "Refresh Disks",
                primarySymbol: "externaldrive",
                primaryAction: { appState.refreshDisks(for: server) }
            )

            if disks.isEmpty {
                EmptyStateView(
                    title: "No disk snapshot",
                    message: "Refresh to read mounted filesystems.",
                    symbol: "externaldrive"
                )
            } else {
                ForEach(disks) { disk in
                    diskRow(disk)
                }
            }

            commandPreview(title: "Block devices", command: DiskService().blockDevicesCommand())
            commandPreview(title: "SMART devices", command: DiskService().smartDevicesCommand())
            commandPreview(title: "Large log files", command: DiskService().largeLogsCommand())
        }
    }

    private func docker(server: ServerProfile) -> some View {
        let containers = appState.dockerContainers(for: server)
        return ProMonitorFeatureSection(
            feature: "Docker monitoring",
            title: "Docker",
            subtitle: "Container states and live stats parsed from Docker CLI.",
            symbol: "shippingbox",
            refreshTitle: "Refresh Containers",
            refreshAction: { appState.refreshDockerContainers(for: server) },
            isEmpty: containers.isEmpty,
            emptyTitle: "No containers loaded",
            emptyMessage: "Refresh to read Docker container states."
        ) {
            ForEach(containers) { container in
                dockerRow(container)
            }
            commandPreview(title: "Docker compose projects", command: "docker compose ls 2>/dev/null || docker-compose ls 2>/dev/null || echo 'Docker Compose not found'")
            commandPreview(title: "Recent Docker state", command: "docker ps -a --format '{{.Names}} {{.Status}}' | head -n 40")
        }
    }

    private func services(server: ServerProfile) -> some View {
        let services = appState.systemdServices(for: server)
        return ProMonitorFeatureSection(
            feature: "systemd monitoring",
            title: "Services",
            subtitle: "systemd units parsed into actionable status rows.",
            symbol: "gearshape.2",
            refreshTitle: "Refresh Services",
            refreshAction: { appState.refreshSystemdServices(for: server) },
            isEmpty: services.isEmpty,
            emptyTitle: "No services loaded",
            emptyMessage: "Refresh to read systemd service states."
        ) {
            ForEach(services) { service in
                serviceRow(service)
            }
            commandPreview(title: "Failed units", command: systemdService.failedUnitsCommand())
            commandPreview(title: "Enabled services", command: "systemctl list-unit-files --type=service --state=enabled --no-pager | head -n 45")
            commandPreview(title: "Recent service errors", command: "journalctl -p err -n 80 --no-pager")
        }
    }

    private func logs(server: ServerProfile) -> some View {
        let entries = appState.logEntries(for: server)
        return ProMonitorFeatureSection(
            feature: "Logs viewer",
            title: "Recent Logs",
            subtitle: "Journal entries parsed into severity-aware rows.",
            symbol: "doc.text.magnifyingglass",
            refreshTitle: "Refresh Logs",
            refreshAction: { appState.refreshLogEntries(for: server) },
            isEmpty: entries.isEmpty,
            emptyTitle: "No logs loaded",
            emptyMessage: "Refresh to read journal entries."
        ) {
            ForEach(entries.prefix(40)) { entry in
                logRow(entry)
            }
            commandPreview(title: "System journal", command: logsService.journalCommand(lines: 200))
            commandPreview(title: "Kernel ring buffer", command: logsService.dmesgCommand(lines: 120))
            commandPreview(title: "nginx error log", command: logsService.nginxErrorLogCommand(lines: 200))
            commandPreview(title: "SSH auth log", command: "sudo tail -n 120 /var/log/auth.log 2>/dev/null || sudo tail -n 120 /var/log/secure 2>/dev/null")
        }
    }

    private func monitorRefreshHeader(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        primaryTitle: LocalizedStringKey,
        primarySymbol: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: LocalizedStringKey? = nil,
        secondarySymbol: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        GlassCard(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primarySymbol)
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 18, verticalPadding: 10))

                    if let secondaryTitle, let secondarySymbol, let secondaryAction {
                        Button(action: secondaryAction) {
                            Label(secondaryTitle, systemImage: secondarySymbol)
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PressableGlassButtonStyle(cornerRadius: 18, verticalPadding: 10))
                    }
                }
            }
        }
    }

    private func processRow(_ item: ProcessInfoItem) -> some View {
        GlassCard(cornerRadius: 18, padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.command)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    Spacer()
                    Text("PID \(item.pid)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label(item.user, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("CPU \(percent(item.cpu))")
                        .font(.caption.monospacedDigit())
                    Text("RAM \(percent(item.memory))")
                        .font(.caption.monospacedDigit())
                }

                HStack(spacing: 10) {
                    CompactProgress(value: item.cpu, color: item.cpu > 80 ? .orange : .cyan)
                    CompactProgress(value: item.memory, color: item.memory > 80 ? .orange : .green)
                }
            }
        }
    }

    private func diskRow(_ disk: DiskInfo) -> some View {
        let color: Color = disk.usagePercent >= 90 ? .red : disk.usagePercent >= 80 ? .orange : .blue
        return GlassCard(cornerRadius: 18, padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(disk.mountPoint)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    Spacer()
                    Text(percent(disk.usagePercent))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(color)
                }

                HStack {
                    Text(disk.filesystem)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(formattedGB(disk.usedGB)) / \(formattedGB(disk.freeGB))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                CompactProgress(value: disk.usagePercent, color: color)
            }
        }
    }

    private func dockerRow(_ container: DockerContainer) -> some View {
        let isRunning = container.status.lowercased().hasPrefix("up")
        return GlassCard(cornerRadius: 18, padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(container.name)
                            .font(.headline.monospaced())
                        Text(container.image)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    StatusDot(title: container.status, color: isRunning ? .green : .orange)
                }

                HStack(spacing: 8) {
                    Text("CPU \(percent(container.cpuUsage))")
                    Text("RAM \(percent(container.memoryUsage))")
                    Spacer()
                    Button("Logs") {
                        runRemote(dockerService.logsCommand(containerName: container.name, lines: 120))
                    }
                    if !isRunning {
                        Button("Start") {
                            confirm(
                                dockerService.actionCommand(action: "start", containerName: container.name),
                                message: appState.localized("Start %@? This command runs remotely over SSH.", container.name)
                            )
                        }
                        .foregroundStyle(.green)
                    } else {
                        Button("Stop") {
                            confirm(
                                dockerService.actionCommand(action: "stop", containerName: container.name),
                                message: appState.localized("Stop %@? This command runs remotely over SSH.", container.name)
                            )
                        }
                        .foregroundStyle(.red)
                    }
                    Button("Restart") {
                        confirm(
                            dockerService.actionCommand(action: "restart", containerName: container.name),
                            message: appState.localized("Restart %@? This command runs remotely over SSH.", container.name)
                        )
                    }
                    .foregroundStyle(.orange)
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func serviceRow(_ service: SystemdServiceItem) -> some View {
        let color: Color = service.isFailed ? .red : service.activeState == "active" ? .green : .orange
        return GlassCard(cornerRadius: 18, padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(service.name)
                        .font(.headline.monospaced())
                        .lineLimit(1)
                    Spacer()
                    StatusDot(title: service.activeState, color: color)
                }

                HStack(spacing: 8) {
                    Text("\(service.loadedState) / \(service.subState)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Status") {
                        runRemote(systemdService.statusCommand(serviceName: service.name))
                    }
                    if service.activeState != "active" {
                        Button("Start") {
                            confirm(
                                systemdService.actionCommand(action: "start", serviceName: service.name),
                                message: appState.localized("Start %@? This command runs remotely over SSH.", service.name)
                            )
                        }
                        .foregroundStyle(.green)
                    } else {
                        Button("Stop") {
                            confirm(
                                systemdService.actionCommand(action: "stop", serviceName: service.name),
                                message: appState.localized("Stop %@? This command runs remotely over SSH.", service.name)
                            )
                        }
                        .foregroundStyle(.red)
                    }
                    Button("Restart") {
                        confirm(
                            systemdService.actionCommand(action: "restart", serviceName: service.name),
                            message: appState.localized("Restart %@? This command runs remotely over SSH.", service.name)
                        )
                    }
                    .foregroundStyle(.orange)
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        GlassCard(cornerRadius: 16, padding: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(entry.severity.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.source)
                            .font(.caption.weight(.bold))
                        Spacer()
                        if !entry.timestamp.isEmpty {
                            Text(entry.timestamp)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(entry.message)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func commandPreview(
        title: LocalizedStringKey,
        command: String,
        requiresConfirmation: Bool = false,
        isLocked: Bool = false,
        isPremium: Bool = false
    ) -> some View {
        GlassCard(cornerRadius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if isPremium {
                            PremiumBadge()
                        }
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = command
                    } label: {
                        Label("Copy Command", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    Button {
                        if isLocked {
                            appState.isPaywallPresented = true
                        } else if requiresConfirmation {
                            confirm(command)
                        } else {
                            runRemote(command)
                        }
                    } label: {
                        Label(
                            isLocked ? LocalizedStringKey("Unlock Pro") : LocalizedStringKey("Run via SSH"),
                            systemImage: isLocked ? "sparkles" : "play.fill"
                        )
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain)
                }
                Text(command)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func inlineCommands(server: ServerProfile) -> some View {
        let filtered: [QuickCommand] = commandSearchText.isEmpty
            ? appState.quickCommands
            : appState.quickCommands.filter {
                $0.title.localizedCaseInsensitiveContains(commandSearchText) ||
                $0.command.localizedCaseInsensitiveContains(commandSearchText)
            }

        return LazyVStack(spacing: 12) {
            GlassCard(cornerRadius: 20, padding: 14) {
                TextField("Search commands", text: $commandSearchText)
                    .textInputAutocapitalization(.never)
                    .font(.subheadline)
            }

            ForEach(filtered) { command in
                let isLocked = isCommandLocked(command)
                commandPreview(
                    title: LocalizedStringKey(command.title),
                    command: command.command,
                    requiresConfirmation: CommandRunner().requiresConfirmation(command),
                    isLocked: isLocked,
                    isPremium: command.isPremium || isLocked
                )
            }

            if filtered.isEmpty {
                EmptyStateView(
                    title: "No commands found",
                    message: "Try a different search term.",
                    symbol: "bolt.horizontal"
                )
            }

            if !appState.remoteCommandOutput.isEmpty {
                remoteOutputCard
            }
        }
    }

    private func isCommandLocked(_ command: QuickCommand) -> Bool {
        guard !appState.isProUnlocked else { return false }
        let catalogIndex = appState.quickCommands.firstIndex { $0.id == command.id } ?? Int.max
        return command.isPremium || catalogIndex >= 3
    }

    private func actions(server: ServerProfile) -> some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ActionTile(title: "Open Terminal", symbol: "terminal", color: .green) {
                    appState.select(server, tab: .terminal)
                }
                ActionTile(title: "Browse Files", symbol: "folder", color: .blue) {
                    appState.select(server, tab: .sftp)
                }
                ActionTile(title: "Refresh Metrics", symbol: "arrow.clockwise", color: .cyan) {
                    appState.refreshMetrics(for: server)
                }
                ActionTile(title: "Live Activity", symbol: "livephoto.play", color: .purple) {
                    appState.startMonitoringLiveActivity()
                }
            }

            GlassCard(cornerRadius: 22, padding: 15) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Diagnostics", systemImage: "wrench.and.screwdriver")
                        .font(.headline)
                    Text("Scan installed tools and detect missing monitoring utilities.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            appState.refreshPackageStatuses(for: appState.selectedServer)
                        } label: {
                            Label("Run Diagnostics", systemImage: "stethoscope")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())

                        Button {
                            showingMissingTools = true
                        } label: {
                            Label("Missing Tools", systemImage: "exclamationmark.magnifyingglass")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                    }

                    if !appState.packageStatuses.isEmpty {
                        Divider()
                        ForEach(appState.packageStatuses) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(item.isInstalled ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.commandName)
                                        .font(.subheadline.weight(.semibold))
                                    Text(LocalizedStringKey(item.featureImpact))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.packageName)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            GlassCard(cornerRadius: 22, padding: 15) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Danger Zone", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Button(role: .destructive) {
                        confirm("sudo reboot", message: appState.localized("Reboot %@? This command runs remotely over SSH.", server.name))
                    } label: {
                        Label("Reboot Server", systemImage: "power")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .background(SysPulseDesign.destructiveAction, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func confirm(_ command: String, message: String? = nil) {
        confirmationMessage = message ?? command
        pendingRemoteCommand = command
        showingConfirmation = true
    }

    private func runRemote(_ command: String) {
        guard let server = appState.selectedServer else {
            appState.postStatus(appState.localized("Select a server before running commands."))
            return
        }
        appState.runRemoteCommand(command, on: server)
    }

    private func runDiagnostics(for server: ServerProfile) {
        guard !isRunningDiagnostics else { return }
        isRunningDiagnostics = true
        Task {
            defer { isRunningDiagnostics = false }
            do {
                diagnosticResult = try await appState.runDiagnosticPack(for: server)
            } catch {
                appState.postStatus(error.localizedDescription, style: .error)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }

    private func formattedGB(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    private func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case disks = "Disks"
    case docker = "Docker"
    case services = "Services"
    case logs = "Logs"
    case logBrowser = "Log Browser"
    case tunnels = "Tunnels"
    case commands = "Commands"
    case actions = "Actions"

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .processes: "list.bullet.rectangle"
        case .disks: "externaldrive"
        case .docker: "shippingbox"
        case .services: "gearshape.2"
        case .logs: "doc.text.magnifyingglass"
        case .logBrowser: "folder.badge.magnifyingglass"
        case .tunnels: "network.badge.shield.half.filled"
        case .commands: "bolt.horizontal"
        case .actions: "square.grid.2x2"
        }
    }

    var shortTitleKey: String {
        switch self {
        case .overview: "Overview"
        case .processes: "Procs"
        case .disks: "Disks"
        case .docker: "Docker"
        case .services: "Services"
        case .logs: "Logs"
        case .logBrowser: "Logs FS"
        case .tunnels: "Tunnels"
        case .commands: "Cmds"
        case .actions: "Actions"
        }
    }
}

private struct StatusDot: View {
    var title: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct MonitorActionChip: View {
    var title: LocalizedStringKey
    var symbol: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MonitorSummaryTile: View {
    var title: LocalizedStringKey
    var value: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DetailRow: View {
    var title: LocalizedStringKey
    var value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

struct CompactProgress: View {
    var value: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color.opacity(0.14))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(value / 100, 1))
                }
        }
        .frame(height: 8)
    }
}

private struct ActionTile: View {
    var title: LocalizedStringKey
    var symbol: String
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct PremiumLockedCard: View {
    @EnvironmentObject private var appState: AppState
    var feature: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey

    var body: some View {
        GlassCard(cornerRadius: 22, padding: 15) {
            HStack(spacing: 12) {
                PremiumBadge()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.presentPaywall(feature: feature)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
