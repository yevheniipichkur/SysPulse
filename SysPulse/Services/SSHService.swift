import Foundation
import Citadel
import Crypto

enum SSHClientError: LocalizedError {
    case realClientNotConfigured
    case notConnected
    case missingCredentials
    case unsupportedAuthentication(String)

    var errorDescription: String? {
        switch self {
        case .realClientNotConfigured:
            "Real SSH client is not configured yet. Integrate SwiftNIO SSH, NMSSH or libssh2-compatible layer here."
        case .notConnected:
            "SSH session is not connected."
        case .missingCredentials:
            "No saved SSH credential was found for this server."
        case .unsupportedAuthentication(let message):
            message
        }
    }
}

protocol SSHClientProtocol {
    func connect(to server: ServerProfile) async throws
    func run(_ command: String, on server: ServerProfile) async throws -> String
    func disconnect(from server: ServerProfile) async
}

struct MockSSHClient: SSHClientProtocol {
    func connect(to server: ServerProfile) async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    func run(_ command: String, on server: ServerProfile) async throws -> String {
        try await Task.sleep(nanoseconds: 180_000_000)
        switch command {
        case "uptime":
            return "19:26:11 up 42 days, 3:11, 1 user, load average: 0.18, 0.21, 0.19"
        case "df -h":
            return """
            Filesystem      Size  Used Avail Use% Mounted on
            /dev/root        60G   41G   18G  70% /
            /dev/sda1       100G   86G   14G  86% /var/lib/docker
            """
        case "free -h":
            return """
                           total        used        free      shared  buff/cache   available
            Mem:           7.7Gi       4.1Gi       1.8Gi       120Mi       1.8Gi       3.1Gi
            Swap:          2.0Gi       245Mi       1.8Gi
            """
        case let value where value.hasPrefix("docker ps"):
            return """
            a1b2c3d4|immich-server|ghcr.io/immich-app/immich-server|Up 8 days
            e5f6a7b8|postgres|postgres:16|Up 8 days
            c9d0e1f2|nginx|nginx:stable|Restarted 2h ago
            """
        case let value where value.hasPrefix("docker stats"):
            return """
            immich-server|12.1%|46.0%
            postgres|4.2%|31.0%
            nginx|2.0%|7.0%
            """
        case let value where value.hasPrefix("systemctl --failed"):
            return """
              UNIT         LOAD   ACTIVE SUB    DESCRIPTION
            * backup.timer loaded failed failed Nightly backup timer

            1 loaded units listed.
            """
        case let value where value.hasPrefix("journalctl") || value.hasPrefix("dmesg") || value.hasPrefix("tail -n"):
            return """
            May 20 11:45:18 \(server.name) systemd[1]: Started Docker Application Container Engine.
            May 20 11:46:02 \(server.name) sshd[1124]: Accepted publickey for \(server.username).
            May 20 11:46:35 \(server.name) kernel: EXT4-fs mounted filesystem with ordered data mode.
            """
        case let value where value.hasPrefix("command -v"):
            let commandName = value.replacingOccurrences(of: "command -v ", with: "")
            let installed = ["docker", "jq", "curl"].contains(commandName)
            return installed ? "/usr/bin/\(commandName)" : ""
        default:
            return "$ \(command)\nDemo Mode: command preview completed on \(server.name)."
        }
    }

    func disconnect(from server: ServerProfile) async {}
}

struct RealSSHClient: SSHClientProtocol {
    private let keychain: KeychainService

    init(keychain: KeychainService = .shared) {
        self.keychain = keychain
    }

    func connect(to server: ServerProfile) async throws {
        let client = try await makeClient(for: server)
        try await client.close()
    }

    func run(_ command: String, on server: ServerProfile) async throws -> String {
        let client = try await makeClient(for: server)
        defer {
            Task {
                try? await client.close()
            }
        }
        var buffer = try await client.executeCommand(command, maxResponseSize: 256 * 1024)
        return buffer.readString(length: buffer.readableBytes) ?? ""
    }

    func disconnect(from server: ServerProfile) async {}

    private func makeClient(for server: ServerProfile) async throws -> SSHClient {
        let authentication = try authenticationMethod(for: server)
        return try await SSHClient.connect(
            host: server.host,
            port: server.port,
            authenticationMethod: authentication,
            hostKeyValidator: .acceptAnything(),
            reconnect: .never,
            algorithms: .all
        )
    }

    private func authenticationMethod(for server: ServerProfile) throws -> SSHAuthenticationMethod {
        guard let credentialIdentifier = server.credentialIdentifier,
              let secret = try keychain.readSecret(
                account: credentialIdentifier,
                prompt: "Unlock SSH credentials for \(server.name)"
              ),
              !secret.isEmpty else {
            throw SSHClientError.missingCredentials
        }

        switch server.authenticationType {
        case .password:
            return .passwordBased(username: server.username, password: secret)
        case .privateKey:
            return try privateKeyAuthentication(username: server.username, privateKey: secret, passphrase: nil)
        case .privateKeyWithPassphrase:
            let payload = SSHPrivateKeyCredentialPayload.decode(from: secret)
            return try privateKeyAuthentication(username: server.username, privateKey: payload.privateKey, passphrase: payload.passphrase)
        }
    }

    private func privateKeyAuthentication(username: String, privateKey: String, passphrase: String?) throws -> SSHAuthenticationMethod {
        let trimmedKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw SSHClientError.missingCredentials
        }

        let decryptionKey = passphrase?.isEmpty == false ? passphrase?.data(using: .utf8) : nil
        do {
            let keyType = try SSHKeyDetection.detectPrivateKeyType(from: trimmedKey)
            switch keyType {
            case .rsa:
                let key = try Insecure.RSA.PrivateKey(sshRsa: trimmedKey, decryptionKey: decryptionKey)
                return .rsa(username: username, privateKey: key)
            case .ed25519:
                let key = try Curve25519.Signing.PrivateKey(sshEd25519: trimmedKey, decryptionKey: decryptionKey)
                return .ed25519(username: username, privateKey: key)
            default:
                throw SSHClientError.unsupportedAuthentication(
                    "This build detects \(keyType.description) keys, but real SSH login currently supports RSA and ED25519 OpenSSH private keys."
                )
            }
        } catch let error as SSHClientError {
            throw error
        } catch {
            throw SSHClientError.unsupportedAuthentication(
                "Could not read the OpenSSH private key. Check the key format and passphrase. \(error.localizedDescription)"
            )
        }
    }
}

struct HybridSSHClient: SSHClientProtocol {
    private let mock = MockSSHClient()
    private let real = RealSSHClient()

    func connect(to server: ServerProfile) async throws {
        if server.isDemo {
            try await mock.connect(to: server)
        } else {
            try await real.connect(to: server)
        }
    }

    func run(_ command: String, on server: ServerProfile) async throws -> String {
        if server.isDemo {
            return try await mock.run(command, on: server)
        }
        return try await real.run(command, on: server)
    }

    func disconnect(from server: ServerProfile) async {
        if server.isDemo {
            await mock.disconnect(from: server)
        } else {
            await real.disconnect(from: server)
        }
    }
}
