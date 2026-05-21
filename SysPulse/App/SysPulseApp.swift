import SwiftData
import SwiftUI

@main
struct SysPulseApp: App {
    @StateObject private var appState = AppState()
    private let modelContainer: ModelContainer

    init() {
        let settings = SettingsStorageService().loadSettings()
        do {
            modelContainer = try SysPulseModelContainerFactory.makeContainer(iCloudSyncEnabled: settings.iCloudSyncEnabled)
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
        }
        .modelContainer(modelContainer)
    }
}
