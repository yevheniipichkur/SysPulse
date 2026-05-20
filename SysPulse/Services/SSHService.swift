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
    func connect(to server: ServerProfile) async throws {
        throw SSHClientError.realClientNotConfigured
    }

    func run(_ command: String, on server: ServerProfile) async throws -> String {
        throw SSHClientError.realClientNotConfigured
    }

    func disconnect(from server: ServerProfile) async {}
}
