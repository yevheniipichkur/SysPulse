import SwiftUI

enum SysPulseDesign {
    static let cornerRadius: CGFloat = 28
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 16
    static let pagePadding: CGFloat = 18
    static let accent = Color(red: 0.20, green: 0.76, blue: 0.92)
    static let ink = Color(red: 0.04, green: 0.06, blue: 0.09)
    static let darkPanel = Color(red: 0.06, green: 0.08, blue: 0.12)
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
                colors: [.cyan.opacity(0.18), .clear, .green.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.screen)
            .ignoresSafeArea()

            LinearGradient(
                colors: [.clear, .purple.opacity(colorScheme == .dark ? 0.16 : 0.08), .clear],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blendMode(.screen)
            .ignoresSafeArea()
        }
    }
}

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = SysPulseDesign.cardRadius
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(.white.opacity(0.18), lineWidth: 1)
                    }
            }
            .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 12)
    }
}

struct StatusPill: View {
    var status: ServerStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
                .shadow(color: status.color.opacity(0.8), radius: 6)
            Text(status.title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel(status.title)
    }
}

struct PremiumBadge: View {
    var body: some View {
        Label("Pro", systemImage: "sparkles")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(
                LinearGradient(colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
    }
}

struct SafetyBadge: View {
    var level: CommandSafetyLevel

    var body: some View {
        Text(level.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(level.color.opacity(0.12), in: Capsule())
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var symbol: String
    var color: Color
    var progress: Double?

    var body: some View {
        GlassCard(cornerRadius: 20, padding: 14) {
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
    var actionSymbol: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.largeTitle.weight(.bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
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
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: SysPulseDesign.controlRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var symbol: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 86, height: 86)
                .background(.ultraThinMaterial, in: Circle())
            Text(title)
                .font(.title2.weight(.bold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .padding(28)
    }
}
