import SwiftUI

struct SecurityPrivacyView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Your credentials stay on device", systemImage: "lock.shield.fill")
                                    .font(.headline)
                                securityRow(
                                    symbol: "key.fill",
                                    title: "Keychain storage",
                                    detail: "Passwords and private keys are stored in the iOS Keychain, not in cloud backups of app data."
                                )
                                securityRow(
                                    symbol: "faceid",
                                    title: "Biometric lock",
                                    detail: "Optional Face ID / Touch ID hides the app when you leave SysPulse."
                                )
                                securityRow(
                                    symbol: "icloud",
                                    title: "iCloud sync",
                                    detail: "When enabled, only server profiles sync — never raw passwords in Settings export."
                                )
                                securityRow(
                                    symbol: "bell.badge",
                                    title: "Alerts",
                                    detail: "Threshold checks run on device after refresh. Notifications are scheduled locally."
                                )
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SSH connections")
                                    .font(.headline)
                                Text("SysPulse opens direct SSH/SFTP sessions to your servers. Command output is kept in memory for the active session and is not uploaded to SysPulse servers.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Security & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func securityRow(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.cyan)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
