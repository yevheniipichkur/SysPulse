import XCTest
@testable import SysPulse

final class SubscriptionStateTests: XCTestCase {
    func testProRequiresActiveEntitlement() {
        let expiredLifetime = SubscriptionState(plan: .lifetime, isActive: false)
        XCTAssertFalse(expiredLifetime.isPro)
    }

    func testActiveSubscriptionWithoutExpirationDoesNotUnlockPro() {
        let activeMonthly = SubscriptionState(plan: .proMonthly, isActive: true)
        XCTAssertFalse(activeMonthly.isPro)
    }

    func testActiveSubscriptionRequiresFutureExpiration() {
        let activeMonthly = SubscriptionState(plan: .proMonthly, isActive: true, expiresAt: Date().addingTimeInterval(3600))
        XCTAssertTrue(activeMonthly.isPro)
    }

    func testExpiredSubscriptionDoesNotUnlockPro() {
        let expiredYearly = SubscriptionState(plan: .proYearly, isActive: true, expiresAt: Date().addingTimeInterval(-3600))
        XCTAssertFalse(expiredYearly.isPro)
    }

    func testLifetimeDoesNotRequireExpiration() {
        let lifetime = SubscriptionState(plan: .lifetime, isActive: true)
        XCTAssertTrue(lifetime.isPro)
    }

    func testBestEntitlementPrefersLifetime() {
        let monthly = SubscriptionState(plan: .proMonthly, isActive: true, expiresAt: Date().addingTimeInterval(3600))
        let lifetime = SubscriptionState(plan: .lifetime, isActive: true)
        XCTAssertTrue(lifetime.isBetterEntitlement(than: monthly))
    }
}
