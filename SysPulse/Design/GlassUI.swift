import Foundation
import SwiftUI

enum SysPulseDesign {
    static let cornerRadius: CGFloat = 28
    static let cardRadius: CGFloat = 24
    static let tileRadius: CGFloat = 20
    static let controlRadius: CGFloat = 16
    static let pagePadding: CGFloat = 18
    static let floatingTabBarHeight: CGFloat = 72
    static let accent = Color(red: 0.20, green: 0.76, blue: 0.92)
    static let warning = Color(red: 0.96, green: 0.58, blue: 0.12)
    static let ink = Color(red: 0.04, green: 0.06, blue: 0.09)
    static let darkPanel = Color(red: 0.06, green: 0.08, blue: 0.12)
    static let actionStart = Color(red: 0.02, green: 0.47, blue: 0.68)
    static let actionEnd = Color(red: 0.08, green: 0.25, blue: 0.78)
    static let proStart = Color(red: 0.02, green: 0.48, blue: 0.68)
    static let proEnd = Color(red: 0.26, green: 0.18, blue: 0.68)
    static let warningAction = Color(red: 0.72, green: 0.34, blue: 0.00)
    static let destructiveAction = Color(red: 0.72, green: 0.08, blue: 0.10)

    static func displayFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static var displayLarge: Font { displayFont(size: 34, weight: .bold) }
    static var displayMetric: Font { displayFont(size: 26, weight: .black) }
}

extension View {
    func sysPulseScreenBottomInset() -> some View {
        safeAreaPadding(.bottom, SysPulseDesign.floatingTabBarHeight)
    }
}

enum SysPulseMotion {
    static func softSpring(disabled: Bool) -> Animation? {
        disabled ? nil : .spring(response: 0.32, dampingFraction: 0.88)
    }

    static func quickSpring(disabled: Bool) -> Animation? {
        disabled ? nil : .spring(response: 0.20, dampingFraction: 0.82)
    }

    static func fade(disabled: Bool) -> Animation? {
        disabled ? nil : .easeOut(duration: 0.18)
    }
}

extension View {
    func tabScreenMotion(tab: AppTab, selectedTab: AppTab, disabled: Bool) -> some View {
        modifier(TabScreenMotionModifier(isSelected: tab == selectedTab, disabled: disabled))
    }

    func listItemEntrance(index: Int, disabled: Bool) -> some View {
        modifier(ListItemEntranceModifier(index: index, disabled: disabled))
    }

    func mainScreenNavigationChrome() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    func translucentNavigationChrome() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

private struct TabScreenMotionModifier: ViewModifier {
    var isSelected: Bool
    var disabled: Bool

    func body(content: Content) -> some View {
        content
            .opacity(disabled || isSelected ? 1 : 0.97)
            .animation(SysPulseMotion.fade(disabled: disabled), value: isSelected)
    }
}

private struct ListItemEntranceModifier: ViewModifier {
    var index: Int
    var disabled: Bool
    @State private var isVisible = false
    @State private var didPlayEntrance = false
    private let animatedItemLimit = 10

    private var shouldAnimate: Bool {
        !disabled && index <= animatedItemLimit
    }

    func body(content: Content) -> some View {
        content
            .opacity(shouldAnimate ? (isVisible ? 1 : 0) : 1)
            .scaleEffect(shouldAnimate ? (isVisible ? 1 : 0.99) : 1)
            .offset(y: shouldAnimate ? (isVisible ? 0 : 8) : 0)
            .onAppear {
                guard shouldAnimate, !didPlayEntrance else {
                    isVisible = true
                    return
                }
                didPlayEntrance = true
                let delay = min(Double(index) * 0.025, 0.18)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        isVisible = true
                    }
                }
            }
            .onChange(of: disabled) { _, newValue in
                if newValue {
                    isVisible = true
                }
            }
    }
}

extension Color {
    init(hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.02, green: 0.03, blue: 0.06), Color(red: 0.05, green: 0.08, blue: 0.11), Color(red: 0.02, green: 0.05, blue: 0.07)]
                    : [Color(red: 0.93, green: 0.97, blue: 0.99), .white, Color(red: 0.90, green: 0.95, blue: 0.97)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    SysPulseDesign.accent.opacity(colorScheme == .dark ? 0.18 : 0.10),
                    .clear,
                    Color.green.opacity(colorScheme == .dark ? 0.10 : 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .dark ? 1 : 0.38)
            .blendMode(colorScheme == .dark ? .screen : .normal)
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .purple.opacity(colorScheme == .dark ? 0.16 : 0.02), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blendMode(colorScheme == .dark ? .screen : .normal)
            .ignoresSafeArea()
        }
    }
}

