import SwiftUI

/// Compact icon dock — terminal is not a tab (opened from server actions).
struct FloatingTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.barTabs) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background { barBackground }
        .padding(.horizontal, 28)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            selection = tab
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                .symbolVariant(isSelected ? .fill : .none)
                .foregroundStyle(isSelected ? SysPulseDesign.accent : Color.primary.opacity(colorScheme == .dark ? 0.55 : 0.45))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(SysPulseDesign.accent.opacity(colorScheme == .dark ? 0.14 : 0.10))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(tab.tabAccessibilityIdentifier)
    }

    @ViewBuilder
    private var barBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 10, y: 4)
    }
}
