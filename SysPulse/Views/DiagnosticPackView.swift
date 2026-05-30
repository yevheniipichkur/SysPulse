import SwiftUI

struct DiagnosticPackView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var server: ServerProfile
    var result: DiagnosticPackResult

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Diagnostic pack", systemImage: "stethoscope")
                                    .font(.headline)
                                Text("Read-only checks and suggested next steps for \(server.name).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        ForEach(result.findings) { finding in
                            GlassCard(cornerRadius: 20, padding: 14) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(finding.title, systemImage: finding.symbol)
                                        .font(.headline)
                                        .foregroundStyle(severityColor(finding.severity))
                                    Text(finding.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if let command = finding.suggestedCommand {
                                        Button {
                                            appState.runRemoteCommand(command, on: server)
                                        } label: {
                                            Label("Run suggested command", systemImage: "terminal")
                                                .font(.caption.weight(.bold))
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14))
                                    }
                                }
                            }
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
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
