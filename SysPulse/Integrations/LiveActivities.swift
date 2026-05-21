import ActivityKit
import Foundation

struct ServerMonitorAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var cpuUsage: Double
        var diskUsage: Double
        var message: String
    }

    var serverName: String
}

@available(iOS 16.2, *)
@MainActor
final class LiveActivityService {
    private var activity: Activity<ServerMonitorAttributes>?

    func startMonitoring(server: ServerProfile, metrics: ServerMetrics) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = ServerMonitorAttributes(serverName: server.name)
        let content = ServerMonitorAttributes.ContentState(
            status: server.status.title,
            cpuUsage: metrics.cpuUsage,
            diskUsage: metrics.diskUsage,
            message: L10n.string("Monitoring active")
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: content, staleDate: .now.addingTimeInterval(900))
            )
        } catch {
            activity = nil
        }
    }

    func update(metrics: ServerMetrics, message: String) async {
        let content = ServerMonitorAttributes.ContentState(
            status: HealthRating.rating(for: metrics.healthScore).rawValue,
            cpuUsage: metrics.cpuUsage,
            diskUsage: metrics.diskUsage,
            message: message
        )
        await activity?.update(ActivityContent(state: content, staleDate: .now.addingTimeInterval(900)))
    }

    func end() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
    }
}
