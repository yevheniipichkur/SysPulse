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
    @Published var settings: AppSettings
    @Published var subscription: SubscriptionState
    @Published var isPaywallPresented = false
    @Published var isDebugMenuPresented = false
    @Published var lastCommandOutput = ""

    let demoDataService = DemoDataService()
    let healthScoreService = HealthScoreService()
    let insightsService = InsightsService()
    let packageDetector = PackageDetector()
    let sshClient: SSHClientProtocol = MockSSHClient()

    init() {
        let demoServers = DemoDataService.makeDemoServers()
        self.serverProfiles = demoServers
        self.metricsByServer = DemoDataService.makeMetrics(for: demoServers)
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
        self.settings = AppSettings()
        self.subscription = SubscriptionState()
        self.selectedServer = demoServers.first
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
        serverProfiles = servers
        metricsByServer = DemoDataService.makeMetrics(for: servers)
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
        haptic(.light)
    }

    func deleteServer(_ server: ServerProfile) {
        serverProfiles.removeAll { $0.id == server.id }
        metricsByServer.removeValue(forKey: server.id)
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

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard !settings.reduceAnimations else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
