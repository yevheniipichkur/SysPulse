import SwiftData
import SwiftUI

@main
struct SysPulseApp: App {
    @StateObject private var appState = AppState()
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try SysPulseModelContainerFactory.makeContainer()
        } catch {
            fatalError("Unable to create SysPulse model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, appState.settings.language.locale)
                .preferredColorScheme(appState.preferredColorScheme)
                .onReceive(NotificationCenter.default.publisher(for: .syspulseRefreshAllServers)) { _ in
                    appState.refreshAllServers()
                }
                .onReceive(NotificationCenter.default.publisher(for: .syspulseOpenMonitor)) { notification in
                    let name = notification.userInfo?[SysPulseShortcutPayload.serverNameKey] as? String
                    appState.handleShortcut(serverName: name, tab: .servers, openMonitor: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .syspulseOpenTerminal)) { notification in
                    let name = notification.userInfo?[SysPulseShortcutPayload.serverNameKey] as? String
                    appState.handleShortcut(serverName: name, tab: .terminal)
                }
                .onReceive(NotificationCenter.default.publisher(for: .syspulseRunScheduledCommands)) { _ in
                    appState.runDueScheduledCommands(markMissedIfNeeded: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .syspulseScheduledCommandsMissed)) { _ in
                    appState.runDueScheduledCommands(markMissedIfNeeded: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .syspulseRunDiagnostic)) { notification in
                    let name = notification.userInfo?[SysPulseShortcutPayload.serverNameKey] as? String
                    appState.runDiagnosticFromShortcut(serverName: name)
                }
                .onReceive(NotificationCenter.default.publisher(for: .syspulseExportMetricsCSV)) { notification in
                    let name = notification.userInfo?[SysPulseShortcutPayload.serverNameKey] as? String
                    if let name,
                       let server = appState.serverProfiles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                        _ = appState.exportMetricsCSV(for: server)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
