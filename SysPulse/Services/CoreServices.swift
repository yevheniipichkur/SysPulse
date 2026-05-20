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
                    details: "One or more units need attention.",
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
    func collect(server: ServerProfile, using client: SSHClientProtocol, previous: ServerMetrics? = nil) async throws -> ServerMetrics {
        if server.isDemo {
            return DemoDataService.makeMetrics(for: [server])[server.id] ?? .empty(serverID: server.id)
        }

        let output = try await client.run(Self.metricsCommand, on: server)
        return parseMetrics(output, serverID: server.id, previous: previous)
    }

    func parseMetrics(_ output: String, serverID: UUID, previous: ServerMetrics? = nil) -> ServerMetrics {
        let values = Dictionary(
            uniqueKeysWithValues: output
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> (String, String)? in
                    let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2 else { return nil }
                    return (String(parts[0]), String(parts[1]))
                }
        )

        let cpu = values.double("CPU")
        let ram = values.double("RAM")
        let disk = values.double("DISK")
        let swap = values.double("SWAP")
        let temperature = values.doubleOptional("TEMP")
        let failedServices = values.int("FAILED_SERVICES")
        let dockerRunning = values.int("DOCKER_RUNNING")
        let dockerTotal = values.int("DOCKER_TOTAL")
        let loadAverage = values["LOAD"]?.nonEmpty ?? "-"
        let metrics = ServerMetrics(
            serverID: serverID,
            timestamp: .now,
            cpuUsage: cpu,
            ramUsage: ram,
            swapUsage: swap,
            diskUsage: disk,
            networkInMB: values.double("NET_RX_MB"),
            networkOutMB: values.double("NET_TX_MB"),
            temperatureCelsius: temperature,
            uptime: values["UPTIME"]?.nonEmpty ?? "Unknown",
            osName: values["OS"]?.nonEmpty ?? "Unknown Linux",
            kernel: values["KERNEL"]?.nonEmpty ?? "-",
            loadAverage: loadAverage,
            ipAddresses: values["IPS"]?
                .split(separator: " ")
                .map(String.init)
                .filter { !$0.isEmpty } ?? [],
            healthScore: HealthScoreService.calculate(
                cpu: cpu,
                ram: ram,
                disk: disk,
                temperature: temperature,
                failedServices: failedServices,
                dockerRunning: dockerRunning,
                dockerTotal: dockerTotal,
                loadAverage: loadAverage
            ),
            cpuHistory: (previous?.cpuHistory ?? []).appending(cpu, keepingLast: 18),
            ramHistory: (previous?.ramHistory ?? []).appending(ram, keepingLast: 18),
            diskHistory: (previous?.diskHistory ?? []).appending(disk, keepingLast: 18),
            failedServices: failedServices,
            dockerRunning: dockerRunning,
            dockerTotal: dockerTotal
        )
        return metrics
    }

    static let metricsCommand = #"""
    sh <<'SYSPULSE'
    read _ u1 n1 s1 i1 w1 q1 r1 st1 _ < /proc/stat
    idle1=$((i1+w1)); total1=$((u1+n1+s1+i1+w1+q1+r1+st1))
    sleep 1
    read _ u2 n2 s2 i2 w2 q2 r2 st2 _ < /proc/stat
    idle2=$((i2+w2)); total2=$((u2+n2+s2+i2+w2+q2+r2+st2))
    totald=$((total2-total1)); idled=$((idle2-idle1))
    if [ "$totald" -gt 0 ]; then cpu=$((100*(totald-idled)/totald)); else cpu=0; fi
    printf "CPU=%s\n" "$cpu"
    awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{if(t>0) printf "RAM=%.0f\n", (t-a)*100/t; else print "RAM=0"}' /proc/meminfo
    awk '/SwapTotal/{t=$2}/SwapFree/{f=$2}END{if(t>0) printf "SWAP=%.0f\n", (t-f)*100/t; else print "SWAP=0"}' /proc/meminfo
    df -P / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print "DISK="$5}'
    load=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null)
    printf "LOAD=%s\n" "$load"
    uptime_value=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo Unknown)
    printf "UPTIME=%s\n" "$uptime_value"
    os_value=$(awk -F= '/^PRETTY_NAME=/{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null)
    printf "OS=%s\n" "${os_value:-Unknown Linux}"
    printf "KERNEL=%s\n" "$(uname -r 2>/dev/null || echo -)"
    printf "IPS=%s\n" "$(hostname -I 2>/dev/null | xargs)"
    if [ -r /sys/class/thermal/thermal_zone0/temp ]; then awk '{printf "TEMP=%.0f\n", $1/1000}' /sys/class/thermal/thermal_zone0/temp; else echo "TEMP="; fi
    systemctl --failed --no-legend >/tmp/syspulse_failed_$$ 2>/dev/null; printf "FAILED_SERVICES=%s\n" "$(wc -l < /tmp/syspulse_failed_$$ 2>/dev/null | xargs)"; rm -f /tmp/syspulse_failed_$$
    printf "DOCKER_RUNNING=%s\n" "$(docker ps -q 2>/dev/null | wc -l | xargs)"
    printf "DOCKER_TOTAL=%s\n" "$(docker ps -aq 2>/dev/null | wc -l | xargs)"
    awk -F'[: ]+' 'NR>2{rx+=$3; tx+=$11}END{printf "NET_RX_MB=%.0f\nNET_TX_MB=%.0f\n", rx/1024/1024, tx/1024/1024}' /proc/net/dev 2>/dev/null
    SYSPULSE
    """#
}

private extension Dictionary where Key == String, Value == String {
    func double(_ key: String) -> Double {
        Double(self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }

    func doubleOptional(_ key: String) -> Double? {
        Double(self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    func int(_ key: String) -> Int {
        Int(self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == Double {
    func appending(_ value: Double, keepingLast limit: Int) -> [Double] {
        Array((self + [value]).suffix(limit))
    }
}

struct CommandRunner {
    func requiresConfirmation(_ command: QuickCommand) -> Bool {
        command.safety == .dangerous || Self.containsDangerousToken(command.command)
    }

    static func containsDangerousToken(_ command: String) -> Bool {
        CommandSafetyAnalyzer().analyze(command).requiresConfirmation
    }
}

struct CommandSafetyAnalyzer {
    struct Result: Hashable {
        var level: CommandSafetyLevel
        var reasons: [String]

        var requiresConfirmation: Bool {
            level == .dangerous || level == .moderate
        }
    }

    private let mutatingUFWActions = ["allow", "deny", "delete", "disable", "enable", "insert", "limit", "reject", "reset"]
    private let packageManagers = ["apt", "apt-get", "dnf", "pacman", "apk"]
    private let mutatingPackageActions = ["update", "install", "remove", "upgrade", "dist-upgrade", "autoremove", "clean", "add", "-s", "-syu"]

    func analyze(_ command: String) -> Result {
        let tokens = tokenize(command)
        guard !tokens.isEmpty else {
            return Result(level: .safe, reasons: [])
        }

        var reasons: [String] = []

        if tokens.contains("reboot") {
            reasons.append("Reboots the remote server.")
        }
        if tokens.contains("shutdown") || tokens.contains("poweroff") || tokens.contains("halt") {
            reasons.append("Can power off the remote server.")
        }
        if tokens.contains("rm") {
            reasons.append("Deletes files or directories.")
        }
        if tokens.contains("kill") || tokens.contains("killall") || tokens.contains("pkill") {
            reasons.append("Terminates running processes.")
        }
        if containsPair("docker", "rm", in: tokens) || containsPair("docker", "rmi", in: tokens) || containsPair("docker", "prune", in: tokens) {
            reasons.append("Can remove Docker resources.")
        }
        if containsPair("systemctl", "stop", in: tokens) || containsPair("systemctl", "disable", in: tokens) || containsPair("service", "stop", in: tokens) {
            reasons.append("Can stop or disable services.")
        }
        if let ufwIndex = tokens.firstIndex(of: "ufw") {
            let tail = tokens.dropFirst(ufwIndex + 1)
            if tail.contains(where: { mutatingUFWActions.contains($0) }) {
                reasons.append("Changes firewall rules.")
            }
        }

        if !reasons.isEmpty {
            return Result(level: .dangerous, reasons: reasons)
        }

        if tokens.contains(where: { packageManagers.contains($0) }) &&
            tokens.contains(where: { mutatingPackageActions.contains($0) }) {
            return Result(level: .moderate, reasons: ["Changes packages or system state."])
        }

        return Result(level: .safe, reasons: [])
    }

    func tokenize(_ command: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ";&|()[]{}<>`'\""))
        return command
            .lowercased()
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func containsPair(_ first: String, _ second: String, in tokens: [String]) -> Bool {
        guard tokens.count > 1 else { return false }
        return zip(tokens, tokens.dropFirst()).contains { pair in
            pair.0 == first && pair.1 == second
        }
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

    func installCommand(for distribution: LinuxDistribution) -> String {
        distribution.installCommand
    }
}

struct DockerService {
    func listContainersCommand() -> String {
        "docker ps --format '{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}'"
    }

    func statsCommand() -> String {
        "docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemPerc}}'"
    }

    func logsCommand(containerName: String, lines: Int = 200) -> String {
        "docker logs --tail \(lines) \(containerName)"
    }

    func actionCommand(action: String, containerName: String) -> String {
        "docker \(action) \(containerName)"
    }

    func containers(for server: ServerProfile) -> [DockerContainer] {
        DemoDataService.makeContainers()
    }
}

struct SystemdService {
    func failedUnitsCommand() -> String {
        "systemctl --failed --no-pager"
    }

    func statusCommand(serviceName: String) -> String {
        "systemctl status \(serviceName) --no-pager"
    }

    func actionCommand(action: String, serviceName: String) -> String {
        "sudo systemctl \(action) \(serviceName)"
    }

    func services(for server: ServerProfile) -> [SystemdServiceItem] {
        DemoDataService.makeServices()
    }
}

struct LogsService {
    func journalCommand(unit: String? = nil, lines: Int = 200) -> String {
        if let unit, !unit.isEmpty {
            return "journalctl -u \(unit) -n \(lines) --no-pager"
        }
        return "journalctl -n \(lines) --no-pager"
    }

    func dmesgCommand(lines: Int = 120) -> String {
        "dmesg --ctime | tail -n \(lines)"
    }

    func nginxErrorLogCommand(lines: Int = 200) -> String {
        "tail -n \(lines) /var/log/nginx/error.log"
    }

    func recentLogs(for server: ServerProfile) -> [String] {
        [
            "May 19 19:23:42 \(server.name) systemd[1]: Started Docker Application Container Engine.",
            "May 19 19:24:08 \(server.name) sshd[9021]: Accepted publickey for \(server.username).",
            "May 19 19:25:11 \(server.name) kernel: EXT4-fs mounted filesystem with ordered data mode."
        ]
    }
}

struct WidgetDataService {
    private let store: WidgetSnapshotStore

    init(store: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.store = store
    }

    func save(profiles: [ServerProfile], metricsByServer: [UUID: ServerMetrics]) {
        let snapshots = profiles.prefix(8).map { profile in
            let metrics = metricsByServer[profile.id] ?? .empty(serverID: profile.id)
            return WidgetServerSnapshot(
                id: profile.id,
                name: profile.name,
                status: profile.status.title,
                cpu: metrics.cpuUsage,
                ram: metrics.ramUsage,
                disk: metrics.diskUsage,
                health: metrics.healthScore,
                uptime: metrics.uptime,
                osName: metrics.osName,
                updatedAt: metrics.timestamp
            )
        }
        store.save(WidgetSnapshotEnvelope(generatedAt: .now, servers: snapshots))
    }

    func load() -> WidgetSnapshotEnvelope {
        store.load() ?? .placeholder
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
