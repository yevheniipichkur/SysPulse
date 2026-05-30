import Foundation
import SwiftData

extension AppState {
    static let debugDemoServerIDs: [UUID] = [
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    ]

    var isDebugMenuAuthorized: Bool {
        guard debugMenuAuthorizedUntil > Date.now.timeIntervalSince1970 else { return false }
        return true
    }

    func authorizeDebugMenu() {
        debugMenuAuthorizedUntil = Date.now
            .addingTimeInterval(DebugGateConfiguration.unlockSessionDuration)
            .timeIntervalSince1970
    }

    func revokeDebugMenuAuthorization() {
        debugMenuAuthorizedUntil = 0
    }

    func setForceProOverride(_ enabled: Bool) {
        settings.forceProOverride = enabled
        if enabled {
            subscription = SubscriptionState(
                plan: .lifetime,
                isActive: true,
                expiresAt: nil,
                productsLoaded: subscription.productsLoaded,
                lastStoreKitMessage: localized("Pro unlocked from debug menu.")
            )
            restartAutoRefreshIfNeeded()
        } else if !subscription.isPro {
            enforceSubscriptionBoundaries()
        }
        postStatus(
            enabled
                ? localized("Pro features forced on.")
                : localized("Pro override turned off."),
            style: .info
        )
    }

    func setDebugDemoModeEnabled(_ enabled: Bool) {
        debugDemoModeEnabled = enabled
        if enabled {
            applyFullDebugDemoEnvironment()
        } else {
            removeDebugDemoArtifacts(reloadProfiles: true)
            postStatus(localized("Demo mode disabled."), style: .info)
        }
    }

    func installDebugDemoServers() {
        guard isDebugMenuAuthorized else { return }
        let servers = Self.debugDemoServerProfiles()
        for server in servers {
            guard !serverProfiles.contains(where: { $0.id == server.id }) else { continue }
            _ = addDebugServer(server)
        }
        applyDebugMonitorSampleData()
        postStatus(localized("Demo servers added."), style: .success)
    }

    func removeDebugDemoServers() {
        guard isDebugMenuAuthorized else { return }
        for id in Self.debugDemoServerIDs {
            guard let server = serverProfiles.first(where: { $0.id == id }) else { continue }
            deleteServer(server)
        }
        postStatus(localized("Demo servers removed."), style: .info)
    }

    func resetOnboardingForDebug() {
        hasSeenOnboarding = false
        hasSeenProFeatureTour = false
        postStatus(localized("Onboarding flags reset."), style: .info)
    }

    func bypassBiometricLockForDebug() {
        settings.requiresBiometrics = false
        isSecurityUnlocked = true
        isPrivacyShieldVisible = false
        postStatus(localized("Biometric lock bypassed for this session."), style: .info)
    }

    @discardableResult
    private func addDebugServer(_ server: ServerProfile) -> Bool {
        if let profileRepository {
            do {
                try profileRepository.saveProfile(server)
            } catch {
                postStatus(localized("Failed to save profile: %@", error.localizedDescription))
                return false
            }
        }
        serverProfiles.append(server)
        metricsByServer[server.id] = metricsByServer[server.id] ?? ServerMetrics.empty(serverID: server.id)
        selectedServer = selectedServer ?? server
        return true
    }

    private func applyFullDebugDemoEnvironment() {
        hasSeenOnboarding = true
        bypassBiometricLockForDebug()
        applyDebugMonitorSampleData()
        installDebugDemoServers()
        postStatus(localized("Demo mode enabled."), style: .success)
    }

