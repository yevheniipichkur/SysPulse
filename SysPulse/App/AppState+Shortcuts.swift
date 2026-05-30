import Foundation

extension AppState {
    func handleShortcut(serverName: String?, tab: AppTab, openMonitor: Bool = false) {
        if let serverName,
           let server = serverProfiles.first(where: { $0.name.localizedCaseInsensitiveCompare(serverName) == .orderedSame }) {
            select(server, tab: tab)
            if openMonitor {
                shouldOpenSelectedServerMonitor = true
            }
        } else {
            if tab == .terminal {
                postStatus(localized("Select a server to open the terminal."), style: .info)
            } else {
                selectedTab = tab
            }
            if let serverName {
                postStatus(localized("Server \"%@\" was not found.", serverName), style: .info)
            }
        }
    }

    func presentPaywall(feature: String, message: String? = nil) {
        paywallFeatureTitle = feature
        paywallFeatureMessage = message
        isPaywallPresented = true
    }

    func silenceMetricAlerts(for hours: Double = 1) {
        metricAlertsSilencedUntil = Date.now.addingTimeInterval(hours * 3600).timeIntervalSince1970
        postStatus(localized("Metric alerts silenced for %.0f hour(s).", hours), style: .info)
    }

    var areMetricAlertsSilenced: Bool {
        metricAlertsSilencedUntil > Date.now.timeIntervalSince1970
    }

    func activeAlertCount(for server: ServerProfile) -> Int {
        guard !areMetricAlertsSilenced else { return 0 }
        let metrics = metric(for: server)
        return alertEvaluationService.evaluations(for: alertRules, server: server, metrics: metrics).count
    }

    @discardableResult
    func requireProFeature(feature: String, message: String? = nil) -> Bool {
        guard isProUnlocked else {
            presentPaywall(feature: feature, message: message)
            return false
        }
        return true
    }
}