/// Lighter list-row surface without UIKit blur material.
struct LightCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = SysPulseDesign.cardRadius
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.92))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                    }
            }
    }
}

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = SysPulseDesign.cardRadius
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.88))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.13 : 0.06), radius: colorScheme == .dark ? 14 : 8, x: 0, y: colorScheme == .dark ? 6 : 4)
    }
}

/// Settings / forms section wrapper shared across settings screens.
struct SettingsSectionCard<Content: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard(cornerRadius: SysPulseDesign.cardRadius) {
            VStack(alignment: .leading, spacing: 13) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsNavigationRow: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(SysPulseDesign.accent)
                .frame(width: 36, height: 36)
                .background(SysPulseDesign.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

struct StatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    var status: ServerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .shadow(color: status.color.opacity(0.8), radius: 6)
            Text(status.titleKey)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .fill(status.color.opacity(colorScheme == .dark ? 0.08 : 0.12))
                }
                .overlay {
                    Capsule()
                        .stroke(status.color.opacity(colorScheme == .dark ? 0.22 : 0.30), lineWidth: 1)
                }
        }
        .accessibilityLabel(Text(status.titleKey))
    }
}

struct PremiumBadge: View {
    var body: some View {
        Label(LocalizedStringKey("Pro"), systemImage: "sparkles")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [SysPulseDesign.proStart, SysPulseDesign.proEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
    }
}

struct SafetyBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    var level: CommandSafetyLevel

    var body: some View {
        Text(level.titleKey)
            .font(.caption.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(level.color.opacity(colorScheme == .dark ? 0.14 : 0.16))
                    .overlay {
                        Capsule()
                            .stroke(level.color.opacity(colorScheme == .dark ? 0.22 : 0.30), lineWidth: 1)
                    }
            }
    }
}

struct MetricTile: View {
    var title: LocalizedStringKey
    var value: String
    var symbol: String
    var color: Color
    var progress: Double?
    var usesGlass: Bool = true

    var body: some View {
        Group {
            if usesGlass {
                GlassCard(cornerRadius: 20, padding: 14) { metricBody }
            } else {
                LightCard(cornerRadius: 20, padding: 14) { metricBody }
            }
        }
    }

    private var metricBody: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol)
                        .font(.headline)
                        .foregroundStyle(color)
                    Spacer()
                    if let progress {
                        MiniRing(progress: progress / 100, color: color)
                            .frame(width: 30, height: 30)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(value)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MiniRing: View {
    var progress: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard let first = values.first else { return }
                let maxValue = max(values.max() ?? 100, 1)
                let minValue = min(values.min() ?? 0, maxValue)
                let width = proxy.size.width
                let height = proxy.size.height
                let step = values.count > 1 ? width / CGFloat(values.count - 1) : width

                func point(index: Int, value: Double) -> CGPoint {
                    let normalized = (value - minValue) / max(maxValue - minValue, 1)
                    return CGPoint(x: CGFloat(index) * step, y: height - CGFloat(normalized) * height)
                }

                path.move(to: point(index: 0, value: first))
                for item in values.enumerated() {
                    path.addLine(to: point(index: item.offset, value: item.element))
                }
            }
            .stroke(
                LinearGradient(colors: [color.opacity(0.4), color], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 36)
        .accessibilityHidden(true)
    }
}

