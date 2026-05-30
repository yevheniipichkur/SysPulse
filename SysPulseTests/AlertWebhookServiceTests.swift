import XCTest
@testable import SysPulse

final class AlertWebhookServiceTests: XCTestCase {
    func testSamplePayloadEncodes() throws {
        let payload = WebhookPreset.samplePayload()
        let data = try JSONEncoder().encode(payload)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["serverName"] as? String, "sample-server")
        XCTAssertEqual(json?["metricKey"] as? String, "cpu")
    }

    func testInvalidEndpointThrows() async {
        let service = AlertWebhookService()
        do {
            try await service.sendSample(to: "not-a-url")
            XCTFail("Expected bad URL")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }
}
