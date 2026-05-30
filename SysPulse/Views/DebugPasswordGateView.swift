import SwiftUI

struct DebugPasswordGateView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var errorMessage = ""
    @State private var isVerifying = false
    @State private var didUnlock = false

    var onUnlocked: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)

                    Text(LocalizedStringKey("Debug access"))
                        .font(.title2.bold())
                    Text(LocalizedStringKey("Enter the password from debug-gate.txt on GitHub."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    SecureField(LocalizedStringKey("Password"), text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel(Text("Password"))

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        verify()
                    } label: {
                        Group {
                            if isVerifying {
                                ProgressView()
                            } else {
                                Text(LocalizedStringKey("Unlock"))
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifying || password.isEmpty)
                }
                .padding(SysPulseDesign.pagePadding)
            }
            .navigationTitle(LocalizedStringKey("Debug menu"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizedStringKey("Cancel")) { dismiss() }
                }
            }
        }
        .onChange(of: didUnlock) { _, unlocked in
            guard unlocked else { return }
            onUnlocked()
            dismiss()
        }
    }

    private func verify() {
        errorMessage = ""
        isVerifying = true
        Task {
            do {
                try await DebugGatePasswordService().verify(password: password)
                await MainActor.run {
                    appState.authorizeDebugMenu()
                    isVerifying = false
                    didUnlock = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isVerifying = false
                }
            }
        }
    }
}
