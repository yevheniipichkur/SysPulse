import CryptoKit
import Foundation
import Security

enum EncryptedProfileSharingError: LocalizedError {
    case emptyPassphrase
    case emptyProfileSet
    case invalidEnvelope
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .emptyPassphrase:
            L10n.string("Enter a sharing passphrase first.")
        case .emptyProfileSet:
            L10n.string("No server profiles to export.")
        case .invalidEnvelope:
            L10n.string("This profile export file is not valid.")
        case .decryptionFailed:
            L10n.string("Could not decrypt profiles. Check the passphrase.")
        }
    }
}

struct EncryptedProfileSharingService {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let currentVersion = 1

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func makeExportFile(profiles: [ServerProfile], passphrase: String) throws -> URL {
        let data = try exportData(profiles: profiles, passphrase: passphrase)
        let filename = "SysPulse-Profiles-\(Self.filenameDateFormatter.string(from: .now)).syspulseprofiles"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    func exportData(profiles: [ServerProfile], passphrase: String) throws -> Data {
        let trimmedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassphrase.isEmpty else { throw EncryptedProfileSharingError.emptyPassphrase }
        guard !profiles.isEmpty else { throw EncryptedProfileSharingError.emptyProfileSet }

        let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let nonce = try AES.GCM.Nonce(data: randomData(count: 12))
        let payload = SharedProfilePayload(
            version: currentVersion,
            exportedAt: .now,
            profiles: profiles.map(SharedProfileSnapshot.init(profile:))
        )
        let plaintext = try encoder.encode(payload)
        let sealedBox = try AES.GCM.seal(plaintext, using: key(passphrase: trimmedPassphrase, salt: salt), nonce: nonce)
        guard let combined = sealedBox.combined else { throw EncryptedProfileSharingError.invalidEnvelope }

        return try encoder.encode(SharedProfileEnvelope(
            version: currentVersion,
            algorithm: "AES.GCM.SHA256",
            salt: salt,
            ciphertext: combined
        ))
    }

    func importProfiles(from url: URL, passphrase: String) throws -> [ServerProfile] {
        let data = try Data(contentsOf: url)
        return try importProfiles(from: data, passphrase: passphrase)
    }

    func importProfiles(from data: Data, passphrase: String) throws -> [ServerProfile] {
        let trimmedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassphrase.isEmpty else { throw EncryptedProfileSharingError.emptyPassphrase }

        let envelope = try decoder.decode(SharedProfileEnvelope.self, from: data)
        guard envelope.algorithm == "AES.GCM.SHA256" else { throw EncryptedProfileSharingError.invalidEnvelope }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: envelope.ciphertext)
            let plaintext = try AES.GCM.open(sealedBox, using: key(passphrase: trimmedPassphrase, salt: envelope.salt))
            let payload = try decoder.decode(SharedProfilePayload.self, from: plaintext)
            return payload.profiles.map { $0.makeServerProfile() }
        } catch {
            throw EncryptedProfileSharingError.decryptionFailed
        }
    }

    private func key(passphrase: String, salt: Data) -> SymmetricKey {
        var material = Data(passphrase.utf8)
        material.append(salt)
        let digest = SHA256.hash(data: material)
        return SymmetricKey(data: digest)
    }

    private func randomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        bytes.withUnsafeMutableBytes { buffer in
            _ = SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        return Data(bytes)
    }

    private static let filenameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct SharedProfileEnvelope: Codable {
    var version: Int
    var algorithm: String
    var salt: Data
    var ciphertext: Data
}

private struct SharedProfilePayload: Codable {
    var version: Int
    var exportedAt: Date
    var profiles: [SharedProfileSnapshot]
}

private struct SharedProfileSnapshot: Codable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authenticationTypeRaw: String
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
            credentialIdentifier: nil,
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
