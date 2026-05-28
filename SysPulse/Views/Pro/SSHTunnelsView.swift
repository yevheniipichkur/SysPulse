import SwiftData
import SwiftUI

struct SSHTunnelsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHTunnel.createdAt, order: .forward) private var tunnels: [SSHTunnel]

    var server: ServerProfile

    @State private var isAdding = false
    @State private var editingTunnel: SSHTunnel?
    @State private var testResults: [UUID: TunnelTestState] = [:]
    @State private var copiedID: UUID?

    private let tunnelService = SSHTunnelService()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(spacing: 16) {
                    PageHeader(
                        title: "SSH Tunnels",
                        subtitle: "Port forwarding rules for \(server.name)",
                        actionSymbol: "plus"
                    ) {
                        guard appState.isProUnlocked else {
                            appState.isPaywallPresented = true
                            return
                        }
                        isAdding = true
                    }

                    if !appState.isProUnlocked {
                        ProLockedBanner(feature: "SSH Tunnels")
                    } else if serverTunnels.isEmpty {
                        ActionEmptyStateView(
                            title: "No tunnels yet",
                            message: "Create a tunnel to forward a remote port through SSH.",
                            symbol: "network.badge.shield.half.filled",
                            actionTitle: "Add Tunnel",
                            actionSymbol: "plus"
                        ) { isAdding = true }
                    } else {
                        ForEach(serverTunnels) { tunnel in
                            TunnelCard(
                                tunnel: tunnel,
                                server: server,
                                testState: testResults[tunnel.id],
                                isCopied: copiedID == tunnel.id
                            ) {
                                editingTunnel = tunnel
                            } onTest: {
                                testTunnel(tunnel)
                            } onCopy: {
                                copySSHCommand(for: tunnel)
                            } onDelete: {
                                deleteTunnel(tunnel)
                            }
                        }
                    }
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isAdding) {
            TunnelFormView(serverID: server.id)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
        .sheet(item: $editingTunnel) { tunnel in
            TunnelFormView(editingTunnel: tunnel, serverID: server.id)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(32)
        }
    }

    private var serverTunnels: [SSHTunnel] {
        tunnels.filter { $0.serverID == server.id }
    }

    private func testTunnel(_ tunnel: SSHTunnel) {
        testResults[tunnel.id] = .testing
        Task {
            let result = await tunnelService.testTunnel(tunnel, server: server, sshClient: appState.sshClient)
            await MainActor.run {
                switch result {
                case .reachable(let ms): testResults[tunnel.id] = .reachable(ms)
                case .unreachable(let msg): testResults[tunnel.id] = .unreachable(msg)
                }
            }
        }
    }

    private func copySSHCommand(for tunnel: SSHTunnel) {
        UIPasteboard.general.string = tunnel.sshCommand(server: server)
        copiedID = tunnel.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedID = nil
        }
    }

    private func deleteTunnel(_ tunnel: SSHTunnel) {
        modelContext.delete(tunnel)
        try? modelContext.save()
    }
}

// MARK: - Tunnel Card

private struct TunnelCard: View {
    var tunnel: SSHTunnel
    var server: ServerProfile
    var testState: TunnelTestState?
    var isCopied: Bool
    var onEdit: () -> Void
    var onTest: () -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tunnel.label.isEmpty ? "Tunnel" : tunnel.label)
                            .font(.headline)
                        Text("localhost:\(tunnel.localPort) → \(tunnel.remoteHost):\(tunnel.remotePort)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    statusView
                }

                // SSH command preview
                HStack {
                    Image(systemName: "terminal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(tunnel.sshCommand(server: server))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(10)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 10) {
                    Button(action: onTest) {
                        Label("Test", systemImage: "network")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .tint(.cyan)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 12))

                    Button(action: onCopy) {
                        Label(isCopied ? "Copied" : "Copy SSH", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .tint(isCopied ? .green : .secondary)
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

    @ViewBuilder
    private var statusView: some View {
        switch testState {
        case nil:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .reachable(let ms):
            Label("\(ms) ms", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .unreachable(let msg):
            Label("Closed", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .help(msg)
        }
    }
}

// MARK: - Tunnel Form

private struct TunnelFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var editingTunnel: SSHTunnel?
    var serverID: UUID

    @State private var label = ""
    @State private var localPort = "8080"
    @State private var remoteHost = "localhost"
    @State private var remotePort = "80"

    var body: some View {
        NavigationStack {
            Form {
                Section("Label") {
                    TextField("e.g. Grafana", text: $label)
                        .autocorrectionDisabled()
                }
                Section("Local (on this device)") {
                    TextField("Local port", text: $localPort)
                        .keyboardType(.numberPad)
                }
                Section("Remote (on the server)") {
                    TextField("Remote host", text: $remoteHost)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                    TextField("Remote port", text: $remotePort)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(editingTunnel == nil ? "New Tunnel" : "Edit Tunnel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let t = editingTunnel {
                label = t.label
                localPort = String(t.localPort)
                remoteHost = t.remoteHost
                remotePort = String(t.remotePort)
            }
        }
    }

    private func save() {
        let lp = Int(localPort) ?? 8080
        let rp = Int(remotePort) ?? 80

        if let tunnel = editingTunnel {
            tunnel.label = label
            tunnel.localPort = lp
            tunnel.remoteHost = remoteHost
            tunnel.remotePort = rp
        } else {
            let tunnel = SSHTunnel(
                label: label,
                serverID: serverID,
                localPort: lp,
                remoteHost: remoteHost,
                remotePort: rp
            )
            modelContext.insert(tunnel)
        }
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Supporting types

private enum TunnelTestState {
    case testing
    case reachable(Int)
    case unreachable(String)
}

// MARK: - Locked banner

struct ProLockedBanner: View {
    @EnvironmentObject private var appState: AppState
    var feature: String

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.cyan)
                Text("\(feature) requires Pro")
                    .font(.headline)
                Text("Upgrade to SysPulse Pro to unlock all features.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Unlock Pro") {
                    appState.isPaywallPresented = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
