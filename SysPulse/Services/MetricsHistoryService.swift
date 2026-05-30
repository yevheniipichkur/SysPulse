import Foundation
import SwiftData

@Model
final class MetricSnapshot {
    var id: UUID = UUID()
    var serverID: UUID = UUID()
    var recordedAt: Date = .now
    var cpuUsage: Double = 0
    var ramUsage: Double = 0
    var diskUsage: Double = 0
    var healthScore: Int = 0

    init(
        id: UUID = UUID(),
        serverID: UUID,
        recordedAt: Date = .now,
        cpuUsage: Double,
        ramUsage: Double,
        diskUsage: Double,
        healthScore: Int
    ) {
        self.id = id
        self.serverID = serverID
        self.recordedAt = recordedAt
        self.cpuUsage = cpuUsage
        self.ramUsage = ramUsage
        self.diskUsage = diskUsage
        self.healthScore = healthScore
    }
}

struct MetricsHistoryService {
    private let retentionDays = 30
    private let maxSnapshotsPerServer = 500

    func record(_ metrics: ServerMetrics, in context: ModelContext) throws {
        let snapshot = MetricSnapshot(
            serverID: metrics.serverID,
            recordedAt: metrics.timestamp,
            cpuUsage: metrics.cpuUsage,
            ramUsage: metrics.ramUsage,
            diskUsage: metrics.diskUsage,
            healthScore: metrics.healthScore
        )
        context.insert(snapshot)
        try context.save()
        try prune(serverID: metrics.serverID, in: context)
    }

    func recentSnapshots(for serverID: UUID, limit: Int = 24, in context: ModelContext) throws -> [MetricSnapshot] {
        let descriptor = FetchDescriptor<MetricSnapshot>(
            predicate: #Predicate { $0.serverID == serverID },
            sortBy: [SortDescriptor(\.recordedAt, order: .forward)]
        )
        let snapshots = try context.fetch(descriptor)
        return Array(snapshots.suffix(limit))
    }

    func applyHistory(to metrics: inout ServerMetrics, in context: ModelContext) throws {
        let snapshots = try recentSnapshots(for: metrics.serverID, limit: 24, in: context)
        guard !snapshots.isEmpty else { return }
        metrics.cpuHistory = snapshots.map(\.cpuUsage)
        metrics.ramHistory = snapshots.map(\.ramUsage)
        metrics.diskHistory = snapshots.map(\.diskUsage)
    }

    private func prune(serverID: UUID, in context: ModelContext) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: .now) ?? .now
        let descriptor = FetchDescriptor<MetricSnapshot>(
            predicate: #Predicate { $0.serverID == serverID }
        )
        let snapshots = try context.fetch(descriptor)
        let sorted = snapshots.sorted { $0.recordedAt > $1.recordedAt }
        for snapshot in sorted.dropFirst(maxSnapshotsPerServer) {
            context.delete(snapshot)
        }
        for snapshot in snapshots where snapshot.recordedAt < cutoff {
            context.delete(snapshot)
        }
        try context.save()
    }
}
