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
        .overlay(alignment: .top) {
            if let toast = appState.statusToast {
                StatusToastView(toast: toast)
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .animation(SysPulseMotion.fade(disabled: appState.shouldReduceMotion), value: appState.statusToast?.id)
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
        .transaction { transaction in
            guard appState.shouldReduceMotion else { return }
            transaction.animation = nil
            transaction.disablesAnimations = true
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
                    .foregroundStyle(SysPulseDesign.accent)

                VStack(spacing: 7) {
                    Text(LocalizedStringKey("SysPulse Locked"))
                        .font(SysPulseDesign.displayFont(size: 24, weight: .bold))
                    Text(LocalizedStringKey("Unlock to view saved server profiles and credentials."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .accessibilityElement(children: .combine)

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
                        .background(
                            LinearGradient(colors: [SysPulseDesign.actionStart, SysPulseDesign.actionEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: SysPulseDesign.controlRadius, style: .continuous)
                        )
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

    private var showsTabBar: Bool {
        appState.selectedTab != .terminal
    }

    var body: some View {
        ZStack {
            AppBackground()

            tabContent
                .tabScreenMotion(tab: appState.selectedTab, selectedTab: appState.selectedTab, disabled: appState.shouldReduceMotion)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsTabBar {
                FloatingTabBar(selection: $appState.selectedTab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: showsTabBar)
        .tint(SysPulseDesign.accent)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch appState.selectedTab {
        case .servers:
            ServersView()
        case .terminal:
            TerminalView()
        case .sftp:
            SFTPFilesView()
        case .settings:
            SettingsView()
        }
    }
}
