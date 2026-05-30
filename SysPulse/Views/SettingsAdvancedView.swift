import SwiftUI
import UniformTypeIdentifiers

struct SettingsAdvancedView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var sharingPassphrase = ""
    @State private var backendMonitoringToken = ""
    @State private var encryptedExportURL: URL?
    @State private var isImportingEncryptedProfiles = false
    @State private var isAdvancedDataExpanded = false
    @State private var isRemoteMonitoringExpanded = false
    @State private var isSSHKeyManagerPresented = false
    @State private var isScheduledCommandsPresented = false
    @State private var isPrometheusDashboardPresented = false
    @State private var webhookPreset: WebhookPreset = .custom
    @State private var telegramBotToken = ""
    @State private var telegramChatID = ""
    @State private var isSendingWebhookSample = false

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    PageHeader(
                        title: "Advanced",
                        subtitle: "Integrations, alerts, keys and encrypted sharing.",
                        actionSymbol: "xmark",
                        action: { dismiss() }
                    )
                    .padding(.top, 8)

                    SettingsSectionCard(title: "SSH Keys", symbol: "key.fill") {
                        Button {
                            isSSHKeyManagerPresented = true
                        } label: {
                            HStack {
                                Text("Manage SSH Key Pairs")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        Text("Generate ED25519 key pairs and install them on your servers for passwordless authentication.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .listItemEntrance(index: 0, disabled: appState.shouldReduceMotion)

                    SettingsSectionCard(title: "Alerts", symbol: "bell.badge") {
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

                        if appState.areMetricAlertsSilenced {
                            Text("Alerts are silenced until the timer expires.")
                                .font(.caption)
                                .foregroundStyle(SysPulseDesign.warning)
                        }

                        Button("Silence alerts for 1 hour") {
                            appState.silenceMetricAlerts(for: 1)
                        }

                        Toggle("Quiet hours", isOn: $appState.settings.alertQuietHoursEnabled)
                        if appState.settings.alertQuietHoursEnabled {
                            Stepper(value: $appState.settings.alertQuietHoursStart, in: 0...23) {
                                Text(appState.localized("Quiet from %d:00", appState.settings.alertQuietHoursStart))
                            }
                            .accessibilityLabel(Text(appState.localized("Quiet from %d:00", appState.settings.alertQuietHoursStart)))
                            Stepper(value: $appState.settings.alertQuietHoursEnd, in: 0...23) {
                                Text(appState.localized("Until %d:00", appState.settings.alertQuietHoursEnd))
                            }
                            .accessibilityLabel(Text(appState.localized("Until %d:00", appState.settings.alertQuietHoursEnd)))
                        }

                        if appState.isProUnlocked {
                            Toggle("Webhook alerts", isOn: $appState.settings.alertWebhookEnabled)
                            Picker("Webhook preset", selection: $webhookPreset) {
                                ForEach(WebhookPreset.allCases) { preset in
                                    Text(LocalizedStringKey(preset.titleKey)).tag(preset)
                                }
                            }
                            if webhookPreset == .telegram {
                                SecureField("Telegram bot token", text: $telegramBotToken)
                                TextField("Telegram chat ID", text: $telegramChatID)
                                    .keyboardType(.numberPad)
                                Button("Apply Telegram URL") {
                                    webhookPreset.apply(to: &appState.settings, botToken: telegramBotToken, chatID: telegramChatID)
                                }
                            } else {
                                TextField("Webhook URL (Slack, Discord, etc.)", text: $appState.settings.alertWebhookEndpoint)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            Button {
                                sendWebhookSample()
                            } label: {
                                if isSendingWebhookSample {
                                    ProgressView()
                                } else {
                                    Label("Send sample", systemImage: "paperplane")
                                }
                            }
                            .disabled(isSendingWebhookSample || appState.settings.alertWebhookEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text("POST JSON when a metric threshold is crossed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listItemEntrance(index: 1, disabled: appState.shouldReduceMotion)

                    SettingsSectionCard(title: "Automation", symbol: "clock.arrow.circlepath") {
                        Text("Schedule safe commands that run while SysPulse is active.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Scheduled commands") {
                            isScheduledCommandsPresented = true
                        }
                    }
                    .listItemEntrance(index: 2, disabled: appState.shouldReduceMotion)

                    SettingsSectionCard(title: "Prometheus / Grafana", symbol: "chart.xyaxis.line") {
                        Toggle("Show metrics dashboard", isOn: $appState.settings.prometheusEnabled)
                        TextField("Dashboard URL", text: $appState.settings.prometheusDashboardURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Open dashboard") {
                            isPrometheusDashboardPresented = true
                        }
                        .disabled(appState.settings.prometheusDashboardURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .listItemEntrance(index: 3, disabled: appState.shouldReduceMotion)

                    SettingsSectionCard(title: "Remote Monitoring", symbol: "antenna.radiowaves.left.and.right") {
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
                    .listItemEntrance(index: 4, disabled: appState.shouldReduceMotion)

                    SettingsSectionCard(title: "Encrypted sharing", symbol: "lock.doc") {
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
                    }
                    .listItemEntrance(index: 5, disabled: appState.shouldReduceMotion)
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .sysPulseScreenBottomInset()
        }
        .mainScreenNavigationChrome()
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
        .sheet(isPresented: $isSSHKeyManagerPresented) {
            NavigationStack {
                SSHKeyManagerView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isSSHKeyManagerPresented = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationCornerRadius(32)
        }
        .sheet(isPresented: $isScheduledCommandsPresented) {
            ScheduledCommandsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $isPrometheusDashboardPresented) {
            if let url = URL(string: appState.settings.prometheusDashboardURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
                PrometheusDashboardView(url: url)
            }
        }
    }

    private func sendWebhookSample() {
        let endpoint = appState.settings.alertWebhookEndpoint
        isSendingWebhookSample = true
        Task {
            do {
                try await AlertWebhookService().sendSample(to: endpoint)
                await MainActor.run {
                    appState.postStatus(appState.localized("Sample webhook sent."), style: .success)
                    isSendingWebhookSample = false
                }
            } catch {
                await MainActor.run {
                    appState.postStatus(appState.localized("Webhook failed: %@", error.localizedDescription), style: .error)
                    isSendingWebhookSample = false
                }
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
            appState.postStatus(error.localizedDescription, style: .error)
        }
    }
}
