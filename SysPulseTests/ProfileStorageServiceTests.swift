import XCTest
@testable import SysPulse

final class ProfileStorageServiceTests: XCTestCase {
    func testProfileMetadataPersistsWithoutSecretMaterial() {
        let suiteName = "ProfileStorageServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let service = ProfileStorageService(userDefaults: defaults)
        let profile = ServerProfile(
            name: "Production",
            host: "prod.example.com",
            port: 2222,
            username: "ubuntu",
            authenticationType: .privateKeyWithPassphrase,
            credentialIdentifier: "keychain-reference-only",
            tags: ["prod", "nginx"],
            groupName: "Cloud",
            icon: "cloud",
            accentHex: "#39A7FF",
            serverType: .vps,
            status: .online,
            isDemo: false
        )

        service.saveProfiles([profile])
        let loaded = service.loadProfiles()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.host, "prod.example.com")
        XCTAssertEqual(loaded.first?.credentialIdentifier, "keychain-reference-only")

        let rawData = defaults.data(forKey: "SysPulse.savedServerProfiles.v1")
        XCTAssertNotNil(rawData)
        XCTAssertFalse(String(data: rawData ?? Data(), encoding: .utf8)?.contains("PRIVATE KEY") ?? true)
    }

    func testDemoProfilesAreNotPersisted() {
        let suiteName = "ProfileStorageServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let service = ProfileStorageService(userDefaults: defaults)
        service.saveProfiles(DemoDataService.makeDemoServers())

        XCTAssertTrue(service.loadProfiles().isEmpty)
    }
}
