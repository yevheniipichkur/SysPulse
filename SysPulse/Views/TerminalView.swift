import SwiftUI
import UIKit

struct TerminalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSessionID: UUID?
    @State private var commandLine = ""
    @State private var ptySessions: [UUID: PTYSession] = [:]
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

    private var isConnected: Bool {
        guard let id = selectedSessionID else { return false }
        return ptySessions[id] != nil
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
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                inputFocused = true
            }
        }
        .onChange(of: appState.selectedServer?.id) {
            ensureSessionForSelectedServer()
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            guard newTab == .terminal else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                inputFocused = true
            }
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
                .fill(isConnected ? Color.green : Color(UIColor.secondaryLabel))
                .frame(width: 8, height: 8)

            Text(sessionServer.map { "\($0.username)@\($0.host)" } ?? "SysPulse SSH")
                .font(.caption.monospaced())
                .foregroundStyle(palette.foreground.opacity(0.82))
                .lineLimit(1)

            Spacer()

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
            TextField("Enter command", text: $commandLine)
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
                            .frame(width: key.count > 2 ? 44 : 34)
                    }
                    .buttonStyle(TerminalKeyStyle())
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
            if ptySessions[existing.id] == nil {
                connectPTY(sessionID: existing.id, server: server)
            }
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
        connectPTY(sessionID: session.id, server: server)
    }

    private func connectPTY(sessionID: UUID, server: ServerProfile) {
        let pty = PTYSession()
        let appStateRef = appState
        pty.onOutput = { [appStateRef] text in
            let cleaned = stripAnsi(text)
            guard !cleaned.isEmpty,
                  let idx = appStateRef.terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
            appStateRef.terminalSessions[idx].transcript += cleaned
        }
        pty.onDisconnect = { [appStateRef] error in
            guard let idx = appStateRef.terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
            if let error {
                appStateRef.terminalSessions[idx].transcript += "\n[Disconnected: \(error.localizedDescription)]\n"
            } else {
                appStateRef.terminalSessions[idx].transcript += "\n[Session ended]\n"
            }
        }
        ptySessions[sessionID] = pty
        pty.connect(to: server, using: appStateRef.sshClient)
    }

    private func welcomeTranscript(for server: ServerProfile) -> String {
        """
        SysPulse SSH — \(server.username)@\(server.host):\(server.port)
        Connecting…

        """
    }

    private func runCommand() {
        let text = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let server = sessionServer ?? appState.selectedServer else {
            append("No server selected. Add a server profile first.\n")
            commandLine = ""
            return
        }

        if selectedSession == nil {
            createSession(for: server)
        }

        commandLine = ""
        inputFocused = true

        // selectedSessionID may be nil while selectedSession returns .first fallback
        let sessionID = selectedSessionID ?? selectedSession?.id
        guard let sessionID else { return }
        if selectedSessionID == nil { selectedSessionID = sessionID }

        if ptySessions[sessionID] == nil {
            append("[Reconnecting PTY…]\n", to: sessionID)
            connectPTY(sessionID: sessionID, server: server)
        }

        ptySessions[sessionID]?.send(text + "\r\n")
    }

    private func stripAnsi(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard result.contains("\u{1B}") || result.contains("\r") else { return result }
        let pattern = "\u{1B}\\[[\\d;?]*[A-Za-z]|\u{1B}[()][B012]|\u{1B}[=>78M]|\u{1B}\\][^\u{07}]*\u{07}|\\r"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )
        return result
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
        ptySessions[id]?.disconnect()
        ptySessions.removeValue(forKey: id)
        appState.terminalSessions.removeAll { $0.id == id }
        selectedSessionID = appState.terminalSessions.first?.id
    }

    private func insertAccessory(_ key: String) {
        let sessionID = selectedSessionID
        let pty = sessionID.flatMap { ptySessions[$0] }

        switch key {
        case "↑":
            pty?.send("\u{1B}[A")
        case "↓":
            pty?.send("\u{1B}[B")
        case "←":
            pty?.send("\u{1B}[D")
        case "→":
            pty?.send("\u{1B}[C")
        case "^C":
            pty?.send("\u{03}")
            commandLine = ""
        case "tab":
            if pty != nil { pty?.send("\t") }
            else { commandLine += "\t" }
        case "esc":
            pty?.send("\u{1B}")
        case "ctrl", "alt":
            commandLine += key + " "
        default:
            commandLine += key
        }
        inputFocused = true
    }
}

private struct TerminalKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 30)
            .padding(.horizontal, 4)
            .background(
                configuration.isPressed
                    ? AnyShapeStyle(.cyan.opacity(0.28))
                    : AnyShapeStyle(.thinMaterial),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
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
