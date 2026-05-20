import SwiftUI
import UIKit

struct TerminalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSessionID: UUID?
    @State private var currentInput: String = ""
    @State private var commandHistory: [String] = []
    @State private var keyboardActive: Bool = false
    @State private var ptySessions: [UUID: PTYSession] = [:]

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

    private var activePTY: PTYSession? {
        let id = selectedSessionID ?? appState.terminalSessions.first?.id
        return id.flatMap { ptySessions[$0] }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                    .ignoresSafeArea()

                terminalCanvas

                // Invisible keyboard capture — sits in ZStack, not in hit-test chain
                TerminalKeyboardCapture(
                    onInsert: handleInsert,
                    onDeleteBackward: handleDeleteBackward,
                    isActive: $keyboardActive
                )
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomConsole
            }
        }
        .onAppear {
            ensureSessionForSelectedServer()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                keyboardActive = true
            }
        }
        .onChange(of: appState.selectedServer?.id) {
            ensureSessionForSelectedServer()
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            guard newTab == .terminal else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.35))
                keyboardActive = true
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
                    .contentShape(Rectangle())
                    .onTapGesture { keyboardActive = true }
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
            if keyboardActive { historySuggestions }
            inputPreviewBar
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

    // Shows recent commands or prefix-filtered history when typing
    private var historySuggestions: some View {
        let suggestions: [String]
        if currentInput.isEmpty {
            suggestions = Array(commandHistory.reversed().prefix(6))
        } else {
            suggestions = Array(
                commandHistory.reversed()
                    .filter { $0.hasPrefix(currentInput) && $0 != currentInput }
                    .prefix(6)
            )
        }

        return Group {
            if !suggestions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { cmd in
                            Button(cmd) {
                                applySuggestion(cmd)
                            }
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // Replaces the old TextField — shows a local mirror of what's being typed
    private var inputPreviewBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan.opacity(0.7))
                Text(currentInput.isEmpty ? "Tap to type…" : currentInput)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(currentInput.isEmpty ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { keyboardActive = true }

            Button("Paste") {
                guard let text = UIPasteboard.general.string else { return }
                for char in text {
                    let s = String(char)
                    currentInput += s
                    activePTY?.send(s)
                }
                keyboardActive = true
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

    // MARK: - Input handling

    private func handleInsert(_ text: String) {
        guard let server = sessionServer ?? appState.selectedServer else { return }
        if selectedSession == nil { createSession(for: server) }
        let sessionID = selectedSessionID ?? appState.terminalSessions.first?.id
        guard let sessionID else { return }
        if selectedSessionID == nil { selectedSessionID = sessionID }
        if ptySessions[sessionID] == nil {
            append("[Reconnecting PTY…]\n", to: sessionID)
            connectPTY(sessionID: sessionID, server: server)
        }
        let pty = ptySessions[sessionID]

        if text == "\n" || text == "\r" {
            let cmd = currentInput
            if !cmd.isEmpty && commandHistory.last != cmd {
                commandHistory.append(cmd)
            }
            currentInput = ""
            pty?.send("\n")
        } else {
            currentInput += text
            pty?.send(text)
        }
    }

    private func handleDeleteBackward() {
        if !currentInput.isEmpty {
            currentInput.removeLast()
        }
        activePTY?.send("\u{7F}")
    }

    private func applySuggestion(_ cmd: String) {
        // ctrl-U clears current line on server, then we type the suggestion
        activePTY?.send("\u{15}")
        activePTY?.send(cmd)
        currentInput = cmd
        keyboardActive = true
    }

    private func insertAccessory(_ key: String) {
        let pty = activePTY
        switch key {
        case "↑": pty?.send("\u{1B}[A")
        case "↓": pty?.send("\u{1B}[B")
        case "←": pty?.send("\u{1B}[D")
        case "→": pty?.send("\u{1B}[C")
        case "^C":
            pty?.send("\u{03}")
            currentInput = ""
        case "tab":
            pty?.send("\t")
        case "esc":
            pty?.send("\u{1B}")
        default:
            // /  |  ~  - ctrl alt
            currentInput += key
            pty?.send(key)
        }
        keyboardActive = true
    }

    // MARK: - Session management

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
        keyboardActive = true
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
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        appState.terminalSessions[index].transcript += text
    }

    private func clearTranscript() {
        guard let id = selectedSessionID,
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        appState.terminalSessions[index].transcript = ""
    }

    private func closeCurrentSession() {
        guard let id = selectedSessionID else { return }
        ptySessions[id]?.disconnect()
        ptySessions.removeValue(forKey: id)
        appState.terminalSessions.removeAll { $0.id == id }
        selectedSessionID = appState.terminalSessions.first?.id
    }
}

// MARK: - Keyboard input capture

private final class TerminalKeyView: UIView, UIKeyInput {
    var onInsert: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?
    var onResign: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }
    override var keyboardType: UIKeyboardType { .asciiCapable }
    override var autocorrectionType: UITextAutocorrectionType { .no }
    override var autocapitalizationType: UITextAutocapitalizationType { .none }
    override var spellCheckingType: UITextSpellCheckingType { .no }
    override var smartQuotesType: UITextSmartQuotesType { .no }
    override var smartDashesType: UITextSmartDashesType { .no }

    // Always true so the system never disables the delete key
    var hasText: Bool { true }

    func insertText(_ text: String) { onInsert?(text) }
    func deleteBackward() { onDeleteBackward?() }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onResign?() }
        return result
    }

    override var inputAssistantItem: UITextInputAssistantItem {
        let item = super.inputAssistantItem
        item.leadingBarButtonGroups = []
        item.trailingBarButtonGroups = []
        return item
    }
}

private struct TerminalKeyboardCapture: UIViewRepresentable {
    var onInsert: (String) -> Void
    var onDeleteBackward: () -> Void
    @Binding var isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> TerminalKeyView {
        let view = TerminalKeyView()
        view.onInsert = onInsert
        view.onDeleteBackward = onDeleteBackward
        view.onResign = { context.coordinator.didResign() }
        return view
    }

    func updateUIView(_ uiView: TerminalKeyView, context: Context) {
        uiView.onInsert = onInsert
        uiView.onDeleteBackward = onDeleteBackward
        DispatchQueue.main.async {
            if isActive, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isActive, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator {
        var parent: TerminalKeyboardCapture
        init(parent: TerminalKeyboardCapture) { self.parent = parent }
        func didResign() {
            DispatchQueue.main.async { self.parent.isActive = false }
        }
    }
}

// MARK: - Sub-views

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
