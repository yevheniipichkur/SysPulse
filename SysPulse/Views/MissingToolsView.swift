import SwiftUI
import UIKit

struct MissingToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @State private var distribution: LinuxDistribution = .debian
    @State private var showRunConfirmation = false

    private var tools: [MissingTool] {
        appState.packageDetector.missingTools(from: appState.packageStatuses)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        PageHeader(
                            title: "Missing Tools",
                            subtitle: "Preview install commands before running anything.",
                            actionSymbol: nil,
                            action: nil
                        )

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Diagnostics", systemImage: "stethoscope")
                                    .font(.headline)
                                ForEach(appState.packageDetector.checkCommandsPreview(), id: \.self) { command in
                                    Text(command)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                GlassPrimaryButton(title: "Run Diagnostics", symbol: "stethoscope") {
                                    appState.refreshPackageStatuses(for: appState.selectedServer)
                                }
                            }
                        }

                        if tools.isEmpty {
                            EmptyStateView(
                                title: "All tools installed",
                                message: "This server supports full SysPulse diagnostics.",
                                symbol: "checkmark.seal"
                            )
                        } else {
                            ForEach(tools) { tool in
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Label(tool.commandName, systemImage: "xmark.circle")
                                                .font(.headline)
                                                .foregroundStyle(.orange)
                                            Spacer()
                                            Text(tool.packageName)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(LocalizedStringKey(tool.reason))
                                            .font(.callout)
                                        HStack(spacing: 4) {
                                            Text("Unavailable:")
                                            ForEach(tool.unavailableFeatures, id: \.self) { feature in
                                                Text(LocalizedStringKey(feature))
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Distribution", selection: $distribution) {
                                    ForEach(LinuxDistribution.allCases) { item in
                                        Text(item.titleKey).tag(item)
                                    }
                                }
                                .pickerStyle(.menu)

                                Text(distribution.installCommand)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                                Text("Docker is never installed automatically. SysPulse only shows instructions and asks for explicit confirmation.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 12) {
                                    Button {
                                        UIPasteboard.general.string = distribution.installCommand
                                    } label: {
                                        Label("Copy Command", systemImage: "doc.on.doc")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 13)
                                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        showRunConfirmation = true
                                    } label: {
                                        Label("Run via SSH", systemImage: "terminal")
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 13)
                                            .foregroundStyle(.white)
                                            .background(.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Packages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("Run install command?", isPresented: $showRunConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) {
                appState.runRemoteCommand(distribution.installCommand, on: appState.selectedServer)
            }
        } message: {
            Text("SysPulse will run the command only on the selected remote server over SSH after this confirmation.")
        }
    }
}
