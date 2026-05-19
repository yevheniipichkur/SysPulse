import SwiftUI

struct ServerDetailView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: DetailTab = .overview
    @State private var showingMissingTools = false
    @State private var confirmationMessage = ""
    @State private var showingConfirmation = false

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
                                    processes
                                case .disks:
                                    disks
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
                appState.lastCommandOutput = "Confirmed: \(confirmationMessage)"
            }
        } message: {
            Text(confirmationMessage)
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
                    StatusPill(status: server.status)
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
                        Label(tab.title, systemImage: tab.symbol)
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
                                Text(insight.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(insight.details)
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
                    Text("System")
                        .font(.headline)
                    DetailRow(title: "Kernel", value: metrics.kernel)
                    DetailRow(title: "Load average", value: metrics.loadAverage)
                    DetailRow(title: "IP addresses", value: metrics.ipAddresses.joined(separator: ", "))
                }
            }
        }
    }

    private var processes: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Top Processes", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                ForEach(DemoDataService.makeProcesses()) { process in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(process.command)
                                .font(.subheadline.weight(.semibold))
                            Text("#\(process.pid) • \(process.user)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("CPU \(process.cpu, specifier: "%.1f")%")
                            .font(.caption.monospacedDigit())
                        Text("RAM \(process.memory, specifier: "%.1f")%")
                            .font(.caption.monospacedDigit())
                        Button {
                            confirmationMessage = "Kill process \(process.pid)? This action runs remotely and cannot be undone."
                            showingConfirmation = true
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private var disks: some View {
        VStack(spacing: 12) {
            ForEach(DemoDataService.makeDisks()) { disk in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(disk.mountPoint, systemImage: "externaldrive")
                                .font(.headline)
                            Spacer()
                            Text(disk.usagePercent >= 90 ? "Critical" : disk.usagePercent >= 80 ? "Warning" : "Healthy")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(disk.usagePercent >= 90 ? .red : disk.usagePercent >= 80 ? .orange : .green)
                        }
                        CompactProgress(value: disk.usagePercent, color: disk.usagePercent >= 80 ? .orange : .blue)
                        DetailRow(title: "Used / Free", value: String(format: "%.0f GB / %.0f GB", disk.usedGB, disk.freeGB))
                        DetailRow(title: "Filesystem", value: disk.filesystem)
                        DetailRow(title: "SMART", value: disk.smartStatus ?? "smartmontools missing")
                    }
                }
            }
        }
    }

    private func docker(server: ServerProfile) -> some View {
        VStack(spacing: 12) {
            if !appState.isProUnlocked {
                PremiumLockedCard(title: "Docker monitoring is Pro", message: "Unlock live container stats, logs and restart actions.")
            }
            ForEach(dockerService.containers(for: server)) { container in
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(container.name, systemImage: "shippingbox")
                                .font(.headline)
                            Spacer()
                            Text(container.status)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(container.restartedRecently ? .orange : .green)
                        }
                        DetailRow(title: "Image", value: container.image)
                        HStack {
                            CompactMetric(title: "CPU", value: container.cpuUsage, color: .cyan)
                            CompactMetric(title: "Memory", value: container.memoryUsage, color: .green)
                        }
                        HStack {
                            Button("Start") { confirm("Start container \(container.name)?") }
                            Button("Stop", role: .destructive) { confirm("Stop container \(container.name)?") }
                            Button("Restart") { confirm("Restart container \(container.name)?") }
                            Spacer()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private func services(server: ServerProfile) -> some View {
        VStack(spacing: 12) {
            if !appState.isProUnlocked {
                PremiumLockedCard(title: "Advanced systemd is Pro", message: "Unlock restart/start/stop actions and failed service diagnostics.")
            }
            ForEach(systemdService.services(for: server)) { service in
                GlassCard {
                    HStack(spacing: 12) {
                        Image(systemName: service.isFailed ? "xmark.seal" : "checkmark.seal")
                            .foregroundStyle(service.isFailed ? .red : .green)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(service.name)
                                .font(.headline)
                            Text("\(service.loadedState) • \(service.activeState) • \(service.subState)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Start") { confirm("Start service \(service.name)?") }
                            Button("Restart") { confirm("Restart service \(service.name)?") }
                            Button("Stop", role: .destructive) { confirm("Stop service \(service.name)?") }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
    }

    private func logs(server: ServerProfile) -> some View {
        VStack(spacing: 12) {
            if !appState.isProUnlocked {
                PremiumLockedCard(title: "Logs viewer is Pro", message: "Unlock journalctl, dmesg, nginx and Docker logs.")
            }
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Recent Logs", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                        Spacer()
                        Button {
                            appState.lastCommandOutput = logsService.recentLogs(for: server).joined(separator: "\n")
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    ForEach(logsService.recentLogs(for: server), id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3)
                    }
                }
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
                    GlassPrimaryButton(title: "Open Missing Tools", symbol: "exclamationmark.magnifyingglass") {
                        showingMissingTools = true
                    }
                }
            }

            ForEach(appState.packageDetector.packageStatuses) { item in
                GlassCard(cornerRadius: 20, padding: 14) {
                    HStack {
                        Image(systemName: item.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.isInstalled ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.commandName)
                                .font(.headline)
                            Text(item.featureImpact)
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
                    appState.metricsByServer[server.id]?.timestamp = .now
                }
                Button("Reboot Server", role: .destructive) {
                    confirm("Reboot \(server.name)? SysPulse will show a final confirmation before running sudo reboot.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confirm(_ message: String) {
        confirmationMessage = message
        showingConfirmation = true
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
    var title: String { rawValue }

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

struct DetailRow: View {
    var title: String
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
