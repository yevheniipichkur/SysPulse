import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRestoringPurchases = false
    @State private var storeKitSettingsMessage: String?
    @State private var isSecurityInfoPresented = false
    @State private var versionTapCount = 0
    @State private var isDebugPasswordGatePresented = false
    @State private var isDebugMenuPresented = false
    @State private var versionTapResetTask: Task<Void, Never>?
    private let buildInfo = GitBuildInfoService()
    private let debugMenuTapThreshold = 7

    var body: some View {
        NavigationStack {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 16) {
                    PageHeader(title: "Settings", subtitle: "Essentials for security, appearance and monitoring.", actionSymbol: nil, action: nil)

                        SettingsSectionCard(title: "Account", symbol: "person.crop.circle") {
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

                        SettingsSectionCard(title: "Security", symbol: "lock.shield") {
                            Button("Security & Privacy") {
                                isSecurityInfoPresented = true
                            }
                            Toggle("Face ID lock", isOn: biometricLockBinding)
                            Stepper("Auto-lock: \(appState.settings.autoLockMinutes) min", value: $appState.settings.autoLockMinutes, in: 1...30)
                            Toggle("Hide sensitive data", isOn: $appState.settings.hideSensitiveData)
                            Toggle("Clear clipboard warning", isOn: $appState.settings.clipboardWarning)
                        }
                        .listItemEntrance(index: 1, disabled: appState.shouldReduceMotion)

                        SettingsSectionCard(title: "Appearance", symbol: "paintpalette") {
                            Picker("Mode", selection: $appState.settings.appearanceMode) {
                                ForEach(AppearanceMode.allCases) { mode in
                                    Text(mode.titleKey).tag(mode)
                                }
                            }
                            Slider(value: $appState.settings.terminalFontSize, in: 11...22, step: 1) {
                                Text("Terminal font size")
                            }
                            TerminalThemePreviewStrip(
                                selected: appState.effectiveTerminalTheme,
                                isProUnlocked: appState.isProUnlocked,
                                onSelect: { theme in
                                    if theme.isPremium && !appState.isProUnlocked {
                                        appState.isPaywallPresented = true
                                    } else {
                                        appState.settings.terminalTheme = theme
                                    }
                                }
                            )
                            Toggle("Reduce animations", isOn: $appState.settings.reduceAnimations)
                        }
                        .listItemEntrance(index: 2, disabled: appState.shouldReduceMotion)

                        SettingsSectionCard(title: "Language", symbol: "globe") {
                            Picker("Language", selection: $appState.settings.language) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.titleKey).tag(language)
                                }
                            }
                        }
                        .listItemEntrance(index: 3, disabled: appState.shouldReduceMotion)

                        SettingsSectionCard(title: "Monitoring", symbol: "waveform.path.ecg") {
                            Toggle("Auto-refresh metrics", isOn: metricsAutoRefreshBinding)
                            if appState.isProUnlocked && appState.settings.metricsAutoRefreshEnabled {
                                Picker("Refresh interval", selection: metricsAutoRefreshIntervalBinding) {
                                    ForEach(MetricsAutoRefreshInterval.allCases) { interval in
                                        Text(interval.titleKey).tag(interval)
                                    }
                                }
                            }
                            Text(appState.isProUnlocked
                                 ? "Pro keeps metric history and records health events on each refresh."
                                 : "Unlock Pro for auto-refresh, metric history and health timeline.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .listItemEntrance(index: 4, disabled: appState.shouldReduceMotion)

                        SettingsSectionCard(title: "Data", symbol: "externaldrive") {
                            Toggle("iCloud sync", isOn: iCloudSyncBinding)
                            ICloudEntitlementStatusRow(diagnostic: iCloudEntitlementDiagnostic)
                            ICloudSyncActivityRow(activity: appState.profileCloudSyncActivity)
                        }
                        .listItemEntrance(index: 5, disabled: appState.shouldReduceMotion)

                        SettingsSectionCard(title: "More", symbol: "slider.horizontal.3") {
                            NavigationLink {
                                SettingsAdvancedView()
                                    .environmentObject(appState)
                            } label: {
                                SettingsNavigationRow(
                                    title: "Advanced & integrations",
                                    subtitle: "SSH keys, alerts, webhooks, Prometheus and sharing.",
                                    symbol: "ellipsis.circle"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .listItemEntrance(index: 6, disabled: appState.shouldReduceMotion)

                        SettingsSectionCard(title: "About", symbol: "info.circle") {
                            Button {
                                handleVersionTap()
                            } label: {
                                HStack {
                                    Text("Version")
                                    Spacer()
                                    Text("\(buildInfo.version) (\(buildInfo.build))")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                Text(appState.localized("Version %@ build %@", buildInfo.version, buildInfo.build))
                            )
                            .accessibilityHint(Text("Debug menu"))
                            Link("Privacy", destination: URL(string: "https://github.com/yevheniipichkur/SysPulse/blob/main/PRIVACY.md")!)
                            Link("Terms", destination: URL(string: "https://github.com/yevheniipichkur/SysPulse/blob/main/TERMS.md")!)
                            Link("Contact support", destination: URL(string: "https://github.com/yevheniipichkur/SysPulse/issues")!)
                        }
                        .listItemEntrance(index: 7, disabled: appState.shouldReduceMotion)
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .sysPulseScreenBottomInset()
        }
        .mainScreenNavigationChrome()
        }
        .sheet(isPresented: $isSecurityInfoPresented) {
            SecurityPrivacyView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $isDebugPasswordGatePresented) {
            DebugPasswordGateView {
                if appState.isDebugMenuAuthorized {
                    isDebugMenuPresented = true
                }
            }
            .environmentObject(appState)
        }
        .sheet(isPresented: $isDebugMenuPresented) {
            DebugMenuView()
                .environmentObject(appState)
        }
        .accessibilityIdentifier(AppTab.settings.screenAccessibilityIdentifier)
    }

    private func handleVersionTap() {
        versionTapResetTask?.cancel()
        versionTapCount += 1
        if versionTapCount >= debugMenuTapThreshold {
            versionTapCount = 0
            versionTapResetTask = nil
            if appState.isDebugMenuAuthorized {
                isDebugMenuPresented = true
            } else {
                isDebugPasswordGatePresented = true
            }
            return
        }
        versionTapResetTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            versionTapCount = 0
        }
    }

    private var metricsAutoRefreshBinding: Binding<Bool> {
        Binding {
            appState.settings.metricsAutoRefreshEnabled
        } set: { isEnabled in
            if isEnabled && !appState.isProUnlocked {
                appState.isPaywallPresented = true
                return
            }
            appState.settings.metricsAutoRefreshEnabled = isEnabled
        }
    }

    private var metricsAutoRefreshIntervalBinding: Binding<MetricsAutoRefreshInterval> {
        Binding {
            MetricsAutoRefreshInterval(rawValue: appState.settings.metricsAutoRefreshIntervalSeconds) ?? .sixty
        } set: { interval in
            appState.settings.metricsAutoRefreshIntervalSeconds = interval.rawValue
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

            if isEnabled, !iCloudEntitlementDiagnostic.canAttemptSync {
                appState.settings.iCloudSyncEnabled = false
                appState.stopICloudProfileSync()
                appState.postStatus(appState.localized(iCloudEntitlementDiagnostic.messageKey))
                return
            }

            appState.settings.iCloudSyncEnabled = isEnabled
            if isEnabled {
                appState.postStatus(appState.localized("Starting iCloud profile sync..."))
                appState.syncProfilesWithICloud(mergeRemote: true)
            } else {
                appState.stopICloudProfileSync()
                appState.postStatus(appState.localized("iCloud sync disabled."))
            }
        }
    }

    private var iCloudEntitlementDiagnostic: CloudKitEntitlementDiagnostic {
        ProfileCloudSyncService.entitlementDiagnostic()
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
        if diagnostic.canAttemptSync { return .cyan }
        return .orange
    }

    private var statusSymbol: String {
        if diagnostic.isReady { return "checkmark.seal.fill" }
        if diagnostic.canAttemptSync { return "info.circle.fill" }
        return "exclamationmark.triangle.fill"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.headline)
                .foregroundStyle(statusColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("iCloud capability")
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

private struct ICloudSyncActivityRow: View {
    var activity: CloudProfileSyncActivity

    private var tint: Color {
        switch activity {
        case .idle:
            .secondary
        case .checking, .syncing:
            .cyan
        case .synced:
            .green
        case .failed:
            .orange
        }
    }

    private var symbol: String {
        switch activity {
        case .idle:
            "icloud"
        case .checking:
            "icloud"
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .synced:
            "checkmark.seal.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if activity.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .tint(tint)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(activity.titleKey))
                    .font(.caption.weight(.semibold))
                if let detail = activity.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        }
    }
}

struct AlertRuleToggleRow: View {
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
