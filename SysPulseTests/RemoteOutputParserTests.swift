import XCTest
@testable import SysPulse

final class RemoteOutputParserTests: XCTestCase {
    func testParseProcessList() {
        let output = """
          129 root     systemd          0.3  1.1
         2421 www-data nginx           12.8  4.5
        12044 admin    postgres         3,4 18,2
        """

        let processes = ProcessService().parseProcesses(output)

        XCTAssertEqual(processes.count, 3)
        XCTAssertEqual(processes[0].pid, 129)
        XCTAssertEqual(processes[1].command, "nginx")
        XCTAssertEqual(processes[2].cpu, 3.4)
        XCTAssertEqual(processes[2].memory, 18.2)
    }

    func testParseDiskUsage() {
        let output = """
        Filesystem 1B-blocks Used Available Use% Mounted on
        /dev/root 62537072640 24830279680 35161145344 42% /
        /dev/sda1 107374182400 96636764160 10737418240 90% /mnt/storage
        """

        let disks = DiskService().parseDisks(output)

        XCTAssertEqual(disks.count, 2)
        XCTAssertEqual(disks[0].mountPoint, "/")
        XCTAssertEqual(Int(disks[0].usagePercent), 42)
        XCTAssertEqual(disks[1].mountPoint, "/mnt/storage")
        XCTAssertEqual(Int(disks[1].freeGB), 10)
    }

    func testParseDiskUsageOutputColumns() {
        let output = """
        /dev/root / 24830279680 35161145344 42%
        tmpfs /run 123000000 456000000 21%
        """

        let disks = DiskService().parseDisks(output)

        XCTAssertEqual(disks.count, 2)
        XCTAssertEqual(disks[0].filesystem, "/dev/root")
        XCTAssertEqual(disks[0].mountPoint, "/")
        XCTAssertEqual(Int(disks[0].usagePercent), 42)
        XCTAssertEqual(disks[1].mountPoint, "/run")
    }

    func testParseDockerInventoryWithStats() {
        let output = """
        __SYSPULSE_CONTAINERS__
        abc123|nginx|nginx:latest|Up 2 hours
        def456|postgres|postgres:16|Exited (0) 3 days ago
        __SYSPULSE_STATS__
        nginx|1.25%|6.70%
        """

        let containers = DockerService().parseContainers(output)

        XCTAssertEqual(containers.count, 2)
        XCTAssertEqual(containers[0].name, "nginx")
        XCTAssertEqual(containers[0].cpuUsage, 1.25)
        XCTAssertEqual(containers[0].memoryUsage, 6.7)
        XCTAssertEqual(containers[1].status, "Exited (0) 3 days ago")
    }

    func testParseSystemdUnits() {
        let output = """
        ssh.service|loaded|active|running
        nginx.service|loaded|failed|failed
        sys-kernel-debug.mount|loaded|active|mounted
        """

        let services = SystemdService().parseServices(output)

        XCTAssertEqual(services.count, 2)
        XCTAssertEqual(services[0].name, "ssh.service")
        XCTAssertFalse(services[0].isFailed)
        XCTAssertTrue(services[1].isFailed)
    }

    func testParseJournalEntries() {
        let output = """
        2026-05-21 12:01:02 raspberrypi sshd[42]: Accepted publickey for admin
        2026-05-21 12:02:03 raspberrypi nginx[11]: error while reading upstream
        """

        let entries = LogsService().parseLogEntries(output)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].source, "sshd[42]")
        XCTAssertEqual(entries[0].severity, .safe)
        XCTAssertEqual(entries[1].severity, .dangerous)
    }
}
