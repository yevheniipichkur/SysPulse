import XCTest
@testable import SysPulse

final class WidgetSnapshotStoreTests: XCTestCase {
    func testWidgetSnapshotRoundTripsThroughDefaults() {
        let suiteName = "WidgetSnapshotStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = WidgetSnapshotStore(defaults: defaults)
        let envelope = WidgetSnapshotEnvelope(
            generatedAt: Date(timeIntervalSince1970: 1_777_000_000),
            servers: [
                WidgetServerSnapshot(
                    id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                    name: "Docker Lab",
                    status: "Online",
                    cpu: 42,
                    ram: 63,
                    disk: 57,
                    health: 84,
                    uptime: "8d 14h",
                    osName: "Debian 12",
                    updatedAt: Date(timeIntervalSince1970: 1_777_000_001)
                )
            ]
        )

        store.save(envelope)
        let loaded = store.load()

        XCTAssertEqual(loaded?.servers.first?.name, "Docker Lab")
        XCTAssertEqual(loaded?.servers.first?.health, 84)
        XCTAssertNotNil(defaults.data(forKey: SysPulseSharedDefaults.widgetEnvelopeKey))
    }
}
