import Foundation

extension AppState {
    func restartAutoRefreshIfNeeded() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        guard isProUnlocked, settings.metricsAutoRefreshEnabled else { return }
        startAutoRefresh()
    }

    func startAutoRefresh() {
        guard isProUnlocked, settings.metricsAutoRefreshEnabled else { return }
        autoRefreshTask?.cancel()
        let interval = UInt64(max(settings.metricsAutoRefreshIntervalSeconds, 30))
        autoRefreshTask = Task {
            await performScheduledMetricsRefresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await performScheduledMetricsRefresh()
            }
        }
    }

    func performScheduledMetricsRefresh() async {
        guard isProUnlocked, settings.metricsAutoRefreshEnabled else { return }
        let profiles = serverProfiles
        guard !profiles.isEmpty else { return }

        if let selected = selectedServer {
            await refreshMetricsAsync(for: selected, announceStatus: false)
        }

        let others = profiles.filter { $0.id != selectedServer?.id }
        guard !others.isEmpty else { return }

        for server in others {
            let lastRefresh = metricsByServer[server.id]?.timestamp
            if let lastRefresh,
               Date.now.timeIntervalSince(lastRefresh) < TimeInterval(Self.backgroundServerRefreshIntervalSeconds) {
                continue
            }
            await refreshMetricsAsync(for: server, announceStatus: false)
        }
    }

    func refreshMetricsBatch(_ servers: [ServerProfile], announceStatus: Bool) async {
        guard !servers.isEmpty else { return }

        var iterator = servers.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(Self.metricsRefreshConcurrency, servers.count) {
                guard let server = iterator.next() else { break }
                group.addTask {
                    await self.refreshMetricsAsync(for: server, announceStatus: announceStatus)
                }
            }

            while let server = iterator.next() {
                await group.next()
                group.addTask {
                    await self.refreshMetricsAsync(for: server, announceStatus: announceStatus)
                }
            }
        }
    }

    func refreshMetrics(for server: ServerProfile, announceStatus: Bool = false) {
        Task {
            await refreshMetricsAsync(for: server, announceStatus: announceStatus)
        }
    }

    func refreshMetricsAsync(for server: ServerProfile, announceStatus: Bool) async {
        await MainActor.run {
            metricRefreshingServerIDs.insert(server.id)
            metricErrorByServer.removeValue(forKey: server.id)
            if announceStatus {
                postStatus(localized("Refreshing metrics for %@...", server.name))
            }
        }

        do {
            let previous = await MainActor.run {
                metricsByServer[server.id]
            }
            let metrics = try await metricsCollector.collect(server: server, using: sshClient, previous: previous)
            await MainActor.run {
                var visibleMetrics = isProUnlocked ? metrics : metricsWithoutPremiumSignals(metrics)
                recordMetricSnapshot(visibleMetrics)
                if isProUnlocked, let modelContext {
                    try? metricsHistoryService.applyHistory(to: &visibleMetrics, in: modelContext)
                }
                metricsByServer[server.id] = visibleMetrics
                metricRefreshingServerIDs.remove(server.id)
                metricErrorByServer.removeValue(forKey: server.id)
                if selectedServer?.id == server.id {
                    selectedServer?.status = .online
                }
                if announceStatus {
                    postStatus(localized("Metrics refreshed for %@.", server.name), style: .success)
                }
                updateLiveActivity(message: localized("Metrics refreshed"))
                evaluateAlertRules(for: server, metrics: visibleMetrics)
                sendBackendMonitoringSnapshotIfEnabled(server: server, metrics: visibleMetrics)
            }
        } catch {
            let recovered = await retryMetricsOnce(for: server, previous: await MainActor.run { metricsByServer[server.id] })
            if recovered != nil {
                await MainActor.run {
                    var visibleMetrics = isProUnlocked ? recovered! : metricsWithoutPremiumSignals(recovered!)
                    recordMetricSnapshot(visibleMetrics)
                    if isProUnlocked, let modelContext {
                        try? metricsHistoryService.applyHistory(to: &visibleMetrics, in: modelContext)
                    }
                    metricsByServer[server.id] = visibleMetrics
                    metricRefreshingServerIDs.remove(server.id)
                    metricErrorByServer.removeValue(forKey: server.id)
                    if selectedServer?.id == server.id {
                        selectedServer?.status = .online
                    }
                    if announceStatus {
                        postStatus(localized("Metrics refreshed for %@.", server.name), style: .success)
                    }
                    evaluateAlertRules(for: server, metrics: visibleMetrics)
                    sendBackendMonitoringSnapshotIfEnabled(server: server, metrics: visibleMetrics)
                }
                return
            }

            await MainActor.run {
                let message = connectionErrorMessage(error, server: server)
                metricRefreshingServerIDs.remove(server.id)
                metricErrorByServer[server.id] = message
                if selectedServer?.id == server.id {
                    selectedServer?.status = .warning
                }
                recordServerEvent(
                    server: server,
                    title: localized("Metrics refresh failed"),
                    details: message,
                    severity: "Dangerous"
                )
                postStatus(localized("Metrics refresh failed for %@: %@", server.name, message), style: .error)
            }
        }
    }

    func retryMetricsOnce(for server: ServerProfile, previous: ServerMetrics?) async -> ServerMetrics? {
        await MainActor.run {
            postStatus(localized("Reconnecting to %@...", server.name), style: .info)
        }
        try? await Task.sleep(for: .seconds(2))
        return try? await metricsCollector.collect(server: server, using: sshClient, previous: previous)
    }

    func metricsWithoutPremiumSignals(_ metrics: ServerMetrics) -> ServerMetrics {
        var sanitized = metrics
        sanitized.failedServices = 0
        sanitized.dockerRunning = 0
        sanitized.dockerTotal = 0
        sanitized.healthScore = healthScoreService.score(for: sanitized)
        return sanitized
    }
}
