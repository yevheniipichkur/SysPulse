import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @Published var selectedTab: AppTab = .servers
    @Published var selectedServer: ServerProfile?
    @Published var serverProfiles: [ServerProfile]
    @Published var metricsByServer: [UUID: ServerMetrics]
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
    let demoDataService = DemoDataService()
    let healthScoreService = HealthScoreService()
    let insightsService = InsightsService()
    let packageDetector = PackageDetector()
    let sshClient: SSHClientProtocol = MockSSHClient()

    init() {
        let demoServers = DemoDataService.makeDemoServers()
        let savedProfiles = ProfileStorageService().loadProfiles()
        let allProfiles = demoServers + savedProfiles
        var metrics = DemoDataService.makeMetrics(for: demoServers)
        for profile in savedProfiles {
            metrics[profile.id] = ServerMetrics.empty(serverID: profile.id)
        }
        self.serverProfiles = allProfiles
        self.metricsByServer = metrics
        self.quickCommands = DemoDataService.makeQuickCommands()
        self.terminalSessions = [
            TerminalSession(
                serverID: demoServers.first?.id,
                title: "Demo SSH",
                transcript: """
                SysPulse Demo Terminal
                Connected to Raspberry Pi Home Server

                pi@home:~ $ uptime
                 19:26:11 up 42 days,  3:11,  1 user,  load average: 0.18, 0.21, 0.19
                """
            )
        ]
        self.settings = SettingsStorageService().loadSettings()
        self.subscription = SettingsStorageService().loadSubscription()
        self.selectedServer = allProfiles.first
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

    func completeOnboarding(enableDemoMode: Bool) {
        hasSeenOnboarding = true
        settings.demoMetricsEnabled = enableDemoMode
        if enableDemoMode {
            enableDemoModeData()
        }
        haptic(.medium)
    }

    func enableDemoModeData() {
        let servers = DemoDataService.makeDemoServers()
        let savedProfiles = profileStorage.loadProfiles()
        serverProfiles = servers + savedProfiles
        metricsByServer = DemoDataService.makeMetrics(for: servers)
        for profile in savedProfiles {
            metricsByServer[profile.id] = ServerMetrics.empty(serverID: profile.id)
        }
        selectedServer = servers.first
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

    func addServer(_ server: ServerProfile) {
        if !isProUnlocked && serverProfiles.filter({ !$0.isDemo }).count >= 1 {
            isPaywallPresented = true
            return
        }
        serverProfiles.append(server)
        metricsByServer[server.id] = ServerMetrics.empty(serverID: server.id)
        selectedServer = server
        profileStorage.saveProfiles(serverProfiles)
        haptic(.light)
    }

    func deleteServer(_ server: ServerProfile) {
        serverProfiles.removeAll { $0.id == server.id }
        metricsByServer.removeValue(forKey: server.id)
        if let credentialIdentifier = server.credentialIdentifier, !server.isDemo {
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

    func simulateHighCPU() {
        guard let server = selectedServer else { return }
        var metrics = metric(for: server)
        metrics.cpuUsage = 94
        metrics.healthScore = 48
        metricsByServer[server.id] = metrics
    }

    func simulateDiskFull() {
        guard let server = selectedServer else { return }
        var metrics = metric(for: server)
        metrics.diskUsage = 93
        metrics.healthScore = 42
        metricsByServer[server.id] = metrics
    }

    func simulateOfflineServer() {
        selectedServer?.status = .offline
    }

    func resetOnboarding() {
        hasSeenOnboarding = false
    }

    func clearSavedProfiles() {
        serverProfiles
            .filter { !$0.isDemo }
            .compactMap(\.credentialIdentifier)
            .forEach { try? KeychainService.shared.deleteSecret(account: $0) }
        profileStorage.clearProfiles()
        enableDemoModeData()
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard !settings.reduceAnimations else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
