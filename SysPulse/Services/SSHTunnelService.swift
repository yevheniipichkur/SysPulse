import Foundation

/// Manages SSH tunnel connection testing.
/// Full in-process port forwarding is iOS-restricted (background TCP listeners);
/// this service tests tunnel reachability via SSH and generates the desktop SSH command.
actor SSHTunnelService {

    enum TunnelTestResult {
        case reachable(latencyMS: Int)
        case unreachable(String)
    }

    // MARK: - Tunnel testing

    /// Tests whether the remote host:port is reachable via SSH.
    func testTunnel(
        _ tunnel: SSHTunnel,
        server: ServerProfile,
        sshClient: SSHClientProtocol
    ) async -> TunnelTestResult {
        let start = Date()
        // nc (netcat) or /dev/tcp as fallback — exits 0 if port is open
        let cmd = "(nc -zw3 \(tunnel.remoteHost) \(tunnel.remotePort) 2>/dev/null && echo open) || echo closed"
        do {
            let output = try await sshClient.run(cmd, on: server)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if output.trimmingCharacters(in: .whitespacesAndNewlines) == "open" {
                return .reachable(latencyMS: ms)
            } else {
                return .unreachable("Port \(tunnel.remotePort) on \(tunnel.remoteHost) is not open.")
            }
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}
