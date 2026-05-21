import XCTest
@testable import SysPulse

final class SFTPFileTransferServiceTests: XCTestCase {
    func testParentPathHandlesRootAndNestedPaths() {
        let service = SFTPFileTransferService()
        XCTAssertEqual(service.parentPath(of: "/var/www"), "/var")
        XCTAssertEqual(service.parentPath(of: "/var"), "/")
        XCTAssertEqual(service.parentPath(of: "/"), ".")
        XCTAssertEqual(service.parentPath(of: "relative"), ".")
        XCTAssertEqual(service.parentPath(of: "."), ".")
    }
}
