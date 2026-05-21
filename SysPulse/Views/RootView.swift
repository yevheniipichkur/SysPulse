import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.hasSeenOnboarding {
                MainShellView()
            } else {
                OnboardingView()
            }
        }
        .overlay {
            if appState.shouldShowSecurityLock {
                SecurityLockView(
                    isAuthenticating: appState.isSecurityPromptInProgress,
                    message: appState.securityLockMessage
                ) {
                    Task {
                        await appState.unlockAppIfNeeded(force: true)
                    }
                }
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $appState.isPaywallPresented) {
            PaywallView(storeKit: appState.storeKit)
                .presentationDetents([.large])
                .presentationCornerRadius(34)
        }
        .sheet(isPresented: $appState.isDebugMenuPresented) {
            DebugMenuView()
                .presentationDetents([.large])
                .presentationCornerRadius(34)
        }
        .onAppear {
            appState.configureProfileRepository(modelContext: modelContext)
            Task {
                await appState.unlockAppIfNeeded()
            }
        }
        .onChange(of: scenePhase) {
            appState.handleScenePhase(scenePhase)
        }
        .onChange(of: appState.hasSeenOnboarding) {
            Task {
                await appState.unlockAppIfNeeded(force: true)
            }
        }
    }
}

private struct SecurityLockView: View {
    var isAuthenticating: Bool
    var message: String
    var unlock: () -> Void

    var body: some View {
        ZStack {
            AppBackground()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.cyan)

                VStack(spacing: 7) {
                    Text("SysPulse Locked")
                        .font(.title2.weight(.bold))
                    Text("Unlock to view saved server profiles and credentials.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !message.isEmpty {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: unlock) {
                    Label(
                        isAuthenticating ? LocalizedStringKey("Authenticating") : LocalizedStringKey("Unlock"),
                        systemImage: "faceid"
                    )
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(.cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating)
            }
            .padding(24)
            .frame(maxWidth: 360)
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
