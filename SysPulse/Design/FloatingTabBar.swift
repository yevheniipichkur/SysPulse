import SwiftUI

/// Premium floating tab bar with labels. Hidden on the Terminal tab.
struct FloatingTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.barTabs) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background { barBackground }
        .padding(.horizontal, SysPulseDesign.pagePadding)
        .padding(.bottom, 6)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                    .symbolRenderingMode(isSelected ? .palette : .monochrome)
                    .foregroundStyle(
                        isSelected ? SysPulseDesign.accent : Color.primary.opacity(colorScheme == .dark ? 0.58 : 0.48),
                        isSelected ? SysPulseDesign.proEnd.opacity(0.85) : Color.primary.opacity(0.48)
                    )

                Text(tab.title)
                    .font(.caption2.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? SysPulseDesign.accent : Color.primary.opacity(colorScheme == .dark ? 0.62 : 0.52))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    SysPulseDesign.accent.opacity(colorScheme == .dark ? 0.22 : 0.14),
                                    SysPulseDesign.proEnd.opacity(colorScheme == .dark ? 0.12 : 0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [SysPulseDesign.accent.opacity(0.45), SysPulseDesign.proEnd.opacity(0.22)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
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
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.07 : 0.55),
                                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: SysPulseDesign.cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.35),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: SysPulseDesign.accent.opacity(colorScheme == .dark ? 0.12 : 0.08), radius: 18, y: 8)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.10), radius: 14, y: 6)
    }
}
