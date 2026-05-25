import Foundation

enum BackendMonitoringServiceError: LocalizedError {
    case invalidEndpoint
    case invalidResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            L10n.string("Backend monitoring endpoint is not a valid URL.")
        case .invalidResponse(let statusCode):
            L10n.string("Backend monitoring returned HTTP %@.", "\(statusCode)")
        }
    }
}

struct BackendMonitoringService {
    func sendSnapshot(
        endpoint: String,
        token: String?,
        payload: BackendMonitoringPayload
    ) async throws {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedEndpoint),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw BackendMonitoringServiceError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder.backendMonitoring.encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BackendMonitoringServiceError.invalidResponse(httpResponse.statusCode)
        }
    }
}

struct BackendMonitoringPayload: Encodable, Sendable {
    var app = "SysPulse"
    var event = "metric_snapshot"
    var sentAt = Date()
    var server: BackendMonitoringServerPayload
    var metrics: BackendMonitoringMetricsPayload

    init(server: ServerProfile, metrics: ServerMetrics) {
        self.server = BackendMonitoringServerPayload(server: server)
        self.metrics = BackendMonitoringMetricsPayload(metrics: metrics)
    }
}

struct BackendMonitoringServerPayload: Encodable, Sendable {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var type: String
    var status: String

    init(server: ServerProfile) {
        id = server.id
        name = server.name
        host = server.host
        port = server.port
        username = server.username
        type = server.serverType.rawValue
        status = server.status.rawValue
    }
}

struct BackendMonitoringMetricsPayload: Encodable, Sendable {
    var timestamp: Date
    var cpuUsage: Double
    var ramUsage: Double
    var swapUsage: Double
    var diskUsage: Double
    var networkInMB: Double
    var networkOutMB: Double
    var temperatureCelsius: Double?
    var uptime: String
    var osName: String
    var kernel: String
    var loadAverage: String
    var ipAddresses: [String]
    var healthScore: Int
    var failedServices: Int
    var dockerRunning: Int
    var dockerTotal: Int

    init(metrics: ServerMetrics) {
        timestamp = metrics.timestamp
        cpuUsage = metrics.cpuUsage
        ramUsage = metrics.ramUsage
        swapUsage = metrics.swapUsage
        diskUsage = metrics.diskUsage
        networkInMB = metrics.networkInMB
        networkOutMB = metrics.networkOutMB
        temperatureCelsius = metrics.temperatureCelsius
        uptime = metrics.uptime
        osName = metrics.osName
        kernel = metrics.kernel
        loadAverage = metrics.loadAverage
        ipAddresses = metrics.ipAddresses
        healthScore = metrics.healthScore
        failedServices = metrics.failedServices
        dockerRunning = metrics.dockerRunning
        dockerTotal = metrics.dockerTotal
    }
}

private extension JSONEncoder {
    static var backendMonitoring: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
