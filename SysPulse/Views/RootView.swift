import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.hasSeenOnboarding {
                MainShellView()
            } else {
                OnboardingView()
            }
        }
        .sheet(isPresented: $appState.isPaywallPresented) {
            PaywallView()
                .presentationDetents([.large])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $appState.isDebugMenuPresented) {
            DebugMenuView()
                .presentationDetents([.large])
                .presentationCornerRadius(34)
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            Tab(AppTab.servers.title, systemImage: AppTab.servers.symbol, value: AppTab.servers) {
                ServersView()
            }
            Tab(AppTab.monitor.title, systemImage: AppTab.monitor.symbol, value: AppTab.monitor) {
                ServerDetailView()
            }
            Tab(AppTab.terminal.title, systemImage: AppTab.terminal.symbol, value: AppTab.terminal) {
                TerminalView()
            }
            Tab(AppTab.commands.title, systemImage: AppTab.commands.symbol, value: AppTab.commands) {
                CommandsView()
            }
            Tab(AppTab.settings.title, systemImage: AppTab.settings.symbol, value: AppTab.settings) {
                SettingsView()
            }
        }
        .onChange(of: appState.selectedTab) {
            appState.haptic(.light)
        }
    }
}
