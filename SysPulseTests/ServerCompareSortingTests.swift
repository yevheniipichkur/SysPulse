import XCTest
@testable import SysPulse

final class ServerCompareSortingTests: XCTestCase {
    private func pair(name: String, health: Int, cpu: Double) -> (ServerProfile, ServerMetrics) {
        let server = ServerProfile(name: name, host: "h", port: 22, username: "u")
        var metrics = ServerMetrics.empty(serverID: server.id)
        metrics.healthScore = health
        metrics.cpuUsage = cpu
        return (server, metrics)
    }

    func testSortByHealthAscending() {
        let input = [pair(name: "b", health: 40, cpu: 10), pair(name: "a", health: 90, cpu: 5)]
        let sorted = ServerCompareSorting.sorted(input, by: .health)
        XCTAssertEqual(sorted.map(\.0.name), ["b", "a"])
    }

    func testSortByCPUDescending() {
        let input = [pair(name: "low", health: 50, cpu: 10), pair(name: "high", health: 50, cpu: 90)]
        let sorted = ServerCompareSorting.sorted(input, by: .cpu)
        XCTAssertEqual(sorted.first?.0.name, "high")
    }
}
