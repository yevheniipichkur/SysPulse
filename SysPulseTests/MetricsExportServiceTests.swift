import XCTest
@testable import SysPulse

final class MetricsExportServiceTests: XCTestCase {
    func testCSVIncludesMetricHeaders() {
        let server = ServerProfile(name: "Lab", host: "10.0.0.1", port: 22, username: "root")
        var metrics = ServerMetrics.empty(serverID: server.id)
        metrics.cpuUsage = 42
        metrics.ramUsage = 61

        let csv = MetricsExportService().csv(server: server, metrics: metrics, events: [])

        XCTAssertTrue(csv.contains("Lab"))
        XCTAssertTrue(csv.contains("CPU %,42"))
        XCTAssertTrue(csv.contains("RAM %,61"))
    }
}
