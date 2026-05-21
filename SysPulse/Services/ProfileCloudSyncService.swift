import CloudKit
import Foundation
import Security

enum ProfileCloudSyncError: LocalizedError {
    case missingSnapshotData
    case unavailableInCurrentBuild(String)

    var shouldDisableSync: Bool {
        switch self {
        case .unavailableInCurrentBuild:
            true
        case .missingSnapshotData:
            false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingSnapshotData:
            L10n.string("iCloud profile snapshot is missing data.")
        case .unavailableInCurrentBuild(let containerIdentifier):
            L10n.string("iCloud sync requires CloudKit entitlement for %@.", containerIdentifier)
        }
    }
}

struct ProfileCloudSyncService {
    private let recordID = CKRecord.ID(recordName: "server-profiles-v1")
    private let recordType = "SysPulseProfileSnapshot"
    private let profilesField = "profilesJSON"
    private let updatedAtField = "updatedAt"
    private let container: CKContainer

    init(containerIdentifier: String = SysPulseModelContainerFactory.iCloudContainerIdentifier) throws {
        guard Self.isCloudKitEntitled(containerIdentifier: containerIdentifier) else {
            throw ProfileCloudSyncError.unavailableInCurrentBuild(containerIdentifier)
        }
        self.container = CKContainer.default()
    }

    func mergeAndUpload(localSnapshots: [CloudServerProfileSnapshot]) async throws -> [CloudServerProfileSnapshot] {
        let remoteSnapshots = try await fetchSnapshots()
        let mergedSnapshots = merge(local: localSnapshots, remote: remoteSnapshots)
        try await saveSnapshots(mergedSnapshots)
        return mergedSnapshots
    }

    func uploadSnapshot(_ snapshots: [CloudServerProfileSnapshot]) async throws {
        try await saveSnapshots(snapshots)
    }

    private func fetchSnapshots() async throws -> [CloudServerProfileSnapshot] {
        guard let record = try await fetchSnapshotRecord() else {
            return []
        }

        let data: Data?
        if let bytes = record[profilesField] as? Data {
            data = bytes
        } else if let bytes = record[profilesField] as? NSData {
            data = Data(referencing: bytes)
        } else {
            data = nil
        }

        guard let data else {
            throw ProfileCloudSyncError.missingSnapshotData
        }

        return try JSONDecoder().decode([CloudServerProfileSnapshot].self, from: data)
    }

    private func saveSnapshots(_ snapshots: [CloudServerProfileSnapshot]) async throws {
        let record = try await fetchSnapshotRecord() ?? CKRecord(recordType: recordType, recordID: recordID)
        record[profilesField] = try JSONEncoder().encode(snapshots) as NSData
        record[updatedAtField] = Date() as NSDate
        _ = try await save(record)
    }

    private func merge(local: [CloudServerProfileSnapshot], remote: [CloudServerProfileSnapshot]) -> [CloudServerProfileSnapshot] {
        var snapshotsByID: [UUID: CloudServerProfileSnapshot] = Dictionary(
            uniqueKeysWithValues: remote.map { ($0.id, $0) }
        )

        for snapshot in local {
            if let existing = snapshotsByID[snapshot.id], existing.updatedAt > snapshot.updatedAt {
                continue
            }
            snapshotsByID[snapshot.id] = snapshot
        }

        return snapshotsByID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func fetchSnapshotRecord() async throws -> CKRecord? {
        let database = container.privateCloudDatabase
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord?, Error>) in
            database.fetch(withRecordID: recordID) { record, error in
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    continuation.resume(returning: nil)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(returning: record)
            }
        }
    }

    private func save(_ record: CKRecord) async throws -> CKRecord {
        let database = container.privateCloudDatabase
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKRecord, Error>) in
            database.save(record) { savedRecord, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let savedRecord else {
                    continuation.resume(throwing: ProfileCloudSyncError.missingSnapshotData)
                    return
                }

                continuation.resume(returning: savedRecord)
            }
        }
    }

    private static func isCloudKitEntitled(containerIdentifier: String) -> Bool {
        let containers = entitlementStrings(for: "com.apple.developer.icloud-container-identifiers")
        let services = entitlementStrings(for: "com.apple.developer.icloud-services")
        return containers.contains(containerIdentifier) && services.contains("CloudKit")
    }

    private static func entitlementStrings(for key: String) -> [String] {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else {
            return []
        }

        if let strings = value as? [String] {
            return strings
        }

        if let string = value as? String {
            return [string]
        }

        return []
    }
}

struct CloudServerProfileSnapshot: Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authenticationTypeRaw: String
    var credentialIdentifier: String?
    var tagsCSV: String
    var groupName: String?
    var icon: String
    var accentHex: String
    var serverTypeRaw: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(profile: ServerProfile) {
        self.id = profile.id
        self.name = profile.name
        self.host = profile.host
        self.port = profile.port
        self.username = profile.username
        self.authenticationTypeRaw = profile.authenticationTypeRaw
        self.credentialIdentifier = profile.credentialIdentifier
        self.tagsCSV = profile.tagsCSV
        self.groupName = profile.groupName
        self.icon = profile.icon
        self.accentHex = profile.accentHex
        self.serverTypeRaw = profile.serverTypeRaw
        self.statusRaw = profile.statusRaw
        self.createdAt = profile.createdAt
        self.updatedAt = profile.updatedAt
    }

    func makeServerProfile() -> ServerProfile {
        let profile = ServerProfile(
            id: id,
            name: name,
            host: host,
            port: port,
            username: username,
            authenticationType: SSHAuthenticationType(rawValue: authenticationTypeRaw) ?? .password,
            credentialIdentifier: credentialIdentifier,
            tags: tagsCSV.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) },
            groupName: groupName,
            icon: icon,
            accentHex: accentHex,
            serverType: ServerType(rawValue: serverTypeRaw) ?? .custom,
            status: ServerStatus(rawValue: statusRaw) ?? .unknown
        )
        profile.createdAt = createdAt
        profile.updatedAt = updatedAt
        return profile
    }
}
