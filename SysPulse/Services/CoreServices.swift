import Foundation
import UserNotifications

struct HealthScoreService {
    func score(for metrics: ServerMetrics) -> Int {
        Self.calculate(
            cpu: metrics.cpuUsage,
            ram: metrics.ramUsage,
            disk: metrics.diskUsage,
            temperature: metrics.temperatureCelsius,
            failedServices: metrics.failedServices,
            dockerRunning: metrics.dockerRunning,
            dockerTotal: metrics.dockerTotal,
            loadAverage: metrics.loadAverage
        )
    }

    static func calculate(
        cpu: Double,
        ram: Double,
        disk: Double,
        temperature: Double?,
        failedServices: Int,
        dockerRunning: Int,
        dockerTotal: Int,
        loadAverage: String
    ) -> Int {
        var score = 100
        score -= cpu > 90 ? 18 : cpu > 75 ? 10 : cpu > 60 ? 5 : 0
        score -= ram > 90 ? 16 : ram > 80 ? 9 : ram > 70 ? 5 : 0
        score -= disk > 90 ? 22 : disk > 80 ? 12 : disk > 70 ? 5 : 0
        if let temperature {
            score -= temperature > 80 ? 18 : temperature > 70 ? 10 : temperature > 60 ? 5 : 0
        }
        score -= min(failedServices * 8, 24)
        if dockerTotal > 0 {
            score -= max(dockerTotal - dockerRunning, 0) * 5
        }
        return min(max(score, 0), 100)
    }
}

struct InsightsService {
    func makeInsights(for metrics: ServerMetrics) -> [SmartInsight] {
        var insights: [SmartInsight] = []

        if metrics.diskUsage >= 85 {
            insights.append(
                SmartInsight(
                    title: "Disk usage is above 85%",
                    details: "Consider cleaning logs, Docker images or package caches.",
                    severity: metrics.diskUsage >= 90 ? .dangerous : .moderate,
                    symbol: "externaldrive.badge.exclamationmark"
                )
            )
        }

        if let temperature = metrics.temperatureCelsius, temperature >= 70 {
            insights.append(
                SmartInsight(
                    title: "CPU temperature is high",
                    details: "Check cooling, dust and throttling on this machine.",
                    severity: temperature >= 80 ? .dangerous : .moderate,
                    symbol: "thermometer.high"
                )
            )
        }

        if metrics.failedServices > 0 {
            insights.append(
                SmartInsight(
                    title: "There are failed systemd services",
                    details: "\(metrics.failedServices) unit needs attention.",
                    severity: .moderate,
                    symbol: "xmark.seal"
                )
            )
        }

        if metrics.swapUsage > 25 {
            insights.append(
                SmartInsight(
                    title: "Swap usage is increasing",
                    details: "Memory pressure may be affecting performance.",
                    severity: .moderate,
                    symbol: "memorychip"
                )
            )
        }

        if metrics.uptime.contains("120") {
            insights.append(
                SmartInsight(
                    title: "Server has been online for 120 days",
                    details: "Schedule maintenance and security updates.",
                    severity: .safe,
                    symbol: "clock.badge.checkmark"
                )
            )
        }

        if metrics.networkInMB + metrics.networkOutMB > 1_200 {
            insights.append(
                SmartInsight(
                    title: "Network traffic is unusually high",
                    details: "Review active services and open ports.",
                    severity: .moderate,
                    symbol: "network"
                )
            )
        }

        if insights.isEmpty {
            insights.append(
                SmartInsight(
                    title: "Everything looks calm",
                    details: "No urgent issues were detected in the latest snapshot.",
                    severity: .safe,
                    symbol: "checkmark.seal"
                )
            )
        }

        return insights
    }
}

struct MetricsCollector {
    func collect(server: ServerProfile, using client: SSHClientProtocol) async throws -> ServerMetrics {
        _ = try await client.run("uptime", on: server)
        return DemoDataService.makeMetrics(for: [server])[server.id] ?? .empty(serverID: server.id)
    }
}

struct CommandRunner {
    func requiresConfirmation(_ command: QuickCommand) -> Bool {
        command.safety == .dangerous || Self.containsDangerousToken(command.command)
    }

    static func containsDangerousToken(_ command: String) -> Bool {
        let lowered = command.lowercased()
        return ["reboot", "shutdown", " rm ", "docker rm", "systemctl stop", " kill ", "ufw "]
            .contains { lowered.contains($0) }
    }
}

struct PackageDetector {
    let packageStatuses: [PackageStatus] = [
        PackageStatus(commandName: "sensors", packageName: "lm-sensors", isInstalled: false, featureImpact: "Temperature monitoring"),
        PackageStatus(commandName: "docker", packageName: "docker", isInstalled: true, featureImpact: "Docker monitoring"),
        PackageStatus(commandName: "jq", packageName: "jq", isInstalled: true, featureImpact: "JSON parsing for advanced diagnostics"),
        PackageStatus(commandName: "htop", packageName: "htop", isInstalled: false, featureImpact: "Process diagnostics"),
        PackageStatus(commandName: "smartctl", packageName: "smartmontools", isInstalled: false, featureImpact: "SMART disk health"),
        PackageStatus(commandName: "sar", packageName: "sysstat", isInstalled: false, featureImpact: "Historical CPU and network metrics")
    ]

    func missingTools() -> [MissingTool] {
        packageStatuses
            .filter { !$0.isInstalled }
            .map {
                MissingTool(
                    commandName: $0.commandName,
                    packageName: $0.packageName,
                    reason: $0.featureImpact,
                    unavailableFeatures: [$0.featureImpact]
                )
            }
    }

    func checkCommandsPreview() -> [String] {
        ["command -v sensors", "command -v docker", "command -v jq", "command -v htop", "command -v smartctl", "command -v sar"]
    }
}

struct DockerService {
    func containers(for server: ServerProfile) -> [DockerContainer] {
        DemoDataService.makeContainers()
    }
}

struct SystemdService {
    func services(for server: ServerProfile) -> [SystemdServiceItem] {
        DemoDataService.makeServices()
    }
}

struct LogsService {
    func recentLogs(for server: ServerProfile) -> [String] {
        [
            "May 19 19:23:42 \(server.name) systemd[1]: Started Docker Application Container Engine.",
            "May 19 19:24:08 \(server.name) sshd[9021]: Accepted publickey for \(server.username).",
            "May 19 19:25:11 \(server.name) kernel: EXT4-fs mounted filesystem with ordered data mode."
        ]
    }
}

struct WidgetDataService {
    private let key = "SysPulse.latestWidgetMetrics"

    func save(metrics: ServerMetrics) {
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func load() -> ServerMetrics? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ServerMetrics.self, from: data)
    }
}

struct LocalizationService {
    func apply(language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: "SysPulse.language")
    }
}

final class NotificationService {
    func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }
}

struct GitBuildInfoService {
    var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
