import Foundation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case servers
    case terminal
    case sftp
    case settings

    var id: String { rawValue }

    /// All tabs shown in the bottom bar (hidden while Terminal tab is active).
    static var barTabs: [AppTab] { allCases }

    var titleText: String {
        switch self {
        case .servers:
            "Servers"
        case .terminal:
            "Terminal"
        case .sftp:
            "Files"
        case .settings:
            "Settings"
        }
    }

    var title: LocalizedStringKey { LocalizedStringKey(titleText) }

    var symbol: String {
        switch self {
        case .servers: "server.rack"
        case .terminal: "terminal"
        case .sftp: "folder"
        case .settings: "gearshape"
        }
    }

    var tabAccessibilityIdentifier: String {
        "tab_\(rawValue)"
    }

    var screenAccessibilityIdentifier: String {
        "screen_\(rawValue)"
    }
}

enum ServerType: String, CaseIterable, Identifiable, Codable, Hashable {
    case raspberryPi = "Raspberry Pi"
    case vps = "VPS"
    case dockerHost = "Docker Host"
    case nas = "NAS"
    case webServer = "Web Server"
    case databaseServer = "Database Server"
    case homeAssistant = "Home Assistant"
    case immichServer = "Immich Server"
    case custom = "Custom"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var symbol: String {
        switch self {
        case .raspberryPi: "cpu"
        case .vps: "cloud"
        case .dockerHost: "shippingbox"
        case .nas: "externaldrive.connected.to.line.below"
        case .webServer: "network"
        case .databaseServer: "cylinder.split.1x2"
        case .homeAssistant: "house"
        case .immichServer: "photo.on.rectangle.angled"
        case .custom: "square.grid.2x2"
        }
    }
}

enum SSHAuthenticationType: String, CaseIterable, Identifiable, Codable, Hashable {
    case password = "Password"
    case privateKey = "Private Key"
    case privateKeyWithPassphrase = "Private Key + Passphrase"

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

enum ServerStatus: String, Codable, Hashable {
    case online
    case offline
    case warning
    case unknown

    var title: String {
        switch self {
        case .online: "Online"
        case .offline: "Offline"
        case .warning: "Warning"
        case .unknown: "Unknown"
        }
    }

    var titleKey: LocalizedStringKey { LocalizedStringKey(title) }

    var color: Color {
        switch self {
        case .online: .green
        case .offline: .red
        case .warning: .yellow
        case .unknown: .secondary
        }
    }
}

enum CommandSafetyLevel: String, CaseIterable, Identifiable, Codable, Hashable {
    case safe = "Safe"
    case moderate = "Moderate"
    case dangerous = "Dangerous"

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var color: Color {
        switch self {
        case .safe: .green
        case .moderate: .yellow
        case .dangerous: .red
        }
    }
}

enum TerminalTheme: String, CaseIterable, Identifiable, Codable, Hashable {
    case liquidDark = "Liquid Dark"
    case matrix = "Matrix"
    case midnight = "Midnight"
    case ice = "Ice"
    case solarized = "Solarized"
    case neon = "Neon"
    case classic = "Classic"
    case raspberry = "Raspberry"
    case cyberGlass = "Cyber Glass"
    case terminalPro = "Terminal Pro"

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var isPremium: Bool { self != .liquidDark }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable, Hashable {
    case system = "System"
    case english = "English"
    case ukrainian = "Українська"
    case russian = "Русский"
    case polish = "Polski"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            .autoupdatingCurrent
        case .english:
            Locale(identifier: "en")
        case .ukrainian:
            Locale(identifier: "uk")
        case .russian:
            Locale(identifier: "ru")
        case .polish:
            Locale(identifier: "pl")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system:
            "System"
        case .english:
            "English"
        case .ukrainian:
            "Українська"
        case .russian:
            "Русский"
        case .polish:
            "Polski"
        }
    }
}

enum SubscriptionPlan: String, Codable, Hashable {
    case free = "Free"
    case proMonthly = "Pro Monthly"
    case proYearly = "Pro Yearly"
    case lifetime = "Lifetime Pro"