    private func applyDebugMonitorSampleData() {
        let api = Self.debugDemoServerProfiles()[0]
        let db = Self.debugDemoServerProfiles()[1]
        let nas = Self.debugDemoServerProfiles()[2]

        metricsByServer[api.id] = Self.debugMetrics(
            serverID: api.id,
            cpu: 6, ram: 67, swap: 4, disk: 12,
            networkIn: 128, networkOut: 42, temperature: 52,
            uptime: "1w 2d",
            osName: "Debian GNU/Linux 12 (bookworm)",
            kernel: "6.1.0-21-arm64",
            loadAverage: "0.16 0.14 0.12",
            ipAddresses: ["192.168.1.16"],
            healthScore: 79, failedServices: 0, dockerRunning: 16, dockerTotal: 17
        )
        metricsByServer[db.id] = Self.debugMetrics(
            serverID: db.id,
            cpu: 72, ram: 81, swap: 18, disk: 78,
            networkIn: 88, networkOut: 21, temperature: 69,
            uptime: "42d 11h", osName: "Debian 12", kernel: "6.1.0-21-amd64",
            loadAverage: "1.92 1.48 1.22",
            ipAddresses: ["10.0.4.12"],
            healthScore: 74, failedServices: 1, dockerRunning: 3, dockerTotal: 4
        )
        metricsByServer[nas.id] = Self.debugMetrics(
            serverID: nas.id,
            cpu: 22, ram: 43, swap: 1, disk: 56,
            networkIn: 44, networkOut: 79, temperature: 47,
            uptime: "9d 2h", osName: "TrueNAS SCALE", kernel: "6.6.20-production",
            loadAverage: "0.18 0.24 0.30",
            ipAddresses: ["192.168.1.40"],
            healthScore: 88, failedServices: 0, dockerRunning: 5, dockerTotal: 5
        )

        processItemsByServer[api.id] = [
            ProcessInfoItem(pid: 1024, user: "www-data", command: "nginx: worker", cpu: 8.2, memory: 2.1),
            ProcessInfoItem(pid: 2158, user: "deploy", command: "node server.js", cpu: 22.8, memory: 14.4)
        ]
        diskInfoByServer[api.id] = [
            DiskInfo(mountPoint: "/", filesystem: "/dev/nvme0n1p2", usedGB: 68.4, freeGB: 38.2, usagePercent: 64, smartStatus: "PASSED")
        ]
        dockerContainersByServer[api.id] = [
            DockerContainer(id: "web", name: "web-api", image: "sys/api:latest", status: "Up 18 hours", cpuUsage: 14.2, memoryUsage: 34.5, restartedRecently: false)
        ]
        systemdServicesByServer[api.id] = [
            SystemdServiceItem(name: "ssh.service", loadedState: "loaded", activeState: "active", subState: "running", isFailed: false)
        ]
        logEntriesByServer[api.id] = [
            LogEntry(timestamp: "10:42:18", source: "nginx", message: "Reloaded TLS certificates successfully", severity: .safe)
        ]
        sftpPathByServer[api.id] = "/var/www/sys"
        sftpItemsByServer[api.id] = [
            SFTPRemoteItem(name: "releases", path: "/var/www/sys/releases", kind: .directory, size: 0, modifiedAt: "Today", permissions: "drwxr-xr-x")
        ]
        if terminalSessions.isEmpty, serverProfiles.contains(where: { $0.id == api.id }) {
            terminalSessions = [
                TerminalSession(serverID: api.id, title: api.name, transcript: screenshotTerminalTranscript(for: api))
            ]
        }
    }

    private func removeDebugDemoArtifacts(reloadProfiles: Bool) {
        for id in Self.debugDemoServerIDs {
            metricsByServer.removeValue(forKey: id)
            processItemsByServer.removeValue(forKey: id)
            diskInfoByServer.removeValue(forKey: id)
            dockerContainersByServer.removeValue(forKey: id)
            systemdServicesByServer.removeValue(forKey: id)
            logEntriesByServer.removeValue(forKey: id)
            sftpItemsByServer.removeValue(forKey: id)
            sftpPathByServer.removeValue(forKey: id)
        }
        if reloadProfiles {
            reloadProfilesFromRepository()
            selectedServer = serverProfiles.first
        }
    }

    static func debugDemoServerProfiles() -> [ServerProfile] {
        [
            ServerProfile(
                id: debugDemoServerIDs[0],
                name: "Raspberry",
                host: "192.168.1.16",
                username: "admin",
                authenticationType: .privateKey,
                credentialIdentifier: "debug-demo-api",
                tags: ["demo", "docker"],
                groupName: "Home Lab",
                icon: "cloud",
                accentHex: "#33C2EA",
                serverType: .vps,
                status: .online
            ),
            ServerProfile(
                id: debugDemoServerIDs[1],
                name: "Postgres Primary",
                host: "10.0.4.12",
                username: "admin",
                authenticationType: .privateKeyWithPassphrase,
                credentialIdentifier: "debug-demo-db",
                tags: ["demo", "database"],
                groupName: "Cloud",
                icon: "cylinder.split.1x2",
                accentHex: "#34C759",
                serverType: .databaseServer,
                status: .warning
            ),
            ServerProfile(
                id: debugDemoServerIDs[2],
                name: "Home NAS",
                host: "nas.local",
                username: "yevhenii",
                authenticationType: .password,
                credentialIdentifier: "debug-demo-nas",
                tags: ["demo", "storage"],
                groupName: "Home Lab",
                icon: "externaldrive.connected.to.line.below",
                accentHex: "#FF9F0A",
                serverType: .nas,
                status: .online
            )
        ]
    }

    func restoreDebugDemoModeIfNeeded() {
        guard debugDemoModeEnabled, isDebugMenuAuthorized else { return }
        applyDebugMonitorSampleData()
    }

    static func debugMetrics(
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
}
