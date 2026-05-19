import XCTest
@testable import SysPulse

final class CommandSafetyAnalyzerTests: XCTestCase {
    private let analyzer = CommandSafetyAnalyzer()

    func testSafeReadOnlyCommandDoesNotRequireConfirmation() {
        let result = analyzer.analyze("df -h")
        XCTAssertEqual(result.level, .safe)
        XCTAssertFalse(result.requiresConfirmation)
    }

    func testRebootRequiresDangerousConfirmation() {
        let result = analyzer.analyze("sudo reboot")
        XCTAssertEqual(result.level, .dangerous)
        XCTAssertTrue(result.reasons.contains("Reboots the remote server."))
    }

    func testRmAtBeginningIsDetected() {
        let result = analyzer.analyze("rm -rf /tmp/cache")
        XCTAssertEqual(result.level, .dangerous)
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testDockerRemoveIsDetected() {
        let result = analyzer.analyze("docker rm old-container")
        XCTAssertEqual(result.level, .dangerous)
        XCTAssertTrue(result.reasons.contains("Can remove Docker resources."))
    }

    func testPackageManagerIsModerate() {
        let result = analyzer.analyze("sudo apt update")
        XCTAssertEqual(result.level, .moderate)
        XCTAssertTrue(result.requiresConfirmation)
    }

    func testReadOnlyPackageQueryIsSafe() {
        let result = analyzer.analyze("apt list --upgradable")
        XCTAssertEqual(result.level, .safe)
        XCTAssertFalse(result.requiresConfirmation)
    }
}
