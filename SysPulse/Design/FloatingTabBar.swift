import SwiftUI

/// Floating pill tab bar (replaces system `TabView` chrome).
struct FloatingTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background { barBackground }
        .padding(.horizontal, SysPulseDesign.pagePadding)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 18, weight: isSelected ? .bold : .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? SysPulseDesign.accent : Color.primary.opacity(colorScheme == .dark ? 0.62 : 0.52))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(SysPulseDesign.accent.opacity(colorScheme == .dark ? 0.16 : 0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(SysPulseDesign.accent.opacity(0.28), lineWidth: 1)
                        }
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
        RoundedRectangle(cornerRadius: SysPulseDesign.cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: SysPulseDesign.cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white.opacity(0.90))
            }
            .overlay {
                RoundedRectangle(cornerRadius: SysPulseDesign.cornerRadius, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 18, y: 8)
    }
}
