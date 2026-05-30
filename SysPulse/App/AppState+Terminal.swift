import Foundation
import SwiftData

extension AppState {
    func jumpHost(for server: ServerProfile) -> ServerProfile? {
        guard let jumpID = server.jumpServerID, jumpID != server.id else { return nil }
        return serverProfiles.first { $0.id == jumpID }
    }

    func terminalHistory(for server: ServerProfile, limit: Int = 24) -> [TerminalCommandEntry] {
        guard let modelContext else { return [] }
        let serverID = server.id
        let descriptor = FetchDescriptor<TerminalCommandEntry>(
            predicate: #Predicate { $0.serverID == serverID },
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return Array(entries.prefix(limit))
    }

    func terminalFavorites(for server: ServerProfile) -> [TerminalCommandEntry] {
        guard let modelContext else { return [] }
        let serverID = server.id
        let descriptor = FetchDescriptor<TerminalCommandEntry>(
            predicate: #Predicate { $0.serverID == serverID && $0.isFavorite },
            sortBy: [SortDescriptor(\.command, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func recordTerminalCommand(_ command: String, server: ServerProfile) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 512, let modelContext else { return }

        let serverID = server.id
        let descriptor = FetchDescriptor<TerminalCommandEntry>(
            predicate: #Predicate { $0.serverID == serverID && $0.command == trimmed }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastUsedAt = .now
        } else {
            modelContext.insert(TerminalCommandEntry(serverID: serverID, command: trimmed))
        }
        try? modelContext.save()
    }

    func toggleTerminalFavorite(_ entry: TerminalCommandEntry) {
        entry.isFavorite.toggle()
        try? modelContext?.save()
    }

    func toggleTerminalFavorite(command: String, server: ServerProfile) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let modelContext else { return }
        let serverID = server.id
        let descriptor = FetchDescriptor<TerminalCommandEntry>(
            predicate: #Predicate { $0.serverID == serverID && $0.command == trimmed }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.isFavorite.toggle()
            existing.lastUsedAt = .now
        } else {
            modelContext.insert(
                TerminalCommandEntry(serverID: serverID, command: trimmed, isFavorite: true)
            )
        }
        try? modelContext.save()
    }

    func clearTerminalHistory(for server: ServerProfile) {
        guard let modelContext else { return }
        let serverID = server.id
        let descriptor = FetchDescriptor<TerminalCommandEntry>(
            predicate: #Predicate { $0.serverID == serverID && !$0.isFavorite }
        )
        if let entries = try? modelContext.fetch(descriptor) {
            entries.forEach { modelContext.delete($0) }
            try? modelContext.save()
        }
    }

    func lastTerminalCommand(for server: ServerProfile) -> String? {
        terminalHistory(for: server, limit: 1).first?.command
    }
}
