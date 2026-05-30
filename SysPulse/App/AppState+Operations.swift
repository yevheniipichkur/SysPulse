import Foundation
import SwiftData

extension AppState {
    func configureSSHProfileLookup() {
        guard let client = sshClient as? RealSSHClient else { return }
        client.profileLookup = { [weak self] id in
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

    func runDueScheduledCommands() {
        guard isProUnlocked, let modelContext else { return }

        let runner = ScheduledCommandService()
        let descriptor = FetchDescriptor<ScheduledCommand>(
            sortBy: [SortDescriptor(\.nextRunAt, order: .forward)]
        )
        guard let commands = try? modelContext.fetch(descriptor) else { return }

        for command in runner.dueCommands(from: commands) {
            guard runner.validate(command: command.command),
                  let server = serverProfiles.first(where: { $0.id == command.serverID }) else {
                continue
            }

            Task {
                do {
                    let output = try await sshClient.run(command.command, on: server)
                    await MainActor.run {
                        runner.markRun(command: command, output: output)
                        try? modelContext.save()
                        recordServerEvent(
                            server: server,
                            title: localized("Scheduled command ran"),
                            details: command.title,
                            severity: "Safe"
                        )
                        postStatus(localized("Ran \"%@\" on %@.", command.title, server.name), style: .success)
                    }
                } catch {
                    await MainActor.run {
                        runner.markRun(command: command, output: connectionErrorMessage(error, server: server))
                        try? modelContext.save()
                        postStatus(
                            localized("Scheduled command failed on %@: %@", server.name, error.localizedDescription),
                            style: .error
                        )
                    }
                }
            }
        }
    }
}
