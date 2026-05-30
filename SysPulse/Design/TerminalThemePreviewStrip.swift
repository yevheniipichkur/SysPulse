import SwiftUI

struct TerminalThemePreviewStrip: View {
    var selected: TerminalTheme
    var isProUnlocked: Bool
    var onSelect: (TerminalTheme) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey("Tap a theme to apply"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TerminalTheme.allCases) { theme in
                        themeChip(theme)
                    }
                }
            }
        }
    }

    private func themeChip(_ theme: TerminalTheme) -> some View {
        let locked = theme.isPremium && !isProUnlocked
        let isSelected = selected == theme

        return Button {
            onSelect(theme)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: TerminalThemePreviewColors.background(for: theme),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 44)
                    .overlay {
                        Text("abc")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(TerminalThemePreviewColors.foreground(for: theme))
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(SysPulseDesign.accent, lineWidth: 2)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                        }
                    }
                    .opacity(locked ? 0.55 : 1)
                Text(theme.titleKey)
                    .font(.caption2.weight(isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? SysPulseDesign.accent : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(theme.titleKey))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private enum TerminalThemePreviewColors {
    static func background(for theme: TerminalTheme) -> [Color] {
        switch theme {
        case .liquidDark: [Color(red: 0.01, green: 0.02, blue: 0.06), Color(red: 0.02, green: 0.05, blue: 0.09)]
        case .matrix: [.black, .green.opacity(0.18)]
        case .midnight: [Color(red: 0.02, green: 0.02, blue: 0.08), Color(red: 0.05, green: 0.05, blue: 0.18)]
        case .ice: [Color(red: 0.90, green: 0.97, blue: 1.0), Color(red: 0.70, green: 0.88, blue: 0.98)]
        case .solarized: [Color(red: 0.00, green: 0.17, blue: 0.21), Color(red: 0.03, green: 0.21, blue: 0.25)]
        case .neon: [.black, .purple.opacity(0.28)]
        case .classic: [.black, Color(red: 0.05, green: 0.05, blue: 0.05)]
        case .raspberry: [Color(red: 0.16, green: 0.02, blue: 0.08), Color(red: 0.32, green: 0.04, blue: 0.14)]
        case .cyberGlass: [Color(red: 0.02, green: 0.08, blue: 0.11), Color(red: 0.08, green: 0.03, blue: 0.15)]
        case .terminalPro: [Color(red: 0.02, green: 0.02, blue: 0.03), Color(red: 0.10, green: 0.11, blue: 0.13)]
        }
    }

    static func foreground(for theme: TerminalTheme) -> Color {
        switch theme {
        case .ice: Color(red: 0.02, green: 0.08, blue: 0.12)
        case .matrix: Color(red: 0.66, green: 1.0, blue: 0.58)
        case .solarized: Color(red: 0.84, green: 0.89, blue: 0.82)
        case .raspberry: Color(red: 1.0, green: 0.80, blue: 0.90)
        case .terminalPro: Color(red: 0.86, green: 0.91, blue: 0.98)
        default: Color(red: 0.76, green: 0.90, blue: 1.0)
        }
    }
}
