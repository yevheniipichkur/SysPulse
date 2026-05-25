import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Your Linux servers, beautifully monitored.",
            subtitle: "Monitor CPU, RAM, disks, Docker and services from your iPhone.",
            symbol: "waveform.path.ecg",
            accent: .cyan
        ),
        OnboardingPage(
            title: "Secure SSH Terminal.",
            subtitle: "Connect to your machines with saved profiles, Face ID and encrypted credentials.",
            symbol: "terminal",
            accent: .green
        ),
        OnboardingPage(
            title: "Remote File Manager.",
            subtitle: "Browse, upload and download files on your Linux servers over a secure SFTP connection.",
            symbol: "folder",
            accent: .blue
        ),
        OnboardingPage(
            title: "Unlock SysPulse Pro.",
            subtitle: "Unlimited servers, Docker monitoring, widgets, Live Activities and premium terminal themes.",
            symbol: "sparkles",
            accent: .purple
        )
    ]

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 28) {
                            Spacer()

                            ZStack {
                                Circle()
                                    .fill(item.accent.opacity(0.18))
                                    .frame(width: 180, height: 180)
                                Image(systemName: item.symbol)
                                    .font(.system(size: 72, weight: .semibold))
                                    .foregroundStyle(item.accent)
                            }
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: item.accent.opacity(0.28), radius: 36)

                            VStack(spacing: 14) {
                                Text(LocalizedStringKey(item.title))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(4)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(LocalizedStringKey(item.subtitle))
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 320)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 28)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                VStack(spacing: 12) {
                    GlassPrimaryButton(
                        title: page == pages.count - 1 ? "Start SysPulse" : "Continue",
                        symbol: page == pages.count - 1 ? "terminal.fill" : "arrow.right"
                    ) {
                        if page == pages.count - 1 {
                            appState.completeOnboarding()
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                page += 1
                            }
                        }
                    }

                    Button {
                        appState.completeOnboarding()
                    } label: {
                        if page == pages.count - 1 {
                            Label("Add your first server", systemImage: "server.rack")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            Label("Skip for now", systemImage: "forward.end")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 34)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("screen_onboarding")
    }
}

private struct OnboardingPage {
    var title: String
    var subtitle: String
    var symbol: String
    var accent: Color
}
