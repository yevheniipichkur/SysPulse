import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @Published var selectedTab: AppTab = .servers
    @Published var selectedServer: ServerProfile?
    @Published var serverProfiles: [ServerProfile] {
        didSet {
            publishWidgetSnapshots()
        }
    }
    @Published var metricsByServer: [UUID: ServerMetrics] {
        didSet {
            publishWidgetSnapshots()
        }
    }
    @Published var quickCommands: [QuickCommand]
    @Published var terminalSessions: [TerminalSession]
    @Published var settings: AppSettings {
        didSet {
            settingsStorage.saveSettings(settings)
        }
    }
    @Published var subscription: SubscriptionState {
        didSet {
            settingsStorage.saveSubscription(subscription)
        }
    }
    @Published var isPaywallPresented = false
    @Published var isDebugMenuPresented = false
    @Published var lastCommandOutput = ""

    private let profileStorage = ProfileStorageService()
    private let settingsStorage = SettingsStorageService()
    private let widgetDataService = WidgetDataService()
    private let liveActivityService = LiveActivityService()
    private let metricsCollector = MetricsCollector()
    let healthScoreService = HealthScoreService()
    let insightsService = InsightsService()
    let packageDetector = PackageDetector()
    let sshClient: SSHClientProtocol = RealSSHClient()
    @Published var packageStatuses: [PackageStatus]
    private var autoRefreshTask: Task<Void, Never>?

    init() {
        let savedProfiles = ProfileStorageService().loadProfiles()
        var metrics: [UUID: ServerMetrics] = [:]
        for profile in savedProfiles {
            metrics[profile.id] = ServerMetrics.empty(serverID: profile.id)
        }
        self.serverProfiles = savedProfiles
        self.metricsByServer = metrics
        self.quickCommands = QuickCommandCatalog.makeQuickCommands()
        self.terminalSessions = []
        self.settings = SettingsStorageService().loadSettings()
        self.subscription = SettingsStorageService().loadSubscription()
        self.packageStatuses = PackageDetector.defaultStatuses
        self.selectedServer = savedProfiles.first
        publishWidgetSnapshots()
        startAutoRefresh()
    }

    var isProUnlocked: Bool {
        subscription.isPro || settings.forceProOverride
    }

    var preferredColorScheme: ColorScheme? {
        switch settings.appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func completeOnboarding() {
        hasSeenOnboarding = true
        haptic(.medium)
    }

    func metric(for server: ServerProfile?) -> ServerMetrics {
        guard let server else {
            return ServerMetrics.empty(serverID: UUID())
        }
        return metricsByServer[server.id] ?? ServerMetrics.empty(serverID: server.id)
    }

    func insights(for server: ServerProfile?) -> [SmartInsight] {
        insightsService.makeInsights(for: metric(for: server))
    }

    @discardableResult
    func addServer(_ server: ServerProfile) -> Bool {
        if !isProUnlocked && serverProfiles.count >= 1 {
            isPaywallPresented = true
            return false
        }
        serverProfiles.append(server)
        metricsByServer[server.id] = ServerMetrics.empty(serverID: server.id)
        selectedServer = server
        profileStorage.saveProfiles(serverProfiles)
        haptic(.light)
        return true
    }

    func updateServer(_ server: ServerProfile) {
        server.updatedAt = .now
        if selectedServer?.id == server.id {
            selectedServer = server
        }
        profileStorage.saveProfiles(serverProfiles)
        objectWillChange.send()
        haptic(.light)
    }

    func deleteServer(_ server: ServerProfile) {
        serverProfiles.removeAll { $0.id == server.id }
        metricsByServer.removeValue(forKey: server.id)
        terminalSessions.removeAll { $0.serverID == server.id }
        if let credentialIdentifier = server.credentialIdentifier {
            try? KeychainService.shared.deleteSecret(account: credentialIdentifier)
        }
        profileStorage.saveProfiles(serverProfiles)
        if selectedServer?.id == server.id {
            selectedServer = serverProfiles.first
        }
        haptic(.rigid)
    }

    func select(_ server: ServerProfile, tab: AppTab = .monitor) {
        selectedServer = server
        selectedTab = tab
        haptic(.light)
    }

    func testConnection(to server: ServerProfile) async throws -> String {
        try await sshClient.connect(to: server)
        return try await sshClient.run("uname -a", on: server)
    }

    func refreshAllServers() {
        for server in serverProfiles {
            refreshMetrics(for: server)
        }
    }

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            refreshAllServers()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                refreshAllServers()
            }
        }
    }

    func refreshMetrics(for server: ServerProfile) {
        lastCommandOutput = "Refreshing metrics for \(server.name)..."
        Task {
            do {
                let previous = await MainActor.run {
                    metricsByServer[server.id]
                }
                let metrics = try await metricsCollector.collect(server: server, using: sshClient, previous: previous)
                await MainActor.run {
                    metricsByServer[server.id] = metrics
                    if selectedServer?.id == server.id {
                        selectedServer?.status = .online
                    }
                    lastCommandOutput = "Metrics refreshed for \(server.name)."
                    updateLiveActivity(message: "Metrics refreshed")
                }
            } catch {
                await MainActor.run {
                    if selectedServer?.id == server.id {
                        selectedServer?.status = .warning
                    }
                    lastCommandOutput = "Metrics refresh failed for \(server.name): \(error.localizedDescription)"
                }
            }
        }
    }

    func runRemoteCommand(_ command: String, on server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = "Select a server before running commands."
            return
        }

        lastCommandOutput = "Running on \(targetServer.name):\n\(command)"
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                await MainActor.run {
                    lastCommandOutput = output.isEmpty ? "Command completed with no output." : output
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func refreshPackageStatuses(for server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = "Select a server before checking packages."
            return
        }

        lastCommandOutput = "Checking packages on \(targetServer.name)..."
        Task {
            do {
                let output = try await sshClient.run(packageDetector.detectionCommand(), on: targetServer)
                let statuses = packageDetector.parseStatuses(output)
                await MainActor.run {
                    packageStatuses = statuses
                    lastCommandOutput = output
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func simulateHighCPU() {
        guard let server = selectedServer else { return }
        var metrics = metric(for: server)
        metrics.cpuUsage = 94
        metrics.healthScore = 48
        metricsByServer[server.id] = metrics
        updateLiveActivity(message: "High CPU simulated")
    }

    func simulateDiskFull() {
        guard let server = selectedServer else { return }
        var metrics = metric(for: server)
        metrics.diskUsage = 93
        metrics.healthScore = 42
        metricsByServer[server.id] = metrics
        updateLiveActivity(message: "Disk warning simulated")
    }

    func simulateOfflineServer() {
        selectedServer?.status = .offline
    }

    func resetOnboarding() {
        hasSeenOnboarding = false
    }

    func clearSavedProfiles() {
        serverProfiles
            .compactMap(\.credentialIdentifier)
            .forEach { try? KeychainService.shared.deleteSecret(account: $0) }
        profileStorage.clearProfiles()
        serverProfiles = []
        metricsByServer = [:]
        terminalSessions = []
        selectedServer = nil
        publishWidgetSnapshots()
    }

    func startMonitoringLiveActivity() {
        guard isProUnlocked else {
            isPaywallPresented = true
            return
        }
        guard let server = selectedServer else { return }
        let metrics = metric(for: server)
        Task {
            await liveActivityService.startMonitoring(server: server, metrics: metrics)
        }
    }

    func updateLiveActivity(message: String = "Monitoring refreshed") {
        guard isProUnlocked else { return }
        guard let server = selectedServer else { return }
        let metrics = metric(for: server)
        Task {
            await liveActivityService.update(metrics: metrics, message: "\(server.name): \(message)")
        }
    }

    func endLiveActivity() {
        Task {
            await liveActivityService.end()
        }
    }

    private func publishWidgetSnapshots() {
        widgetDataService.save(profiles: serverProfiles, metricsByServer: metricsByServer)
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard !settings.reduceAnimations else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
