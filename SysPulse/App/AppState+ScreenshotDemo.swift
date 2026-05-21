import Foundation

extension AppState {
    func configureScreenshotDemo() {
        hasSeenOnboarding = true
        isSecurityUnlocked = true
        isPrivacyShieldVisible = false
        isSecurityPromptInProgress = false
        securityLockMessage = ""

        settings.requiresBiometrics = false
        settings.appearanceMode = .dark
        settings.language = .english
        settings.iCloudSyncEnabled = true
        settings.forceProOverride = true
        settings.terminalTheme = .cyberGlass
        settings.terminalFontSize = 15
        settings.reduceAnimations = true

        subscription = SubscriptionState(
            plan: .lifetime,
            isActive: true,
            expiresAt: nil,
            productsLoaded: true,
            lastStoreKitMessage: "Lifetime Pro active for screenshots."
        )
        areNotificationsAuthorized = true
        alertRules = AlertRule.defaultRules()

        let api = ServerProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Production API",
            host: "api.sys.example",
            username: "deploy",
            authenticationType: .privateKey,
            credentialIdentifier: "screenshot-api",
            tags: ["docker", "nginx"],
            groupName: "Cloud",
            icon: "cloud",
            accentHex: "#33C2EA",
            serverType: .dockerHost,
            status: .online
        )
        let db = ServerProfile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Postgres Primary",
            host: "10.0.4.12",
            username: "admin",
            authenticationType: .privateKeyWithPassphrase,
            credentialIdentifier: "screenshot-db",
            tags: ["database", "backup"],
            groupName: "Cloud",
            icon: "cylinder.split.1x2",
            accentHex: "#34C759",
            serverType: .databaseServer,
            status: .warning
        )
        let nas = ServerProfile(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Home NAS",
            host: "nas.local",
            username: "yevhenii",
            authenticationType: .password,
            credentialIdentifier: "screenshot-nas",
            tags: ["storage", "media"],
            groupName: "Home Lab",
            icon: "externaldrive.connected.to.line.below",
            accentHex: "#FF9F0A",
            serverType: .nas,
            status: .online
        )

        serverProfiles = [api, db, nas]
        selectedServer = api
        selectedTab = screenshotSelectedTab()
        metricsByServer = [
            api.id: screenshotMetrics(
                serverID: api.id,
                cpu: 37,
                ram: 58,
                swap: 4,
                disk: 64,
                networkIn: 128,
                networkOut: 42,
                temperature: 62,
                uptime: "18d 6h",
                osName: "Ubuntu 24.04 LTS",
                kernel: "6.8.0-52-generic",
                loadAverage: "0.42 0.51 0.47",
                ipAddresses: ["10.0.2.24", "172.18.0.1"],
                healthScore: 91,
                failedServices: 0,
                dockerRunning: 12,
                dockerTotal: 14
            ),
            db.id: screenshotMetrics(
                serverID: db.id,
                cpu: 72,
                ram: 81,
                swap: 18,
                disk: 78,
                networkIn: 88,
                networkOut: 21,
                temperature: 69,
                uptime: "42d 11h",
                osName: "Debian 12",
                kernel: "6.1.0-21-amd64",
                loadAverage: "1.92 1.48 1.22",
                ipAddresses: ["10.0.4.12"],
                healthScore: 74,
                failedServices: 1,
                dockerRunning: 3,
                dockerTotal: 4
            ),
            nas.id: screenshotMetrics(
                serverID: nas.id,
                cpu: 22,
                ram: 43,
                swap: 1,
                disk: 56,
                networkIn: 44,
                networkOut: 79,
                temperature: 47,
                uptime: "9d 2h",
                osName: "TrueNAS SCALE",
                kernel: "6.6.20-production",
                loadAverage: "0.18 0.24 0.30",
                ipAddresses: ["192.168.1.40"],
                healthScore: 88,
                failedServices: 0,
                dockerRunning: 5,
                dockerTotal: 5
            )
        ]

        processItemsByServer = [
            api.id: [
                ProcessInfoItem(pid: 1024, user: "www-data", command: "nginx: worker", cpu: 8.2, memory: 2.1),
                ProcessInfoItem(pid: 2158, user: "deploy", command: "node server.js", cpu: 22.8, memory: 14.4),
                ProcessInfoItem(pid: 3110, user: "root", command: "dockerd", cpu: 5.9, memory: 8.7)
            ]
        ]
        diskInfoByServer = [
            api.id: [
                DiskInfo(mountPoint: "/", filesystem: "/dev/nvme0n1p2", usedGB: 68.4, freeGB: 38.2, usagePercent: 64, smartStatus: "PASSED"),
                DiskInfo(mountPoint: "/var/lib/docker", filesystem: "/dev/nvme1n1", usedGB: 214.8, freeGB: 96.1, usagePercent: 69, smartStatus: "PASSED")
            ]
        ]
        dockerContainersByServer = [
            api.id: [
                DockerContainer(id: "web", name: "web-api", image: "sys/api:latest", status: "Up 18 hours", cpuUsage: 14.2, memoryUsage: 34.5, restartedRecently: false),
                DockerContainer(id: "redis", name: "redis-cache", image: "redis:7", status: "Up 18 hours", cpuUsage: 2.1, memoryUsage: 12.4, restartedRecently: false),
                DockerContainer(id: "worker", name: "queue-worker", image: "sys/worker:latest", status: "Restarting", cpuUsage: 0, memoryUsage: 0, restartedRecently: true)
            ]
        ]
        systemdServicesByServer = [
            api.id: [
                SystemdServiceItem(name: "ssh.service", loadedState: "loaded", activeState: "active", subState: "running", isFailed: false),
                SystemdServiceItem(name: "docker.service", loadedState: "loaded", activeState: "active", subState: "running", isFailed: false),
                SystemdServiceItem(name: "backup.timer", loadedState: "loaded", activeState: "active", subState: "waiting", isFailed: false)
            ]
        ]
        logEntriesByServer = [
            api.id: [
                LogEntry(timestamp: "10:42:18", source: "nginx", message: "Reloaded TLS certificates successfully", severity: .safe),
                LogEntry(timestamp: "10:39:07", source: "docker", message: "Container queue-worker restarted after health check", severity: .moderate),
                LogEntry(timestamp: "10:31:44", source: "systemd", message: "Started Daily apt download activities", severity: .safe)
            ]
        ]
        terminalSessions = [
            TerminalSession(
                serverID: api.id,
                title: api.name,
                transcript: screenshotTerminalTranscript(for: api)
            )
        ]
        lastCommandOutput = """
        deploy@api.sys.example
        CPU 37%  RAM 58%  Disk 64%
        Docker: 12 running / 14 total
        """
    }

    private func screenshotSelectedTab() -> AppTab {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-sysPulseScreenshotTab"),
              arguments.indices.contains(index + 1),
              let tab = AppTab(rawValue: arguments[index + 1]) else {
            return .servers
        }
        return tab
    }

    private func screenshotMetrics(
        serverID: UUID,
        cpu: Double,
        ram: Double,
        swap: Double,
        disk: Double,
        networkIn: Double,
        networkOut: Double,
        temperature: Double,
        uptime: String,
        osName: String,
        kernel: String,
        loadAverage: String,
        ipAddresses: [String],
        healthScore: Int,
        failedServices: Int,
        dockerRunning: Int,
        dockerTotal: Int
    ) -> ServerMetrics {
        ServerMetrics(
            serverID: serverID,
            timestamp: .now,
            cpuUsage: cpu,
            ramUsage: ram,
            swapUsage: swap,
            diskUsage: disk,
            networkInMB: networkIn,
            networkOutMB: networkOut,
            temperatureCelsius: temperature,
            uptime: uptime,
            osName: osName,
            kernel: kernel,
            loadAverage: loadAverage,
            ipAddresses: ipAddresses,
            healthScore: healthScore,
            cpuHistory: [28, 31, 26, 42, 38, 48, 37, cpu],
            ramHistory: [48, 50, 53, 51, 57, 59, 56, ram],
            diskHistory: [61, 61, 62, 62, 63, 63, 64, disk],
            failedServices: failedServices,
            dockerRunning: dockerRunning,
            dockerTotal: dockerTotal
        )
    }

    func screenshotTerminalTranscript(for server: ServerProfile) -> String {
        """
        \(server.username)@\(server.host):~ $ uptime
         10:42:18 up 18 days, 6:14, 1 user, load average: 0.42, 0.51, 0.47
        \(server.username)@\(server.host):~ $ docker ps --format 'table {{.Names}}\\t{{.Status}}'
        NAMES          STATUS
        web-api        Up 18 hours
        redis-cache    Up 18 hours
        queue-worker   Restarting
        \(server.username)@\(server.host):~ $
        """
    }
}
