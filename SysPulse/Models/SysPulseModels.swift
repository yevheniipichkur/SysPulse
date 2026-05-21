import Foundation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case servers
    case monitor
    case terminal
    case commands
    case settings

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .servers: "Servers"
        case .monitor: "Monitor"
        case .terminal: "Terminal"
        case .commands: "Commands"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .servers: "server.rack"
        case .monitor: "waveform.path.ecg"
        case .terminal: "terminal"
        case .commands: "bolt.horizontal"
        case .settings: "gearshape"
        }
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
        status: ServerStatus = .unknown
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

    init(
        id: UUID = UUID(),
        title: String,
        details: String,
        command: String,
        safety: CommandSafetyLevel,
        isPremium: Bool = false,
        variables: [String] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.command = command
        self.safetyRaw = safety.rawValue
        self.isPremium = isPremium
        self.variablesCSV = variables.joined(separator: ",")
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
    var forceProOverride: Bool = false
}

struct SubscriptionState: Codable, Hashable {
    var plan: SubscriptionPlan = .free
    var isActive: Bool = false
    var expiresAt: Date?
    var productsLoaded: Bool = false
    var lastStoreKitMessage: String = L10n.string("Mock StoreKit is ready")

    var isPro: Bool {
        isActive
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