    var rank: Int {
        switch self {
        case .free: 0
        case .proMonthly: 1
        case .proYearly: 2
        case .lifetime: 3
        }
    }
}

enum HealthRating: String, Hashable {
    case excellent = "Excellent"
    case good = "Good"
    case warning = "Warning"
    case critical = "Critical"

    static func rating(for score: Int) -> HealthRating {
        switch score {
        case 90...100: .excellent
        case 70...89: .good
        case 50...69: .warning
        default: .critical
        }
    }

    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var color: Color {
        switch self {
        case .excellent: .green
        case .good: .teal
        case .warning: .orange
        case .critical: .red
        }
    }
}

enum MetricThresholdColor {
    static func forPercent(_ value: Double) -> Color {
        if value >= 85 { return .red }
        if value >= 70 { return .orange }
        return .green
    }
}

struct ServerPrimaryRisk {
    var messageKey: String
    var messageArgs: [CVarArg]
    var color: Color
    var symbol: String

    static func evaluate(
        server: ServerProfile,
        metrics: ServerMetrics,
        alertCount: Int
    ) -> ServerPrimaryRisk {
        if server.status == .offline {
            return ServerPrimaryRisk(messageKey: "Server offline", messageArgs: [], color: .red, symbol: "wifi.slash")
        }
        if metrics.cpuUsage >= 85 {
            return ServerPrimaryRisk(messageKey: "CPU at %d%%", messageArgs: [Int(metrics.cpuUsage)], color: .red, symbol: "cpu")
        }
        if metrics.ramUsage >= 85 {
            return ServerPrimaryRisk(messageKey: "RAM at %d%%", messageArgs: [Int(metrics.ramUsage)], color: .red, symbol: "memorychip")
        }
        if metrics.diskUsage >= 85 {
            return ServerPrimaryRisk(messageKey: "Disk at %d%%", messageArgs: [Int(metrics.diskUsage)], color: .red, symbol: "externaldrive")
        }
        if metrics.failedServices > 0 {
            return ServerPrimaryRisk(
                messageKey: "%d failed service(s)",
                messageArgs: [metrics.failedServices],
                color: .orange,
                symbol: "exclamationmark.triangle"
            )
        }
        if metrics.healthScore < 70 {
            return ServerPrimaryRisk(
                messageKey: "Health score %d",
                messageArgs: [metrics.healthScore],
                color: HealthRating.rating(for: metrics.healthScore).color,
                symbol: "heart.text.square"
            )
        }
        if alertCount > 0 {
            return ServerPrimaryRisk(
                messageKey: "%d active alert(s)",
                messageArgs: [alertCount],
                color: .orange,
                symbol: "bell.badge"
            )
        }
        if server.status == .warning {
            return ServerPrimaryRisk(messageKey: "Needs attention", messageArgs: [], color: .orange, symbol: "exclamationmark.circle")
        }
        return ServerPrimaryRisk(messageKey: "All good", messageArgs: [], color: .green, symbol: "checkmark.seal")
    }
}

