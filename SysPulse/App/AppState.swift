import Foundation
import StoreKit
import SwiftData
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
    @Published var isSecurityUnlocked = false
    @Published var isSecurityPromptInProgress = false
    @Published var isPrivacyShieldVisible = false
    @Published var securityLockMessage = ""
    @Published var lastCommandOutput = ""
    @Published var processItemsByServer: [UUID: [ProcessInfoItem]] = [:]
    @Published var diskInfoByServer: [UUID: [DiskInfo]] = [:]
    @Published var dockerContainersByServer: [UUID: [DockerContainer]] = [:]
    @Published var systemdServicesByServer: [UUID: [SystemdServiceItem]] = [:]
    @Published var logEntriesByServer: [UUID: [LogEntry]] = [:]

    private var profileRepository: ProfileRepository?
    private let settingsStorage = SettingsStorageService()
    private let widgetDataService = WidgetDataService()
    private let liveActivityService = LiveActivityService()
    private let biometricLockService = BiometricLockService()
    private let metricsCollector = MetricsCollector()
    private let processService = ProcessService()
    private let diskService = DiskService()
    private let dockerService = DockerService()
    private let systemdService = SystemdService()
    private let logsService = LogsService()
    let healthScoreService = HealthScoreService()
    let insightsService = InsightsService()
    let packageDetector = PackageDetector()
    let sshClient: SSHClientProtocol = RealSSHClient()
    let storeKit = StoreKitService()
    @Published var packageStatuses: [PackageStatus]
    private var autoRefreshTask: Task<Void, Never>?
    private var protectedBackgroundDate: Date?

    init() {
        self.serverProfiles = []
        self.metricsByServer = [:]
        self.quickCommands = QuickCommandCatalog.makeQuickCommands()
        self.terminalSessions = []
        self.settings = SettingsStorageService().loadSettings()
        self.subscription = SettingsStorageService().loadSubscription()
        self.packageStatuses = PackageDetector.defaultStatuses
        self.selectedServer = nil
        startStoreKit()
    }

    private func startStoreKit() {
        storeKit.onSubscriptionChange = { [weak self] state in
            self?.subscription = state
        }
        Task {
            await storeKit.loadProducts()
            let state = await storeKit.verifyCurrentEntitlements()
            if state.isPro { subscription = state }
        }
    }

    func purchaseProduct(_ product: Product) async throws {
        let state = try await storeKit.purchase(product)
        subscription = state
        isPaywallPresented = false
    }

    func restorePurchases() async throws {
        try await storeKit.restorePurchases()
        if subscription.isPro { isPaywallPresented = false }
    }

    func configureProfileRepository(modelContext: ModelContext) {
        guard profileRepository == nil else { return }
        profileRepository = SwiftDataProfileRepository(modelContext: modelContext)
        reloadProfilesFromRepository()
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

    var shouldShowSecurityLock: Bool {
        settings.requiresBiometrics && hasSeenOnboarding && (isPrivacyShieldVisible || !isSecurityUnlocked)
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: settings.language, arguments: arguments)
    }

    func completeOnboarding() {
        hasSeenOnboarding = true
        haptic(.medium)
    }

    func handleScenePhase(_ phase: ScenePhase) {
        guard settings.requiresBiometrics, hasSeenOnboarding else {
            isSecurityUnlocked = true
            isPrivacyShieldVisible = false
            return
        }

        switch phase {
        case .active:
            Task {
                await unlockAppIfNeeded()
            }
        case .inactive, .background:
            protectedBackgroundDate = .now
            isPrivacyShieldVisible = true
        @unknown default:
            break
        }
    }

    func unlockAppIfNeeded(force: Bool = false) async {
        guard settings.requiresBiometrics, hasSeenOnboarding else {
            isSecurityUnlocked = true
            isPrivacyShieldVisible = false
            securityLockMessage = ""
            return
        }

        let didPassAutoLock = protectedBackgroundDate.map { backgroundDate in
            Date.now.timeIntervalSince(backgroundDate) >= TimeInterval(settings.autoLockMinutes * 60)
        } ?? false

        guard force || !isSecurityUnlocked || didPassAutoLock else {
            isPrivacyShieldVisible = false
            return
        }

        isSecurityUnlocked = false
        isPrivacyShieldVisible = true
        await authenticateForSecurityUnlock(reason: localized("Unlock SysPulse"))
    }

    func enableBiometricLockFromSettings() async {
        guard !settings.requiresBiometrics else { return }

        isPrivacyShieldVisible = true
        let result = await biometricLockService.unlock(reason: localized("Enable Face ID lock for SysPulse"))
        switch result {
        case .success:
            settings.requiresBiometrics = true
            isSecurityUnlocked = true
            isPrivacyShieldVisible = false
            securityLockMessage = ""
            lastCommandOutput = localized("Face ID lock enabled.")
        case .unavailable(let message), .failed(let message):
            isSecurityUnlocked = true
            isPrivacyShieldVisible = false
            securityLockMessage = message
            lastCommandOutput = localized("Face ID lock was not enabled: %@", message)
        }
    }

    func disableBiometricLock() {
        settings.requiresBiometrics = false
        isSecurityUnlocked = true
        isPrivacyShieldVisible = false
        securityLockMessage = ""
        lastCommandOutput = localized("Face ID lock disabled.")
    }

    private func authenticateForSecurityUnlock(reason: String) async {
        guard !isSecurityPromptInProgress else { return }

        isSecurityPromptInProgress = true
        securityLockMessage = ""
        let result = await biometricLockService.unlock(reason: reason)
        isSecurityPromptInProgress = false

        switch result {
        case .success:
            isSecurityUnlocked = true
            isPrivacyShieldVisible = false
            securityLockMessage = ""
            protectedBackgroundDate = nil
        case .unavailable(let message):
            settings.requiresBiometrics = false
            isSecurityUnlocked = true
            isPrivacyShieldVisible = false
            securityLockMessage = ""
            lastCommandOutput = localized("Face ID lock is unavailable and was turned off: %@", message)
        case .failed(let message):
            isSecurityUnlocked = false
            isPrivacyShieldVisible = true
            securityLockMessage = message
        }
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

    func processes(for server: ServerProfile?) -> [ProcessInfoItem] {
        guard let server else { return [] }
        return processItemsByServer[server.id] ?? []
    }

    func disks(for server: ServerProfile?) -> [DiskInfo] {
        guard let server else { return [] }
        return diskInfoByServer[server.id] ?? []
    }

    func dockerContainers(for server: ServerProfile?) -> [DockerContainer] {
        guard let server else { return [] }
        return dockerContainersByServer[server.id] ?? []
    }

    func systemdServices(for server: ServerProfile?) -> [SystemdServiceItem] {
        guard let server else { return [] }
        return systemdServicesByServer[server.id] ?? []
    }

    func logEntries(for server: ServerProfile?) -> [LogEntry] {
        guard let server else { return [] }
        return logEntriesByServer[server.id] ?? []
    }

    @discardableResult
    func addServer(_ server: ServerProfile) -> Bool {
        if !isProUnlocked && serverProfiles.count >= 1 {
            isPaywallPresented = true
            return false
        }

        guard let profileRepository else {
            lastCommandOutput = localized("Profile database is not ready yet.")
            return false
        }

        do {
            try profileRepository.saveProfile(server)
        } catch {
            lastCommandOutput = localized("Failed to save profile: %@", error.localizedDescription)
            return false
        }

        serverProfiles.append(server)
        metricsByServer[server.id] = ServerMetrics.empty(serverID: server.id)
        selectedServer = server
        uploadProfilesToICloudIfEnabled()
        haptic(.light)
        return true
    }

    func updateServer(_ server: ServerProfile) {
        guard let profileRepository else {
            lastCommandOutput = localized("Profile database is not ready yet.")
            return
        }

        server.updatedAt = .now
        do {
            try profileRepository.saveProfile(server)
        } catch {
            lastCommandOutput = localized("Failed to save profile: %@", error.localizedDescription)
            return
        }

        if selectedServer?.id == server.id {
            selectedServer = server
        }
        objectWillChange.send()
        uploadProfilesToICloudIfEnabled()
        haptic(.light)
    }

    func deleteServer(_ server: ServerProfile) {
        guard let profileRepository else {
            lastCommandOutput = localized("Profile database is not ready yet.")
            return
        }

        let serverID = server.id
        let credentialIdentifier = server.credentialIdentifier
        do {
            try profileRepository.deleteProfile(server)
        } catch {
            lastCommandOutput = localized("Failed to delete profile: %@", error.localizedDescription)
            return
        }

        serverProfiles.removeAll { $0.id == serverID }
        metricsByServer.removeValue(forKey: serverID)
        processItemsByServer.removeValue(forKey: serverID)
        diskInfoByServer.removeValue(forKey: serverID)
        dockerContainersByServer.removeValue(forKey: serverID)
        systemdServicesByServer.removeValue(forKey: serverID)
        logEntriesByServer.removeValue(forKey: serverID)
        terminalSessions.removeAll { $0.serverID == serverID }
        if let credentialIdentifier {
            try? KeychainService.shared.deleteSecret(account: credentialIdentifier)
        }
        if selectedServer?.id == serverID {
            selectedServer = serverProfiles.first
        }
        uploadProfilesToICloudIfEnabled()
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
        lastCommandOutput = localized("Refreshing metrics for %@...", server.name)
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
                    lastCommandOutput = localized("Metrics refreshed for %@.", server.name)
                    updateLiveActivity(message: localized("Metrics refreshed"))
                }
            } catch {
                await MainActor.run {
                    if selectedServer?.id == server.id {
                        selectedServer?.status = .warning
                    }
                    lastCommandOutput = localized("Metrics refresh failed for %@: %@", server.name, error.localizedDescription)
                }
            }
        }
    }

    func runRemoteCommand(_ command: String, on server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = localized("Select a server before running commands.")
            return
        }

        lastCommandOutput = localized("Running on %@:\n%@", targetServer.name, command)
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                await MainActor.run {
                    lastCommandOutput = output.isEmpty ? localized("Command completed with no output.") : output
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func refreshProcesses(for server: ServerProfile? = nil, sortedByMemory: Bool = false) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = localized("Select a server before running commands.")
            return
        }

        let command = sortedByMemory ? processService.topMemoryCommand() : processService.topCPUCommand()
        lastCommandOutput = localized("Loading processes from %@...", targetServer.name)
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let processes = processService.parseProcesses(output)
                await MainActor.run {
                    processItemsByServer[targetServer.id] = processes
                    lastCommandOutput = output.isEmpty ? localized("Command completed with no output.") : output
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func refreshDisks(for server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = localized("Select a server before running commands.")
            return
        }

        let command = diskService.usageCommand()
        lastCommandOutput = localized("Loading disks from %@...", targetServer.name)
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let disks = diskService.parseDisks(output)
                await MainActor.run {
                    diskInfoByServer[targetServer.id] = disks
                    lastCommandOutput = output.isEmpty ? localized("Command completed with no output.") : output
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func refreshDockerContainers(for server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = localized("Select a server before running commands.")
            return
        }

        let command = dockerService.inventoryCommand()
        lastCommandOutput = localized("Loading Docker containers from %@...", targetServer.name)
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let containers = dockerService.parseContainers(output)
                await MainActor.run {
                    dockerContainersByServer[targetServer.id] = containers
                    lastCommandOutput = output.isEmpty ? localized("Command completed with no output.") : output
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func refreshSystemdServices(for server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = localized("Select a server before running commands.")
            return
        }

        let command = systemdService.unitsCommand()
        lastCommandOutput = localized("Loading systemd services from %@...", targetServer.name)
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let services = systemdService.parseServices(output)
                await MainActor.run {
                    systemdServicesByServer[targetServer.id] = services
                    lastCommandOutput = output.isEmpty ? localized("Command completed with no output.") : output
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func refreshLogEntries(for server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = localized("Select a server before running commands.")
            return
        }

        let command = logsService.structuredJournalCommand()
        lastCommandOutput = localized("Loading logs from %@...", targetServer.name)
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let logs = logsService.parseLogEntries(output)
                await MainActor.run {
                    logEntriesByServer[targetServer.id] = logs
                    lastCommandOutput = output.isEmpty ? localized("Command completed with no output.") : output
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
            lastCommandOutput = localized("Select a server before checking packages.")
            return
        }

        lastCommandOutput = localized("Checking packages on %@...", targetServer.name)
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
        updateLiveActivity(message: localized("High CPU simulated"))
    }

    func simulateDiskFull() {
        guard let server = selectedServer else { return }
        var metrics = metric(for: server)
        metrics.diskUsage = 93
        metrics.healthScore = 42
        metricsByServer[server.id] = metrics
        updateLiveActivity(message: localized("Disk warning simulated"))
    }

    func simulateOfflineServer() {
        selectedServer?.status = .offline
    }

    func resetOnboarding() {
        hasSeenOnboarding = false
    }

    func clearSavedProfiles() {
        guard let profileRepository else {
            lastCommandOutput = localized("Profile database is not ready yet.")
            return
        }

        let credentialIdentifiers = serverProfiles.compactMap(\.credentialIdentifier)
        do {
            try profileRepository.deleteAllProfiles()
        } catch {
            lastCommandOutput = localized("Failed to clear profiles: %@", error.localizedDescription)
            return
        }

        credentialIdentifiers.forEach { try? KeychainService.shared.deleteSecret(account: $0) }
        serverProfiles = []
        metricsByServer = [:]
        terminalSessions = []
        selectedServer = nil
        processItemsByServer = [:]
        diskInfoByServer = [:]
        dockerContainersByServer = [:]
        systemdServicesByServer = [:]
        logEntriesByServer = [:]
        publishWidgetSnapshots()
        uploadProfilesToICloudIfEnabled()
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

    func updateLiveActivity(message: String? = nil) {
        guard isProUnlocked else { return }
        guard let server = selectedServer else { return }
        let metrics = metric(for: server)
        let statusMessage = message ?? localized("Monitoring refreshed")
        Task {
            await liveActivityService.update(metrics: metrics, message: "\(server.name): \(statusMessage)")
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

    private func reloadProfilesFromRepository() {
        guard let profileRepository else { return }
        do {
            let savedProfiles = try profileRepository.loadProfiles()
            serverProfiles = savedProfiles
            metricsByServer = Dictionary(
                uniqueKeysWithValues: savedProfiles.map { profile in
                    (profile.id, metricsByServer[profile.id] ?? ServerMetrics.empty(serverID: profile.id))
                }
            )
            selectedServer = selectedServer.flatMap { selected in
                savedProfiles.first { $0.id == selected.id }
            } ?? savedProfiles.first
            publishWidgetSnapshots()
        } catch {
            lastCommandOutput = localized("Failed to load profiles: %@", error.localizedDescription)
        }
    }

    func syncProfilesWithICloud(mergeRemote: Bool = false) {
        guard settings.iCloudSyncEnabled else { return }
        guard let profileRepository else { return }

        let localProfiles = serverProfiles
        Task {
            do {
                let profileCloudSyncService = ProfileCloudSyncService()
                if mergeRemote {
                    let syncedProfiles = try await profileCloudSyncService.mergeAndUpload(localProfiles: localProfiles)
                    for profile in syncedProfiles {
                        try profileRepository.saveProfile(profile)
                    }
                    reloadProfilesFromRepository()
                    lastCommandOutput = localized("iCloud profile sync completed.")
                } else {
                    try await profileCloudSyncService.uploadSnapshot(localProfiles: localProfiles)
                    lastCommandOutput = localized("iCloud profile snapshot updated.")
                }
            } catch {
                lastCommandOutput = localized("iCloud sync failed: %@", error.localizedDescription)
            }
        }
    }

    private func uploadProfilesToICloudIfEnabled() {
        guard settings.iCloudSyncEnabled else { return }
        syncProfilesWithICloud()
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard !settings.reduceAnimations else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
