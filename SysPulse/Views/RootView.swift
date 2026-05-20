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
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            Group {
                switch appState.selectedTab {
                case .servers:
                    ServersView()
                case .monitor:
                    ServerDetailView()
                case .terminal:
                    TerminalView()
                case .commands:
                    CommandsView()
                case .settings:
                    SettingsView()
                }
            }
            .safeAreaPadding(.bottom, 88)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar()
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(.clear)
        }
    }
}

struct FloatingTabBar: View {
    @EnvironmentObject private var appState: AppState
    @Namespace private var namespace

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabBar(showLabels: true)
            tabBar(showLabels: false)
        }
    }

    private func tabBar(showLabels: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        appState.selectedTab = tab
                    }
                    appState.haptic(.light)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .semibold))
                        if showLabels {
                            Text(tab.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                    .frame(minWidth: showLabels ? 58 : 44, maxWidth: .infinity)
                    .frame(height: showLabels ? 58 : 52)
                    .foregroundStyle(appState.selectedTab == tab ? .primary : .secondary)
                    .background {
                        if appState.selectedTab == tab {
                            RoundedRectangle(cornerRadius: showLabels ? 20 : 18, style: .continuous)
                                .fill(.thinMaterial)
                                .matchedGeometryEffect(id: "selectedTab", in: namespace)
                                .overlay(
                                    RoundedRectangle(cornerRadius: showLabels ? 20 : 18, style: .continuous)
                                        .stroke(.white.opacity(0.22), lineWidth: 1)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: showLabels ? 620 : 360)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 16)
        }
    }
}
