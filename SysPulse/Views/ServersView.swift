import SwiftUI

struct ServersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isAddingServer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PageHeader(
                        title: "Servers",
                        subtitle: "Linux Monitor & SSH Terminal",
                        actionSymbol: "plus"
                    ) {
                        isAddingServer = true
                    }
                    .padding(.top, 8)

                    if !appState.isProUnlocked {
                        FreePlanBanner()
                    }

                    ForEach(appState.serverProfiles) { server in
                        ServerCardView(server: server, metrics: appState.metric(for: server))
                            .onTapGesture {
                                appState.select(server, tab: .monitor)
                            }
                            .contextMenu {
                                Button {
                                    appState.select(server, tab: .terminal)
                                } label: {
                                    Label("Open Terminal", systemImage: "terminal")
                                }
                                Button {
                                    appState.select(server, tab: .monitor)
                                } label: {
                                    Label("Open Monitor", systemImage: "waveform.path.ecg")
                                }
                                Button {
                                    appState.selectedServer = server
                                    appState.selectedTab = .commands
                                } label: {
                                    Label("Run Quick Command", systemImage: "bolt.horizontal")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    appState.deleteServer(server)
                                } label: {
                                    Label("Delete Server", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isAddingServer) {
            AddServerView()
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
    }
}

private struct FreePlanBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        GlassCard(cornerRadius: 22, padding: 15) {
            HStack(spacing: 14) {
                Image(systemName: "lock.open.display")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                    .frame(width: 44, height: 44)
                    .background(.cyan.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Free plan")
                        .font(.headline)
                    Text("One real server, basic dashboard and basic terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.isPaywallPresented = true
                } label: {
                    Image(systemName: "sparkles")
                        .font(.headline)
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ServerCardView: View {
    var server: ServerProfile
    var metrics: ServerMetrics

    private var accent: Color { Color(hex: server.accentHex) }

    var body: some View {
        GlassCard(cornerRadius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent.opacity(0.16))
                            .frame(width: 52, height: 52)
                            .shadow(color: accent.opacity(0.25), radius: 16)
                        Image(systemName: server.serverType.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(server.name)
                                .font(.headline.weight(.bold))
                                .lineLimit(1)
                            if server.isDemo {
                                Text("Demo")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(.cyan.opacity(0.12), in: Capsule())
                            }
                        }
                        Text("\(server.serverType.rawValue) • \(server.host)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(metrics.osName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    StatusPill(status: server.status)
                }

                HStack(spacing: 10) {
                    CompactMetric(title: "CPU", value: metrics.cpuUsage, color: .cyan)
                    CompactMetric(title: "RAM", value: metrics.ramUsage, color: .green)
                    CompactMetric(title: "Disk", value: metrics.diskUsage, color: metrics.diskUsage > 80 ? .orange : .blue)
                    HealthScoreView(score: metrics.healthScore)
                }

                Sparkline(values: metrics.cpuHistory, color: accent)

                HStack(spacing: 10) {
                    Label(metrics.uptime, systemImage: "clock")
                    Label("\(Int(metrics.temperatureCelsius ?? 0))°C", systemImage: "thermometer.medium")
                    Label("\(metrics.dockerRunning)/\(metrics.dockerTotal)", systemImage: "shippingbox")
                    if metrics.failedServices > 0 {
                        Label("\(metrics.failedServices)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct CompactMetric: View {
    var title: String
    var value: Double
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(value))%")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            GeometryReader { proxy in
                Capsule()
                    .fill(color.opacity(0.16))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(color)
                            .frame(width: proxy.size.width * min(value / 100, 1))
                    }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HealthScoreView: View {
    var score: Int
    private var rating: HealthRating { .rating(for: score) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Health")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                Image(systemName: "heart.text.square")
                Text("\(score)")
                    .monospacedDigit()
            }
            .font(.subheadline.weight(.bold))
            Text(rating.rawValue)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(rating.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authType: SSHAuthenticationType = .password
    @State private var secret = ""
    @State private var tags = ""
    @State private var group = ""
    @State private var icon = "server.rack"
    @State private var accentHex = "#33C2EA"
    @State private var serverType: ServerType = .vps
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        GlassCard {
                            VStack(spacing: 14) {
                                TextField("Server name", text: $name)
                                    .textContentType(.name)
                                TextField("Host / IP", text: $host)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                TextField("Port", text: $port)
                                    .keyboardType(.numberPad)
                                TextField("Username", text: $username)
                                    .textInputAutocapitalization(.never)
                            }
                            .textFieldStyle(.roundedBorder)
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Picker("Authentication", selection: $authType) {
                                    ForEach(SSHAuthenticationType.allCases) { type in
                                        Text(type.rawValue).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)

                                SecureField(secretPlaceholder, text: $secret)
                                    .textFieldStyle(.roundedBorder)

                                Text("Secrets are saved only in iOS Keychain.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        GlassCard {
                            VStack(spacing: 14) {
                                Picker("Server type", selection: $serverType) {
                                    ForEach(ServerType.allCases) { type in
                                        Label(type.rawValue, systemImage: type.symbol).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)

                                TextField("Tags", text: $tags)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Group", text: $group)
                                    .textFieldStyle(.roundedBorder)
                                TextField("SF Symbol icon", text: $icon)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Accent color hex", text: $accentHex)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button {
                                statusMessage = "Demo check complete. Real SSH test will use SSHClientProtocol integration."
                            } label: {
                                Label("Test Connection", systemImage: "checkmark.shield")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button {
                                save(connectAfterSave: false)
                            } label: {
                                Label("Save Securely", systemImage: "key")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .foregroundStyle(.white)
                                    .background(.cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSave)
                        }

                        GlassPrimaryButton(title: "Save & Connect", symbol: "terminal") {
                            save(connectAfterSave: true)
                        }
                        .disabled(!canSave)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var secretPlaceholder: String {
        switch authType {
        case .password: "Password"
        case .privateKey: "Private key"
        case .privateKeyWithPassphrase: "Private key + passphrase"
        }
    }

    private func save(connectAfterSave: Bool) {
        let serverID = UUID()
        let credentialID = "server-\(serverID.uuidString)"
        if !secret.isEmpty {
            do {
                try KeychainService.shared.saveSecret(secret, account: credentialID)
            } catch {
                statusMessage = error.localizedDescription
                return
            }
        }

        let server = ServerProfile(
            id: serverID,
            name: name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authenticationType: authType,
            credentialIdentifier: secret.isEmpty ? nil : credentialID,
            tags: tags.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) },
            groupName: group.isEmpty ? nil : group,
            icon: icon,
            accentHex: accentHex,
            serverType: serverType,
            status: .unknown,
            isDemo: false
        )
        appState.addServer(server)
        if connectAfterSave {
            appState.select(server, tab: .terminal)
        }
        dismiss()
    }
}
