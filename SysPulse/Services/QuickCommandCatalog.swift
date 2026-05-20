import Foundation

struct QuickCommandCatalog {
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
}
