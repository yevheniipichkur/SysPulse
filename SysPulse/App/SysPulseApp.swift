import SwiftData
import SwiftUI

@main
struct SysPulseApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.locale, appState.settings.language.locale)
                .preferredColorScheme(appState.preferredColorScheme)
        }
        .modelContainer(
            for: [
                ServerProfile.self,
                TerminalSession.self,
                QuickCommand.self,
                CommandExecution.self,
                ServerGroup.self,
                AlertRule.self,
                ServerEvent.self
            ]
        )
    }
}
