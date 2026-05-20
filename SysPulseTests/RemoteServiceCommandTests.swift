import XCTest
@testable import SysPulse

final class RemoteServiceCommandTests: XCTestCase {
    func testDockerCommandBuildersUsePreviewSafeCommands() {
        let service = DockerService()

        XCTAssertTrue(service.listContainersCommand().hasPrefix("docker ps"))
        XCTAssertEqual(service.statsCommand(), "docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}'")
        XCTAssertEqual(service.actionCommand(action: "restart", containerName: "nginx"), "docker restart nginx")
    }

    func testSystemdCommandBuildersRequireSudoForMutatingActions() {
        let service = SystemdService()

        XCTAssertEqual(service.failedUnitsCommand(), "systemctl --failed --no-pager")
        XCTAssertEqual(service.statusCommand(serviceName: "ssh.service"), "systemctl status ssh.service --no-pager")
        XCTAssertEqual(service.actionCommand(action: "stop", serviceName: "nginx.service"), "sudo systemctl stop nginx.service")
    }

    func testPackageInstallCommandsRemainPreviewOnly() {
        let detector = PackageDetector()

        XCTAssertTrue(detector.checkCommandsPreview().contains("command -v docker"))
        XCTAssertEqual(detector.installCommand(for: .alpine), "sudo apk add sysstat lm-sensors htop curl jq smartmontools")
    }
}
