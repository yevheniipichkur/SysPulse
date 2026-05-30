import Foundation
import Citadel

/// Reuses SSH clients per server to avoid repeated handshakes for metrics and commands.
actor SSHSessionPool {
    private struct Entry {
        var client: SSHClient
        var lastUsed: Date
        var leaseCount: Int
    }

    private var entries: [UUID: Entry] = [:]
    private let idleTimeout: TimeInterval
    private var cleanupTask: Task<Void, Never>?

    init(idleTimeout: TimeInterval = 45) {
        self.idleTimeout = idleTimeout
        startCleanupLoop()
    }

    deinit {
        cleanupTask?.cancel()
    }

    func acquire(
        for server: ServerProfile,
        factory: () async throws -> SSHClient
    ) async throws -> SSHClient {
        if var entry = entries[server.id] {
            entry.leaseCount += 1
            entry.lastUsed = .now
            entries[server.id] = entry
            return entry.client
        }

        let client = try await factory()
        entries[server.id] = Entry(client: client, lastUsed: .now, leaseCount: 1)
        return client
    }

    func release(for serverID: UUID) {
        guard var entry = entries[serverID] else { return }
        entry.leaseCount = max(0, entry.leaseCount - 1)
        entry.lastUsed = .now
        entries[serverID] = entry
    }

    func invalidate(for serverID: UUID) async {
        guard let entry = entries.removeValue(forKey: serverID) else { return }
        try? await entry.client.close()
    }

    func invalidateAll() async {
        let clients = entries.values.map(\.client)
        entries.removeAll()
        for client in clients {
            try? await client.close()
        }
    }

    private func startCleanupLoop() {
        cleanupTask?.cancel()
        cleanupTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await evictIdleSessions()
            }
        }
    }

    private func evictIdleSessions() async {
        let now = Date.now
        let staleIDs = entries.compactMap { id, entry -> UUID? in
            guard entry.leaseCount == 0 else { return nil }
            return now.timeIntervalSince(entry.lastUsed) >= idleTimeout ? id : nil
        }
        for id in staleIDs {
            await invalidate(for: id)
        }
    }
}
