import SwiftUI

struct StatusToastView: View {
    @Environment(\.colorScheme) private var colorScheme
    var toast: StatusToast

    private var tint: Color {
        switch toast.style {
        case .info: .cyan
        case .success: .green
        case .error: .orange
        }
    }

    private var symbol: String {
        switch toast.style {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(tint.opacity(colorScheme == .dark ? 0.10 : 0.12))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tint.opacity(0.35), lineWidth: 1)
                }
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 12, y: 6)
        .accessibilityLabel(toast.message)
    }
}