enum AlertMetricKey: String, CaseIterable, Identifiable, Codable, Hashable {
    case cpuUsage = "cpu"
    case ramUsage = "ram"
    case diskUsage = "disk"
    case healthScore = "health"
    case failedServices = "failed_services"

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .cpuUsage: "CPU usage"
        case .ramUsage: "RAM usage"
        case .diskUsage: "Disk usage"
        case .healthScore: "Health score"
        case .failedServices: "Failed services"
        }
    }

    var symbol: String {
        switch self {
        case .cpuUsage: "cpu"
        case .ramUsage: "memorychip"
        case .diskUsage: "externaldrive"
        case .healthScore: "heart.text.square"
        case .failedServices: "exclamationmark.triangle"
        }
    }

    var defaultTitle: String {
        switch self {
        case .cpuUsage: "High CPU"
        case .ramUsage: "High RAM"
        case .diskUsage: "High Disk"
        case .healthScore: "Low Health Score"
        case .failedServices: "Failed Services"
        }
    }

    var defaultThreshold: Double {
        switch self {
        case .cpuUsage, .ramUsage:
            90
        case .diskUsage:
            85
        case .healthScore:
            50
        case .failedServices:
            0
        }
    }

    var thresholdFormatKey: String {
        switch self {
        case .cpuUsage, .ramUsage, .diskUsage:
            "Triggers at %.0f%% or higher."
        case .healthScore:
            "Triggers at %.0f or lower."
        case .failedServices:
            "Triggers when any service fails."
        }
    }

    var notificationBodyKey: String {
        switch self {
        case .cpuUsage:
            "CPU is %.0f%% on %@."
        case .ramUsage:
            "RAM is %.0f%% on %@."
        case .diskUsage:
            "Disk is %.0f%% on %@."
        case .healthScore:
            "Health score is %.0f on %@."
        case .failedServices:
            "%.0f failed services on %@."
        }
    }

    func value(in metrics: ServerMetrics) -> Double {
        switch self {
        case .cpuUsage:
            metrics.cpuUsage
        case .ramUsage:
            metrics.ramUsage
        case .diskUsage:
            metrics.diskUsage
        case .healthScore:
            Double(metrics.healthScore)
        case .failedServices:
            Double(metrics.failedServices)
        }
    }

    func isTriggered(value: Double, threshold: Double) -> Bool {
        switch self {
        case .healthScore:
            value <= threshold
        case .failedServices:
            value > threshold
        case .cpuUsage, .ramUsage, .diskUsage:
            value >= threshold
        }
    }
}

@Model
final class ServerProfile: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var authenticationTypeRaw: String = "Password"
    var credentialIdentifier: String?
    var tagsCSV: String = ""
    var groupName: String?
    var icon: String = "server.rack"
    var accentHex: String = "#33C2EA"
    var serverTypeRaw: String = "Custom"
    var statusRaw: String = "unknown"
    /// Optional bastion/jump server profile used for SSH command proxying.
    var jumpServerID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authenticationType: SSHAuthenticationType = .password,
        credentialIdentifier: String? = nil,
        tags: [String] = [],
        groupName: String? = nil,
        icon: String = "server.rack",
        accentHex: String = "#33C2EA",
        serverType: ServerType = .custom,
        status: ServerStatus = .unknown,
        jumpServerID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authenticationTypeRaw = authenticationType.rawValue
        self.credentialIdentifier = credentialIdentifier
        self.tagsCSV = tags.joined(separator: ",")
        self.groupName = groupName
        self.icon = icon
        self.accentHex = accentHex
        self.serverTypeRaw = serverType.rawValue
        self.statusRaw = status.rawValue
        self.jumpServerID = jumpServerID
        self.createdAt = .now
        self.updatedAt = .now
    }

    var serverType: ServerType {
        get { ServerType(rawValue: serverTypeRaw) ?? .custom }
        set { serverTypeRaw = newValue.rawValue }
    }

    var authenticationType: SSHAuthenticationType {
        get { SSHAuthenticationType(rawValue: authenticationTypeRaw) ?? .password }
        set { authenticationTypeRaw = newValue.rawValue }
    }

    var status: ServerStatus {
        get { ServerStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }

    var tags: [String] {
        tagsCSV
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var displayIcon: String {
        let trimmedIcon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedIcon.isEmpty ? serverType.symbol : trimmedIcon
    }
}

enum SFTPOperationKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case upload
    case download
    case delete

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .upload:
            "Upload"
        case .download:
            "Download"
        case .delete:
            "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .upload:
            "arrow.up.doc"
        case .download:
            "arrow.down.doc"
        case .delete:
            "trash"
        }
    }
}

enum SFTPOperationStatus: String, Codable, Hashable {
    case running
    case succeeded
    case failed

    var titleKey: LocalizedStringKey {
        switch self {
        case .running:
            "Running"
        case .succeeded:
            "Done"
        case .failed:
            "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .running:
            "arrow.triangle.2.circlepath"
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .running:
            .cyan
        case .succeeded:
            .green
        case .failed:
            .red
        }
    }
}

struct SFTPOperation: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var serverID: UUID
    var kind: SFTPOperationKind
    var fileName: String
    var remotePath: String
    var status: SFTPOperationStatus
    var message: String
    var startedAt: Date = .now
    var completedAt: Date?
}

