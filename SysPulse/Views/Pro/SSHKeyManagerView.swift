import SwiftData
import SwiftUI

struct SSHKeyManagerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHKeyPair.createdAt, order: .forward) private var keyPairs: [SSHKeyPair]

    @State private var isGenerating = false
    @State private var generatingError: String?
    @State private var copiedKeyID: UUID?
    @State private var showingDeleteConfirm = false
    @State private var pendingDeleteKey: SSHKeyPair?
    @State private var newKeyName = ""
    @State private var showingNamePrompt = false

    private let generator = SSHKeyGeneratorService()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(spacing: 16) {
                    PageHeader(
                        title: "SSH Keys",
                        subtitle: "Manage ED25519 key pairs",
                        actionSymbol: "plus"
                    ) {
                        guard appState.isProUnlocked else {
                            appState.isPaywallPresented = true
                            return
                        }
                        showingNamePrompt = true
                    }

                    if !appState.isProUnlocked {
                        ProLockedBanner(feature: "SSH Key Manager")
                    } else {
                        if let error = generatingError {
                            GlassCard {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        if keyPairs.isEmpty {
                            ActionEmptyStateView(
                                title: "No SSH keys",
                                message: "Generate an ED25519 key pair to use for passwordless authentication.",
                                symbol: "key.fill",
                                actionTitle: "Generate Key",
                                actionSymbol: "plus"
                            ) { showingNamePrompt = true }
                        } else {
                            ForEach(keyPairs) { keyPair in
                                KeyPairCard(
                                    keyPair: keyPair,
                                    isCopied: copiedKeyID == keyPair.id
                                ) {
                                    copyPublicKey(keyPair)
                                } onDelete: {
                                    pendingDeleteKey = keyPair
                                    showingDeleteConfirm = true
                                }
                            }
                        }

                        howToInstallCard
                    }
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .alert("Key Name", isPresented: $showingNamePrompt) {
            TextField("e.g. iPad Pro", text: $newKeyName)
                .autocorrectionDisabled()
            Button("Generate") {
                generateKey(name: newKeyName.trimmingCharacters(in: .whitespaces))
                newKeyName = ""
            }
            .disabled(newKeyName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { newKeyName = "" }
        } message: {
            Text("Name this key pair for easy identification.")
        }
        .alert("Delete Key?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let key = pendingDeleteKey { deleteKey(key) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The private key will be removed from Keychain. The public key on any server remains.")
        }
    }

    private var howToInstallCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("How to install on a server", systemImage: "info.circle")
                    .font(.headline)
                Text("Copy the public key above, then run this on your server:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("echo \"<paste key>\" >> ~/.ssh/authorized_keys")
                    .font(.caption2.monospaced())
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Then set the credential to this key in the server profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func generateKey(name: String) {
        guard !name.isEmpty else { return }
        isGenerating = true
        generatingError = nil
        Task {
            do {
                let pair = try generator.generateED25519(comment: name)
                try KeychainService.shared.saveSecret(pair.privateKeyPEM, account: pair.keychainAccount)
                let keyPair = SSHKeyPair(
                    name: name,
                    publicKey: pair.publicKeyOpenSSH,
                    keychainAccount: pair.keychainAccount,
                    keyType: .ed25519
                )
                await MainActor.run {
                    modelContext.insert(keyPair)
                    try? modelContext.save()
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    generatingError = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func copyPublicKey(_ keyPair: SSHKeyPair) {
        UIPasteboard.general.string = keyPair.publicKey
        copiedKeyID = keyPair.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedKeyID = nil
        }
    }

    private func deleteKey(_ key: SSHKeyPair) {
        try? KeychainService.shared.deleteSecret(account: key.keychainAccount)
        modelContext.delete(key)
        try? modelContext.save()
    }
}

// MARK: - Key Pair Card

private struct KeyPairCard: View {
    var keyPair: SSHKeyPair
    var isCopied: Bool
    var onCopy: () -> Void
    var onDelete: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(keyPair.name, systemImage: keyPair.keyType.symbol)
                        .font(.headline)
                    Spacer()
                    Text(keyPair.keyType.rawValue)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.cyan.opacity(0.18), in: Capsule())
                        .foregroundStyle(.cyan)
                }

                Text(keyPair.publicKey)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Created \(keyPair.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                HStack(spacing: 10) {
                    Button(action: onCopy) {
                        Label(
                            isCopied ? "Copied!" : "Copy Public Key",
                            systemImage: isCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .tint(isCopied ? .green : .cyan)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                }
            }
        }
    }
}
