import Foundation

struct MetricsExportService {
    func csv(
        server: ServerProfile,
        metrics: ServerMetrics,
        events: [ServerEvent]
    ) -> String {
        var lines: [String] = []
        lines.append("SysPulse export,\(server.name),\(ISO8601DateFormatter().string(from: .now))")
        lines.append("")
        lines.append("Metric,Value")
        lines.append("CPU %,\(Int(metrics.cpuUsage))")
        lines.append("RAM %,\(Int(metrics.ramUsage))")
        lines.append("Disk %,\(Int(metrics.diskUsage))")
        lines.append("Health,\(metrics.healthScore)")
        lines.append("Uptime,\"\(metrics.uptime)\"")
        lines.append("OS,\"\(metrics.osName)\"")
        lines.append("")
        lines.append("CPU history")
        lines.append(metrics.cpuHistory.map { String(format: "%.1f", $0) }.joined(separator: ","))
        lines.append("RAM history")
        lines.append(metrics.ramHistory.map { String(format: "%.1f", $0) }.joined(separator: ","))
        lines.append("")
        lines.append("Health events")
        lines.append("Time,Severity,Title,Details")
        let formatter = ISO8601DateFormatter()
        for event in events.prefix(200) {
            let time = formatter.string(from: event.createdAt)
            let details = event.details.replacingOccurrences(of: "\"", with: "'")
            lines.append("\(time),\(event.severity),\"\(event.title)\",\"\(details)\"")
        }
        return lines.joined(separator: "\n")
    }
}
