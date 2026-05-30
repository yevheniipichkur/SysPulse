import Foundation

struct AlertWebhookPayload: Encodable {
    var serverName: String
    var serverHost: String
    var metricKey: String
    var metricTitle: String
    var value: Double
    var threshold: Double
    var message: String
    var firedAt: Date
}

struct AlertWebhookService {
    func send(payload: AlertWebhookPayload, to endpoint: String) async throws {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
