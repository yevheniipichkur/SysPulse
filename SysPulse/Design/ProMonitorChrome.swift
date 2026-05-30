import SwiftUI

/// Monitor tab section with unified GlassCard header (free tabs: Processes, Disks, Commands).
struct MonitorFeatureSection<Content: View, Empty: View>: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var symbol: String
    var refreshTitle: LocalizedStringKey
    var refreshAction: () -> Void
    var isEmpty: Bool
    var emptyTitle: LocalizedStringKey
    var emptyMessage: LocalizedStringKey
    @ViewBuilder var content: () -> Content
    @ViewBuilder var emptyContent: () -> Empty

    var body: some View {
        VStack(spacing: 12) {
            GlassCard(cornerRadius: 22, padding: 16) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(title, systemImage: symbol)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(action: refreshAction) {
                        Image(systemName: "arrow.clockwise")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14, verticalPadding: 0, horizontalPadding: 0))
                    .accessibilityLabel(refreshTitle)
                }
            }

            if isEmpty {
                ActionEmptyStateView(
                    title: emptyTitle,
                    message: emptyMessage,
                    symbol: symbol,
                    actionTitle: refreshTitle,
                    actionSymbol: "arrow.clockwise",
                    action: refreshAction
                )
            } else {
                content()
            }
        }
    }
}

extension MonitorFeatureSection where Empty == EmptyView {
    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String,
        refreshTitle: LocalizedStringKey,
        refreshAction: @escaping () -> Void,
        isEmpty: Bool,
        emptyTitle: LocalizedStringKey,
        emptyMessage: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.refreshTitle = refreshTitle
        self.refreshAction = refreshAction
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.content = content
        self.emptyContent = { EmptyView() }
    }
}

/// Pro-gated Monitor tab section with unified header (matches Logs FS / Tunnels).
struct ProMonitorFeatureSection<Content: View, Empty: View>: View {
    @EnvironmentObject private var appState: AppState

    var feature: String
    var paywallMessage: String?
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var symbol: String
    var refreshTitle: LocalizedStringKey
    var refreshAction: () -> Void
    var isEmpty: Bool
    var emptyTitle: LocalizedStringKey
    var emptyMessage: LocalizedStringKey
    @ViewBuilder var content: () -> Content
    @ViewBuilder var emptyContent: () -> Empty

    var body: some View {
        VStack(spacing: 12) {
            if !appState.isProUnlocked {
                ProLockedBanner(feature: feature, message: paywallMessage)
            } else {
                GlassCard(cornerRadius: 22, padding: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(title, systemImage: symbol)
                                .font(.headline)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button(action: refreshAction) {
                            Image(systemName: "arrow.clockwise")
                                .font(.headline)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14, verticalPadding: 0, horizontalPadding: 0))
                        .accessibilityLabel(refreshTitle)
                    }
                }

                if isEmpty {
                    ActionEmptyStateView(
                        title: emptyTitle,
                        message: emptyMessage,
                        symbol: symbol,
                        actionTitle: refreshTitle,
                        actionSymbol: "arrow.clockwise",
                        action: refreshAction
                    )
                } else {
                    content()
                }
            }
        }
    }
}

extension ProMonitorFeatureSection where Empty == EmptyView {
    init(
        feature: String,
        paywallMessage: String? = nil,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String,
        refreshTitle: LocalizedStringKey,
        refreshAction: @escaping () -> Void,
        isEmpty: Bool,
        emptyTitle: LocalizedStringKey,
        emptyMessage: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.feature = feature
        self.paywallMessage = paywallMessage
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.refreshTitle = refreshTitle
        self.refreshAction = refreshAction
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.content = content
        self.emptyContent = { EmptyView() }
    }
}

enum PaywallFeatureBullets {
    static func bullets(for feature: String) -> [(String, String)]? {
        switch feature {
        case "Docker monitoring":
            return [
                ("Live container stats and status rows", "shippingbox"),
                ("Start, stop and restart containers remotely", "play.circle"),
                ("Compose project overview from Docker CLI", "square.stack.3d.up")
            ]
        case "Logs viewer":
            return [
                ("Journal entries with severity colors", "doc.text.magnifyingglass"),
                ("nginx, auth and kernel log shortcuts", "list.bullet.rectangle"),
                ("Refresh and inspect without leaving Monitor", "arrow.clockwise")
            ]
        case "systemd monitoring":
            return [
                ("Failed units surfaced instantly", "exclamationmark.triangle"),
                ("Start, stop and restart services over SSH", "gearshape.2"),
                ("Status and journal error shortcuts", "terminal")
            ]
        case "Compare servers":
            return [
                ("Sort by health, CPU, RAM or disk", "chart.bar"),
                ("Color-coded thresholds at a glance", "paintpalette"),
                ("Jump to any server Monitor in one tap", "waveform.path.ecg")
            ]
        case "Diagnostic pack":
            return [
                ("Automated CPU, RAM, disk and systemd checks", "stethoscope"),
                ("Runbook commands you can run safely", "list.bullet.rectangle"),
                ("Export findings for your team", "square.and.arrow.up")
            ]
        case "Scheduled commands":
            return [
                ("Automate safe read-only checks", "clock.arrow.circlepath"),
                ("Per-server schedules while SysPulse is active", "server.rack"),
                ("Minimum 15-minute intervals", "timer")
            ]
        case "Log Browser":
            return [
                ("Browse /var/log files on the server", "folder.badge.magnifyingglass"),
                ("Tail 100–1000 lines with search", "magnifyingglass"),
                ("Switch files without leaving Monitor", "doc.text")
            ]
        case "SSH Tunnels":
            return [
                ("Local port forwarding through SSH", "network.badge.shield.half.filled"),
                ("Test reachability before you connect", "checkmark.shield"),
                ("Copy ready-to-run SSH commands", "doc.on.doc")
            ]
        case "Custom Commands":
            return [
                ("Save your own SSH command library", "bolt.horizontal"),
                ("Run on any server profile", "server.rack"),
                ("Safety levels and confirmation for risky ops", "lock.shield")
            ]
        default:
            return nil
        }
    }
}
