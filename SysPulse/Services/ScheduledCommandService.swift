import Foundation
import SwiftData

struct ScheduledCommandService {
    func dueCommands(from commands: [ScheduledCommand], now: Date = .now) -> [ScheduledCommand] {
        commands.filter { command in
            command.isEnabled && command.nextRunAt <= now
        }
    }

    func markRun(command: ScheduledCommand, output: String, now: Date = .now) {
        command.lastRunAt = now
        command.lastOutput = String(output.prefix(4000))
        command.nextRunAt = now.addingTimeInterval(TimeInterval(command.intervalMinutes * 60))
    }

    func validate(command: String) -> Bool {
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !CommandRunner.containsDangerousToken(command)
    }
}
