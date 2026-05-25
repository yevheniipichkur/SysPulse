import SwiftData
import SwiftUI
import UIKit

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
            ServersView()
                .tabScreenMotion(tab: .servers, selectedTab: appState.selectedTab, disabled: appState.shouldReduceMotion)
                .tabItem { tabLabel(for: .servers) }
                .tag(AppTab.servers)
            ServerDetailView()
                .tabScreenMotion(tab: .monitor, selectedTab: appState.selectedTab, disabled: appState.shouldReduceMotion)
                .tabItem { tabLabel(for: .monitor) }
                .tag(AppTab.monitor)
            TerminalView()
                .tabScreenMotion(tab: .terminal, selectedTab: appState.selectedTab, disabled: appState.shouldReduceMotion)
                .tabItem { tabLabel(for: .terminal) }
                .tag(AppTab.terminal)
            SFTPFilesView()
                .tabScreenMotion(tab: .sftp, selectedTab: appState.selectedTab, disabled: appState.shouldReduceMotion)
                .tabItem { tabLabel(for: .sftp) }
                .tag(AppTab.sftp)
            SettingsView()
                .tabScreenMotion(tab: .settings, selectedTab: appState.selectedTab, disabled: appState.shouldReduceMotion)
                .tabItem { tabLabel(for: .settings) }
                .tag(AppTab.settings)
        }
        .background(TabBarAccessibilityConfigurator())
        .onChange(of: appState.selectedTab) {
            appState.haptic(.light)
        }
    }

    private func tabLabel(for tab: AppTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image(systemName: tab.symbol)
        }
        .accessibilityLabel(Text(tab.title))
        .accessibilityIdentifier(tab.tabAccessibilityIdentifier)
    }
}

private struct TabBarAccessibilityConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.applySoon()
    }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applySoon()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applySoon()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.apply()
            }
        }

        private func apply() {
            guard let tabBarController = findTabBarController() else { return }
            let tabs = AppTab.allCases
            for (index, item) in (tabBarController.tabBar.items ?? []).enumerated() where tabs.indices.contains(index) {
                let tab = tabs[index]
                let title = NSLocalizedString(tab.titleText, comment: "")
                item.title = title
                item.accessibilityLabel = title
                item.accessibilityIdentifier = tab.tabAccessibilityIdentifier
            }
        }

        private func findTabBarController() -> UITabBarController? {
            var current: UIViewController? = self
            while let candidate = current {
                if let tabBarController = candidate as? UITabBarController {
                    return tabBarController
                }
                current = candidate.parent
            }
            return view.window?.rootViewController?.descendantTabBarController()
        }
    }
}

private extension UIViewController {
    func descendantTabBarController() -> UITabBarController? {
        if let tabBarController = self as? UITabBarController {
            return tabBarController
        }
        for child in children {
            if let tabBarController = child.descendantTabBarController() {
                return tabBarController
            }
        }
        if let presentedViewController,
           let tabBarController = presentedViewController.descendantTabBarController() {
            return tabBarController
        }
        return nil
    }
}
