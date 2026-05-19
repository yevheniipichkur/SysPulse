import XCTest
@testable import SysPulse

final class HealthScoreServiceTests: XCTestCase {
    func testExcellentScoreForHealthyMetrics() {
        let score = HealthScoreService.calculate(
            cpu: 20,
            ram: 35,
            disk: 40,
            temperature: 45,
            failedServices: 0,
            dockerRunning: 3,
            dockerTotal: 3,
            loadAverage: "0.10 0.15 0.20"
        )
        XCTAssertGreaterThanOrEqual(score, 90)
    }

    func testCriticalScoreForDiskAndServices() {
        let score = HealthScoreService.calculate(
            cpu: 92,
            ram: 91,
            disk: 94,
            temperature: 82,
            failedServices: 3,
            dockerRunning: 2,
            dockerTotal: 5,
            loadAverage: "4.00 3.50 3.00"
        )
        XCTAssertLessThan(score, 50)
    }
}
