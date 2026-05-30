import Foundation
import StoreKit
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @AppStorage("metricAlertsSilencedUntil") var metricAlertsSilencedUntil: Double = 0
    @Published var paywallFeatureTitle: String?
    @Published var paywallFeatureMessage: String?
    @Published var shouldOpenSelectedServerMonitor = false
    @Published var selectedTab: AppTab = .servers
    @Published var selectedServer: ServerProfile?
    @Published var serverProfiles: [ServerProfile] {
        didSet {
            scheduleWidgetSnapshotPublish()
            configureSSHProfileLookup()
        }
    }
    @Published var metricsByServer: [UUID: ServerMetrics] {
        didSet {
            scheduleWidgetSnapshotPublish()
        }
    }
    @Published var quickCommands: [QuickCommand]
    @Published var terminalSessions: [TerminalSession]
    @Published var settings: AppSettings {
        didSet {
            settingsStorage.saveSettings(settings)
            if oldValue.metricsAutoRefreshEnabled != settings.metricsAutoRefreshEnabled ||
                oldValue.metricsAutoRefreshIntervalSeconds != settings.metricsAutoRefreshIntervalSeconds {
                restartAutoRefreshIfNeeded()
            }
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
    @Published var remoteCommandOutput = ""
    @Published var statusToast: StatusToast?
    @Published var processItemsByServer: [UUID: [ProcessInfoItem]] = [:]
    @Published var diskInfoByServer: [UUID: [DiskInfo]] = [:]
    @Published var dockerContainersByServer: [UUID: [DockerContainer]] = [:]
    @Published var systemdServicesByServer: [UUID: [SystemdServiceItem]] = [:]
    @Published var logEntriesByServer: [UUID: [LogEntry]] = [:]
    @Published var sftpItemsByServer: [UUID: [SFTPRemoteItem]] = [:]
    @Published var sftpPathByServer: [UUID: String] = [:]
    @Published var sftpLoadingServerIDs: Set<UUID> = []
    @Published var sftpErrorByServer: [UUID: String] = [:]
    @Published var sftpOperationsByServer: [UUID: [SFTPOperation]] = [:]
    @Published var metricRefreshingServerIDs: Set<UUID> = []
    @Published var metricErrorByServer: [UUID: String] = [:]
    @Published var alertRules: [AlertRule] = []
    @Published var areNotificationsAuthorized = false
    @Published var profileCloudSyncActivity: CloudProfileSyncActivity = .idle

    var modelContext: ModelContext?
    private var profileRepository: ProfileRepository?
    private let settingsStorage = SettingsStorageService()
    private let widgetDataService = WidgetDataService()
    private let liveActivityService = LiveActivityService()
    private let biometricLockService = BiometricLockService()
    let notificationService = NotificationService()
    let alertEvaluationService = AlertRuleEvaluationService()
    private let encryptedProfileSharingService = EncryptedProfileSharingService()
    private let sftpService = SFTPFileTransferService()
    private let backendMonitoringService = BackendMonitoringService()
    private let metricsCollector = MetricsCollector()
    private let metricsHistoryService = MetricsHistoryService()
    private let serverEventService = ServerEventService()
    private let processService = ProcessService()
    private let diskService = DiskService()
    private let dockerService = DockerService()
    private let systemdService = SystemdService()
    private let logsService = LogsService()
    let healthScoreService = HealthScoreService()
    let insightsService = InsightsService()
    let packageDetector = PackageDetector()
    private var realSSHClient = RealSSHClient()
    var sshClient: SSHClientProtocol { realSSHClient }
    let storeKit = StoreKitService()
    let isScreenshotMode: Bool
    let areUITestAnimationsDisabled: Bool
    @Published var packageStatuses: [PackageStatus]
    private var autoRefreshTask: Task<Void, Never>?
    private var profileCloudSyncTask: Task<Void, Never>?
    private var protectedBackgroundDate: Date?
    var alertLastFiredAt: [String: Date] = [:]
    private var sftpLoadTokensByServer: [UUID: UUID] = [:]
    var statusToastDismissTask: Task<Void, Never>?
    var widgetPublishTask: Task<Void, Never>?
    let alertCooldown: TimeInterval = 15 * 60
    private static let backendMonitoringTokenAccount = "backend-monitoring-token"
    private static let metricsRefreshConcurrency = 2
    private static let backgroundServerRefreshIntervalSeconds: UInt64 = 120

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
        configureSSHProfileLookup()
        restartAutoRefreshIfNeeded()
        loadPersistedMetricsHistory()
        runDueScheduledCommands()
    }

    func serverEvents(for server: ServerProfile?) -> [ServerEvent] {
        guard let server, let modelContext else { return [] }
        return (try? serverEventService.recentEvents(for: server.id, in: modelContext)) ?? []
    }

    func loadPersistedMetricsHistory() {
        guard isProUnlocked, let modelContext else { return }
        for server in serverProfiles {
            guard var metrics = metricsByServer[server.id] else { continue }
            try? metricsHistoryService.applyHistory(to: &metrics, in: modelContext)
            metricsByServer[server.id] = metrics
        }
    }

    private func recordMetricSnapshot(_ metrics: ServerMetrics) {
        guard isProUnlocked, let modelContext else { return }
        try? metricsHistoryService.record(metrics, in: modelContext)
    }

    func recordServerEvent(
        server: ServerProfile,
        title: String,
        details: String,
        severity: String = "Moderate"
    ) {
        guard let modelContext else { return }
        try? serverEventService.record(
            serverID: server.id,
            title: title,
            details: details,
            severity: severity,
            in: modelContext
        )
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
        settings.reduceAnimations || areUITestAnimationsDisabled || UIAccessibility.isReduceMotionEnabled
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        L10n.string(key, language: settings.language, arguments: arguments)
    }

    func connectionErrorMessage(_ error: Error, server: ServerProfile? = nil) -> String {
        let rawMessage = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if error is SSHClientError || error is SFTPFileTransferError {
            return rawMessage.isEmpty ? localized("Connection failed. Check the server and try again.") : rawMessage
        }

        let message = rawMessage.isEmpty ? String(describing: error) : rawMessage
        let lowercased = message.lowercased()
        let serverName = server?.name ?? localized("the server")

        if lowercased.contains("not connected to the internet") ||
            lowercased.contains("network is unreachable") ||
            lowercased.contains("offline") ||
            lowercased.contains("internet connection appears") {
            return localized("Network appears offline. Check Wi-Fi, mobile data or VPN and try again.")
        }
        if lowercased.contains("timed out") || lowercased.contains("timeout") {
            return localized("Connection to %@ timed out. Check the host, port, firewall or VPN.", serverName)
        }
        if lowercased.contains("connection refused") || lowercased.contains("refused") {
            return localized("%@ refused the connection. Check that SSH is running and the port is correct.", serverName)
        }
        if lowercased.contains("permission denied") ||
            lowercased.contains("authentication") ||
            lowercased.contains("auth failed") {
            return localized("SSH authentication failed for %@. Check username and saved credentials.", serverName)
        }
        if lowercased.contains("could not resolve") ||
            lowercased.contains("dns") ||
            lowercased.contains("name or service not known") {
            return localized("Could not resolve %@. Check the host name or DNS.", serverName)
        }
        if lowercased.contains("no route to host") ||
            lowercased.contains("host is down") ||
            lowercased.contains("host unreachable") {
            return localized("Cannot reach %@. Check the network, host and VPN.", serverName)
        }

        if server != nil {
            return localized("Connection failed for %@: %@", serverName, message)
        }
        return localized("Connection failed: %@", message)
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
            runDueScheduledCommands()
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
            postStatus(localized("Face ID lock enabled."))
        case .unavailable(let message), .failed(let message):
            isSecurityUnlocked = true
            isPrivacyShieldVisible = false
            securityLockMessage = message
            postStatus(localized("Face ID lock was not enabled: %@", message))
        }
    }

    func disableBiometricLock() {
        settings.requiresBiometrics = false
        isSecurityUnlocked = true
        isPrivacyShieldVisible = false
        securityLockMessage = ""
        postStatus(localized("Face ID lock disabled."))
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
            postStatus(localized("Face ID lock is unavailable and was turned off: %@", message))
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

    func sftpError(for server: ServerProfile?) -> String? {
        guard let server else { return nil }
        return sftpErrorByServer[server.id]
    }

    func sftpOperations(for server: ServerProfile?) -> [SFTPOperation] {
        guard let server else { return [] }
        return sftpOperationsByServer[server.id] ?? []
    }

    func clearFinishedSFTPOperations(for server: ServerProfile?) {
        guard let server else { return }
        sftpOperationsByServer[server.id] = sftpOperations(for: server).filter { $0.status == .running }
    }

    func dismissSFTPOperation(_ operation: SFTPOperation) {
        var operations = sftpOperationsByServer[operation.serverID] ?? []
        operations.removeAll { $0.id == operation.id }
        sftpOperationsByServer[operation.serverID] = operations
    }

    func isRefreshingMetrics(for server: ServerProfile?) -> Bool {
        guard let server else { return false }
        return metricRefreshingServerIDs.contains(server.id)
    }

    func metricError(for server: ServerProfile?) -> String? {
        guard let server else { return nil }
        return metricErrorByServer[server.id]
    }

    @discardableResult
    func addServer(_ server: ServerProfile) -> Bool {
        if !isProUnlocked && serverProfiles.count >= 1 {
            presentPaywall(feature: "Unlimited servers", message: localized("Free plan includes one server. Upgrade to add more."))
            return false
        }

        guard let profileRepository else {
            postStatus(localized("Profile database is not ready yet."))
            return false
        }

        do {
            try profileRepository.saveProfile(server)
        } catch {
            postStatus(localized("Failed to save profile: %@", error.localizedDescription))
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
            postStatus(localized("Profile database is not ready yet."))
            return
        }

        server.updatedAt = .now
        do {
            try profileRepository.saveProfile(server)
        } catch {
            postStatus(localized("Failed to save profile: %@", error.localizedDescription))
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
            postStatus(localized("Profile database is not ready yet."))
            return
        }

        let serverID = server.id
        let credentialIdentifier = server.credentialIdentifier
        do {
            try profileRepository.deleteProfile(server)
        } catch {
            postStatus(localized("Failed to delete profile: %@", error.localizedDescription))
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
        sftpErrorByServer.removeValue(forKey: serverID)
        sftpOperationsByServer.removeValue(forKey: serverID)
        sftpLoadTokensByServer.removeValue(forKey: serverID)
        metricRefreshingServerIDs.remove(serverID)
        metricErrorByServer.removeValue(forKey: serverID)
        terminalSessions.removeAll { $0.serverID == serverID }
        if let credentialIdentifier {
            try? KeychainService.shared.deleteSecret(account: credentialIdentifier)
        }
        Task { await sshClient.disconnect(from: server) }
        if selectedServer?.id == serverID {
            selectedServer = serverProfiles.first
        }
        uploadProfilesToICloudIfEnabled()
        haptic(.rigid)
    }

    func select(_ server: ServerProfile, tab: AppTab = .servers) {
        selectedServer = server
        selectedTab = tab
        haptic(.light)
    }

    func testConnection(to server: ServerProfile) async throws -> String {
        try await sshClient.connect(to: server)
        return try await sshClient.run("uname -a", on: server)
    }

    func refreshAllServers() {
        Task {
            await refreshMetricsBatch(serverProfiles, announceStatus: true)
        }
    }

    func restartAutoRefreshIfNeeded() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        guard isProUnlocked, settings.metricsAutoRefreshEnabled else { return }
        startAutoRefresh()
    }

    private func startAutoRefresh() {
        guard isProUnlocked, settings.metricsAutoRefreshEnabled else { return }
        autoRefreshTask?.cancel()
        let interval = UInt64(max(settings.metricsAutoRefreshIntervalSeconds, 30))
        autoRefreshTask = Task {
            await performScheduledMetricsRefresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await performScheduledMetricsRefresh()
            }
        }
    }

    private func performScheduledMetricsRefresh() async {
        guard isProUnlocked, settings.metricsAutoRefreshEnabled else { return }
        let profiles = serverProfiles
        guard !profiles.isEmpty else { return }

        if let selected = selectedServer {
            await refreshMetricsAsync(for: selected, announceStatus: false)
        }

        let others = profiles.filter { $0.id != selectedServer?.id }
        guard !others.isEmpty else { return }

        for server in others {
            let lastRefresh = metricsByServer[server.id]?.timestamp
            if let lastRefresh,
               Date.now.timeIntervalSince(lastRefresh) < TimeInterval(Self.backgroundServerRefreshIntervalSeconds) {
                continue
            }
            await refreshMetricsAsync(for: server, announceStatus: false)
        }
    }

    private func refreshMetricsBatch(_ servers: [ServerProfile], announceStatus: Bool) async {
        guard !servers.isEmpty else { return }

        var iterator = servers.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(Self.metricsRefreshConcurrency, servers.count) {
                guard let server = iterator.next() else { break }
                group.addTask {
                    await self.refreshMetricsAsync(for: server, announceStatus: announceStatus)
                }
            }

            while let server = iterator.next() {
                await group.next()
                group.addTask {
                    await self.refreshMetricsAsync(for: server, announceStatus: announceStatus)
                }
            }
        }
    }

    func refreshMetrics(for server: ServerProfile, announceStatus: Bool = false) {
        Task {
            await refreshMetricsAsync(for: server, announceStatus: announceStatus)
        }
    }

    private func refreshMetricsAsync(for server: ServerProfile, announceStatus: Bool) async {
        await MainActor.run {
            metricRefreshingServerIDs.insert(server.id)
            metricErrorByServer.removeValue(forKey: server.id)
            if announceStatus {
                postStatus(localized("Refreshing metrics for %@...", server.name))
            }
        }

        do {
            let previous = await MainActor.run {
                metricsByServer[server.id]
            }
            let metrics = try await metricsCollector.collect(server: server, using: sshClient, previous: previous)
            await MainActor.run {
                var visibleMetrics = isProUnlocked ? metrics : metricsWithoutPremiumSignals(metrics)
                recordMetricSnapshot(visibleMetrics)
                if isProUnlocked, let modelContext {
                    try? metricsHistoryService.applyHistory(to: &visibleMetrics, in: modelContext)
                }
                metricsByServer[server.id] = visibleMetrics
                metricRefreshingServerIDs.remove(server.id)
                metricErrorByServer.removeValue(forKey: server.id)
                if selectedServer?.id == server.id {
                    selectedServer?.status = .online
                }
                if announceStatus {
                    postStatus(localized("Metrics refreshed for %@.", server.name), style: .success)
                }
                updateLiveActivity(message: localized("Metrics refreshed"))
                evaluateAlertRules(for: server, metrics: visibleMetrics)
                sendBackendMonitoringSnapshotIfEnabled(server: server, metrics: visibleMetrics)
            }
        } catch {
            let recovered = await retryMetricsOnce(for: server, previous: await MainActor.run { metricsByServer[server.id] })
            if recovered != nil {
                await MainActor.run {
                    var visibleMetrics = isProUnlocked ? recovered! : metricsWithoutPremiumSignals(recovered!)
                    recordMetricSnapshot(visibleMetrics)
                    if isProUnlocked, let modelContext {
                        try? metricsHistoryService.applyHistory(to: &visibleMetrics, in: modelContext)
                    }
                    metricsByServer[server.id] = visibleMetrics
                    metricRefreshingServerIDs.remove(server.id)
                    metricErrorByServer.removeValue(forKey: server.id)
                    if selectedServer?.id == server.id {
                        selectedServer?.status = .online
                    }
                    if announceStatus {
                        postStatus(localized("Metrics refreshed for %@.", server.name), style: .success)
                    }
                    evaluateAlertRules(for: server, metrics: visibleMetrics)
                    sendBackendMonitoringSnapshotIfEnabled(server: server, metrics: visibleMetrics)
                }
                return
            }

            await MainActor.run {
                let message = connectionErrorMessage(error, server: server)
                metricRefreshingServerIDs.remove(server.id)
                metricErrorByServer[server.id] = message
                if selectedServer?.id == server.id {
                    selectedServer?.status = .warning
                }
                recordServerEvent(
                    server: server,
                    title: localized("Metrics refresh failed"),
                    details: message,
                    severity: "Dangerous"
                )
                postStatus(localized("Metrics refresh failed for %@: %@", server.name, message), style: .error)
            }
        }
    }

    private func retryMetricsOnce(for server: ServerProfile, previous: ServerMetrics?) async -> ServerMetrics? {
        await MainActor.run {
            postStatus(localized("Reconnecting to %@...", server.name), style: .info)
        }
        try? await Task.sleep(for: .seconds(2))
        return try? await metricsCollector.collect(server: server, using: sshClient, previous: previous)
    }

    func backendMonitoringTokenForSettings() -> String {
        (try? KeychainService.shared.readSecret(account: Self.backendMonitoringTokenAccount)) ?? ""
    }

    func saveBackendMonitoringTokenFromSettings(_ token: String) {
        do {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedToken.isEmpty {
                try KeychainService.shared.deleteSecret(account: Self.backendMonitoringTokenAccount)
                postStatus(localized("Backend monitoring token cleared."))
            } else {
                try KeychainService.shared.saveSecret(trimmedToken, account: Self.backendMonitoringTokenAccount)
                postStatus(localized("Backend monitoring token saved."))
            }
        } catch {
            postStatus(error.localizedDescription, style: .error)
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
                    guard let self else { return }
                    self.postStatus(self.localized("Backend monitoring failed: %@", self.connectionErrorMessage(error)), style: .error)
                }
            }
        }
    }

    func runRemoteCommand(_ command: String, on server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        postStatus(localized("Running command on %@...", targetServer.name))
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                await MainActor.run {
                    setRemoteCommandOutput(output.isEmpty ? localized("Command completed with no output.") : output)
                }
            } catch {
                await MainActor.run {
                    setRemoteCommandOutput(connectionErrorMessage(error, server: targetServer))
                }
            }
        }
    }

    func refreshProcesses(for server: ServerProfile? = nil, sortedByMemory: Bool = false) {
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        let command = sortedByMemory ? processService.topMemoryCommand() : processService.topCPUCommand()
        postStatus(localized("Loading processes from %@...", targetServer.name))
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let processes = processService.parseProcesses(output)
                await MainActor.run {
                    processItemsByServer[targetServer.id] = processes
                    setRemoteCommandOutput(output.isEmpty ? localized("Command completed with no output.") : output)
                }
            } catch {
                await MainActor.run {
                    setRemoteCommandOutput(connectionErrorMessage(error, server: targetServer))
                }
            }
        }
    }

    func refreshDisks(for server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        let command = diskService.usageCommand()
        postStatus(localized("Loading disks from %@...", targetServer.name))
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let disks = diskService.parseDisks(output)
                await MainActor.run {
                    diskInfoByServer[targetServer.id] = disks
                    setRemoteCommandOutput(output.isEmpty ? localized("Command completed with no output.") : output)
                }
            } catch {
                await MainActor.run {
                    setRemoteCommandOutput(connectionErrorMessage(error, server: targetServer))
                }
            }
        }
    }

    func refreshDockerContainers(for server: ServerProfile? = nil) {
        guard requireProFeature(feature: "Docker monitoring") else { return }
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        let command = dockerService.inventoryCommand()
        postStatus(localized("Loading Docker containers from %@...", targetServer.name))
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let containers = dockerService.parseContainers(output)
                await MainActor.run {
                    dockerContainersByServer[targetServer.id] = containers
                    setRemoteCommandOutput(output.isEmpty ? localized("Command completed with no output.") : output)
                }
            } catch {
                await MainActor.run {
                    setRemoteCommandOutput(connectionErrorMessage(error, server: targetServer))
                }
            }
        }
    }

    func refreshSystemdServices(for server: ServerProfile? = nil) {
        guard requireProFeature(feature: "systemd monitoring") else { return }
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        let command = systemdService.unitsCommand()
        postStatus(localized("Loading systemd services from %@...", targetServer.name))
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let services = systemdService.parseServices(output)
                await MainActor.run {
                    systemdServicesByServer[targetServer.id] = services
                    setRemoteCommandOutput(output.isEmpty ? localized("Command completed with no output.") : output)
                }
            } catch {
                await MainActor.run {
                    setRemoteCommandOutput(connectionErrorMessage(error, server: targetServer))
                }
            }
        }
    }

    func refreshLogEntries(for server: ServerProfile? = nil) {
        guard requireProFeature(feature: "Logs viewer") else { return }
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        let command = logsService.structuredJournalCommand()
        postStatus(localized("Loading logs from %@...", targetServer.name))
        Task {
            do {
                let output = try await sshClient.run(command, on: targetServer)
                let logs = logsService.parseLogEntries(output)
                await MainActor.run {
                    logEntriesByServer[targetServer.id] = logs
                    setRemoteCommandOutput(output.isEmpty ? localized("Command completed with no output.") : output)
                }
            } catch {
                await MainActor.run {
                    setRemoteCommandOutput(connectionErrorMessage(error, server: targetServer))
                }
            }
        }
    }

    func refreshPackageStatuses(for server: ServerProfile? = nil) {
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before checking packages."))
            return
        }

        postStatus(localized("Checking packages on %@...", targetServer.name))
        Task {
            do {
                let output = try await sshClient.run(packageDetector.detectionCommand(), on: targetServer)
                let statuses = packageDetector.parseStatuses(output)
                await MainActor.run {
                    packageStatuses = statuses
                    setRemoteCommandOutput(output)
                }
            } catch {
                await MainActor.run {
                    setRemoteCommandOutput(connectionErrorMessage(error, server: targetServer))
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
            postStatus(localized("Encrypted profile export is ready."))
            return url
        } catch {
            postStatus(error.localizedDescription, style: .error)
            return nil
        }
    }

    func importEncryptedProfiles(from url: URL, passphrase: String) {
        guard let profileRepository else {
            postStatus(localized("Profile database is not ready yet."))
            return
        }

        do {
            let importedProfiles = try encryptedProfileSharingService.importProfiles(from: url, passphrase: passphrase)
            let existingIDs = Set(serverProfiles.map(\.id))
            let newProfileCount = importedProfiles.filter { !existingIDs.contains($0.id) }.count
            if !isProUnlocked && serverProfiles.count + newProfileCount > 1 {
                isPaywallPresented = true
                postStatus(localized("Encrypted import needs Pro for multiple servers."))
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
            postStatus(localized("Imported %d encrypted profiles.", importedProfiles.count))
        } catch {
            postStatus(error.localizedDescription, style: .error)
        }
    }

    @discardableResult
    private func beginSFTPOperation(
        kind: SFTPOperationKind,
        fileName: String,
        server: ServerProfile,
        remotePath: String
    ) -> UUID {
        let operation = SFTPOperation(
            serverID: server.id,
            kind: kind,
            fileName: fileName,
            remotePath: remotePath,
            status: .running,
            message: localized("Waiting for server...")
        )
        var operations = sftpOperationsByServer[server.id] ?? []
        operations.insert(operation, at: 0)
        sftpOperationsByServer[server.id] = Array(operations.prefix(8))
        return operation.id
    }

    private func finishSFTPOperation(
        _ operationID: UUID,
        serverID: UUID,
        status: SFTPOperationStatus,
        message: String
    ) {
        guard var operations = sftpOperationsByServer[serverID],
              let index = operations.firstIndex(where: { $0.id == operationID }) else {
            return
        }
        operations[index].status = status
        operations[index].message = message
        operations[index].completedAt = status == .running ? nil : .now
        sftpOperationsByServer[serverID] = Array(operations.prefix(8))
    }

    func refreshSFTPDirectory(for server: ServerProfile? = nil, path: String? = nil) {
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        let targetPath = path ?? sftpPath(for: targetServer)
        postStatus(localized("Loading SFTP directory %@...", targetPath))
        sftpErrorByServer.removeValue(forKey: targetServer.id)
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
                    sftpErrorByServer.removeValue(forKey: targetServer.id)
                    postStatus(localized("Loaded %d SFTP items from %@.", listing.items.count, listing.path))
                }
            } catch {
                await MainActor.run {
                    guard sftpLoadTokensByServer[targetServer.id] == loadToken else { return }
                    let message = connectionErrorMessage(error, server: targetServer)
                    sftpLoadTokensByServer.removeValue(forKey: targetServer.id)
                    sftpLoadingServerIDs.remove(targetServer.id)
                    sftpErrorByServer[targetServer.id] = message
                    postStatus(localized("SFTP failed for %@: %@", targetServer.name, message))
                }
            }
        }
    }

    func openSFTPParent(for server: ServerProfile) {
        refreshSFTPDirectory(for: server, path: sftpService.parentPath(of: sftpPath(for: server)))
    }

    func uploadSFTPFile(from url: URL, to server: ServerProfile) {
        let fileName = url.lastPathComponent
        let directory = sftpPath(for: server)
        let operationID = beginSFTPOperation(kind: .upload, fileName: fileName, server: server, remotePath: directory)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let message = localized("Could not read the local file: %@", error.localizedDescription)
            finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
            postStatus(message, style: .error)
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            return
        }
        if didStartAccess { url.stopAccessingSecurityScopedResource() }

        postStatus(localized("Uploading %@ via SFTP...", fileName))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Uploading to %@...", directory))
        sftpErrorByServer.removeValue(forKey: server.id)
        Task {
            do {
                try await sftpService.upload(data, named: fileName, to: directory, server: server, via: sshClient)
                await MainActor.run {
                    sftpErrorByServer.removeValue(forKey: server.id)
                    finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Uploaded %@.", fileName))
                    postStatus(localized("Uploaded %@ via SFTP.", fileName))
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    let message = connectionErrorMessage(error, server: server)
                    sftpErrorByServer[server.id] = message
                    finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
                    postStatus(localized("SFTP failed for %@: %@", server.name, message))
                }
            }
        }
    }

    func downloadSFTPFile(_ item: SFTPRemoteItem, from server: ServerProfile) async -> URL? {
        let operationID = beginSFTPOperation(kind: .download, fileName: item.name, server: server, remotePath: item.path)
        postStatus(localized("Downloading %@ via SFTP...", item.name))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Downloading from %@...", item.path))
        sftpErrorByServer.removeValue(forKey: server.id)
        do {
            let data = try await sftpService.download(item, server: server, via: sshClient)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try data.write(to: url, options: .atomic)
            sftpErrorByServer.removeValue(forKey: server.id)
            finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Download ready."))
            postStatus(localized("Downloaded %@ via SFTP.", item.name))
            return url
        } catch {
            let message = connectionErrorMessage(error, server: server)
            sftpErrorByServer[server.id] = message
            finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
            postStatus(localized("SFTP failed for %@: %@", server.name, message))
            return nil
        }
    }

    func deleteSFTPItem(_ item: SFTPRemoteItem, from server: ServerProfile) {
        let operationID = beginSFTPOperation(kind: .delete, fileName: item.name, server: server, remotePath: item.path)
        postStatus(localized("Deleting %@ via SFTP...", item.name))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Deleting from %@...", item.path))
        sftpErrorByServer.removeValue(forKey: server.id)
        Task {
            do {
                try await sftpService.delete(item, server: server, via: sshClient)
                await MainActor.run {
                    sftpErrorByServer.removeValue(forKey: server.id)
                    finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Deleted %@.", item.name))
                    postStatus(localized("Deleted %@ via SFTP.", item.name))
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    let message = connectionErrorMessage(error, server: server)
                    sftpErrorByServer[server.id] = message
                    finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
                    postStatus(localized("SFTP failed for %@: %@", server.name, message))
                }
            }
        }
    }

    func deleteSFTPItems(_ items: [SFTPRemoteItem], from server: ServerProfile) {
        guard !items.isEmpty else { return }
        let operationTitle = localized("%d items", items.count)
        let operationID = beginSFTPOperation(kind: .delete, fileName: operationTitle, server: server, remotePath: sftpPath(for: server))
        postStatus(localized("Deleting %d SFTP items...", items.count))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Deleting %d items...", items.count))
        sftpErrorByServer.removeValue(forKey: server.id)
        Task {
            do {
                for item in items {
                    try await sftpService.delete(item, server: server, via: sshClient)
                }
                await MainActor.run {
                    sftpErrorByServer.removeValue(forKey: server.id)
                    finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Deleted %d items.", items.count))
                    postStatus(localized("Deleted %d SFTP items.", items.count))
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    let message = connectionErrorMessage(error, server: server)
                    sftpErrorByServer[server.id] = message
                    finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
                    postStatus(localized("SFTP failed for %@: %@", server.name, message))
                }
            }
        }
    }

    func startMonitoringLiveActivity() {
        guard isProUnlocked else {
            presentPaywall(feature: "Live Activities", message: localized("Show live CPU, RAM and health on the Lock Screen."))
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

    func publishWidgetSnapshots() {
        if isProUnlocked {
            widgetDataService.save(profiles: serverProfiles, metricsByServer: metricsByServer)
        } else {
            widgetDataService.saveLocked()
        }
    }


    private func enforceSubscriptionBoundaries() {
        guard !subscription.isPro else {
            publishWidgetSnapshots()
            restartAutoRefreshIfNeeded()
            return
        }
        settings.metricsAutoRefreshEnabled = false
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        if settings.terminalTheme.isPremium {
            settings.terminalTheme = .liquidDark
        }
        if settings.iCloudSyncEnabled {
            settings.iCloudSyncEnabled = false
            stopICloudProfileSync()
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
            postStatus(localized("Failed to load profiles: %@", error.localizedDescription))
        }
    }

    func syncProfilesWithICloud(mergeRemote: Bool = false) {
        guard settings.iCloudSyncEnabled else { return }
        guard let profileRepository else { return }

        let localSnapshots = serverProfiles.map(CloudServerProfileSnapshot.init)
        let previousSyncTask = profileCloudSyncTask
        previousSyncTask?.cancel()
        profileCloudSyncActivity = .checking
        profileCloudSyncTask = Task {
            do {
                if let previousSyncTask {
                    _ = await previousSyncTask.result
                }
                try Task.checkCancellation()

                let profileCloudSyncService = try ProfileCloudSyncService()
                try await profileCloudSyncService.preflight()
                try Task.checkCancellation()
                guard settings.iCloudSyncEnabled else { return }
                profileCloudSyncActivity = .syncing

                if mergeRemote {
                    let syncedSnapshots = try await profileCloudSyncService.mergeAndUpload(localSnapshots: localSnapshots)
                    try Task.checkCancellation()
                    guard settings.iCloudSyncEnabled else { return }
                    for snapshot in syncedSnapshots {
                        try profileRepository.saveProfile(snapshot.makeServerProfile())
                    }
                    reloadProfilesFromRepository()
                    postStatus(localized("iCloud profile sync completed."))
                    profileCloudSyncActivity = .synced(.now)
                } else {
                    try await profileCloudSyncService.uploadSnapshot(localSnapshots)
                    try Task.checkCancellation()
                    guard settings.iCloudSyncEnabled else { return }
                    postStatus(localized("iCloud profile snapshot updated."))
                    profileCloudSyncActivity = .synced(.now)
                }
            } catch is CancellationError {
                return
            } catch let error as ProfileCloudSyncError {
                if error.shouldDisableSync {
                    settings.iCloudSyncEnabled = false
                }
                postStatus(localized("iCloud sync failed: %@", error.localizedDescription))
                profileCloudSyncActivity = .failed(error.localizedDescription)
            } catch {
                postStatus(localized("iCloud sync failed: %@", error.localizedDescription))
                profileCloudSyncActivity = .failed(error.localizedDescription)
            }
        }
    }

    private func uploadProfilesToICloudIfEnabled() {
        guard settings.iCloudSyncEnabled else { return }
        syncProfilesWithICloud()
    }

    func stopICloudProfileSync() {
        profileCloudSyncTask?.cancel()
        profileCloudSyncTask = nil
        profileCloudSyncActivity = .idle
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard !shouldReduceMotion else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

enum CloudProfileSyncActivity: Equatable {
    case idle
    case checking
    case syncing
    case synced(Date)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .syncing:
            true
        case .idle, .synced, .failed:
            false
        }
    }

    var titleKey: String {
        switch self {
        case .idle:
            "iCloud sync is idle."
        case .checking:
            "Checking iCloud account..."
        case .syncing:
            "Syncing profiles with iCloud..."
        case .synced:
            "iCloud sync is up to date."
        case .failed:
            "iCloud sync needs attention."
        }
    }

    var detail: String? {
        switch self {
        case .failed(let message):
            message
        default:
            nil
        }
    }
}
