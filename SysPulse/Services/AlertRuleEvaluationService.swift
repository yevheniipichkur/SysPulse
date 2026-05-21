import Foundation

struct AlertRuleEvaluation: Identifiable {
    var id: String { "\(rule.id.uuidString)-\(serverID.uuidString)" }
    var rule: AlertRule
    var serverID: UUID
    var metric: AlertMetricKey
    var value: Double
}

struct AlertRuleEvaluationService {
    func evaluations(for rules: [AlertRule], server: ServerProfile, metrics: ServerMetrics) -> [AlertRuleEvaluation] {
        rules.compactMap { rule in
            guard rule.isEnabled else { return nil }
            if let scopedServerID = rule.serverID, scopedServerID != server.id {
                return nil
            }

            let metric = rule.metric
            let value = metric.value(in: metrics)
            guard metric.isTriggered(value: value, threshold: rule.threshold) else {
                return nil
            }

            return AlertRuleEvaluation(
                rule: rule,
                serverID: server.id,
                metric: metric,
                value: value
            )
        }
    }
}