struct SSHCredential: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var serverID: UUID
    var keychainAccount: String
    var authenticationType: SSHAuthenticationType
    var displayName: String
}

struct SSHPrivateKeyCredentialPayload: Codable, Hashable {
    var privateKey: String
    var passphrase: String?

    var keychainValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let value = String(data: data, encoding: .utf8) else {
            return privateKey
        }
        return value
    }

    static func decode(from value: String) -> SSHPrivateKeyCredentialPayload {
        guard let data = value.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SSHPrivateKeyCredentialPayload.self, from: data) else {
            return SSHPrivateKeyCredentialPayload(privateKey: value, passphrase: nil)
        }
        return payload
    }
}

struct ServerMetrics: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var serverID: UUID
    var timestamp: Date
    var cpuUsage: Double
    var ramUsage: Double
    var swapUsage: Double
    var diskUsage: Double
    var networkInMB: Double
    var networkOutMB: Double
    var temperatureCelsius: Double?
    var uptime: String
    var osName: String
    var kernel: String
    var loadAverage: String
    var ipAddresses: [String]
    var healthScore: Int
    var cpuHistory: [Double]
    var ramHistory: [Double]
    var diskHistory: [Double]
    var failedServices: Int
    var dockerRunning: Int
    var dockerTotal: Int

    static func empty(serverID: UUID) -> ServerMetrics {
        ServerMetrics(
            serverID: serverID,
            timestamp: .now,
            cpuUsage: 0,
            ramUsage: 0,
            swapUsage: 0,
            diskUsage: 0,
            networkInMB: 0,
            networkOutMB: 0,
            temperatureCelsius: nil,
            uptime: "Unknown",
            osName: "Unknown Linux",
            kernel: "-",
            loadAverage: "-",
            ipAddresses: [],
            healthScore: 0,
            cpuHistory: [],
            ramHistory: [],
            diskHistory: [],
            failedServices: 0,
            dockerRunning: 0,
            dockerTotal: 0
        )
    }
}

@Model
final class TerminalSession: Identifiable {
    var id: UUID = UUID()
    var serverID: UUID?
    var title: String = ""
    var startedAt: Date = Date.now
    var isActive: Bool = true
    var themeRaw: String = "Liquid Dark"
    var transcript: String = ""

    init(
        id: UUID = UUID(),
        serverID: UUID?,
        title: String,
        startedAt: Date = .now,
        isActive: Bool = true,
        theme: TerminalTheme = .liquidDark,
        transcript: String = ""
    ) {
        self.id = id
        self.serverID = serverID
        self.title = title
        self.startedAt = startedAt
        self.isActive = isActive
        self.themeRaw = theme.rawValue
        self.transcript = transcript
    }

    var theme: TerminalTheme {
        get { TerminalTheme(rawValue: themeRaw) ?? .liquidDark }
        set { themeRaw = newValue.rawValue }
    }
}

@Model
final class QuickCommand: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var command: String = ""
    var safetyRaw: String = "Safe"
    var isPremium: Bool = false
    var variablesCSV: String = ""
    var isUserDefined: Bool = false

    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        command: String,
        safety: CommandSafetyLevel,
        isPremium: Bool = false,
        variables: [String] = [],
        isUserDefined: Bool = false
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.command = command
        self.safetyRaw = safety.rawValue
        self.isPremium = isPremium
        self.variablesCSV = variables.joined(separator: ",")
        self.isUserDefined = isUserDefined
    }

    var safety: CommandSafetyLevel {
        get { CommandSafetyLevel(rawValue: safetyRaw) ?? .safe }
        set { safetyRaw = newValue.rawValue }
    }

    var variables: [String] {
        variablesCSV
            .split(separator: ",")
            .map(String.init)
    }
}

@Model
final class CommandExecution: Identifiable {
    var id: UUID = UUID()
    var commandID: UUID?
    var serverID: UUID?
    var commandText: String = ""
    var output: String = ""
    var exitCode: Int = 0
    var executedAt: Date = Date.now
    var requiredConfirmation: Bool = false

