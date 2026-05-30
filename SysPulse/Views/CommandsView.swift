import SwiftData
import SwiftUI

struct CommandsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: CommandsTab = .catalog
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

            VStack(spacing: 0) {
                // Tab bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CommandsTab.allCases) { tab in
                            FilterChip(label: tab.label, isSelected: selectedTab == tab) {
                                selectedTab = tab
                            }
                        }
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }

                switch selectedTab {
                case .catalog:
                    catalogContent
                case .custom:
                    CustomCommandsContent()
                case .snippets:
                    SnippetsView(presentation: .embedded)
                }
            }
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

    private var catalogContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
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

                if !appState.remoteCommandOutput.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Last Output", systemImage: "terminal")
                                .font(.headline)
                            Text(appState.remoteCommandOutput)
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
            .animation(SysPulseMotion.fade(disabled: appState.shouldReduceMotion), value: appState.remoteCommandOutput.isEmpty)
        }
        .scrollIndicators(.hidden)
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
            appState.postStatus(appState.localized("Select a server before running commands."))
            return
        }

        Task {
            do {
                let output = try await appState.sshClient.run(command.command, on: server)
                await MainActor.run {
                    appState.setRemoteCommandOutput(output)
                }
            } catch {
                await MainActor.run {
                    appState.setRemoteCommandOutput(appState.connectionErrorMessage(error, server: server))
                }
            }
        }
    }
}

// MARK: - Tab enum

private enum CommandsTab: String, CaseIterable, Identifiable {
    case catalog = "Catalog"
    case custom = "My Commands"
    case snippets = "Snippets"

    var id: String { rawValue }
    var label: String { rawValue }
}

// MARK: - Custom Commands Content

private struct CustomCommandsContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<QuickCommand> { $0.isUserDefined == true },
        sort: \QuickCommand.title
    ) private var customCommands: [QuickCommand]

    @State private var isAdding = false
    @State private var editingCommand: QuickCommand?
    @State private var pendingDelete: QuickCommand?
    @State private var showingDeleteAlert = false
    @State private var searchText = ""
    @State private var lastOutput = ""

    private var filtered: [QuickCommand] {
        guard !searchText.isEmpty else { return customCommands }
        return customCommands.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.command.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                PageHeader(
                    title: "My Commands",
                    subtitle: "Custom SSH commands",
                    actionSymbol: "plus"
                ) {
                    guard appState.isProUnlocked else {
                        appState.isPaywallPresented = true
                        return
                    }
                    isAdding = true
                }

                if !appState.isProUnlocked {
                    ProLockedBanner(feature: "Custom Commands")
                } else {
                    TextField("Search my commands", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if filtered.isEmpty {
                        if customCommands.isEmpty {
                            ActionEmptyStateView(
                                title: "No custom commands",
                                message: "Create your own commands to run on any server.",
                                symbol: "plus.rectangle.on.rectangle",
                                actionTitle: "New Command",
                                actionSymbol: "plus"
                            ) { isAdding = true }
                        } else {
                            Text("No results")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, command in
                            CommandCard(command: command, isLocked: false) {
                                runCustom(command)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    pendingDelete = command
                                    showingDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    editingCommand = command
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.cyan)
                            }
                            .listItemEntrance(index: index, disabled: appState.shouldReduceMotion)
                        }
                    }

                    if !lastOutput.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Last Output", systemImage: "terminal")
                                    .font(.headline)
                                Text(lastOutput)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, SysPulseDesign.pagePadding)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $isAdding) {
            CustomCommandFormView()
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .sheet(item: $editingCommand) { cmd in
            CustomCommandFormView(editingCommand: cmd)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .alert("Delete command?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let cmd = pendingDelete { deleteCommand(cmd) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func runCustom(_ command: QuickCommand) {
        guard let server = appState.selectedServer else {
            lastOutput = appState.localized("Select a server before running commands.")
            return
        }
        Task {
            do {
                let output = try await appState.sshClient.run(command.command, on: server)
                await MainActor.run { lastOutput = output.isEmpty ? "Done." : output }
            } catch {
                await MainActor.run {
                    lastOutput = appState.connectionErrorMessage(error, server: server)
                }
            }
        }
    }

    private func deleteCommand(_ command: QuickCommand) {
        modelContext.delete(command)
        try? modelContext.save()
    }
}

// MARK: - Custom Command Form

private struct CustomCommandFormView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editingCommand: QuickCommand?

    @State private var title = ""
    @State private var details = ""
    @State private var command = ""
    @State private var safety: CommandSafetyLevel = .safe

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Clear Nginx cache", text: $title)
                        .autocorrectionDisabled()
                }
                Section("Description") {
                    TextField("What does this command do?", text: $details)
                        .autocorrectionDisabled()
                }
                Section("Command") {
                    TextField("e.g. sudo systemctl reload nginx", text: $command)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                Section("Safety") {
                    Picker("Safety Level", selection: $safety) {
                        ForEach(CommandSafetyLevel.allCases) { level in
                            Text(level.titleKey).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(editingCommand == nil ? "New Command" : "Edit Command")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let cmd = editingCommand {
                title = cmd.title
                details = cmd.details
                command = cmd.command
                safety = cmd.safety
            }
        }
    }

    private func save() {
        if let cmd = editingCommand {
            cmd.title = title
            cmd.details = details
            cmd.command = command
            cmd.safetyRaw = safety.rawValue
        } else {
            let cmd = QuickCommand(
                title: title,
                details: details.isEmpty ? title : details,
                command: command,
                safety: safety,
                isUserDefined: true
            )
            modelContext.insert(cmd)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - CommandCard (unchanged)

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
