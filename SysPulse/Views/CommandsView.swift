import SwiftUI

struct CommandsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var pendingCommand: QuickCommand?
    @State private var showingConfirmation = false

    private let runner = CommandRunner()

    private var filteredCommands: [QuickCommand] {
        guard !searchText.isEmpty else { return appState.quickCommands }
        return appState.quickCommands.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    PageHeader(
                        title: "Commands",
                        subtitle: "Safe snippets for routine Linux checks.",
                        actionSymbol: "folder.badge.plus"
                    ) {
                        appState.isPaywallPresented = true
                    }

                    TextField("Search commands", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                        CommandCard(command: command, isLocked: isLocked(command)) {
                            run(command)
                        }
                        .listItemEntrance(index: index, disabled: appState.shouldReduceMotion)
                    }

                    if !appState.lastCommandOutput.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Last Output", systemImage: "terminal")
                                    .font(.headline)
                                Text(appState.lastCommandOutput)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, 8)
                .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: filteredCommands.count)
                .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: appState.lastCommandOutput.isEmpty)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("screen_commands")
        .alert("Run dangerous command?", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run", role: .destructive) {
                if let pendingCommand {
                    execute(pendingCommand)
                }
            }
        } message: {
            Text(pendingCommand?.command ?? "")
        }
    }

    private func isLocked(_ command: QuickCommand) -> Bool {
        guard !appState.isProUnlocked else { return false }
        let catalogIndex = appState.quickCommands.firstIndex { $0.id == command.id } ?? Int.max
        return command.isPremium || catalogIndex >= 3
    }

    private func run(_ command: QuickCommand) {
        guard !isLocked(command) else {
            appState.isPaywallPresented = true
            return
        }

        if runner.requiresConfirmation(command) {
            pendingCommand = command
            showingConfirmation = true
        } else {
            execute(command)
        }
    }

    private func execute(_ command: QuickCommand) {
        guard let server = appState.selectedServer else {
            appState.lastCommandOutput = appState.localized("Select a server before running commands.")
            return
        }

        Task {
            do {
                let output = try await appState.sshClient.run(command.command, on: server)
                await MainActor.run {
                    appState.lastCommandOutput = output
                }
            } catch {
                await MainActor.run {
                    appState.lastCommandOutput = error.localizedDescription
                }
            }
        }
    }
}

private struct CommandCard: View {
    var command: QuickCommand
    var isLocked: Bool
    var action: () -> Void

    var body: some View {
        GlassCard(cornerRadius: 22, padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(LocalizedStringKey(command.title))
                                .font(.headline)
                            if command.isPremium {
                                PremiumBadge()
                            }
                        }
                        Text(LocalizedStringKey(command.details))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    SafetyBadge(level: command.safety)
                }

                Text(command.command)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !command.variables.isEmpty {
                    HStack(spacing: 4) {
                        Text("Variables:")
                        Text(command.variables.map { "{\($0)}" }.joined(separator: ", "))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Button(action: action) {
                    Label(isLocked ? LocalizedStringKey("Unlock Pro") : LocalizedStringKey("Run Command"), systemImage: isLocked ? "sparkles" : "play.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(isLocked ? Color.primary : Color.white)
                        .background {
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(isLocked ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.cyan))
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
