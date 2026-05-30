import BackgroundTasks
import Foundation

enum BackgroundRefreshCoordinator {
    static let scheduledTaskIdentifier = "com.yevheniipichkur.syspulse.scheduled-commands"

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: scheduledTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func scheduleNextRefresh(earliestBeginDate: Date? = nil) {
        let request = BGAppRefreshTaskRequest(identifier: scheduledTaskIdentifier)
        request.earliestBeginDate = earliestBeginDate ?? Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()
        let completion = {
            NotificationCenter.default.post(name: .syspulseRunScheduledCommands, object: nil)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            NotificationCenter.default.post(name: .syspulseScheduledCommandsMissed, object: nil)
            task.setTaskCompleted(success: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: completion)
    }
}

extension Notification.Name {
    static let syspulseRunScheduledCommands = Notification.Name("syspulseRunScheduledCommands")
    static let syspulseScheduledCommandsMissed = Notification.Name("syspulseScheduledCommandsMissed")
    static let syspulseRunDiagnostic = Notification.Name("syspulseRunDiagnostic")
    static let syspulseExportMetricsCSV = Notification.Name("syspulseExportMetricsCSV")
}
