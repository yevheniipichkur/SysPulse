import Foundation

struct DemoDataService {
    static func makeDemoServers() -> [ServerProfile] {
        [
            ServerProfile(
                name: "Raspberry Pi Home Server",
                host: "192.168.1.24",
                username: "pi",
                tags: ["home", "arm64"],
                groupName: "Home Lab",
                icon: "cpu",
                accentHex: "#44D07B",
                serverType: .raspberryPi,
                status: .online,
                isDemo: true
            ),
            ServerProfile(
                name: "VPS Production",
                host: "prod.syspulse.example",
                username: "ubuntu",
                authenticationType: .privateKey,
                tags: ["prod", "nginx"],
                groupName: "Cloud",
                icon: "cloud",
                accentHex: "#39A7FF",
                serverType: .vps,
                status: .warning,
                isDemo: true
            ),
            ServerProfile(
                name: "Docker Lab",
                host: "10.0.0.42",
                username: "admin",
                authenticationType: .privateKeyWithPassphrase,
                tags: ["docker", "lab"],
                groupName: "Containers",
                icon: "shippingbox",
                accentHex: "#B56CFF",
                serverType: .dockerHost,
                status: .online,
                isDemo: true
            )
        ]
    }

    static func makeMetrics(for servers: [ServerProfile]) -> [UUID: ServerMetrics] {
        Dictionary(uniqueKeysWithValues: servers.map { server in
            let metrics: ServerMetrics
            switch server.serverType {
            case .raspberryPi:
                metrics = ServerMetrics(
                    serverID: server.id,
                    timestamp: .now,
                    cpuUsage: 27,
                    ramUsage: 54,
                    swapUsage: 12,
                    diskUsage: 68,
                    networkInMB: 124,
                    networkOutMB: 87,
                    temperatureCelsius: 52,
                    uptime: "42d 3h",
                    osName: "Raspberry Pi OS 12",
                    kernel: "6.6.31+rpt",
                    loadAverage: "0.18 0.21 0.19",
                    ipAddresses: ["192.168.1.24", "fe80::a4d1"],
                    healthScore: 91,
                    cpuHistory: [18, 22, 19, 31, 25, 27, 23, 26, 27],
                    ramHistory: [48, 50, 51, 55, 54, 53, 56, 54, 54],
                    diskHistory: [64, 65, 65, 66, 66, 67, 67, 68, 68],
                    failedServices: 0,
                    dockerRunning: 3,
                    dockerTotal: 3
                )
            case .vps:
                metrics = ServerMetrics(
                    serverID: server.id,
                    timestamp: .now,
                    cpuUsage: 71,
                    ramUsage: 77,
                    swapUsage: 26,
                    diskUsage: 86,
                    networkInMB: 902,
                    networkOutMB: 621,
                    temperatureCelsius: nil,
                    uptime: "120d 9h",
                    osName: "Ubuntu 24.04 LTS",
                    kernel: "6.8.0-51-generic",
                    loadAverage: "1.81 1.44 1.28",
                    ipAddresses: ["203.0.113.42", "10.10.0.8"],
                    healthScore: 66,
                    cpuHistory: [38, 44, 52, 63, 68, 73, 70, 69, 71],
                    ramHistory: [61, 64, 70, 73, 76, 79, 78, 77, 77],
                    diskHistory: [79, 80, 82, 83, 84, 85, 86, 86, 86],
                    failedServices: 1,
                    dockerRunning: 5,
                    dockerTotal: 6
                )
            default:
                metrics = ServerMetrics(
                    serverID: server.id,
                    timestamp: .now,
                    cpuUsage: 42,
                    ramUsage: 63,
                    swapUsage: 8,
                    diskUsage: 57,
                    networkInMB: 384,
                    networkOutMB: 291,
                    temperatureCelsius: 46,
                    uptime: "8d 14h",
                    osName: "Debian 12",
                    kernel: "6.1.0-28-amd64",
                    loadAverage: "0.64 0.52 0.49",
                    ipAddresses: ["10.0.0.42"],
                    healthScore: 84,
                    cpuHistory: [22, 30, 28, 45, 52, 39, 41, 43, 42],
                    ramHistory: [55, 58, 59, 60, 61, 62, 63, 63, 63],
                    diskHistory: [52, 53, 54, 55, 56, 56, 57, 57, 57],
                    failedServices: 0,
                    dockerRunning: 9,
                    dockerTotal: 10
                )
            }
            return (server.id, metrics)
        })
    }