    init(
        id: UUID = UUID(),
        commandID: UUID? = nil,
        serverID: UUID? = nil,
        commandText: String,
        output: String = "",
        exitCode: Int = 0,
        executedAt: Date = .now,
        requiredConfirmation: Bool = false
    ) {
        self.id = id
        self.commandID = commandID
        self.serverID = serverID
        self.commandText = commandText
        self.output = output
        self.exitCode = exitCode
        self.executedAt = executedAt
        self.requiredConfirmation = requiredConfirmation
    }
}

@Model
final class ServerGroup: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var accentHex: String = "#33C2EA"
    var icon: String = "folder"

    init(id: UUID = UUID(), name: String, accentHex: String = "#33C2EA", icon: String = "folder") {
        self.id = id
        self.name = name
        self.accentHex = accentHex
        self.icon = icon
    }
}

struct AppSettings: Codable, Hashable {
    var requiresBiometrics: Bool = true
    var autoLockMinutes: Int = 5
    var hideSensitiveData: Bool = false
    var clipboardWarning: Bool = true
    var appearanceMode: AppearanceMode = .system
    var accentHex: String = "#33C2EA"
    var terminalTheme: TerminalTheme = .liquidDark
    var terminalFontSize: Double = 14
    var reduceAnimations: Bool = false
    var language: AppLanguage = .system
    var iCloudSyncEnabled: Bool = false
    var backendMonitoringEnabled: Bool = false
    var backendMonitoringEndpoint: String = ""
    var forceProOverride: Bool = false
    var metricsAutoRefreshEnabled: Bool = false
    var metricsAutoRefreshIntervalSeconds: Int = 60
    var alertWebhookEnabled: Bool = false
    var alertWebhookEndpoint: String = ""
    var prometheusDashboardURL: String = ""
    var prometheusEnabled: Bool = false
    var alertQuietHoursEnabled: Bool = false
    var alertQuietHoursStart: Int = 22
    var alertQuietHoursEnd: Int = 7

    init() {}

    enum CodingKeys: String, CodingKey {
        case requiresBiometrics
        case autoLockMinutes
        case hideSensitiveData
        case clipboardWarning
        case appearanceMode
        case accentHex
        case terminalTheme
        case terminalFontSize
        case reduceAnimations
        case language
        case iCloudSyncEnabled
        case backendMonitoringEnabled
        case backendMonitoringEndpoint
        case forceProOverride
        case metricsAutoRefreshEnabled
        case metricsAutoRefreshIntervalSeconds
        case alertWebhookEnabled
        case alertWebhookEndpoint
        case prometheusDashboardURL
        case prometheusEnabled
        case alertQuietHoursEnabled
        case alertQuietHoursStart
        case alertQuietHoursEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requiresBiometrics = try container.decodeIfPresent(Bool.self, forKey: .requiresBiometrics) ?? true
        autoLockMinutes = try container.decodeIfPresent(Int.self, forKey: .autoLockMinutes) ?? 5
        hideSensitiveData = try container.decodeIfPresent(Bool.self, forKey: .hideSensitiveData) ?? false
        clipboardWarning = try container.decodeIfPresent(Bool.self, forKey: .clipboardWarning) ?? true
        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? "#33C2EA"
        terminalTheme = try container.decodeIfPresent(TerminalTheme.self, forKey: .terminalTheme) ?? .liquidDark
        terminalFontSize = try container.decodeIfPresent(Double.self, forKey: .terminalFontSize) ?? 14
        reduceAnimations = try container.decodeIfPresent(Bool.self, forKey: .reduceAnimations) ?? false
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        iCloudSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .iCloudSyncEnabled) ?? false
        backendMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .backendMonitoringEnabled) ?? false
        backendMonitoringEndpoint = try container.decodeIfPresent(String.self, forKey: .backendMonitoringEndpoint) ?? ""
        forceProOverride = try container.decodeIfPresent(Bool.self, forKey: .forceProOverride) ?? false
        metricsAutoRefreshEnabled = try container.decodeIfPresent(Bool.self, forKey: .metricsAutoRefreshEnabled) ?? false
        metricsAutoRefreshIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .metricsAutoRefreshIntervalSeconds) ?? 60
        alertWebhookEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertWebhookEnabled) ?? false
        alertWebhookEndpoint = try container.decodeIfPresent(String.self, forKey: .alertWebhookEndpoint) ?? ""
        prometheusDashboardURL = try container.decodeIfPresent(String.self, forKey: .prometheusDashboardURL) ?? ""
        prometheusEnabled = try container.decodeIfPresent(Bool.self, forKey: .prometheusEnabled) ?? false
        alertQuietHoursEnabled = try container.decodeIfPresent(Bool.self, forKey: .alertQuietHoursEnabled) ?? false
        alertQuietHoursStart = try container.decodeIfPresent(Int.self, forKey: .alertQuietHoursStart) ?? 22
        alertQuietHoursEnd = try container.decodeIfPresent(Int.self, forKey: .alertQuietHoursEnd) ?? 7
    }
}

