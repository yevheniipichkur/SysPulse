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
            L10n.string("Real SSH client is not configured yet. Integrate SwiftNIO SSH, NMSSH or libssh2-compatible layer here.")
        case .notConnected:
            L10n.string("SSH session is not connected.")
        case .missingCredentials:
            L10n.string("No saved SSH credential was found for this server.")
        case .unsupportedAuthentication(let message):
            message
        }
    }
}

protocol SSHClientProtocol {
    func connect(to server: ServerProfile) async throws
    func run(_ command: String, on server: ServerProfile) async throws -> String
    func disconnect(from server: ServerProfile) async
    func makeCitadelClient(for server: ServerProfile) async throws -> SSHClient
}

struct RealSSHClient: SSHClientProtocol {
    private let keychain: KeychainService

    init(keychain: KeychainService = .shared) {
        self.keychain = keychain
    }

    func connect(to server: ServerProfile) async throws {
        let client = try await makeCitadelClient(for: server)
        try await client.close()
    }

    func run(_ command: String, on server: ServerProfile) async throws -> String {
        let client = try await makeCitadelClient(for: server)
        defer {
            Task {
                try? await client.close()
            }
        }
        var buffer = try await client.executeCommand(command, maxResponseSize: 256 * 1024)
        return buffer.readString(length: buffer.readableBytes) ?? ""
    }

    func disconnect(from server: ServerProfile) async {}

    func makeCitadelClient(for server: ServerProfile) async throws -> SSHClient {
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
                prompt: L10n.string("Unlock SSH credentials for %@", server.name)
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
                    L10n.string(
                        "This build detects %@ keys, but real SSH login currently supports RSA and ED25519 OpenSSH private keys.",
                        keyType.description
                    )
                )
            }
        } catch let error as SSHClientError {
            throw error
        } catch {
            throw SSHClientError.unsupportedAuthentication(
                L10n.string(
                    "Could not read the OpenSSH private key. Check the key format and passphrase. %@",
                    error.localizedDescription
                )
            )
        }
    }
}
