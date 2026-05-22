import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var versionTapCount = 0
    @State private var sharingPassphrase = ""
    @State private var encryptedExportURL: URL?
    @State private var isImportingEncryptedProfiles = false
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
                                Task {
                                    try? await appState.restorePurchases()
                                }
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
                            ICloudEntitlementStatusRow(diagnostic: iCloudEntitlementDiagnostic)
                            SecureField("Sharing passphrase", text: $sharingPassphrase)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("Encrypted sharing exports metadata only. Passwords and private keys stay in Keychain.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Prepare encrypted export") {
                                encryptedExportURL = appState.makeEncryptedProfileExport(passphrase: sharingPassphrase)
                            }
                            if let encryptedExportURL {
                                ShareLink(item: encryptedExportURL) {
                                    Label("Share encrypted export", systemImage: "square.and.arrow.up")
                                }
                            }
                            Button("Import encrypted profiles") {
                                isImportingEncryptedProfiles = true
                            }
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
        .fileImporter(
            isPresented: $isImportingEncryptedProfiles,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            importEncryptedProfiles(result)
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

            if isEnabled, !iCloudEntitlementDiagnostic.isReady {
                appState.settings.iCloudSyncEnabled = false
                appState.lastCommandOutput = appState.localized(iCloudEntitlementDiagnostic.messageKey)
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

    private var iCloudEntitlementDiagnostic: CloudKitEntitlementDiagnostic {
        ProfileCloudSyncService.entitlementDiagnostic()
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

    private func importEncryptedProfiles(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            appState.importEncryptedProfiles(from: url, passphrase: sharingPassphrase)
        } catch {
            appState.lastCommandOutput = error.localizedDescription
        }
    }
}

private struct ICloudEntitlementStatusRow: View {
    var diagnostic: CloudKitEntitlementDiagnostic

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: diagnostic.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(diagnostic.isReady ? .green : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("CloudKit entitlement")
                    .font(.caption.weight(.semibold))
                Text(LocalizedStringKey(diagnostic.messageKey))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !diagnostic.isReady {
                    Text(diagnostic.containerIdentifier)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary.opacity(0.82))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((diagnostic.isReady ? Color.green : Color.orange).opacity(0.22), lineWidth: 1)
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