@Model
final class TerminalCommandEntry: Identifiable {
    var id: UUID = UUID()
    var serverID: UUID = UUID()
    var command: String = ""
    var isFavorite: Bool = false
    var lastUsedAt: Date = Date.now

    init(id: UUID = UUID(), serverID: UUID, command: String, isFavorite: Bool = false, lastUsedAt: Date = .now) {
        self.id = id
        self.serverID = serverID
        self.command = command
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
    }
}

@Model
final class SFTPPathBookmark: Identifiable {
    var id: UUID = UUID()
    var serverID: UUID = UUID()
    var path: String = ""
    var label: String = ""
    var isFavorite: Bool = false
    var lastVisitedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        serverID: UUID,
        path: String,
        label: String = "",
        isFavorite: Bool = false,
        lastVisitedAt: Date = .now
    ) {
        self.id = id
        self.serverID = serverID
        self.path = path
        self.label = label.isEmpty ? path : label
        self.isFavorite = isFavorite
        self.lastVisitedAt = lastVisitedAt
    }
}

@Model
final class ScheduledCommand: Identifiable {
    var id: UUID = UUID()
    var serverID: UUID = UUID()
    var title: String = ""
    var command: String = ""
    var intervalMinutes: Int = 60
    var isEnabled: Bool = true
    var nextRunAt: Date = Date.now
    var lastRunAt: Date?
    var lastOutput: String = ""
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        serverID: UUID,
        title: String,
        command: String,
        intervalMinutes: Int = 60,
        isEnabled: Bool = true,
        nextRunAt: Date = .now
    ) {
        self.id = id
        self.serverID = serverID
        self.title = title
        self.command = command
        self.intervalMinutes = max(intervalMinutes, 15)
        self.isEnabled = isEnabled
        self.nextRunAt = nextRunAt
        self.createdAt = .now
    }
}

enum MetricsAutoRefreshInterval: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60
    case twoMinutes = 120
    case fiveMinutes = 300

    var id: Int { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .thirty: "30 sec"
        case .sixty: "1 min"
        case .twoMinutes: "2 min"
        case .fiveMinutes: "5 min"
        }
    }
}

struct SubscriptionState: Codable, Hashable {
    var plan: SubscriptionPlan = .free
    var isActive: Bool = false
    var expiresAt: Date?
    var productsLoaded: Bool = false
    var lastStoreKitMessage: String = ""

    var isPro: Bool {
        guard isActive else { return false }
        if plan == .lifetime { return true }
        guard let expiresAt else { return false }
        return expiresAt > .now
    }

    func isBetterEntitlement(than other: SubscriptionState) -> Bool {
        guard isPro else { return false }
        guard other.isPro else { return true }
        if plan.rank != other.plan.rank {
            return plan.rank > other.plan.rank
        }
        return (expiresAt ?? .distantFuture) > (other.expiresAt ?? .distantFuture)
    }
}

@Model
final class AlertRule: Identifiable {
    var id: UUID = UUID()
    var serverID: UUID?
    var title: String = ""
    var metricKey: String = ""
    var threshold: Double = 0
    var isEnabled: Bool = true

    init(id: UUID = UUID(), serverID: UUID? = nil, title: String, metricKey: String, threshold: Double, isEnabled: Bool = true) {
        self.id = id
        self.serverID = serverID
        self.title = title
        self.metricKey = metricKey
        self.threshold = threshold
        self.isEnabled = isEnabled
    }

