import Foundation
import SwiftData

struct ServerEventService {
    func record(
        serverID: UUID,
        title: String,
        details: String,
        severity: String,
        in context: ModelContext
    ) throws {
        context.insert(
            ServerEvent(
                serverID: serverID,
                title: title,
                details: details,
                severity: severity
            )
        )
        try context.save()
        try prune(serverID: serverID, in: context)
    }

    func recentEvents(for serverID: UUID, limit: Int = 12, in context: ModelContext) throws -> [ServerEvent] {
        let descriptor = FetchDescriptor<ServerEvent>(
            predicate: #Predicate { $0.serverID == serverID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return Array(try context.fetch(descriptor).prefix(limit))
    }

    private func prune(serverID: UUID, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ServerEvent>(
            predicate: #Predicate { $0.serverID == serverID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let events = try context.fetch(descriptor)
        for event in events.dropFirst(40) {
            context.delete(event)
        }
        try context.save()
    }
}
