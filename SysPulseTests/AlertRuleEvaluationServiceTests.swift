import XCTest
@testable import SysPulse

final class AlertRuleEvaluationServiceTests: XCTestCase {
    func testHighCPUAlertTriggers() {
        let server = ServerProfile(name: "Prod", host: "prod.local", username: "root")
        let rule = AlertRule(title: "High CPU", metricKey: AlertMetricKey.cpuUsage.rawValue, threshold: 90)
        var metrics = ServerMetrics.empty(serverID: server.id)
        metrics.cpuUsage = 94

        let evaluations = AlertRuleEvaluationService().evaluations(for: [rule], server: server, metrics: metrics)

        XCTAssertEqual(evaluations.count, 1)
        XCTAssertEqual(evaluations.first?.metric, .cpuUsage)
        XCTAssertEqual(evaluations.first?.value, 94)
    }

    func testDisabledAlertDoesNotTrigger() {
        let server = ServerProfile(name: "Prod", host: "prod.local", username: "root")
        let rule = AlertRule(title: "High RAM", metricKey: AlertMetricKey.ramUsage.rawValue, threshold: 90, isEnabled: false)
        var metrics = ServerMetrics.empty(serverID: server.id)
        metrics.ramUsage = 98

        let evaluations = AlertRuleEvaluationService().evaluations(for: [rule], server: server, metrics: metrics)

        XCTAssertTrue(evaluations.isEmpty)
    }

    func testLowHealthAlertTriggersAtOrBelowThreshold() {
        let server = ServerProfile(name: "Prod", host: "prod.local", username: "root")
        let rule = AlertRule(title: "Low Health Score", metricKey: AlertMetricKey.healthScore.rawValue, threshold: 50)
        var metrics = ServerMetrics.empty(serverID: server.id)
        metrics.healthScore = 42

        let evaluations = AlertRuleEvaluationService().evaluations(for: [rule], server: server, metrics: metrics)

        XCTAssertEqual(evaluations.count, 1)
        XCTAssertEqual(evaluations.first?.metric, .healthScore)
    }
}
