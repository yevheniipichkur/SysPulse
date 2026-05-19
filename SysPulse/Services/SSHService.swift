import Foundation

enum SSHClientError: LocalizedError {
    case realClientNotConfigured
    case notConnected

    var errorDescription: String? {
        switch self {
        case .realClientNotConfigured:
            "Real SSH client is not configured yet. Integrate SwiftNIO SSH, NMSSH or libssh2-compatible layer here."
        case .notConnected:
            "SSH session is not connected."
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
        default:
            return "$ \(command)\nDemo Mode: command preview completed on \(server.name)."
        }
    }

    func disconnect(from server: ServerProfile) async {}
}

struct RealSSHClient: SSHClientProtocol {
    func connect(to server: ServerProfile) async throws {
        throw SSHClientError.realClientNotConfigured
    }

    func run(_ command: String, on server: ServerProfile) async throws -> String {
        throw SSHClientError.realClientNotConfigured
    }

    func disconnect(from server: ServerProfile) async {}
}
