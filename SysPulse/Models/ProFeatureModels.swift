import Foundation
import SwiftData

// MARK: - SSH Tunnel

@Model
final class SSHTunnel: Identifiable {
    var id: UUID = UUID()
    var label: String = ""
    var serverID: UUID?
    var localPort: Int = 8080
    var remoteHost: String = "localhost"
    var remotePort: Int = 80
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        label: String,
        serverID: UUID? = nil,
        localPort: Int,
        remoteHost: String,
        remotePort: Int
    ) {
        self.id = id
        self.label = label
        self.serverID = serverID
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.createdAt = .now
    }

    /// The equivalent desktop SSH command for this tunnel.
    func sshCommand(server: ServerProfile) -> String {
        "ssh -L \(localPort):\(remoteHost):\(remotePort) \(server.username)@\(server.host) -p \(server.port)"
    }
}

// MARK: - Command Snippet

@Model
final class CommandSnippet: Identifiable {
    var id: UUID = UUID()
    var title: String = ""
    var body: String = ""
    var category: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        category: String = ""
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.createdAt = .now
        self.updatedAt = .now
    }
}

// MARK: - SSH Key Pair

enum SSHKeyType: String, CaseIterable, Identifiable, Codable, Hashable {
    case ed25519 = "ED25519"
    case rsa4096 = "RSA 4096"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .ed25519: "key.fill"
        case .rsa4096: "lock.fill"
        }
    }
}

@Model
final class SSHKeyPair: Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var publicKey: String = ""
    var keychainAccount: String = ""
    var keyTypeRaw: String = "ED25519"
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        publicKey: String,
        keychainAccount: String,
        keyType: SSHKeyType = .ed25519
    ) {
        self.id = id
        self.name = name
        self.publicKey = publicKey
        self.keychainAccount = keychainAccount
        self.keyTypeRaw = keyType.rawValue
        self.createdAt = .now
    }

    var keyType: SSHKeyType {
        get { SSHKeyType(rawValue: keyTypeRaw) ?? .ed25519 }
        set { keyTypeRaw = newValue.rawValue }
    }
}
