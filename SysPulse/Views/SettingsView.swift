import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var versionTapCount = 0
    @State private var sharingPassphrase = ""
    @State private var backendMonitoringToken = ""
    @State private var encryptedExportURL: URL?
    @State private var isImportingEncryptedProfiles = false
    @State private var isAdvancedDataExpanded = false
    @State private var isRemoteMonitoringExpanded = false
    @State private var isRestoringPurchases = false
    @State private var storeKitSettingsMessage: String?
    private let buildInfo = GitBuildInfoService()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    PageHeader(title: "Settings", subtitle: "Security, appearance and Pro controls.", actionSymbol: nil, action: nil)

                        settingsSection("Account", symbol: "person.crop.circle") {
                            SubscriptionStatusCard(
                                subscription: appState.subscription,
                                isProUnlocked: appState.isProUnlocked,
                                message: storeKitSettingsMessage
                            )
                            Button("View plans") { appState.isPaywallPresented = true }
                            Link("Manage Apple subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                            Button {
                                restorePurchasesFromSettings()
                            } label: {
                                if isRestoringPurchases {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Restoring purchases...")
                                    }
                                } else {
                                    Text("Restore purchases")
                                }
                            }
                            .disabled(isRestoringPurchases)
                        }
                        .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)

                        settingsSection("Security", symbol: "lock.shield") {
                            Toggle("Face ID lock", isOn: biometricLockBinding)
                            Stepper("Auto-lock: \(appState.settings.autoLockMinutes) min", value: $appState.settings.autoLockMinutes, in: 1...30)
                            Toggle("Hide sensitive data", isOn: $appState.settings.hideSensitiveData)
                            Toggle("Clear clipboard warning", isOn: $appState.settings.clipboardWarning)
                        }
                        .listItemEntrance(index: 1, disabled: appState.shouldReduceMotion)

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
                        .listItemEntrance(index: 2, disabled: appState.shouldReduceMotion)

                        settingsSection("Language", symbol: "globe") {
                            Picker("Language", selection: $appState.settings.language) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.titleKey).tag(language)
                                }
                            }
                        }
                        .listItemEntrance(index: 3, disabled: appState.shouldReduceMotion)

                        settingsSection("Data", symbol: "externaldrive") {
                            Toggle("iCloud sync", isOn: iCloudSyncBinding)
                            ICloudEntitlementStatusRow(diagnostic: iCloudEntitlementDiagnostic)

                            DisclosureGroup("Encrypted sharing", isExpanded: $isAdvancedDataExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
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
                                }
                            }

                            Button("Clear terminal history", role: .destructive) {
                                appState.terminalSessions.forEach { $0.transcript = "" }
                            }
                            Button("Clear cache", role: .destructive) {
                                appState.lastCommandOutput = appState.localized("Cache cleared.")
                            }
                        }
                        .listItemEntrance(index: 4, disabled: appState.shouldReduceMotion)

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
                        .listItemEntrance(index: 5, disabled: appState.shouldReduceMotion)

                        settingsSection("Remote Monitoring", symbol: "antenna.radiowaves.left.and.right") {
                            Toggle("Backend monitoring", isOn: $appState.settings.backendMonitoringEnabled)
                            SettingsRow(title: "Endpoint") {
                                if appState.settings.backendMonitoringEndpoint.isEmpty {
                                    Text("Not configured")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Configured")
                                        .foregroundStyle(.green)
                                }
                            }

                            DisclosureGroup("Connection details", isExpanded: $isRemoteMonitoringExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    TextField("Backend endpoint URL", text: $appState.settings.backendMonitoringEndpoint)
                                        .keyboardType(.URL)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                    SecureField("Bearer token (optional)", text: $backendMonitoringToken)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                    Text("Sends metrics snapshots after refresh. Passwords and private keys are never included.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Button("Save backend token") {
                                        appState.saveBackendMonitoringTokenFromSettings(backendMonitoringToken)
                                    }
                                }
                            }
                        }
                        .listItemEntrance(index: 6, disabled: appState.shouldReduceMotion)

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
                            Link("Privacy", destination: URL(string: "https://github.com/yevheniipichkur/SysPulse/blob/main/PRIVACY.md")!)
                            Link("Terms", destination: URL(string: "https://github.com/yevheniipichkur/SysPulse/blob/main/TERMS.md")!)
                            Link("Contact support", destination: URL(string: "https://github.com/yevheniipichkur/SysPulse/issues")!)
                        }
                        .listItemEntrance(index: 7, disabled: appState.shouldReduceMotion)
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
        .fileImporter(
            isPresented: $isImportingEncryptedProfiles,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            importEncryptedProfiles(result)
        }
        .onAppear {
            backendMonitoringToken = appState.backendMonitoringTokenForSettings()
        }
        .accessibilityIdentifier(AppTab.settings.screenAccessibilityIdentifier)
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

            if isEnabled, !iCloudEntitlementDiagnostic.canAttemptSync {
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

    private func restorePurchasesFromSettings() {
        guard !isRestoringPurchases else { return }
        isRestoringPurchases = true
        Task {
            defer { isRestoringPurchases = false }
            do {
                try await appState.restorePurchases()
                storeKitSettingsMessage = appState.subscription.lastStoreKitMessage
            } catch {
                storeKitSettingsMessage = appState.localized("Restore failed: %@", error.localizedDescription)
            }
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

private struct SubscriptionStatusCard: View {
    var subscription: SubscriptionState
    var isProUnlocked: Bool
    var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: isProUnlocked ? "checkmark.seal.fill" : "sparkles")
                    .font(.title3)
                    .foregroundStyle(isProUnlocked ? .green : .cyan)
                    .frame(width: 38, height: 38)
                    .background((isProUnlocked ? Color.green : Color.cyan).opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    if isProUnlocked {
                        Text("Pro active")
                            .font(.headline)
                    } else {
                        Text("Free plan")
                            .font(.headline)
                    }
                    Text(LocalizedStringKey(subscription.plan.rawValue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if isProUnlocked, subscription.plan == .lifetime {
                SettingsRow(title: "Plan") {
                    Text("Lifetime access")
                }
            } else if let expiresAt = subscription.expiresAt {
                SettingsRow(title: "Expires") {
                    Text(expiresAt, style: .date)
                }
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !subscription.lastStoreKitMessage.isEmpty {
                Text(subscription.lastStoreKitMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke((isProUnlocked ? Color.green : Color.cyan).opacity(0.18), lineWidth: 1)
        }
    }
}

private struct ICloudEntitlementStatusRow: View {
    var diagnostic: CloudKitEntitlementDiagnostic

    private var statusColor: Color {
        if diagnostic.isReady { return .green }
        if diagnostic.verificationSource == .unavailable { return .cyan }
        return .orange
    }

    private var statusSymbol: String {
        if diagnostic.isReady { return "checkmark.seal.fill" }
        if diagnostic.verificationSource == .unavailable { return "info.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.headline)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("CloudKit entitlement")
                    .font(.caption.weight(.semibold))
                Text(LocalizedStringKey(diagnostic.messageKey))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !diagnostic.canAttemptSync {
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
                .stroke(statusColor.opacity(0.22), lineWidth: 1)
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
