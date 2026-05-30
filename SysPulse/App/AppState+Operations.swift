import Foundation
import SwiftData

extension AppState {
    func configureSSHProfileLookup() {
        realSSHClient.profileLookup = { [weak self] id in
            self?.serverProfiles.first { $0.id == id }
        }
    }

    func runDiagnosticPack(for server: ServerProfile) async throws -> DiagnosticPackResult {
        guard requireProFeature(feature: "Diagnostic pack") else {
            throw SSHClientError.unsupportedAuthentication(
                localized("Unlock Pro to run the diagnostic pack.")
            )
        }

        let metrics = metric(for: server)
        let service = DiagnosticPackService()
        postStatus(localized("Running diagnostics on %@...", server.name))
        let result = try await service.collect(
            server: server,
            metrics: metrics,
            failedServices: metrics.failedServices,
            using: sshClient
        )
        postStatus(localized("Diagnostics completed for %@.", server.name), style: .success)
        return result
    }

}
