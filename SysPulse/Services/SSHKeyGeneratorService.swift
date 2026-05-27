import Crypto
import Foundation

/// Generates ED25519 SSH key pairs in OpenSSH format.
struct SSHKeyGeneratorService {

    struct GeneratedKeyPair {
        let publicKeyOpenSSH: String
        let privateKeyPEM: String
        let keychainAccount: String
    }

    enum GeneratorError: LocalizedError {
        case encodingFailed
        var errorDescription: String? { "Key encoding failed." }
    }

    // MARK: - Public API

    func generateED25519(comment: String) throws -> GeneratedKeyPair {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pubBytes = privateKey.publicKey.rawRepresentation     // 32 bytes
        let privBytes = privateKey.rawRepresentation + pubBytes   // 64 bytes (seed + pub)

        let publicKeyStr = try makeOpenSSHPublicKey(pubBytes: pubBytes, comment: comment)
        let privateKeyPEM = try makeOpenSSHPrivateKeyPEM(pubBytes: pubBytes, privBytes: privBytes, comment: comment)
        let keychainAccount = "syspulse-key-\(UUID().uuidString)"

        return GeneratedKeyPair(
            publicKeyOpenSSH: publicKeyStr,
            privateKeyPEM: privateKeyPEM,
            keychainAccount: keychainAccount
        )
    }

    // MARK: - Private helpers

    private func makeOpenSSHPublicKey(pubBytes: Data, comment: String) throws -> String {
        var blob = Data()
        blob += encodeString("ssh-ed25519")
        blob += encodeData(pubBytes)
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }

    private func makeOpenSSHPrivateKeyPEM(pubBytes: Data, privBytes: Data, comment: String) throws -> String {
        // Public key blob: key-type || public-key-bytes
        var pubBlob = Data()
        pubBlob += encodeString("ssh-ed25519")
        pubBlob += encodeData(pubBytes)

        // Private section
        var checkInt: UInt32 = .random(in: 0 ... .max)
        let checkData = Data(bytes: &checkInt, count: 4)

        var privSection = Data()
        privSection += checkData         // checkint1
        privSection += checkData         // checkint2
        privSection += encodeString("ssh-ed25519")
        privSection += encodeData(pubBytes)
        privSection += encodeData(privBytes)
        privSection += encodeString(comment)
        // Pad to 8-byte boundary with incrementing bytes
        var padByte: UInt8 = 1
        while privSection.count % 8 != 0 {
            privSection.append(padByte)
            padByte &+= 1
        }

        // Assemble the outer wrapper
        var outer = Data()
        outer += Data("openssh-key-v1\0".utf8)   // magic
        outer += encodeString("none")              // cipher
        outer += encodeString("none")              // kdf
        outer += uint32BE(0)                       // kdf options (empty)
        outer += uint32BE(1)                       // number of keys
        outer += encodeData(pubBlob)               // public key blob
        outer += encodeData(privSection)           // private section

        // Wrap in PEM
        let base64 = outer.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
        return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(base64)\n-----END OPENSSH PRIVATE KEY-----"
    }

    private func uint32BE(_ value: UInt32) -> Data {
        var v = value.bigEndian
        return Data(bytes: &v, count: 4)
    }

    private func encodeString(_ s: String) -> Data {
        let bytes = Data(s.utf8)
        return uint32BE(UInt32(bytes.count)) + bytes
    }

    private func encodeData(_ d: Data) -> Data {
        uint32BE(UInt32(d.count)) + d
    }
}
