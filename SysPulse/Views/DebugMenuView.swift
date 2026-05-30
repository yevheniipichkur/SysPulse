import SwiftUI

struct DebugMenuView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var authorizedUntilText: String {
        let date = Date(timeIntervalSince1970: appState.debugMenuAuthorizedUntil)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard(cornerRadius: 22, padding: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(LocalizedStringKey("Debug session"), systemImage: "checkmark.shield")
                                    .font(.headline)
                                Text(appState.localized("Authorized until %@", authorizedUntilText))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(appState.localized("Password file: debug-gate.txt on GitHub"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        debugSection("Demo", symbol: "play.rectangle") {
                            Toggle(LocalizedStringKey("Demo mode"), isOn: demoModeBinding)
                            Button(LocalizedStringKey("Add demo servers")) {
                                appState.installDebugDemoServers()
                            }
                            .buttonStyle(.bordered)
                            Button(LocalizedStringKey("Remove demo servers"), role: .destructive) {
                                appState.removeDebugDemoServers()
                            }
                            .buttonStyle(.bordered)
                        }

                        debugSection("Pro", symbol: "sparkles") {
                            Toggle(LocalizedStringKey("Force Pro (persistent)"), isOn: forceProBinding)
                            Text(LocalizedStringKey("Unlocks all Pro gates until turned off or subscription is active."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        debugSection("App state", symbol: "wrench.and.screwdriver") {
                            Button(LocalizedStringKey("Reset onboarding & Pro tour")) {
                                appState.resetOnboardingForDebug()
                            }
                            .buttonStyle(.bordered)
                            Button(LocalizedStringKey("Bypass biometric lock")) {
                                appState.bypassBiometricLockForDebug()
                            }
                            .buttonStyle(.bordered)
                            Button(LocalizedStringKey("Reload servers from storage")) {
                                appState.reloadProfilesFromRepository()
                                appState.postStatus(appState.localized("Profiles reloaded."), style: .info)
                            }
                            .buttonStyle(.bordered)
                        }

                        debugSection("Session", symbol: "door.left.hand.open") {
                            Button(LocalizedStringKey("Lock debug menu"), role: .destructive) {
                                appState.revokeDebugMenuAuthorization()
                                appState.debugDemoModeEnabled = false
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(SysPulseDesign.pagePadding)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(LocalizedStringKey("Debug menu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizedStringKey("Done")) { dismiss() }
                }
            }
        }
    }

    private var demoModeBinding: Binding<Bool> {
        Binding {
            appState.debugDemoModeEnabled
        } set: { value in
            appState.setDebugDemoModeEnabled(value)
        }
    }

    private var forceProBinding: Binding<Bool> {
        Binding {
            appState.settings.forceProOverride
        } set: { value in
            appState.setForceProOverride(value)
        }
    }

    private func debugSection<Content: View>(_ title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(cornerRadius: 22, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
