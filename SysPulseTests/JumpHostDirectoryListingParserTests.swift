import XCTest
@testable import SysPulse

final class JumpHostDirectoryListingParserTests: XCTestCase {
    func testParsesLsOutput() {
        let output = """
        drwxr-xr-x  2 root root 4096 2026-05-01 10:00 etc
        -rw-r--r--  1 root root  220 2026-05-01 10:01 hosts
        """
        let items = JumpHostDirectoryListingParser.parse(output: output, basePath: ".")
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.name, "etc")
        XCTAssertTrue(items.first?.isDirectory == true)
    }
}
