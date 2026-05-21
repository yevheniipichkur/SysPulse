import XCTest
@testable import SysPulse

final class SubscriptionStateTests: XCTestCase {
    func testProRequiresActiveEntitlement() {
        let expiredLifetime = SubscriptionState(plan: .lifetime, isActive: false)
        XCTAssertFalse(expiredLifetime.isPro)
    }

    func testActiveEntitlementUnlocksPro() {
        let activeMonthly = SubscriptionState(plan: .proMonthly, isActive: true)
        XCTAssertTrue(activeMonthly.isPro)
    }
}
