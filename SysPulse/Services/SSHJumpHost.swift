import Foundation

enum SSHJumpHost {
    static func proxiedCommand(_ command: String, target: ServerProfile) -> String {
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        return "ssh -p \(target.port) -o BatchMode=yes -o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new \(target.username)@\(target.host) '\(escaped)'"
    }

    /// Opens an interactive shell on the target via the bastion PTY.
    static func interactiveSSHLaunch(target: ServerProfile) -> String {
        "ssh -tt -p \(target.port) -o BatchMode=yes -o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new \(target.username)@\(target.host)\n"
    }

    static func proxiedListDirectory(at path: String, target: ServerProfile) -> String {
        let directory = path.isEmpty || path == "." ? "." : path
        let escaped = directory.replacingOccurrences(of: "'", with: "'\\''")
        return proxiedCommand("ls -la --time-style=long-iso '\(escaped)'", target: target)
    }
}
