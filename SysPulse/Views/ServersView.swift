import SwiftUI
import UIKit

struct ServersView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isAddingServer = false
    @State private var editingServer: ServerProfile?

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
                                    editingServer = server
                                } label: {
                                    Label("Edit Server", systemImage: "pencil")
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
        .sheet(item: $editingServer) { server in
            AddServerView(editingServer: server)
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
                        }
                        HStack(spacing: 0) {
                            Text(server.serverType.titleKey)
                            Text(" • \(server.host)")
                        }
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

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                    CompactMetric(title: "CPU", value: metrics.cpuUsage, color: .cyan)
                    CompactMetric(title: "RAM", value: metrics.ramUsage, color: .green)
                    CompactMetric(title: "Disk", value: metrics.diskUsage, color: metrics.diskUsage > 80 ? .orange : .blue)
                    HealthScoreView(score: metrics.healthScore)
                }

                Sparkline(values: metrics.cpuHistory, color: accent)

                ScrollView(.horizontal) {
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
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct CompactMetric: View {
    var title: LocalizedStringKey
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
            Text(rating.titleKey)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(rating.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    private let editingServer: ServerProfile?

    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authType: SSHAuthenticationType = .password
    @State private var secret = ""
    @State private var passphrase = ""
    @State private var tags = ""
    @State private var group = ""
    @State private var icon = "server.rack"
    @State private var accentHex = "#33C2EA"
    @State private var serverType: ServerType = .vps
    @State private var statusMessage = ""

    init(editingServer: ServerProfile? = nil) {
        self.editingServer = editingServer
        _name = State(initialValue: editingServer?.name ?? "")
        _host = State(initialValue: editingServer?.host ?? "")
        _port = State(initialValue: editingServer.map { String($0.port) } ?? "22")
        _username = State(initialValue: editingServer?.username ?? "")
        _authType = State(initialValue: editingServer?.authenticationType ?? .password)
        _tags = State(initialValue: editingServer?.tags.joined(separator: ", ") ?? "")
        _group = State(initialValue: editingServer?.groupName ?? "")
        _icon = State(initialValue: editingServer?.icon ?? "server.rack")
        _accentHex = State(initialValue: editingServer?.accentHex ?? "#33C2EA")
        _serverType = State(initialValue: editingServer?.serverType ?? .vps)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        AddServerPreviewCard(
                            name: previewName,
                            endpoint: previewEndpoint,
                            type: serverType,
                            icon: icon,
                            accent: accent
                        )

                        ServerFormSection(title: "Connection", symbol: "network") {
                            ServerFormTextField(
                                title: "Name",
                                placeholder: "Production API",
                                text: $name,
                                symbol: "server.rack"
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Host",
                                placeholder: "192.168.1.10",
                                text: $host,
                                symbol: "globe",
                                keyboardType: .URL,
                                autocapitalization: .never
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Port",
                                placeholder: "22",
                                text: $port,
                                symbol: "number",
                                keyboardType: .numberPad
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "User",
                                placeholder: "root",
                                text: $username,
                                symbol: "person",
                                autocapitalization: .never
                            )
                        }

                        ServerFormSection(title: "Security", symbol: "lock.shield") {
                            ServerPickerRow(title: "Authentication", symbol: authType.symbol) {
                                Picker("Authentication", selection: $authType) {
                                    ForEach(SSHAuthenticationType.allCases) { type in
                                        Text(type.titleKey).tag(type)
                                    }
                                }
                            }
                            ServerFormDivider()
                            credentialInput
                        }

                        ServerFormSection(title: "Profile", symbol: "slider.horizontal.3") {
                            ServerPickerRow(title: "Type", symbol: serverType.symbol) {
                                Picker("Server type", selection: $serverType) {
                                    ForEach(ServerType.allCases) { type in
                                        Label(type.titleKey, systemImage: type.symbol).tag(type)
                                    }
                                }
                            }
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Group",
                                placeholder: "Home lab",
                                text: $group,
                                symbol: "folder"
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Tags",
                                placeholder: "docker, backup",
                                text: $tags,
                                symbol: "tag"
                            )
                            ServerFormDivider()
                            ServerFormTextField(
                                title: "Icon",
                                placeholder: serverType.symbol,
                                text: $icon,
                                symbol: "square.grid.2x2",
                                autocapitalization: .never
                            )
                            ServerFormDivider()
                            ServerAccentPicker(selection: $accentHex)
                        }

                        if !statusMessage.isEmpty {
                            ServerStatusMessage(message: statusMessage)
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                testConnectionButton
                                saveAndConnectButton
                            }

                            VStack(spacing: 10) {
                                testConnectionButton
                                saveAndConnectButton
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(editingServer == nil ? LocalizedStringKey("Add Server") : LocalizedStringKey("Edit Server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        save(connectAfterSave: false)
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }

    private var accent: Color {
        Color(hex: accentHex)
    }

    private var previewName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.localized("New Server") : trimmed
    }

    private var previewEndpoint: String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointHost = trimmedHost.isEmpty ? "host.local" : trimmedHost
        return "\(usernamePrefix)\(endpointHost):\(trimmedPort.isEmpty ? "22" : trimmedPort)"
    }

    private var usernamePrefix: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : "\(trimmed)@"
    }

    private var testConnectionButton: some View {
        Button {
            testConnection()
        } label: {
            Label("Test Connection", systemImage: "checkmark.shield")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var saveAndConnectButton: some View {
        Button {
            save(connectAfterSave: true)
        } label: {
            Label("Save & Connect", systemImage: "terminal")
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .background(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.55)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var credentialInput: some View {
        switch authType {
        case .password:
            ServerFormSecureField(
                title: editingServer == nil ? "Password" : "Password",
                placeholder: editingServer == nil ? "Required for password login" : "Keep current password",
                text: $secret,
                symbol: "key"
            )
        case .privateKey, .privateKeyWithPassphrase:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.horizontal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                        .frame(width: 28, height: 28)
                        .background(.cyan.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Private Key")
                            .font(.subheadline.weight(.semibold))
                        Text(editingServer == nil ? LocalizedStringKey("OpenSSH RSA or ED25519") : LocalizedStringKey("Leave empty to keep current key"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: $secret)
                    .font(.caption.monospaced())
                    .frame(minHeight: 132)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                if authType == .privateKeyWithPassphrase {
                    ServerFormSecureField(
                        title: "Passphrase",
                        placeholder: "Optional",
                        text: $passphrase,
                        symbol: "ellipsis.rectangle"
                    )
                }
            }
        }
    }

    private var keychainSecretValue: String {
        switch authType {
        case .password, .privateKey:
            secret
        case .privateKeyWithPassphrase:
            SSHPrivateKeyCredentialPayload(
                privateKey: secret,
                passphrase: passphrase.isEmpty ? nil : passphrase
            ).keychainValue
        }
    }

    private func save(connectAfterSave: Bool) {
        let serverID = UUID()
        let targetID = editingServer?.id ?? serverID
        let credentialID = editingServer?.credentialIdentifier ?? "server-\(targetID.uuidString)"
        if !secret.isEmpty {
            do {
                try KeychainService.shared.saveSecret(keychainSecretValue, account: credentialID)
            } catch {
                statusMessage = error.localizedDescription
                return
            }
        }

        if let editingServer {
            editingServer.name = name
            editingServer.host = host
            editingServer.port = Int(port) ?? 22
            editingServer.username = username
            editingServer.authenticationType = authType
            editingServer.credentialIdentifier = secret.isEmpty ? editingServer.credentialIdentifier : credentialID
            editingServer.tagsCSV = tags
            editingServer.groupName = group.isEmpty ? nil : group
            editingServer.icon = icon
            editingServer.accentHex = accentHex
            editingServer.serverType = serverType
            appState.updateServer(editingServer)
            if connectAfterSave {
                appState.select(editingServer, tab: .terminal)
                appState.refreshMetrics(for: editingServer)
            }
            dismiss()
            return
        }

        let server = ServerProfile(
            id: targetID,
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
            status: .unknown
        )
        guard appState.addServer(server) else {
            return
        }
        if connectAfterSave {
            appState.select(server, tab: .terminal)
            appState.refreshMetrics(for: server)
        }
        dismiss()
    }

    private func testConnection() {
        guard canSave else {
            statusMessage = appState.localized("Enter server name, host and username first.")
            return
        }

        let targetID = editingServer?.id ?? UUID()
        let temporaryCredentialID = "server-test-\(targetID.uuidString)"
        let credentialID = editingServer?.credentialIdentifier ?? temporaryCredentialID

        if !secret.isEmpty {
            do {
                try KeychainService.shared.saveSecret(keychainSecretValue, account: credentialID)
            } catch {
                statusMessage = error.localizedDescription
                return
            }
        }

        let server = ServerProfile(
            id: targetID,
            name: name.isEmpty ? appState.localized("Connection Test") : name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authenticationType: authType,
            credentialIdentifier: credentialID,
            serverType: serverType,
            status: .unknown
        )

        statusMessage = appState.localized("Connecting to %@...", host)
        Task {
            do {
                let output = try await appState.testConnection(to: server)
                await MainActor.run {
                    let firstLine = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? appState.localized("SSH is ready.")
                    statusMessage = appState.localized("Connected. %@", firstLine)
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                }
            }
            if editingServer == nil {
                try? KeychainService.shared.deleteSecret(account: temporaryCredentialID)
            }
        }
    }
}

private extension SSHAuthenticationType {
    var symbol: String {
        switch self {
        case .password:
            "key"
        case .privateKey:
            "key.horizontal"
        case .privateKeyWithPassphrase:
            "lock.rectangle.stack"
        }
    }
}

private struct AddServerPreviewCard: View {
    var name: String
    var endpoint: String
    var type: ServerType
    var icon: String
    var accent: Color

    var body: some View {
        GlassCard(cornerRadius: 28, padding: 18) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(accent.opacity(0.16))
                        .frame(width: 58, height: 58)
                        .shadow(color: accent.opacity(0.22), radius: 18)

                    Image(systemName: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? type.symbol : icon)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    HStack(spacing: 7) {
                        Image(systemName: type.symbol)
                        Text(type.titleKey)
                        Text(endpoint)
                            .lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct ServerFormSection<Content: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        GlassCard(cornerRadius: 24, padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ServerFormTextField: View {
    var title: LocalizedStringKey
    var placeholder: LocalizedStringKey
    @Binding var text: String
    var symbol: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(.cyan.opacity(0.12), in: Circle())

            Text(title)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 8)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(minHeight: 46)
    }
}

private struct ServerFormSecureField: View {
    var title: LocalizedStringKey
    var placeholder: LocalizedStringKey
    @Binding var text: String
    var symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(.cyan.opacity(0.12), in: Circle())

            Text(title)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 8)

            SecureField(placeholder, text: $text)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .frame(minHeight: 46)
    }
}

private struct ServerPickerRow<Content: View>: View {
    var title: LocalizedStringKey
    var symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)
                .frame(width: 28, height: 28)
                .background(.cyan.opacity(0.12), in: Circle())

            Text(title)
                .font(.callout.weight(.semibold))

            Spacer(minLength: 8)

            content
                .labelsHidden()
                .pickerStyle(.menu)
                .font(.callout.weight(.semibold))
                .tint(.primary)
        }
        .frame(minHeight: 46)
    }
}

private struct ServerAccentPicker: View {
    @Binding var selection: String

    private static let choices = [
        "#33C2EA",
        "#34C759",
        "#FF9F0A",
        "#FF453A",
        "#AF52DE",
        "#5E5CE6"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 28, height: 28)
                    .background(.cyan.opacity(0.12), in: Circle())

                Text("Accent")
                    .font(.callout.weight(.semibold))

                Spacer()

                TextField("#33C2EA", text: $selection)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.caption.monospaced().weight(.semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
            }

            HStack(spacing: 11) {
                ForEach(Self.choices, id: \.self) { hex in
                    swatch(hex)
                }
            }
        }
        .frame(minHeight: 74)
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = selection.caseInsensitiveCompare(hex) == .orderedSame

        return Button {
            selection = hex
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.primary : Color.white.opacity(0.45), lineWidth: isSelected ? 2.5 : 1)
                }
                .shadow(color: Color(hex: hex).opacity(isSelected ? 0.35 : 0.12), radius: isSelected ? 10 : 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Accent \(hex)"))
    }
}

private struct ServerFormDivider: View {
    var body: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 38)
            .padding(.vertical, 4)
    }
}

private struct ServerStatusMessage: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
