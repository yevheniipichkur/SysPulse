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
            enforceSubscriptionBoundaries()
        }
    }
    @Published var isPaywallPresented = false
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
    @Published var sftpItemsByServer: [UUID: [SFTPRemoteItem]] = [:]
    @Published var sftpPathByServer: [UUID: String] = [:]
    @Published var sftpLoadingServerIDs: Set<UUID> = []
    @Published var metricRefreshingServerIDs: Set<UUID> = []
    @Published var alertRules: [AlertRule] = []
    @Published var areNotificationsAuthorized = false

    private var modelContext: ModelContext?
    private var profileRepository: ProfileRepository?
    private let settingsStorage = SettingsStorageService()
    private let widgetDataService = WidgetDataService()
    private let liveActivityService = LiveActivityService()
    private let biometricLockService = BiometricLockService()
    private let notificationService = NotificationService()
    private let alertEvaluationService = AlertRuleEvaluationService()
    private let encryptedProfileSharingService = EncryptedProfileSharingService()
    private let sftpService = SFTPFileTransferService()
    private let backendMonitoringService = BackendMonitoringService()
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
    let isScreenshotMode: Bool
    let areUITestAnimationsDisabled: Bool
    @Published var packageStatuses: [PackageStatus]
    private var autoRefreshTask: Task<Void, Never>?
    private var profileCloudSyncTask: Task<Void, Never>?
    private var protectedBackgroundDate: Date?
    private var alertLastFiredAt: [String: Date] = [:]
    private var sftpLoadTokensByServer: [UUID: UUID] = [:]
    private let alertCooldown: TimeInterval = 15 * 60
    private static let backendMonitoringTokenAccount = "backend-monitoring-token"

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let environment = ProcessInfo.processInfo.environment
        self.isScreenshotMode = arguments.contains("-sysPulseScreenshotMode") || arguments.contains("UITEST_SCREENSHOTS")
        self.areUITestAnimationsDisabled = arguments.contains("DISABLE_ANIMATIONS") || environment["UITEST_DISABLE_ANIMATIONS"] == "1"
        self.serverProfiles = []
        self.metricsByServer = [:]
        self.quickCommands = QuickCommandCatalog.makeQuickCommands()
        self.terminalSessions = []
        self.settings = SettingsStorageService().loadSettings()
        self.subscription = SettingsStorageService().loadSubscription()
        self.packageStatuses = PackageDetector.defaultStatuses
        self.selectedServer = nil
        enforceSubscriptionBoundaries()
        if areUITestAnimationsDisabled {
            UIView.setAnimationsEnabled(false)
        }
        if isScreenshotMode {
            configureScreenshotDemo()
        } else {
            startStoreKit()
        }
    }

    private func startStoreKit() {
        storeKit.onSubscriptionChange = { [weak self] state in
            self?.subscription = state
        }
        Task {
            await storeKit.loadProducts()
            let state = await storeKit.verifyCurrentEntitlements()
            subscription = state
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
        if isScreenshotMode {
            configureScreenshotDemo()
            return
        }
        self.modelContext = modelContext
        guard profileRepository == nil else { return }
        profileRepository = SwiftDataProfileRepository(modelContext: modelContext)
        reloadProfilesFromRepository()
        reloadAlertRules()
        refreshAlertNotificationAuthorization()
        startAutoRefresh()
    }

    var isProUnlocked: Bool {
        if subscription.isPro { return true }
        #if DEBUG
        return settings.forceProOverride
        #else
        return isScreenshotMode && settings.forceProOverride
        #endif
    }

    var effectiveTerminalTheme: TerminalTheme {
        isProUnlocked || !settings.terminalTheme.isPremium ? settings.terminalTheme : .liquidDark
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

    var shouldReduceMotion: Bool {
        settings.reduceAnimations || areUITestAnimationsDisabled
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

    func sftpItems(for server: ServerProfile?) -> [SFTPRemoteItem] {
        guard let server else { return [] }
        return sftpItemsByServer[server.id] ?? []
    }

    func sftpPath(for server: ServerProfile?) -> String {
        guard let server else { return "." }
        return sftpPathByServer[server.id] ?? "."
    }

    func isSFTPLoading(for server: ServerProfile?) -> Bool {
        guard let server else { return false }
        return sftpLoadingServerIDs.contains(server.id)
    }

    func isRefreshingMetrics(for server: ServerProfile?) -> Bool {
        guard let server else { return false }
        return metricRefreshingServerIDs.contains(server.id)
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
        sftpItemsByServer.removeValue(forKey: serverID)
        sftpPathByServer.removeValue(forKey: serverID)
        sftpLoadingServerIDs.remove(serverID)
        sftpLoadTokensByServer.removeValue(forKey: serverID)
        metricRefreshingServerIDs.remove(serverID)
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
        metricRefreshingServerIDs.insert(server.id)
        Task {
            do {
                let previous = await MainActor.run {
                    metricsByServer[server.id]
                }
                let metrics = try await metricsCollector.collect(server: server, using: sshClient, previous: previous)
                await MainActor.run {
                    let visibleMetrics = isProUnlocked ? metrics : metricsWithoutPremiumSignals(metrics)
                    metricsByServer[server.id] = visibleMetrics
                    metricRefreshingServerIDs.remove(server.id)
                    if selectedServer?.id == server.id {
                        selectedServer?.status = .online
                    }
                    lastCommandOutput = localized("Metrics refreshed for %@.", server.name)
                    updateLiveActivity(message: localized("Metrics refreshed"))
                    evaluateAlertRules(for: server, metrics: visibleMetrics)
                    sendBackendMonitoringSnapshotIfEnabled(server: server, metrics: visibleMetrics)
                }
            } catch {
                await MainActor.run {
                    metricRefreshingServerIDs.remove(server.id)
                    if selectedServer?.id == server.id {
                        selectedServer?.status = .warning
                    }
                    lastCommandOutput = localized("Metrics refresh failed for %@: %@", server.name, error.localizedDescription)
                }
            }
        }
    }

    func backendMonitoringTokenForSettings() -> String {
        (try? KeychainService.shared.readSecret(account: Self.backendMonitoringTokenAccount)) ?? ""
    }

    func saveBackendMonitoringTokenFromSettings(_ token: String) {
        do {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedToken.isEmpty {
                try KeychainService.shared.deleteSecret(account: Self.backendMonitoringTokenAccount)
                lastCommandOutput = localized("Backend monitoring token cleared.")
            } else {
                try KeychainService.shared.saveSecret(trimmedToken, account: Self.backendMonitoringTokenAccount)
                lastCommandOutput = localized("Backend monitoring token saved.")
            }
        } catch {
            lastCommandOutput = error.localizedDescription
        }
    }

    private func sendBackendMonitoringSnapshotIfEnabled(server: ServerProfile, metrics: ServerMetrics) {
        guard settings.backendMonitoringEnabled else { return }
        let endpoint = settings.backendMonitoringEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return }
        let token = try? KeychainService.shared.readSecret(account: Self.backendMonitoringTokenAccount)
        let payload = BackendMonitoringPayload(server: server, metrics: metrics)
        let service = backendMonitoringService

        Task { [weak self] in
            do {
                try await service.sendSnapshot(endpoint: endpoint, token: token, payload: payload)
            } catch {
                await MainActor.run {
                    self?.lastCommandOutput = self?.localized("Backend monitoring failed: %@", error.localizedDescription) ?? error.localizedDescription
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
        guard requireProFeature() else { return }
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
        guard requireProFeature() else { return }
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
        guard requireProFeature() else { return }
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

    func makeEncryptedProfileExport(passphrase: String) -> URL? {
        do {
            let url = try encryptedProfileSharingService.makeExportFile(
                profiles: serverProfiles,
                passphrase: passphrase
            )
            lastCommandOutput = localized("Encrypted profile export is ready.")
            return url
        } catch {
            lastCommandOutput = error.localizedDescription
            return nil
        }
    }

    func importEncryptedProfiles(from url: URL, passphrase: String) {
        guard let profileRepository else {
            lastCommandOutput = localized("Profile database is not ready yet.")
            return
        }

        do {
            let importedProfiles = try encryptedProfileSharingService.importProfiles(from: url, passphrase: passphrase)
            let existingIDs = Set(serverProfiles.map(\.id))
            let newProfileCount = importedProfiles.filter { !existingIDs.contains($0.id) }.count
            if !isProUnlocked && serverProfiles.count + newProfileCount > 1 {
                isPaywallPresented = true
                lastCommandOutput = localized("Encrypted import needs Pro for multiple servers.")
                return
            }

            for profile in importedProfiles {
                if let existing = serverProfiles.first(where: { $0.id == profile.id }) {
                    profile.credentialIdentifier = existing.credentialIdentifier
                }
                try profileRepository.saveProfile(profile)
            }
            reloadProfilesFromRepository()
            uploadProfilesToICloudIfEnabled()
            lastCommandOutput = localized("Imported %d encrypted profiles.", importedProfiles.count)
        } catch {
            lastCommandOutput = error.localizedDescription
        }
    }

    func refreshSFTPDirectory(for server: ServerProfile? = nil, path: String? = nil) {
        guard let targetServer = server ?? selectedServer else {
            lastCommandOutput = localized("Select a server before running commands.")
            return
        }

        let targetPath = path ?? sftpPath(for: targetServer)
        lastCommandOutput = localized("Loading SFTP directory %@...", targetPath)
        if path != nil {
            sftpPathByServer[targetServer.id] = targetPath
            sftpItemsByServer[targetServer.id] = []
        }
        let loadToken = UUID()
        sftpLoadTokensByServer[targetServer.id] = loadToken
        sftpLoadingServerIDs.insert(targetServer.id)
        Task {
            do {
                let listing = try await sftpService.listDirectory(at: targetPath, server: targetServer, via: sshClient)
                await MainActor.run {
                    guard sftpLoadTokensByServer[targetServer.id] == loadToken else { return }
                    sftpPathByServer[targetServer.id] = listing.path
                    sftpItemsByServer[targetServer.id] = listing.items
                    sftpLoadTokensByServer.removeValue(forKey: targetServer.id)
                    sftpLoadingServerIDs.remove(targetServer.id)
                    lastCommandOutput = localized("Loaded %d SFTP items from %@.", listing.items.count, listing.path)
                }
            } catch {
                await MainActor.run {
                    guard sftpLoadTokensByServer[targetServer.id] == loadToken else { return }
                    sftpLoadTokensByServer.removeValue(forKey: targetServer.id)
                    sftpLoadingServerIDs.remove(targetServer.id)
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func openSFTPParent(for server: ServerProfile) {
        refreshSFTPDirectory(for: server, path: sftpService.parentPath(of: sftpPath(for: server)))
    }

    func uploadSFTPFile(from url: URL, to server: ServerProfile) {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            lastCommandOutput = error.localizedDescription
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            return
        }
        if didStartAccess { url.stopAccessingSecurityScopedResource() }

        let fileName = url.lastPathComponent
        let directory = sftpPath(for: server)
        lastCommandOutput = localized("Uploading %@ via SFTP...", fileName)
        Task {
            do {
                try await sftpService.upload(data, named: fileName, to: directory, server: server, via: sshClient)
                await MainActor.run {
                    lastCommandOutput = localized("Uploaded %@ via SFTP.", fileName)
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func downloadSFTPFile(_ item: SFTPRemoteItem, from server: ServerProfile) async -> URL? {
        lastCommandOutput = localized("Downloading %@ via SFTP...", item.name)
        do {
            let data = try await sftpService.download(item, server: server, via: sshClient)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try data.write(to: url, options: .atomic)
            lastCommandOutput = localized("Downloaded %@ via SFTP.", item.name)
            return url
        } catch {
            lastCommandOutput = error.localizedDescription
            return nil
        }
    }

    func deleteSFTPItem(_ item: SFTPRemoteItem, from server: ServerProfile) {
        lastCommandOutput = localized("Deleting %@ via SFTP...", item.name)
        Task {
            do {
                try await sftpService.delete(item, server: server, via: sshClient)
                await MainActor.run {
                    lastCommandOutput = localized("Deleted %@ via SFTP.", item.name)
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                }
            }
        }
    }

    func deleteSFTPItems(_ items: [SFTPRemoteItem], from server: ServerProfile) {
        guard !items.isEmpty else { return }
        lastCommandOutput = localized("Deleting %d SFTP items...", items.count)
        Task {
            do {
                for item in items {
                    try await sftpService.delete(item, server: server, via: sshClient)
                }
                await MainActor.run {
                    lastCommandOutput = localized("Deleted %d SFTP items.", items.count)
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    lastCommandOutput = error.localizedDescription
                    refreshSFTPDirectory(for: server)
                }
            }
        }
    }

    func requestAlertNotifications() async {
        let granted = await notificationService.requestPermission()
        areNotificationsAuthorized = granted
        lastCommandOutput = granted
            ? localized("Notifications enabled for metric alerts.")
            : localized("Notifications are disabled in iOS Settings.")
    }

    func refreshAlertNotificationAuthorization() {
        Task {
            areNotificationsAuthorized = await notificationService.isAuthorized()
        }
    }

    func setAlertRule(_ rule: AlertRule, isEnabled: Bool) {
        rule.isEnabled = isEnabled
        saveAlertRules()
        objectWillChange.send()
    }

    private func reloadAlertRules() {
        guard let modelContext else { return }
        do {
            let descriptor = FetchDescriptor<AlertRule>(
                sortBy: [SortDescriptor(\.title, order: .forward)]
            )
            var rules = try modelContext.fetch(descriptor)
            if rules.isEmpty {
                rules = AlertRule.defaultRules()
                for rule in rules {
                    modelContext.insert(rule)
                }
                try modelContext.save()
            }
            alertRules = rules
        } catch {
            lastCommandOutput = localized("Failed to load alert rules: %@", error.localizedDescription)
        }
    }

    private func saveAlertRules() {
        do {
            try modelContext?.save()
        } catch {
            lastCommandOutput = localized("Failed to save alert rules: %@", error.localizedDescription)
        }
    }

    private func evaluateAlertRules(for server: ServerProfile, metrics: ServerMetrics) {
        guard areNotificationsAuthorized else { return }
        let evaluations = alertEvaluationService.evaluations(for: alertRules, server: server, metrics: metrics)
        guard !evaluations.isEmpty else { return }

        let now = Date()
        for evaluation in evaluations {
            let cooldownKey = evaluation.id
            if let lastFiredAt = alertLastFiredAt[cooldownKey],
               now.timeIntervalSince(lastFiredAt) < alertCooldown {
                continue
            }

            alertLastFiredAt[cooldownKey] = now
            let title = localized(evaluation.rule.title)
            let body = localized(evaluation.metric.notificationBodyKey, evaluation.value, server.name)
            Task {
                try? await notificationService.scheduleAlert(
                    title: title,
                    body: body,
                    identifier: "syspulse.\(cooldownKey)"
                )
            }
        }
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
        if isProUnlocked {
            widgetDataService.save(profiles: serverProfiles, metricsByServer: metricsByServer)
        } else {
            widgetDataService.saveLocked()
        }
    }

    private func requireProFeature(message: String = "Unlock Pro to use this feature.") -> Bool {
        guard isProUnlocked else {
            lastCommandOutput = localized(message)
            isPaywallPresented = true
            return false
        }
        return true
    }

    private func enforceSubscriptionBoundaries() {
        guard !subscription.isPro else {
            publishWidgetSnapshots()
            return
        }
        if settings.terminalTheme.isPremium {
            settings.terminalTheme = .liquidDark
        }
        if settings.iCloudSyncEnabled {
            settings.iCloudSyncEnabled = false
        }
        metricsByServer = metricsByServer.mapValues(metricsWithoutPremiumSignals)
        dockerContainersByServer = [:]
        systemdServicesByServer = [:]
        logEntriesByServer = [:]
        if !isScreenshotMode {
            settings.forceProOverride = false
        }
        publishWidgetSnapshots()
    }

    private func metricsWithoutPremiumSignals(_ metrics: ServerMetrics) -> ServerMetrics {
        var sanitized = metrics
        sanitized.failedServices = 0
        sanitized.dockerRunning = 0
        sanitized.dockerTotal = 0
        sanitized.healthScore = healthScoreService.score(for: sanitized)
        return sanitized
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

        let localSnapshots = serverProfiles.map(CloudServerProfileSnapshot.init)
        let previousSyncTask = profileCloudSyncTask
        previousSyncTask?.cancel()
        profileCloudSyncTask = Task {
            do {
                if let previousSyncTask {
                    _ = await previousSyncTask.result
                }
                try Task.checkCancellation()

                let profileCloudSyncService = try ProfileCloudSyncService()
                if mergeRemote {
                    let syncedSnapshots = try await profileCloudSyncService.mergeAndUpload(localSnapshots: localSnapshots)
                    try Task.checkCancellation()
                    guard settings.iCloudSyncEnabled else { return }
                    for snapshot in syncedSnapshots {
                        try profileRepository.saveProfile(snapshot.makeServerProfile())
                    }
                    reloadProfilesFromRepository()
                    lastCommandOutput = localized("iCloud profile sync completed.")
                } else {
                    try await profileCloudSyncService.uploadSnapshot(localSnapshots)
                    try Task.checkCancellation()
                    guard settings.iCloudSyncEnabled else { return }
                    lastCommandOutput = localized("iCloud profile snapshot updated.")
                }
            } catch is CancellationError {
                return
            } catch let error as ProfileCloudSyncError {
                if error.shouldDisableSync {
                    settings.iCloudSyncEnabled = false
                }
                lastCommandOutput = localized("iCloud sync failed: %@", error.localizedDescription)
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
        guard !shouldReduceMotion else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}