    static func makeQuickCommands() -> [QuickCommand] {
        [
            QuickCommand(title: "Check uptime", details: "Show current uptime and load average.", command: "uptime", safety: .safe),
            QuickCommand(title: "Check disk usage", details: "Display mounted filesystems and free space.", command: "df -h", safety: .safe),
            QuickCommand(title: "Check RAM", details: "Show memory and swap usage.", command: "free -h", safety: .safe),
            QuickCommand(title: "Show IP address", details: "List IPv4 and IPv6 addresses.", command: "ip addr show", safety: .safe),
            QuickCommand(title: "Basic update check", details: "Preview pending package updates.", command: "apt list --upgradable", safety: .moderate),
            QuickCommand(title: "Reboot server", details: "Restart the selected server after confirmation.", command: "sudo reboot", safety: .dangerous),
            QuickCommand(title: "Restart Docker container", details: "Restart a container by name.", command: "docker restart {container}", safety: .dangerous, isPremium: true, variables: ["container"]),
            QuickCommand(title: "Restart systemd service", details: "Restart a service by unit name.", command: "sudo systemctl restart {service}", safety: .dangerous, isPremium: true, variables: ["service"]),
            QuickCommand(title: "Tail logs", details: "Follow a log file.", command: "tail -n 200 -f {path}", safety: .moderate, isPremium: true, variables: ["path"]),
            QuickCommand(title: "Clean apt cache", details: "Remove cached package files.", command: "sudo apt clean", safety: .moderate, isPremium: true),
            QuickCommand(title: "Check failed services", details: "Show failed systemd units.", command: "systemctl --failed", safety: .safe, isPremium: true),
            QuickCommand(title: "Show top CPU processes", details: "List CPU-heavy processes.", command: "ps aux --sort=-%cpu | head -n 12", safety: .safe, isPremium: true),
            QuickCommand(title: "Show top RAM processes", details: "List memory-heavy processes.", command: "ps aux --sort=-%mem | head -n 12", safety: .safe, isPremium: true),
            QuickCommand(title: "Check open ports", details: "List listening sockets.", command: "ss -tulpn", safety: .safe, isPremium: true),
            QuickCommand(title: "Check nginx status", details: "Show nginx service status.", command: "systemctl status nginx --no-pager", safety: .safe, isPremium: true),
            QuickCommand(title: "Check PostgreSQL status", details: "Show PostgreSQL status.", command: "systemctl status postgresql --no-pager", safety: .safe, isPremium: true),
            QuickCommand(title: "Check Immich containers", details: "List Immich containers.", command: "docker ps --filter name=immich", safety: .safe, isPremium: true),
            QuickCommand(title: "Check Home Assistant status", details: "Show Home Assistant status.", command: "docker ps --filter name=homeassistant", safety: .safe, isPremium: true)
        ]
    }

    static func makeProcesses() -> [ProcessInfoItem] {
        [
            ProcessInfoItem(pid: 823, user: "root", command: "dockerd", cpu: 11.4, memory: 8.2),
            ProcessInfoItem(pid: 1204, user: "postgres", command: "postgres", cpu: 8.8, memory: 18.5),
            ProcessInfoItem(pid: 9031, user: "www-data", command: "nginx", cpu: 5.1, memory: 2.4),
            ProcessInfoItem(pid: 442, user: "root", command: "systemd-journald", cpu: 2.0, memory: 1.1)
        ]
    }

    static func makeDisks() -> [DiskInfo] {
        [
            DiskInfo(mountPoint: "/", filesystem: "ext4", usedGB: 42, freeGB: 18, usagePercent: 70, smartStatus: "PASSED"),
            DiskInfo(mountPoint: "/var/lib/docker", filesystem: "ext4", usedGB: 86, freeGB: 14, usagePercent: 86, smartStatus: "PASSED"),
            DiskInfo(mountPoint: "/mnt/media", filesystem: "btrfs", usedGB: 1800, freeGB: 620, usagePercent: 74, smartStatus: "PASSED")
        ]
    }

    static func makeContainers() -> [DockerContainer] {
        [
            DockerContainer(id: "immich-server", name: "immich-server", image: "ghcr.io/immich-app/immich-server", status: "Up 8 days", cpuUsage: 12, memoryUsage: 46, restartedRecently: false),
            DockerContainer(id: "postgres", name: "postgres", image: "postgres:16", status: "Up 8 days", cpuUsage: 4, memoryUsage: 31, restartedRecently: false),
            DockerContainer(id: "nginx", name: "nginx", image: "nginx:stable", status: "Restarted 2h ago", cpuUsage: 2, memoryUsage: 7, restartedRecently: true)
        ]
    }

    static func makeServices() -> [SystemdServiceItem] {
        [
            SystemdServiceItem(name: "ssh.service", loadedState: "loaded", activeState: "active", subState: "running", isFailed: false),
            SystemdServiceItem(name: "docker.service", loadedState: "loaded", activeState: "active", subState: "running", isFailed: false),
            SystemdServiceItem(name: "backup.timer", loadedState: "loaded", activeState: "failed", subState: "failed", isFailed: true)
        ]
    }
}
