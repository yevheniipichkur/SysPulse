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
                        .background(
                            LinearGradient(colors: [SysPulseDesign.actionStart, SysPulseDesign.actionEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
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

    var body: some View {
        ZStack {
            AppBackground()

            TabView(selection: $appState.selectedTab) {
                ServersView()
                    .tabScreenMotion(tab: .servers, selectedTab: appState.selectedTab, disabled: appState.shouldReduceMotion)
                    .tabItem { tabLabel(for: .servers) }
                    .tag(AppTab.servers)
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
            .tint(SysPulseDesign.accent)
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

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
            applySoon()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.apply()
            }
        }

        private func apply() {
            guard let tabBarController = findTabBarController() else { return }
            applyAppearance(to: tabBarController.tabBar)
            let tabs = AppTab.allCases
            for (index, item) in (tabBarController.tabBar.items ?? []).enumerated() where tabs.indices.contains(index) {
                let tab = tabs[index]
                let title = NSLocalizedString(tab.titleText, comment: "")
                item.title = title
                item.accessibilityLabel = title
                item.accessibilityIdentifier = tab.tabAccessibilityIdentifier
            }
        }

        private func applyAppearance(to tabBar: UITabBar) {
            let isDark = tabBar.traitCollection.userInterfaceStyle == .dark
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: isDark ? .systemUltraThinMaterialDark : .systemThinMaterialLight)
            appearance.backgroundColor = isDark
                ? UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 0.82)
                : UIColor(red: 0.97, green: 0.99, blue: 1.00, alpha: 0.92)

            let selectedColor = isDark
                ? UIColor(red: 0.20, green: 0.76, blue: 0.92, alpha: 1)
                : UIColor(red: 0.00, green: 0.38, blue: 0.58, alpha: 1)
            let normalColor = isDark
                ? UIColor.white.withAlphaComponent(0.74)
                : UIColor(red: 0.10, green: 0.15, blue: 0.20, alpha: 0.68)
            styleTabItemAppearance(appearance.stackedLayoutAppearance, selectedColor: selectedColor, normalColor: normalColor)
            styleTabItemAppearance(appearance.inlineLayoutAppearance, selectedColor: selectedColor, normalColor: normalColor)
            styleTabItemAppearance(appearance.compactInlineLayoutAppearance, selectedColor: selectedColor, normalColor: normalColor)

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.isTranslucent = true
        }

        private func styleTabItemAppearance(
            _ itemAppearance: UITabBarItemAppearance,
            selectedColor: UIColor,
            normalColor: UIColor
        ) {
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: normalColor]
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
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
