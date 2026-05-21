import XCTest
@testable import SysPulse

final class EncryptedProfileSharingServiceTests: XCTestCase {
    func testEncryptedExportRoundTripRestoresProfileMetadataWithoutCredentials() throws {
        let profile = ServerProfile(
            name: "Prod API",
            host: "prod.example.com",
            port: 2222,
            username: "deploy",
            authenticationType: .privateKey,
            credentialIdentifier: "server-secret",
            tags: ["prod", "docker"],
            groupName: "Cloud",
            icon: "cloud",
            accentHex: "#33C2EA",
            serverType: .dockerHost,
            status: .online
        )
        let service = EncryptedProfileSharingService()

        let data = try service.exportData(profiles: [profile], passphrase: "shared-secret")
        let imported = try service.importProfiles(from: data, passphrase: "shared-secret")

        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported[0].name, "Prod API")
        XCTAssertEqual(imported[0].host, "prod.example.com")
        XCTAssertEqual(imported[0].port, 2222)
        XCTAssertEqual(imported[0].username, "deploy")
        XCTAssertEqual(imported[0].tags, ["prod", "docker"])
        XCTAssertNil(imported[0].credentialIdentifier)
    }

    func testWrongPassphraseFailsImport() throws {
        let profile = ServerProfile(name: "Prod API", host: "prod.example.com", username: "deploy")
        let service = EncryptedProfileSharingService()
        let data = try service.exportData(profiles: [profile], passphrase: "correct")

        XCTAssertThrowsError(try service.importProfiles(from: data, passphrase: "wrong"))
    }
}