struct PageHeader: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// Leading accessory button (shown to the left of the primary action).
    var leadingActionSymbol: String? = nil
    var leadingActionActive: Bool = false
    var leadingAction: (() -> Void)? = nil
    var secondaryActionSymbol: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var actionSymbol: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(SysPulseDesign.displayLarge)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if let leadingActionSymbol, let leadingAction {
                    Button(action: leadingAction) {
                        Image(systemName: leadingActionSymbol)
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .foregroundStyle(leadingActionActive ? Color.cyan : Color.primary)
                            .background(
                                leadingActionActive ? Color.cyan.opacity(0.14) : Color.clear,
                                in: Circle()
                            )
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                if let secondaryActionSymbol, let secondaryAction {
                    Button(action: secondaryAction) {
                        Image(systemName: secondaryActionSymbol)
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                if let actionSymbol, let action {
                    Button(action: action) {
                        Image(systemName: actionSymbol)
                            .font(.headline)
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Compact header for Pro features embedded in Monitor, Commands, or sheets.
struct ProEmbeddedHeader: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey
    var symbol: String
    var actionSymbol: String? = "plus"
    var action: (() -> Void)?

    var body: some View {
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
                if let actionSymbol, let action {
                    Button(action: action) {
                        Image(systemName: actionSymbol)
                            .font(.headline)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14, verticalPadding: 0, horizontalPadding: 0))
                }
            }
        }
    }
}

struct MonitorNavigationHintBanner: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("hasSeenMonitorNavigationHint") private var hasSeenHint = false

    var body: some View {
        if !hasSeenHint {
            GlassCard(cornerRadius: 20, padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 36, height: 36)
                        .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.localized("Back to servers"))
                            .font(.subheadline.weight(.semibold))
                        Text(LocalizedStringKey("Swipe from the left edge or tap the back button in the header."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        appState.haptic(.light)
                        hasSeenHint = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(appState.localized("Dismiss hint"))
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

struct MonitorStickyHeader: View {
    @EnvironmentObject private var appState: AppState
    var server: ServerProfile
    var metrics: ServerMetrics

    private var healthRating: HealthRating { .rating(for: metrics.healthScore) }

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: server.displayIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: server.accentHex))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: server.accentHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text("\(server.username)@\(server.host)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    StatusPill(status: server.status)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.text.square.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(healthRating.color)
                        Text("\(metrics.healthScore)")
                            .font(SysPulseDesign.displayMetric)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(healthRating.color.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

struct GlassPrimaryButton: View {
    var title: LocalizedStringKey
    var symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: [SysPulseDesign.actionStart, SysPulseDesign.actionEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: SysPulseDesign.controlRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

struct PressableGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color = .cyan
    var cornerRadius: CGFloat = SysPulseDesign.controlRadius
    var verticalPadding: CGFloat = 10
    var horizontalPadding: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        let idleTintOpacity = colorScheme == .dark ? 0.08 : 0.10
        let idleStroke = colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.14)

        return configuration.label
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .foregroundStyle(configuration.isPressed ? tint : .primary)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.025) : Color.white.opacity(0.82))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(configuration.isPressed ? 0.22 : idleTintOpacity))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                configuration.isPressed
                                    ? tint.opacity(0.48)
                                    : idleStroke,
                                lineWidth: 1
                            )
                    }
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct RefreshGlyph: View {
    var isRefreshing: Bool
    var disabled: Bool

    var body: some View {
        ZStack {
            Image(systemName: "arrow.clockwise")
                .opacity(isRefreshing ? 0 : 1)
                .scaleEffect(isRefreshing ? 0.72 : 1)
                .rotationEffect(.degrees(isRefreshing ? 160 : 0))

            ProgressView()
                .controlSize(.small)
                .opacity(isRefreshing ? 1 : 0)
                .scaleEffect(isRefreshing ? 1 : 0.72)
        }
        .animation(SysPulseMotion.quickSpring(disabled: disabled), value: isRefreshing)
    }
}

struct SysPulseEmptyStateIllustration: View {
    @Environment(\.colorScheme) private var colorScheme
    var symbol: String
    var tint: Color = SysPulseDesign.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(colorScheme == .dark ? 0.22 : 0.14), .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 52
                    )
                )
                .frame(width: 104, height: 104)

            Circle()
                .stroke(tint.opacity(0.18), lineWidth: 1)
                .frame(width: 86, height: 86)

            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var symbol: String
    var tint: Color = SysPulseDesign.accent

    var body: some View {
        VStack(spacing: 14) {
            SysPulseEmptyStateIllustration(symbol: symbol, tint: tint)
            Text(title)
                .font(SysPulseDesign.displayFont(size: 22, weight: .bold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(28)
    }
}

struct ActionEmptyStateView: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var symbol: String
    var tint: Color = SysPulseDesign.accent
    var actionTitle: LocalizedStringKey
    var actionSymbol: String = "plus.circle.fill"
    var action: () -> Void

    var body: some View {
        GlassCard(cornerRadius: SysPulseDesign.cornerRadius, padding: 0) {
            VStack(spacing: 16) {
                EmptyStateView(title: title, message: message, symbol: symbol, tint: tint)
                    .padding(.bottom, -10)

                Button(action: action) {
                    Label(actionTitle, systemImage: actionSymbol)
                        .font(.callout.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(colors: [SysPulseDesign.actionStart, SysPulseDesign.actionEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
        }
    }
}
