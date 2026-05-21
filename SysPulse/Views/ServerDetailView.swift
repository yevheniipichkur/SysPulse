import SwiftUI
import UIKit

struct ServerDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: DetailTab = .overview
    @State private var showingMissingTools = false
    @State private var confirmationMessage = ""
    @State private var showingConfirmation = false
    @State private var pendingRemoteCommand: String?

    private let dockerService = DockerService()
    private let systemdService = SystemdService()
    private let logsService = LogsService()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if let server = appState.selectedServer {
                    ScrollView {
                        VStack(spacing: 16) {
                            detailHeader(server: server)
                            detailTabs

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
                                case .packages:
                                    packages
                                case .terminal:
                                    terminalShortcut(server: server)
                                case .actions:
                                    actions(server: server)
                                }
                            }

                            if !appState.lastCommandOutput.isEmpty {
                                remoteOutputCard
                            }
                        }
                        .padding(.horizontal, SysPulseDesign.pagePadding)
                        .padding(.top, 8)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    EmptyStateView(
                        title: "No server selected",
                        message: "Choose a server to open monitoring details.",
                        symbol: "server.rack"
                    )
                }
            }
        }
        .sheet(isPresented: $showingMissingTools) {
            MissingToolsView()
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .alert("Confirmation required", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
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
                        UIPasteboard.general.string = appState.lastCommandOutput
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.horizontal) {
                    Text(appState.lastCommandOutput)
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(server.name)
                            .font(.largeTitle.weight(.bold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                        Text("\(server.username)@\(server.host):\(server.port)")
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        StatusPill(status: server.status)
                        Button {
                            appState.refreshMetrics(for: server)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 34, height: 34)
                                .background(.thinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Refresh metrics")
                    }
                }

                HStack(spacing: 12) {
                    HealthScoreView(score: metrics.healthScore)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Uptime")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(metrics.uptime)
                            .font(.headline.monospacedDigit())
                        Text(metrics.osName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var detailTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(DetailTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selectedTab = tab
                        }
                    } label: {
                        Label(tab.titleKey, systemImage: tab.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                selectedTab == tab ? .thinMaterial : .ultraThinMaterial,
                                in: Capsule()
                            )
                            .overlay {
                                Capsule().stroke(.white.opacity(selectedTab == tab ? 0.24 : 0.08), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func overview(server: ServerProfile, metrics: ServerMetrics) -> some View {
        VStack(spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(title: "CPU", value: "\(Int(metrics.cpuUsage))%", symbol: "cpu", color: .cyan, progress: metrics.cpuUsage)
                MetricTile(title: "RAM", value: "\(Int(metrics.ramUsage))%", symbol: "memorychip", color: .green, progress: metrics.ramUsage)
                MetricTile(title: "Disk", value: "\(Int(metrics.diskUsage))%", symbol: "externaldrive", color: metrics.diskUsage > 80 ? .orange : .blue, progress: metrics.diskUsage)
                MetricTile(title: "Network", value: "\(Int(metrics.networkInMB + metrics.networkOutMB)) MB", symbol: "network", color: .purple, progress: nil)
                MetricTile(title: "Swap", value: "\(Int(metrics.swapUsage))%", symbol: "arrow.triangle.2.circlepath", color: .yellow, progress: metrics.swapUsage)
                MetricTile(title: "Temp", value: metrics.temperatureCelsius.map { "\(Int($0))°C" } ?? "N/A", symbol: "thermometer.medium", color: .red, progress: metrics.temperatureCelsius)
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
        }
    }

    private func processes(server: ServerProfile) -> some View {
        let items = appState.processes(for: server)
        return VStack(spacing: 12) {
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
        return VStack(spacing: 12) {
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
        return VStack(spacing: 12) {
            if !appState.isProUnlocked {
                PremiumLockedCard(title: "Docker monitoring is Pro", message: "Unlock live container stats, logs and restart actions.")
            }

            monitorRefreshHeader(
                title: "Docker scan",
                message: "Container states and live stats parsed from Docker CLI.",
                primaryTitle: "Refresh Containers",
                primarySymbol: "shippingbox",
                primaryAction: { appState.refreshDockerContainers(for: server) }
            )

            if containers.isEmpty {
                EmptyStateView(
                    title: "No containers loaded",
                    message: "Refresh to read Docker container states.",
                    symbol: "shippingbox"
                )
            } else {
                ForEach(containers) { container in
                    dockerRow(container)
                }
            }

            commandPreview(title: "Docker compose projects", command: "docker compose ls 2>/dev/null || docker-compose ls 2>/dev/null || echo 'Docker Compose not found'")
            commandPreview(title: "Recent Docker state", command: "docker ps -a --format '{{.Names}} {{.Status}}' | head -n 40")
        }
    }

    private func services(server: ServerProfile) -> some View {
        let services = appState.systemdServices(for: server)
        return VStack(spacing: 12) {
            if !appState.isProUnlocked {
                PremiumLockedCard(title: "Advanced systemd is Pro", message: "Unlock restart/start/stop actions and failed service diagnostics.")
            }

            monitorRefreshHeader(
                title: "Services",
                message: "systemd units parsed into actionable status rows.",
                primaryTitle: "Refresh Services",
                primarySymbol: "gearshape.2",
                primaryAction: { appState.refreshSystemdServices(for: server) }
            )

            if services.isEmpty {
                EmptyStateView(
                    title: "No services loaded",
                    message: "Refresh to read systemd service states.",
                    symbol: "gearshape.2"
                )
            } else {
                ForEach(services) { service in
                    serviceRow(service)
                }
            }

            commandPreview(title: "Failed units", command: systemdService.failedUnitsCommand())
            commandPreview(title: "Enabled services", command: "systemctl list-unit-files --type=service --state=enabled --no-pager | head -n 45")
            commandPreview(title: "Recent service errors", command: "journalctl -p err -n 80 --no-pager")
        }
    }

    private func logs(server: ServerProfile) -> some View {
        let entries = appState.logEntries(for: server)
        return VStack(spacing: 12) {
            if !appState.isProUnlocked {
                PremiumLockedCard(title: "Logs viewer is Pro", message: "Unlock journalctl, dmesg, nginx and Docker logs.")
            }

            monitorRefreshHeader(
                title: "Recent Logs",
                message: "Journal entries parsed into severity-aware rows.",
                primaryTitle: "Refresh Logs",
                primarySymbol: "doc.text.magnifyingglass",
                primaryAction: { appState.refreshLogEntries(for: server) }
            )

            if entries.isEmpty {
                EmptyStateView(
                    title: "No logs loaded",
                    message: "Refresh to read journal entries.",
                    symbol: "doc.text.magnifyingglass"
                )
            } else {
                ForEach(entries.prefix(40)) { entry in
                    logRow(entry)
                }
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
                    .buttonStyle(.plain)
                    .padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())

                    if let secondaryTitle, let secondarySymbol, let secondaryAction {
                        Button(action: secondaryAction) {
                            Label(secondaryTitle, systemImage: secondarySymbol)
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
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

                HStack {
                    Text("CPU \(percent(container.cpuUsage))")
                    Text("RAM \(percent(container.memoryUsage))")
                    Spacer()
                    Button("Logs") {
                        runRemote(dockerService.logsCommand(containerName: container.name, lines: 120))
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

                HStack {
                    Text("\(service.loadedState) / \(service.subState)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Status") {
                        runRemote(systemdService.statusCommand(serviceName: service.name))
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

    private func commandPreview(title: LocalizedStringKey, command: String, requiresConfirmation: Bool = false) -> some View {
        GlassCard(cornerRadius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = command
                    } label: {
                        Label("Copy Command", systemImage: "doc.on.doc")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    Button {
                        if requiresConfirmation {
                            confirm(command)
                        } else {
                            runRemote(command)
                        }
                    } label: {
                        Label("Run via SSH", systemImage: "play.fill")
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

    private var packages: some View {
        VStack(spacing: 12) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Package Diagnostics", systemImage: "wrench.and.screwdriver")
                        .font(.headline)
                    ForEach(appState.packageDetector.checkCommandsPreview(), id: \.self) { command in
                        Text(command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    GlassPrimaryButton(title: "Run Diagnostics", symbol: "stethoscope") {
                        appState.refreshPackageStatuses(for: appState.selectedServer)
                    }
                    GlassPrimaryButton(title: "Open Missing Tools", symbol: "exclamationmark.magnifyingglass") {
                        showingMissingTools = true
                    }
                }
            }

            ForEach(appState.packageStatuses) { item in
                GlassCard(cornerRadius: 20, padding: 14) {
                    HStack {
                        Image(systemName: item.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.isInstalled ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.commandName)
                                .font(.headline)
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

    private func terminalShortcut(server: ServerProfile) -> some View {
        GlassCard {
            VStack(spacing: 16) {
                EmptyStateView(
                    title: "Terminal ready",
                    message: "Open a protected SSH session for this server.",
                    symbol: "terminal"
                )
                GlassPrimaryButton(title: "Open Terminal", symbol: "terminal") {
                    appState.select(server, tab: .terminal)
                }
            }
        }
    }

    private func actions(server: ServerProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Label("Server Actions", systemImage: "bolt.horizontal")
                    .font(.headline)
                Button("Run Quick Command") {
                    appState.select(server, tab: .commands)
                }
                Button("Refresh Metrics") {
                    appState.refreshMetrics(for: server)
                }
                Button("Start Live Activity") {
                    appState.startMonitoringLiveActivity()
                }
                Button("End Live Activity") {
                    appState.endLiveActivity()
                }
                Button("Reboot Server", role: .destructive) {
                    confirm("sudo reboot", message: appState.localized("Reboot %@? This command runs remotely over SSH.", server.name))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confirm(_ command: String, message: String? = nil) {
        confirmationMessage = message ?? command
        pendingRemoteCommand = command
        showingConfirmation = true
    }

    private func runRemote(_ command: String) {
        guard let server = appState.selectedServer else {
            appState.lastCommandOutput = appState.localized("Select a server before running commands.")
            return
        }
        appState.runRemoteCommand(command, on: server)
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
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case processes = "Processes"
    case disks = "Disks"
    case docker = "Docker"
    case services = "Services"
    case logs = "Logs"
    case packages = "Packages"
    case terminal = "Terminal"
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
        case .packages: "wrench.and.screwdriver"
        case .terminal: "terminal"
        case .actions: "bolt.horizontal"
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

struct PremiumLockedCard: View {
    @EnvironmentObject private var appState: AppState
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
                    appState.isPaywallPresented = true
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
