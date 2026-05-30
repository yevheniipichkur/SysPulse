import Foundation
import SwiftData
import UIKit

extension AppState {
    func registerBackgroundRefresh() {
        BackgroundRefreshCoordinator.register()
        BackgroundRefreshCoordinator.scheduleNextRefresh()
    }

    func runDueScheduledCommands(markMissedIfNeeded: Bool = false) {
        guard isProUnlocked, let modelContext else { return }

        let runner = ScheduledCommandService()
        let descriptor = FetchDescriptor<ScheduledCommand>(
            sortBy: [SortDescriptor(\.nextRunAt, order: .forward)]
        )
        guard let commands = try? modelContext.fetch(descriptor) else { return }

        let due = runner.dueCommands(from: commands)
        if due.isEmpty { return }

        if markMissedIfNeeded, UIApplication.shared.applicationState != .active {
            scheduleMissedScheduledCommandsReminder(count: due.count)
        }

        for command in due {
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

    func scheduleMissedScheduledCommandsReminder(count: Int) {
        guard count > 0 else { return }
        Task {
            try? await notificationService.scheduleAlert(
                title: localized("Scheduled commands waiting"),
                body: localized("Open SysPulse to run %d scheduled command(s) iOS could not execute in the background.", count),
                identifier: "syspulse.scheduled.missed"
            )
        }
    }

    func exportMetricsCSV(for server: ServerProfile) -> URL? {
        guard requireProFeature(feature: localized("Metrics export")) else { return nil }
        let metrics = metric(for: server)
        let events = serverEvents(for: server)
        let exporter = MetricsExportService()
        let csv = exporter.csv(server: server, metrics: metrics, events: events)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(server.name)-metrics-\(Int(Date.now.timeIntervalSince1970)).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            postStatus(localized("CSV export ready for %@.", server.name), style: .success)
            return url
        } catch {
            postStatus(localized("Export failed: %@", error.localizedDescription), style: .error)
            return nil
        }
    }

    func runDiagnosticFromShortcut(serverName: String?) {
        guard let serverName,
              let server = serverProfiles.first(where: { $0.name.localizedCaseInsensitiveCompare(serverName) == .orderedSame }) else {
            postStatus(localized("Server not found."), style: .info)
            return
        }
        select(server, tab: .servers)
        shouldOpenSelectedServerMonitor = true
        Task {
            do {
                _ = try await runDiagnosticPack(for: server)
            } catch {
                postStatus(error.localizedDescription, style: .error)
            }
        }
    }
}
