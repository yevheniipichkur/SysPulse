import Foundation
import SwiftData

extension AppState {
    func requestAlertNotifications() async {
        let granted = await notificationService.requestPermission()
        areNotificationsAuthorized = granted
        postStatus(
            granted
                ? localized("Notifications enabled for metric alerts.")
                : localized("Notifications are disabled in iOS Settings."),
            style: granted ? .success : .info
        )
    }

    func refreshAlertNotificationAuthorization() {
        Task {
            areNotificationsAuthorized = await notificationService.isAuthorized()
        }
    }

    func setAlertRule(_ rule: AlertRule, isEnabled: Bool) {
        rule.isEnabled = isEnabled
        saveAlertRules()
        objectWillChange.send()
    }

    func reloadAlertRules() {
        guard let modelContext else { return }
        do {
            let descriptor = FetchDescriptor<AlertRule>(
                sortBy: [SortDescriptor(\.title, order: .forward)]
            )
            var rules = try modelContext.fetch(descriptor)
            if rules.isEmpty {
                rules = AlertRule.defaultRules()
                for rule in rules {
                    modelContext.insert(rule)
                }
                try modelContext.save()
            }
            alertRules = rules
        } catch {
            postStatus(localized("Failed to load alert rules: %@", error.localizedDescription))
        }
    }

    func saveAlertRules() {
        do {
            try modelContext?.save()
        } catch {
            postStatus(localized("Failed to save alert rules: %@", error.localizedDescription))
        }
    }

    func evaluateAlertRules(for server: ServerProfile, metrics: ServerMetrics) {
        guard areNotificationsAuthorized else { return }
        let evaluations = alertEvaluationService.evaluations(for: alertRules, server: server, metrics: metrics)
        guard !evaluations.isEmpty else { return }

        let now = Date()
        for evaluation in evaluations {
            let cooldownKey = evaluation.id
            if let lastFiredAt = alertLastFiredAt[cooldownKey],
               now.timeIntervalSince(lastFiredAt) < alertCooldown {
                continue
            }

            alertLastFiredAt[cooldownKey] = now
            let title = localized(evaluation.rule.title)
            let body = localized(evaluation.metric.notificationBodyKey, evaluation.value, server.name)
            recordServerEvent(
                server: server,
                title: title,
                details: body,
                severity: "Warning"
            )
            Task {
                try? await notificationService.scheduleAlert(
                    title: title,
                    body: body,
                    identifier: "syspulse.\(cooldownKey)"
                )
            }
        }
    }
}
