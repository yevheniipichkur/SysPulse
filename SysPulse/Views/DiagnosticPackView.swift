import SwiftUI

struct DiagnosticPackView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var server: ServerProfile
    var result: DiagnosticPackResult

    @State private var pendingCommand: String?
    @State private var showingConfirmation = false
    @State private var confirmationMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        if !appState.isProUnlocked {
                            ProLockedBanner(
                                feature: "Diagnostic pack",
                                message: "Automated checks with safe runbook commands for your fleet."
                            )
                        } else {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label(LocalizedStringKey("Diagnostic pack"), systemImage: "stethoscope")
                                        .font(.headline)
                                    Text(appState.localized("Read-only checks and suggested next steps for %@.", server.name))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            ForEach(result.findings) { finding in
                                findingCard(finding)
                            }

                            ForEach(Array(result.rawSections.enumerated()), id: \.offset) { _, section in
                                GlassCard(cornerRadius: 20, padding: 14) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(section.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(section.output)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(LocalizedStringKey("Diagnostics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Confirmation required", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingCommand = nil
                }
                Button("Confirm", role: .destructive) {
                    if let pendingCommand {
                        appState.runRemoteCommand(pendingCommand, on: server)
                    }
                    pendingCommand = nil
                }
            } message: {
                Text(confirmationMessage)
            }
        }
    }

    @ViewBuilder
    private func findingCard(_ finding: DiagnosticFinding) -> some View {
        GlassCard(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label(finding.title, systemImage: finding.symbol)
                    .font(.headline)
                    .foregroundStyle(severityColor(finding.severity))
                Text(finding.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let command = finding.suggestedCommand,
                   !CommandRunner.containsDangerousToken(command) {
                    Button {
                        runSuggested(command)
                    } label: {
                        Label(LocalizedStringKey("Run suggested command"), systemImage: "terminal")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14))
                }
            }
        }
    }

    private func runSuggested(_ command: String) {
        guard appState.isProUnlocked else {
            appState.presentPaywall(
                feature: "Diagnostic pack",
                message: "Run safe runbook commands from diagnostic findings."
            )
            return
        }
        if CommandRunner.containsDangerousToken(command) {
            return
        }
        let analysis = CommandSafetyAnalyzer().analyze(command)
        if analysis.requiresConfirmation {
            confirmationMessage = appState.localized("Run this command on %@?", server.name)
            pendingCommand = command
            showingConfirmation = true
        } else {
            appState.runRemoteCommand(command, on: server)
        }
    }

    private func severityColor(_ severity: String) -> Color {
        switch severity {
        case "Dangerous": .red
        case "Warning": .orange
        default: .green
        }
    }
}
