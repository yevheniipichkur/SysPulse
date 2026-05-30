import SwiftUI

/// Pro-gated Monitor tab section with unified header (matches Logs FS / Tunnels).
struct ProMonitorFeatureSection<Content: View, Empty: View>: View {
    @EnvironmentObject private var appState: AppState

    var feature: String
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
                ProLockedBanner(feature: feature)
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
