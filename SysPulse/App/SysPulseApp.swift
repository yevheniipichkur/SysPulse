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
        }
        .modelContainer(modelContainer)
    }
}
