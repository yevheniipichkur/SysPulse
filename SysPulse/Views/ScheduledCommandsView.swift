import SwiftData
import SwiftUI

struct ScheduledCommandsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScheduledCommand.nextRunAt, order: .forward) private var commands: [ScheduledCommand]

    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        if !appState.isProUnlocked {
                            ProLockedBanner(
                                feature: "Scheduled commands",
                                message: "Automate safe read-only checks while SysPulse is active."
                            )
                        } else {
                            ProEmbeddedHeader(
                                title: "Scheduled commands",
                                subtitle: "Safe read-only commands run when the app is active",
                                symbol: "clock.arrow.circlepath",
                                actionSymbol: "plus"
                            ) {
                                isAdding = true
                            }

                            Text("Commands must be safe (no rm, reboot, etc.). Minimum interval is 15 minutes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if commands.isEmpty {
                                ActionEmptyStateView(
                                    title: "No schedules",
                                    message: "Schedule uptime checks, disk usage snapshots or custom safe scripts.",
                                    symbol: "clock.arrow.circlepath",
                                    actionTitle: "Add schedule",
                                    actionSymbol: "plus"
                                ) { isAdding = true }
                            } else {
                                ForEach(commands) { command in
                                    ScheduledCommandRow(command: command, serverName: serverName(for: command))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(LocalizedStringKey("Schedules"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isAdding) {
                ScheduledCommandFormView()
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(32)
            }
        }
    }

    private func serverName(for command: ScheduledCommand) -> String {
        appState.serverProfiles.first(where: { $0.id == command.serverID })?.name ?? appState.localized("Unknown server")
    }
}

private struct ScheduledCommandRow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    var command: ScheduledCommand
    var serverName: String

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(command.title)
                            .font(.headline)
                        Text(serverName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { command.isEnabled },
                        set: { command.isEnabled = $0; try? modelContext.save() }
                    ))
                    .labelsHidden()
                }

                Text(command.command)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(appState.localized("Every %lld min", Int64(command.intervalMinutes)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(appState.localized("Next: %@", command.nextRunAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button(role: .destructive) {
                    modelContext.delete(command)
                    try? modelContext.save()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ScheduledCommandFormView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var command = "uptime"
    @State private var intervalMinutes = 60
    @State private var selectedServerID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    Picker("Server", selection: $selectedServerID) {
                        Text("Select server").tag(Optional<UUID>.none)
                        ForEach(appState.serverProfiles) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                }
                Section("Schedule") {
                    TextField("Title", text: $title)
                    TextField("Command", text: $command)
                        .font(.caption.monospaced())
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Picker("Interval", selection: $intervalMinutes) {
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("1 hour").tag(60)
                        Text("6 hours").tag(360)
                        Text("24 hours").tag(1440)
                    }
                }
            }
            .navigationTitle("New schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                selectedServerID = appState.selectedServer?.id ?? appState.serverProfiles.first?.id
            }
        }
    }

    private var canSave: Bool {
        guard let selectedServerID,
              !title.trimmingCharacters(in: .whitespaces).isEmpty,
              ScheduledCommandService().validate(command: command) else { return false }
        return appState.serverProfiles.contains { $0.id == selectedServerID }
    }

    private func save() {
        guard let selectedServerID, canSave else { return }
        let item = ScheduledCommand(
            serverID: selectedServerID,
            title: title.trimmingCharacters(in: .whitespaces),
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            intervalMinutes: max(intervalMinutes, 15)
        )
        modelContext.insert(item)
        try? modelContext.save()
        dismiss()
    }
}
