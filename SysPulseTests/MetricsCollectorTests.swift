import XCTest
@testable import SysPulse

final class MetricsCollectorTests: XCTestCase {
    func testParseLinuxMetricsOutput() {
        let serverID = UUID()
        let output = """
        CPU=23
        RAM=64
        SWAP=7
        DISK=82
        LOAD=0.21 0.30 0.44
        UPTIME=up 4 weeks, 2 days
        OS=Ubuntu 24.04 LTS
        KERNEL=6.8.0-51-generic
        IPS=192.168.1.10 10.0.0.5
        TEMP=54
        FAILED_SERVICES=1
        DOCKER_RUNNING=4
        DOCKER_TOTAL=5
        NET_RX_MB=128
        NET_TX_MB=64
        """

        let metrics = MetricsCollector().parseMetrics(output, serverID: serverID)

        XCTAssertEqual(metrics.serverID, serverID)
        XCTAssertEqual(metrics.cpuUsage, 23)
        XCTAssertEqual(metrics.ramUsage, 64)
        XCTAssertEqual(metrics.diskUsage, 82)
        XCTAssertEqual(metrics.temperatureCelsius, 54)
        XCTAssertEqual(metrics.failedServices, 1)
        XCTAssertEqual(metrics.dockerRunning, 4)
        XCTAssertEqual(metrics.dockerTotal, 5)
        XCTAssertEqual(metrics.ipAddresses, ["192.168.1.10", "10.0.0.5"])
        XCTAssertLessThan(metrics.healthScore, 100)
    }
}
