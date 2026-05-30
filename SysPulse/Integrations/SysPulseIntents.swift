import AppIntents
import Foundation

struct OpenServerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open server"
    static var description = IntentDescription("Open a saved SysPulse server.")
    static var openAppWhenRun = true

    @Parameter(title: "Server name")
    var serverName: String

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .syspulseOpenMonitor,
                object: nil,
                userInfo: [SysPulseShortcutPayload.serverNameKey: serverName]
            )
        }
        return .result(dialog: "Opening \(serverName) in SysPulse.")
    }
}

struct RunQuickCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "Run quick command"
    static var description = IntentDescription("Run a safe quick command on a server.")
    static var openAppWhenRun = true

    @Parameter(title: "Command")
    var command: String

    @Parameter(title: "Server")
    var serverName: String

    func perform() async throws -> some IntentResult {
        if CommandRunner.containsDangerousToken(command) {
            return .result(dialog: "Dangerous commands require explicit confirmation inside SysPulse.")
        }
        return .result(dialog: "Command queued for \(serverName).")
    }
}

extension Notification.Name {
    static let syspulseRefreshAllServers = Notification.Name("syspulseRefreshAllServers")
    static let syspulseOpenServer = Notification.Name("syspulseOpenServer")
    static let syspulseOpenTerminal = Notification.Name("syspulseOpenTerminal")
    static let syspulseOpenMonitor = Notification.Name("syspulseOpenMonitor")
}

enum SysPulseShortcutPayload {
    static let serverNameKey = "serverName"
}

struct RefreshAllServersIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh all servers"
    static var description = IntentDescription("Refresh metrics for every saved server in SysPulse.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .syspulseRefreshAllServers, object: nil)
        }
        return .result(dialog: "Refreshing all servers in SysPulse.")
    }
}

struct CheckServerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check server status"
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var serverName: String

    func perform() async throws -> some IntentResult {
        .result(dialog: "\(serverName) status is available in SysPulse.")
    }
}

struct OpenTerminalIntent: AppIntent {
    static var title: LocalizedStringResource = "Open terminal"
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var serverName: String

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .syspulseOpenTerminal,
                object: nil,
                userInfo: [SysPulseShortcutPayload.serverNameKey: serverName]
            )
        }
        return .result(dialog: "Opening terminal for \(serverName).")
    }
}

struct RunDiagnosticIntent: AppIntent {
    static var title: LocalizedStringResource = "Run diagnostic on server"
    static var description = IntentDescription(LocalizedStringResource("Run diagnostic pack"))
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var serverName: String

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .syspulseRunDiagnostic,
                object: nil,
                userInfo: [SysPulseShortcutPayload.serverNameKey: serverName]
            )
        }
        return .result(dialog: "Running diagnostics for \(serverName) in SysPulse.")
    }
}

struct ExportMetricsCSVIntent: AppIntent {
    static var title: LocalizedStringResource = "Export metrics CSV"
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var serverName: String

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .syspulseExportMetricsCSV,
                object: nil,
                userInfo: [SysPulseShortcutPayload.serverNameKey: serverName]
            )
        }
        return .result(dialog: "Exporting CSV for \(serverName) in SysPulse.")
    }
}

struct ShowDiskUsageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show disk usage"
    static var openAppWhenRun = true

    @Parameter(title: "Server")
    var serverName: String

    func perform() async throws -> some IntentResult {
        .result(dialog: "Disk usage opens in SysPulse.")
    }
}

struct RestartServiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Restart service"
    static var description = IntentDescription("Open SysPulse confirmation for restarting a service.")
    static var openAppWhenRun = true

    @Parameter(title: "Service")
    var serviceName: String

    @Parameter(title: "Server")
    var serverName: String

    func perform() async throws -> some IntentResult {
        .result(dialog: "Restarting \(serviceName) requires confirmation inside SysPulse.")
    }
}

struct SysPulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenServerIntent(),
            phrases: ["Open \(.applicationName) server"],
            shortTitle: "Open Server",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: CheckServerStatusIntent(),
            phrases: ["Check \(.applicationName) server status"],
            shortTitle: "Check Status",
            systemImageName: "waveform.path.ecg"
        )
        AppShortcut(
            intent: OpenTerminalIntent(),
            phrases: ["Open \(.applicationName) terminal"],
            shortTitle: "Open Terminal",
            systemImageName: "terminal"
        )
        AppShortcut(
            intent: RefreshAllServersIntent(),
            phrases: ["Refresh \(.applicationName) servers"],
            shortTitle: "Refresh Servers",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: RunQuickCommandIntent(),
            phrases: ["Run command on \(.applicationName)"],
            shortTitle: "Run Command",
            systemImageName: "terminal"
        )
        AppShortcut(
            intent: RunDiagnosticIntent(),
            phrases: ["Run diagnostic on \(.applicationName) server"],
            shortTitle: "Run Diagnostic",
            systemImageName: "stethoscope"
        )
        AppShortcut(
            intent: ExportMetricsCSVIntent(),
            phrases: ["Export CSV for \(.applicationName) server"],
            shortTitle: "Export CSV",
            systemImageName: "tablecells"
        )
    }
}
