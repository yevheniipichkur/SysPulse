import XCTest
@testable import SysPulse

final class SSHJumpHostTests: XCTestCase {
    func testProxiedCommandEscapesQuotes() {
        let target = ServerProfile(name: "db", host: "10.0.0.5", port: 22, username: "ubuntu")
        let command = SSHJumpHost.proxiedCommand("echo 'hi'", target: target)
        XCTAssertTrue(command.contains("ssh -p 22"))
        XCTAssertTrue(command.contains("ubuntu@10.0.0.5"))
        XCTAssertTrue(command.contains("echo"))
    }

    func testInteractiveLaunchIncludesTTYFlag() {
        let target = ServerProfile(name: "app", host: "app.local", port: 2222, username: "root")
        let launch = SSHJumpHost.interactiveSSHLaunch(target: target)
        XCTAssertTrue(launch.contains("ssh -tt"))
        XCTAssertTrue(launch.contains("-p 2222"))
    }
}
