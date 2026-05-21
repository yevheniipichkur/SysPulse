import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var versionTapCount = 0
    private let buildInfo = GitBuildInfoService()

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        PageHeader(title: "Settings", subtitle: "Security, appearance and Pro controls.", actionSymbol: nil, action: nil)

                        settingsSection("Account", symbol: "person.crop.circle") {
                            SettingsRow(title: "Pro status") {
                                Text(appState.isProUnlocked ? LocalizedStringKey("Active") : LocalizedStringKey("Free"))
                            }
                            Button("Manage subscription") { appState.isPaywallPresented = true }
                            Button("Restore purchases") {
                                appState.subscription.lastStoreKitMessage = appState.localized("Restore purchases will sync through StoreKit 2.")
                            }
                        }

                        settingsSection("Security", symbol: "lock.shield") {
                            Toggle("Face ID lock", isOn: biometricLockBinding)
                            Stepper("Auto-lock: \(appState.settings.autoLockMinutes) min", value: $appState.settings.autoLockMinutes, in: 1...30)
                            Toggle("Hide sensitive data", isOn: $appState.settings.hideSensitiveData)
                            Toggle("Clear clipboard warning", isOn: $appState.settings.clipboardWarning)
                        }

                        settingsSection("Appearance", symbol: "paintpalette") {
                            Picker("Mode", selection: $appState.settings.appearanceMode) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(mode.titleKey).tag(mode)
                                }
                            }
                            Picker("Terminal theme", selection: $appState.settings.terminalTheme) {
                                ForEach(TerminalTheme.allCases) { theme in
                                    HStack {
                                        Text(theme.titleKey)
                                        if theme.isPremium { Text("Pro") }
                                    }
                                    .tag(theme)
                                }
                            }
                            Slider(value: $appState.settings.terminalFontSize, in: 11...22, step: 1) {
                                Text("Terminal font size")
                            }
                            Toggle("Reduce animations", isOn: $appState.settings.reduceAnimations)
                        }

                        settingsSection("Language", symbol: "globe") {
                            Picker("Language", selection: $appState.settings.language) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.titleKey).tag(language)
                                }
                            }
                        }

                        settingsSection("Data", symbol: "externaldrive") {
                            Toggle("iCloud sync", isOn: iCloudSyncBinding)
                            Button("Export profiles") { appState.lastCommandOutput = appState.localized("Export profiles placeholder.") }
                            Button("Import profiles") { appState.lastCommandOutput = appState.localized("Import profiles placeholder.") }
                            Button("Clear terminal history", role: .destructive) {
                                appState.terminalSessions.forEach { $0.transcript = "" }
                            }
                            Button("Clear cache", role: .destructive) {
                                appState.lastCommandOutput = appState.localized("Cache cleared.")
                            }
                        }

                        settingsSection("Alerts", symbol: "bell.badge") {
                            Text("Metric alerts are checked after manual refreshes and auto-refresh.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            SettingsRow(title: "Notification permission") {
                                Text(appState.areNotificationsAuthorized ? LocalizedStringKey("Allowed") : LocalizedStringKey("Not allowed"))
                            }

                            Button("Enable notifications") {
                                Task {
                                    await appState.requestAlertNotifications()
                                }
                            }
                            .disabled(appState.areNotificationsAuthorized)

                            ForEach(appState.alertRules) { rule in
                                AlertRuleToggleRow(rule: rule)
                            }
                        }

                        settingsSection("About", symbol: "info.circle") {
                            Button {
                                versionTapCount += 1
                                if versionTapCount >= 7 {
                                    appState.isDebugMenuPresented = true
                                    versionTapCount = 0
                                }
                            } label: {
                                SettingsRow(title: "Version") {
                                    Text("\(buildInfo.version) (\(buildInfo.build))")
                                }
                            }
                            .buttonStyle(.plain)
                            Link("Privacy", destination: URL(string: "https://example.com/syspulse/privacy")!)
                            Link("Terms", destination: URL(string: "https://example.com/syspulse/terms")!)
                            Link("Contact support", destination: URL(string: "mailto:support@example.com")!)
                        }
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var biometricLockBinding: Binding<Bool> {
        Binding {
            appState.settings.requiresBiometrics
        } set: { isEnabled in
            if isEnabled {
                Task {
                    await appState.enableBiometricLockFromSettings()
                }
            } else {
                appState.disableBiometricLock()
            }
        }
    }

    private var iCloudSyncBinding: Binding<Bool> {
        Binding {
            appState.settings.iCloudSyncEnabled
        } set: { isEnabled in
            if isEnabled && !appState.isProUnlocked {
                appState.isPaywallPresented = true
                return
            }

            appState.settings.iCloudSyncEnabled = isEnabled
            if isEnabled {
                appState.lastCommandOutput = appState.localized("Starting iCloud profile sync...")
                appState.syncProfilesWithICloud(mergeRemote: true)
            } else {
                appState.lastCommandOutput = appState.localized("iCloud sync disabled.")
            }
        }
    }

    private func settingsSection<Content: View>(_ title: LocalizedStringKey, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 13) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AlertRuleToggleRow: View {
    @EnvironmentObject private var appState: AppState
    var rule: AlertRule

    var body: some View {
        Toggle(isOn: Binding(
            get: { rule.isEnabled },
            set: { appState.setAlertRule(rule, isEnabled: $0) }
        )) {
            HStack(spacing: 10) {
                Image(systemName: rule.metric.symbol)
                    .foregroundStyle(.cyan)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(rule.title))
                        .font(.callout.weight(.semibold))
                    Text(thresholdText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var thresholdText: String {
        if rule.metric == .failedServices {
            return appState.localized(rule.metric.thresholdFormatKey)
        }
        return appState.localized(rule.metric.thresholdFormatKey, rule.threshold)
    }
}

struct SettingsRow<Value: View>: View {
    var title: LocalizedStringKey
    private let value: Value

    init(title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            value
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

struct DebugMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        PageHeader(title: "Debug", subtitle: "Local QA controls for real-device testing.", actionSymbol: nil, action: nil)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Toggle("Force Pro locally", isOn: $appState.settings.forceProOverride)
                                Button("Reset onboarding") { appState.resetOnboarding() }
                                Button("Simulate offline server") { appState.simulateOfflineServer() }
                                Button("Simulate high CPU") { appState.simulateHighCPU() }
                                Button("Simulate disk full") { appState.simulateDiskFull() }
                                Button("Simulate expired subscription") {
                                    appState.subscription.isActive = false
                                    appState.subscription.plan = .free
                                    appState.subscription.expiresAt = .now.addingTimeInterval(-86_400)
                                }
                                Button("Show StoreKit debug state") {
                                    appState.lastCommandOutput = appState.subscription.lastStoreKitMessage
                                }
                                Button("Clear local database", role: .destructive) {
                                    appState.clearSavedProfiles()
                                }
                                Button("Export logs") {
                                    appState.lastCommandOutput = appState.terminalSessions.map(\.transcript).joined(separator: "\n---\n")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Developer / QA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
