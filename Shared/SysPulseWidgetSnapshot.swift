import Foundation

enum SysPulseSharedDefaults {
    static let appGroupIdentifier = "group.com.yevheniipichkur.syspulse"
    static let widgetEnvelopeKey = "SysPulse.widget.envelope.v1"

    static var sharedOrStandard: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

struct WidgetServerSnapshot: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var status: String
    var cpu: Double
    var ram: Double
    var disk: Double
    var health: Int
    var uptime: String
    var osName: String
    var updatedAt: Date
    var needsAttention: Bool

    static let placeholder = WidgetServerSnapshot(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID(),
        name: "Raspberry Pi",
        status: "Online",
        cpu: 27,
        ram: 54,
        disk: 68,
        health: 91,
        uptime: "42d 3h",
        osName: "Raspberry Pi OS",
        updatedAt: .now,
        needsAttention: false
    )
}

struct WidgetSnapshotEnvelope: Codable, Hashable {
    var generatedAt: Date
    var servers: [WidgetServerSnapshot]
    var spotlightServerID: UUID?

    static let placeholder = WidgetSnapshotEnvelope(
        generatedAt: .now,
        servers: [
            .placeholder,
            WidgetServerSnapshot(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID(),
                name: "VPS Production",
                status: "Warning",
                cpu: 71,
                ram: 77,
                disk: 86,
                health: 66,
                uptime: "120d 9h",
                osName: "Ubuntu 24.04 LTS",
                updatedAt: .now,
                needsAttention: true
            ),
            WidgetServerSnapshot(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID(),
                name: "Docker Lab",
                status: "Online",
                cpu: 42,
                ram: 63,
                disk: 57,
                health: 84,
                uptime: "8d 14h",
                osName: "Debian 12",
                updatedAt: .now,
                needsAttention: false
            )
        ],
        spotlightServerID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")
    )
}

struct WidgetSnapshotStore {
    var defaults: UserDefaults

    init(defaults: UserDefaults = SysPulseSharedDefaults.sharedOrStandard) {
        self.defaults = defaults
    }

    func save(_ envelope: WidgetSnapshotEnvelope) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        defaults.set(data, forKey: SysPulseSharedDefaults.widgetEnvelopeKey)
    }

    func load() -> WidgetSnapshotEnvelope? {
        guard let data = defaults.data(forKey: SysPulseSharedDefaults.widgetEnvelopeKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshotEnvelope.self, from: data)
    }
}
