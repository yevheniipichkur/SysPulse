import Foundation

enum SSHJumpHost {
    static func proxiedCommand(_ command: String, target: ServerProfile) -> String {
        let escaped = command.replacingOccurrences(of: "'", with: "'\\''")
        return "ssh -p \(target.port) -o BatchMode=yes -o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new \(target.username)@\(target.host) '\(escaped)'"
    }
}
