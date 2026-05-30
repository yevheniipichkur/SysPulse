import Foundation

struct DiagnosticFinding: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var severity: String
    var suggestedCommand: String?
}

struct DiagnosticPackResult: Identifiable {
    var id = UUID()
    var findings: [DiagnosticFinding]
    var rawSections: [(title: String, output: String)]
}

struct DiagnosticPackService {
    private let processService = ProcessService()
    private let diskService = DiskService()
    private let systemdService = SystemdService()

    func collect(
        server: ServerProfile,
        metrics: ServerMetrics,
        failedServices: Int,
        using client: SSHClientProtocol
    ) async throws -> DiagnosticPackResult {
        var sections: [(String, String)] = []
        var findings: [DiagnosticFinding] = []

        let commands: [(String, String)] = [
            ("Top CPU", processService.topCPUCommand()),
            ("Top memory", processService.topMemoryCommand()),
            ("Disk usage", diskService.usageCommand()),
            ("Failed units", systemdService.failedUnitsCommand())
        ]

        for (title, command) in commands {
            let output = try await client.run(command, on: server)
            sections.append((title, output))
        }

        if metrics.cpuUsage >= 85 {
            findings.append(
                DiagnosticFinding(
                    id: "cpu",
                    title: "High CPU",
                    detail: "CPU is at \(Int(metrics.cpuUsage))%. Inspect top processes.",
                    symbol: "cpu",
                    severity: "Warning",
                    suggestedCommand: processService.topCPUCommand()
                )
            )
        }

        if metrics.ramUsage >= 85 {
            findings.append(
                DiagnosticFinding(
                    id: "ram",
                    title: "High RAM",
                    detail: "RAM is at \(Int(metrics.ramUsage))%. Check memory hogs.",
                    symbol: "memorychip",
                    severity: "Warning",
                    suggestedCommand: processService.topMemoryCommand()
                )
            )
        }

        if metrics.diskUsage >= 85 {
            findings.append(
                DiagnosticFinding(
                    id: "disk",
                    title: "High disk usage",
                    detail: "Disk is at \(Int(metrics.diskUsage))%. Free space or rotate logs.",
                    symbol: "externaldrive",
                    severity: "Warning",
                    suggestedCommand: diskService.usageCommand()
                )
            )
        }

        if failedServices > 0 {
            findings.append(
                DiagnosticFinding(
                    id: "systemd",
                    title: "Failed services",
                    detail: "\(failedServices) systemd units are failing.",
                    symbol: "gearshape.2",
                    severity: "Dangerous",
                    suggestedCommand: systemdService.failedUnitsCommand()
                )
            )
        }

        if metrics.healthScore <= 55 {
            findings.append(
                DiagnosticFinding(
                    id: "health",
                    title: "Low health score",
                    detail: "Health score is \(metrics.healthScore). Review metrics and logs.",
                    symbol: "heart.text.square",
                    severity: "Warning",
                    suggestedCommand: nil
                )
            )
        }

        if findings.isEmpty {
            findings.append(
                DiagnosticFinding(
                    id: "ok",
                    title: "No critical signals",
                    detail: "Diagnostics did not detect immediate issues. Keep monitoring trends.",
                    symbol: "checkmark.seal",
                    severity: "Safe",
                    suggestedCommand: nil
                )
            )
        }

        return DiagnosticPackResult(findings: findings, rawSections: sections)
    }
}
