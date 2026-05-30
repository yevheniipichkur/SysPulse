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

enum WebhookPreset: String, CaseIterable, Identifiable {
    case custom
    case slack
    case telegram

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .custom: "Custom URL"
        case .slack: "Slack incoming webhook"
        case .telegram: "Telegram Bot API"
        }
    }

    func apply(to settings: inout AppSettings, botToken: String = "", chatID: String = "") {
        switch self {
        case .custom:
            break
        case .slack:
            break
        case .telegram:
            let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let chat = chatID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, !chat.isEmpty else { return }
            settings.alertWebhookEndpoint = "https://api.telegram.org/bot\(token)/sendMessage?chat_id=\(chat)"
        }
    }

    static func samplePayload() -> AlertWebhookPayload {
        AlertWebhookPayload(
            serverName: "sample-server",
            serverHost: "10.0.0.1",
            metricKey: "cpu",
            metricTitle: "CPU threshold",
            value: 92.5,
            threshold: 85,
            message: L10n.string("SysPulse sample alert — webhook is configured correctly."),
            firedAt: .now
        )
    }
}

struct AlertWebhookService {
    func sendSample(to endpoint: String) async throws {
        try await send(payload: WebhookPreset.samplePayload(), to: endpoint)
    }

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
