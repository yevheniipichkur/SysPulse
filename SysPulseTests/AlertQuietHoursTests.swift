import XCTest
@testable import SysPulse

final class AlertQuietHoursTests: XCTestCase {
    func testDisabledReturnsFalse() {
        XCTAssertFalse(AlertQuietHours.isActive(enabled: false, startHour: 22, endHour: 7))
    }

    func testOvernightQuietHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 30
        components.hour = 23
        let date = calendar.date(from: components)!
        XCTAssertTrue(AlertQuietHours.isActive(now: date, calendar: calendar, enabled: true, startHour: 22, endHour: 7))
    }

    func testOutsideQuietHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 30
        components.hour = 12
        let date = calendar.date(from: components)!
        XCTAssertFalse(AlertQuietHours.isActive(now: date, calendar: calendar, enabled: true, startHour: 22, endHour: 7))
    }
}
