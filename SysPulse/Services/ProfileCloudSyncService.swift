import CloudKit
import Foundation

enum ProfileCloudSyncError: LocalizedError {
    case missingSnapshotData
    case unavailableInCurrentBuild(String)
    case accountUnavailable(CKAccountStatus)

    var shouldDisableSync: Bool {
        switch self {
        case .unavailableInCurrentBuild, .accountUnavailable:
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
        case .accountUnavailable(let status):
            switch status {
            case .noAccount:
                L10n.string("iCloud account is not available. Sign in to iCloud and try again.")
            case .restricted:
                L10n.string("iCloud sync is restricted on this device.")
            case .temporarilyUnavailable:
                L10n.string("iCloud is temporarily unavailable. Try again later.")
            case .couldNotDetermine:
                L10n.string("iCloud account status could not be verified.")
            case .available:
                L10n.string("iCloud account is available.")
            @unknown default:
                L10n.string("iCloud account status could not be verified.")
            }
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
        let diagnostic = Self.entitlementDiagnostic(containerIdentifier: containerIdentifier)
        guard diagnostic.canAttemptSync else {
            throw ProfileCloudSyncError.unavailableInCurrentBuild(containerIdentifier)
        }
        self.container = CKContainer(identifier: containerIdentifier)
    }

    func preflight() async throws {
        try await validateAccountStatus()
    }

    func mergeAndUpload(localSnapshots: [CloudServerProfileSnapshot]) async throws -> [CloudServerProfileSnapshot] {
        try await validateAccountStatus()
        let remoteSnapshots = try await fetchSnapshots()
        let mergedSnapshots = merge(local: localSnapshots, remote: remoteSnapshots)
        try await saveSnapshots(mergedSnapshots)
        return mergedSnapshots
    }

    func uploadSnapshot(_ snapshots: [CloudServerProfileSnapshot]) async throws {
        try await validateAccountStatus()
        try await saveSnapshots(snapshots)
    }

    private func validateAccountStatus() async throws {
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKAccountStatus, Error>) in
            container.accountStatus { status, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: status)
            }
        }

        guard status == .available else {
            throw ProfileCloudSyncError.accountUnavailable(status)
        }
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

    static func entitlementDiagnostic(
        containerIdentifier: String = SysPulseModelContainerFactory.iCloudContainerIdentifier
    ) -> CloudKitEntitlementDiagnostic {
        guard let profile = embeddedProvisioningProfileText() else {
            return CloudKitEntitlementDiagnostic(
                containerIdentifier: containerIdentifier,
                verificationSource: .unavailable,
                hasEmbeddedProvisioningProfile: false,
                hasContainerIdentifier: false,
                hasCloudKitService: false
            )
        }

        return CloudKitEntitlementDiagnostic(
            containerIdentifier: containerIdentifier,
            verificationSource: .embeddedProvisioningProfile,
            hasEmbeddedProvisioningProfile: true,
            hasContainerIdentifier: profile.contains(containerIdentifier),
            hasCloudKitService: profile.contains("<string>CloudKit</string>")
        )
    }

    private static func embeddedProvisioningProfileText() -> String? {
        guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: profileURL),
              let profile = String(data: data, encoding: .isoLatin1) ?? String(data: data, encoding: .utf8) else {
            return nil
        }

        return profile
    }
}

struct CloudKitEntitlementDiagnostic: Equatable {
    enum VerificationSource: Equatable {
        case embeddedProvisioningProfile
        case unavailable
    }

    var containerIdentifier: String
    var verificationSource: VerificationSource
    var hasEmbeddedProvisioningProfile: Bool
    var hasContainerIdentifier: Bool
    var hasCloudKitService: Bool

    var isReady: Bool {
        verificationSource != .unavailable && hasContainerIdentifier && hasCloudKitService
    }

    var canAttemptSync: Bool {
        isReady || verificationSource == .unavailable
    }

    var messageKey: String {
        if isReady {
            return "Signed build is ready for iCloud sync."
        }
        if verificationSource == .unavailable {
            return "CloudKit entitlement could not be verified at runtime."
        }
        if verificationSource == .embeddedProvisioningProfile && !hasEmbeddedProvisioningProfile {
            return "Provisioning profile is missing in this build."
        }
        if !hasContainerIdentifier {
            return "iCloud container is missing from the provisioning profile."
        }
        if !hasCloudKitService {
            return "CloudKit service is missing from the provisioning profile."
        }
        return "iCloud sync is not available in this build."
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
