import SwiftUI
import UIKit

struct TerminalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSessionID: UUID?
    @State private var commandLine = ""
    @State private var isRunning = false
    @FocusState private var inputFocused: Bool

    private var selectedSession: TerminalSession? {
        if let selectedSessionID {
            return appState.terminalSessions.first { $0.id == selectedSessionID }
        }
        return appState.terminalSessions.first
    }

    private var sessionServer: ServerProfile? {
        if let serverID = selectedSession?.serverID,
           let server = appState.serverProfiles.first(where: { $0.id == serverID }) {
            return server
        }
        return appState.selectedServer
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                    .ignoresSafeArea()

                terminalCanvas
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomConsole
            }
        }
        .onAppear {
            ensureSessionForSelectedServer()
            inputFocused = true
        }
        .onChange(of: appState.selectedServer?.id) {
            ensureSessionForSelectedServer()
        }
    }

    private var terminalCanvas: some View {
        let palette = TerminalThemePalette(theme: appState.settings.terminalTheme)

        return VStack(spacing: 0) {
            topChrome(palette: palette)

            if selectedSession == nil {
                VStack(spacing: 16) {
                    Image(systemName: "terminal")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(palette.glow)
                    VStack(spacing: 6) {
                        Text("Select or add a server to open SSH terminal.")
                            .font(.headline)
                        Text("Saved SSH profiles run commands directly on your Linux machine.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    GlassPrimaryButton(title: "Add Server", symbol: "plus") {
                        appState.selectedTab = .servers
                    }
                    .frame(maxWidth: 260)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(selectedSession?.transcript ?? "")
                            .font(.system(size: CGFloat(appState.settings.terminalFontSize), weight: .regular, design: .monospaced))
                            .foregroundStyle(palette.foreground)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 180)
                            .id("terminal-bottom")
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selectedSession?.transcript ?? "") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            proxy.scrollTo("terminal-bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: palette.background, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.24)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .allowsHitTesting(false)
        }
    }

    private func topChrome(palette: TerminalThemePalette) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(sessionServer == nil ? .secondary : .green)
                .frame(width: 8, height: 8)

            Text(sessionServer.map { "\($0.username)@\($0.host)" } ?? "SysPulse SSH")
                .font(.caption.monospaced())
                .foregroundStyle(palette.foreground.opacity(0.82))
                .lineLimit(1)

            Spacer()

            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.glow)
            }

            Button {
                UIPasteboard.general.string = selectedSession?.transcript ?? ""
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.foreground.opacity(0.82))

            Button {
                clearTranscript()
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.foreground.opacity(0.82))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.black.opacity(0.08))
    }

    private var bottomConsole: some View {
        VStack(spacing: 8) {
            connectionBar
            commandComposer
            keyboardAccessory
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 8) {
            TerminalIconButton(systemName: "chevron.left") {
                appState.selectedTab = .servers
            }

            Menu {
                if appState.serverProfiles.isEmpty {
                    Button("Add Server") { appState.selectedTab = .servers }
                } else {
                    ForEach(appState.serverProfiles) { server in
                        Button("\(server.name) · \(server.host)") {
                            appState.select(server, tab: .terminal)
                            ensureSession(for: server)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                    Text(sessionServer?.host ?? "No saved servers")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            TerminalIconButton(systemName: "plus") {
                if let server = appState.selectedServer {
                    createSession(for: server)
                } else {
                    appState.selectedTab = .servers
                }
            }

            Menu {
                if appState.terminalSessions.isEmpty {
                    Button("New session") {
                        if let server = appState.selectedServer {
                            createSession(for: server)
                        }
                    }
                } else {
                    ForEach(appState.terminalSessions) { session in
                        Button(session.title) {
                            selectedSessionID = session.id
                        }
                    }
                    Divider()
                    Button("Close session", role: .destructive) {
                        closeCurrentSession()
                    }
                }
            } label: {
                Image(systemName: "square.grid.2x2")
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var commandComposer: some View {
        HStack(spacing: 8) {
            TextField("Ask AI to generate a command", text: $commandLine)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($inputFocused)
                .submitLabel(.send)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onSubmit(runCommand)

            Button("Paste") {
                commandLine += UIPasteboard.general.string ?? ""
                inputFocused = true
            }
            .font(.caption.weight(.bold))
            .buttonStyle(.plain)

            Button {
                appState.isPaywallPresented = true
            } label: {
                Text("AI")
                    .font(.caption.weight(.black))
                    .frame(width: 30, height: 30)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var keyboardAccessory: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(["esc", "tab", "ctrl", "alt", "/", "|", "~", "-", "^C", "↑", "↓", "←", "→"], id: \.self) { key in
                    Button {
                        insertAccessory(key)
                    } label: {
                        Text(key)
                            .font(.caption.weight(.bold))
                            .frame(width: key.count > 2 ? 44 : 34, height: 30)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func ensureSessionForSelectedServer() {
        guard let server = appState.selectedServer else {
            selectedSessionID = appState.terminalSessions.first?.id
            return
        }
        ensureSession(for: server)
    }

    private func ensureSession(for server: ServerProfile) {
        if let existing = appState.terminalSessions.first(where: { $0.serverID == server.id }) {
            selectedSessionID = existing.id
        } else {
            createSession(for: server)
        }
    }

    private func createSession(for server: ServerProfile) {
        let session = TerminalSession(
            serverID: server.id,
            title: server.name,
            transcript: welcomeTranscript(for: server)
        )
        appState.terminalSessions.append(session)
        selectedSessionID = session.id
        appState.haptic(.light)
        inputFocused = true
    }

    private func welcomeTranscript(for server: ServerProfile) -> String {
        """
        SysPulse SSH
        Profile: \(server.username)@\(server.host):\(server.port)
        Commands are executed on the remote Linux server over SSH.

        """
    }

    private func runCommand() {
        let text = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning else { return }
        guard let server = sessionServer ?? appState.selectedServer else {
            append("No server selected. Add a server profile first.\n")
            commandLine = ""
            return
        }

        if selectedSession == nil {
            createSession(for: server)
        }

        let sessionID = selectedSessionID
        append("\(prompt(for: server))\(text)\n", to: sessionID)
        commandLine = ""
        isRunning = true

        Task {
            do {
                let output = try await appState.sshClient.run(text, on: server)
                await MainActor.run {
                    append(normalizedOutput(output), to: sessionID)
                    isRunning = false
                }
            } catch {
                await MainActor.run {
                    append("Error: \(error.localizedDescription)\n", to: sessionID)
                    isRunning = false
                }
            }
        }
    }

    private func prompt(for server: ServerProfile) -> String {
        "\(server.username)@\(server.host):~$ "
    }

    private func normalizedOutput(_ output: String) -> String {
        if output.isEmpty {
            return "\n"
        }
        return output.hasSuffix("\n") ? output : "\(output)\n"
    }

    private func append(_ text: String, to sessionID: UUID? = nil) {
        guard let id = sessionID ?? selectedSessionID ?? appState.terminalSessions.first?.id,
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else {
            return
        }
        appState.terminalSessions[index].transcript += text
    }

    private func clearTranscript() {
        guard let id = selectedSessionID,
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else {
            return
        }
        appState.terminalSessions[index].transcript = ""
    }

    private func closeCurrentSession() {
        guard let id = selectedSessionID else { return }
        appState.terminalSessions.removeAll { $0.id == id }
        selectedSessionID = appState.terminalSessions.first?.id
    }

    private func insertAccessory(_ key: String) {
        switch key {
        case "tab":
            commandLine += "\t"
        case "esc":
            commandLine += "\u{1b}"
        case "^C":
            commandLine = ""
            append("^C\n")
        case "ctrl", "alt", "↑", "↓", "←", "→":
            break
        default:
            commandLine += key
        }
        inputFocused = true
    }
}

private struct TerminalIconButton: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.callout.weight(.bold))
                .frame(width: 38, height: 38)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TerminalThemePalette {
    var theme: TerminalTheme

    var background: [Color] {
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

    var foreground: Color {
        switch theme {
        case .ice: .black
        case .matrix: .green
        case .solarized: Color(red: 0.51, green: 0.58, blue: 0.59)
        default: Color(red: 0.62, green: 0.82, blue: 1.0)
        }
    }

    var glow: Color {
        switch theme {
        case .matrix: .green
        case .raspberry: .pink
        case .ice: .cyan
        case .neon, .cyberGlass: .purple
        default: .cyan
        }
    }
}