    var metric: AlertMetricKey {
        get { AlertMetricKey(rawValue: metricKey) ?? .cpuUsage }
        set { metricKey = newValue.rawValue }
    }

    static func defaultRules() -> [AlertRule] {
        AlertMetricKey.allCases.map { metric in
            AlertRule(
                title: metric.defaultTitle,
                metricKey: metric.rawValue,
                threshold: metric.defaultThreshold,
                isEnabled: true
            )
        }
    }
}

@Model
final class ServerEvent: Identifiable {
    var id: UUID = UUID()
    var serverID: UUID?
    var title: String = ""
    var details: String = ""
    var severity: String = "Safe"
    var createdAt: Date = Date.now

    init(id: UUID = UUID(), serverID: UUID? = nil, title: String, details: String, severity: String, createdAt: Date = .now) {
        self.id = id
        self.serverID = serverID
        self.title = title
        self.details = details
        self.severity = severity
        self.createdAt = createdAt
    }
}

struct DockerContainer: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var image: String
    var status: String
    var cpuUsage: Double
    var memoryUsage: Double
    var restartedRecently: Bool
}

struct SystemdServiceItem: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var loadedState: String
    var activeState: String
    var subState: String
    var isFailed: Bool
}

struct DiskInfo: Identifiable, Codable, Hashable {
    var id: String { mountPoint }
    var mountPoint: String
    var filesystem: String
    var usedGB: Double
    var freeGB: Double
    var usagePercent: Double
    var smartStatus: String?
}

struct ProcessInfoItem: Identifiable, Codable, Hashable {
    var id: Int { pid }
    var pid: Int
    var user: String
    var command: String
    var cpu: Double
    var memory: Double
}

struct LogEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var timestamp: String
    var source: String
    var message: String
    var severity: CommandSafetyLevel
}

struct SmartInsight: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var details: String
    var severity: CommandSafetyLevel
    var symbol: String
}

struct PackageStatus: Identifiable, Codable, Hashable {
    var id: String { commandName }
    var commandName: String
    var packageName: String
    var isInstalled: Bool
    var featureImpact: String
}

struct MissingTool: Identifiable, Hashable {
    var id: String { commandName }
    var commandName: String
    var packageName: String
    var reason: String
    var unavailableFeatures: [String]
}

enum SFTPRemoteItemKind: String, Codable, Hashable {
    case directory
    case file
    case symlink
    case other

    var titleText: String {
        switch self {
        case .directory:
            "Directory"
        case .file:
            "File"
        case .symlink:
            "Symlink"
        case .other:
            "Other"
        }
    }

    var titleKey: LocalizedStringKey {
        LocalizedStringKey(titleText)
    }

    var symbol: String {
        switch self {
        case .directory:
            "folder"
        case .file:
            "doc"
        case .symlink:
            "link"
        case .other:
            "questionmark.square"
        }
    }
}

struct SFTPRemoteItem: Identifiable, Codable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var kind: SFTPRemoteItemKind
    var size: Int64
    var modifiedAt: String
    var permissions: String

    var isDirectory: Bool {
        kind == .directory
    }
}

enum LinuxDistribution: String, CaseIterable, Identifiable, Hashable {
    case debian = "Debian / Ubuntu / Raspberry Pi OS"
    case fedora = "Fedora"
    case arch = "Arch"
    case alpine = "Alpine"

    var id: String { rawValue }
    var titleKey: LocalizedStringKey { LocalizedStringKey(rawValue) }

    var installCommand: String {
        switch self {
        case .debian:
            "sudo apt update && sudo apt install -y sysstat lm-sensors htop curl jq net-tools smartmontools"
        case .fedora:
            "sudo dnf install -y sysstat lm_sensors htop curl jq net-tools smartmontools"
        case .arch:
            "sudo pacman -Syu --needed sysstat lm_sensors htop curl jq net-tools smartmontools"
        case .alpine:
            "sudo apk add sysstat lm-sensors htop curl jq smartmontools"
        }
    }
}
