import SwiftData
import XCTest
@testable import SysPulse

final class ProfileStorageServiceTests: XCTestCase {
    @MainActor
    func testProfileMetadataPersistsInSwiftDataWithoutSecretMaterial() throws {
        let repository = try makeRepository()
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
            status: .online
        )

        try repository.saveProfile(profile)
        let loaded = try repository.loadProfiles()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.host, "prod.example.com")
        XCTAssertEqual(loaded.first?.credentialIdentifier, "keychain-reference-only")
        XCTAssertEqual(loaded.first?.authenticationType, .privateKeyWithPassphrase)
        XCTAssertEqual(loaded.first?.tags, ["prod", "nginx"])
    }

    @MainActor
    func testSavingExistingProfileUpdatesSingleSwiftDataRecord() throws {
        let repository = try makeRepository()
        let profile = ServerProfile(
            name: "Staging",
            host: "staging.example.com",
            username: "ubuntu",
            credentialIdentifier: "keychain-reference-only",
            serverType: .vps
        )

        try repository.saveProfile(profile)
        profile.name = "Production"
        profile.host = "prod.example.com"
        profile.tagsCSV = "prod,nginx"
        try repository.saveProfile(profile)

        let loaded = try repository.loadProfiles()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "Production")
        XCTAssertEqual(loaded.first?.host, "prod.example.com")
        XCTAssertEqual(loaded.first?.tags, ["prod", "nginx"])
    }

    @MainActor
    func testDeletingProfileRemovesSwiftDataRecord() throws {
        let repository = try makeRepository()
        let profile = ServerProfile(
            name: "Disposable",
            host: "test.example.com",
            username: "ubuntu",
            serverType: .custom
        )

        try repository.saveProfile(profile)
        try repository.deleteProfile(profile)

        XCTAssertTrue(try repository.loadProfiles().isEmpty)
    }

    @MainActor
    private func makeRepository() throws -> SwiftDataProfileRepository {
        let schema = Schema([ServerProfile.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SwiftDataProfileRepository(modelContext: container.mainContext, legacyUserDefaults: nil)
    }
}
