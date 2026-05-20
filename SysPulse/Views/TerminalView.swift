import SwiftUI
import UIKit
import SwiftTerm

struct TerminalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSessionID: UUID?
    @State private var currentInput: String = ""
    @State private var commandHistory: [String] = []
    @State private var keyboardActive: Bool = false
    @State private var controlModifierActive: Bool = false
    @State private var altModifierActive: Bool = false
    @State private var ptySessions: [UUID: PTYSession] = [:]
    @State private var runtimeStates: [UUID: TerminalRuntimeState] = [:]
    @StateObject private var terminalBridgeStore = TerminalBridgeStore()

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

    private var activePrompt: String {
        guard let server = sessionServer,
              let sessionID = selectedSessionID ?? selectedSession?.id else {
            return "$ "
        }
        let state = runtimeStates[sessionID] ?? TerminalRuntimeState(server: server)
        let marker = server.username == "root" ? "#" : "$"
        return "\(server.username)@\(state.host):\(state.displayDirectory) \(marker) "
    }

    private var displayedTranscript: String {
        guard selectedSession != nil else { return "" }
        let base = selectedSession?.transcript ?? ""
        let separator = base.isEmpty || base.hasSuffix("\n") ? "" : "\n"
        return base + separator + activePrompt + currentInput + "█"
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
            } else if let session = selectedSession {
                SwiftTermTerminalSurface(
                    bridge: terminalBridgeStore.bridge(for: session.id),
                    fontSize: CGFloat(appState.settings.terminalFontSize),
                    palette: palette,
                    onInput: { bytes in
                        mirrorTerminalInput(bytes)
                        activePTY?.send(bytes)
                    },
                    onResize: { cols, rows in
                        ptySessions[session.id]?.resize(cols: cols, rows: rows)
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 174)
                .contentShape(Rectangle())
                .onTapGesture { keyboardActive = true }
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
                .fill(isConnected ? SwiftUI.Color.green : SwiftUI.Color(UIColor.secondaryLabel))
                .frame(width: 8, height: 8)

            Text(sessionServer == nil ? "SysPulse SSH" : activePrompt.trimmingCharacters(in: .whitespaces))
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
                Text(activePrompt)
                    .foregroundStyle(.cyan.opacity(0.82))
                Text(currentInput + "█")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(SwiftUI.Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
            .font(.system(size: 15, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { keyboardActive = true }

            Button("Paste") {
                guard let text = UIPasteboard.general.string else { return }
                for char in text {
                    handleInsert(String(char))
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
                ForEach(["esc", "tab", "ctrl", "alt", "/", "|", "~", "-", "^C", "^X", "^O", "↑", "↓", "←", "→"], id: \.self) { key in
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

        if applyPendingModifier(to: text, pty: pty) {
            return
        }

        if text == "\n" || text == "\r" {
            let cmd = currentInput
            if !cmd.isEmpty && commandHistory.last != cmd {
                commandHistory.append(cmd)
            }
            if pty == nil {
                append("\(activePrompt)\(cmd)\n", to: sessionID)
            }
            currentInput = ""
            pty?.send("\n")
            if cmd.trimmingCharacters(in: .whitespacesAndNewlines) == "clear" {
                clearTranscript()
            }
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
        case "↑":
            if let previous = commandHistory.last {
                applySuggestion(previous)
            }
        case "↓":
            pty?.send("\u{15}")
            currentInput = ""
        case "←": pty?.send("\u{1B}[D")
        case "→": pty?.send("\u{1B}[C")
        case "^C":
            pty?.send("\u{03}")
            currentInput = ""
            controlModifierActive = false
            altModifierActive = false
        case "^X":
            pty?.send("\u{18}")
            controlModifierActive = false
            altModifierActive = false
        case "^O":
            pty?.send("\u{0F}")
            controlModifierActive = false
            altModifierActive = false
        case "tab":
            pty?.send("\t")
        case "esc":
            pty?.send("\u{1B}")
        case "ctrl":
            controlModifierActive.toggle()
            if controlModifierActive { altModifierActive = false }
        case "alt":
            altModifierActive.toggle()
            if altModifierActive { controlModifierActive = false }
        default:
            if applyPendingModifier(to: key, pty: pty) {
                break
            }
            currentInput += key
            pty?.send(key)
        }
        keyboardActive = true
    }

    private func applyPendingModifier(to text: String, pty: PTYSession?) -> Bool {
        guard controlModifierActive || altModifierActive else { return false }
        defer {
            controlModifierActive = false
            altModifierActive = false
        }

        if controlModifierActive, let control = controlCharacter(for: text) {
            pty?.send(control)
            if control == "\u{03}" || control == "\u{15}" {
                currentInput = ""
            }
            return true
        }

        if altModifierActive {
            pty?.send("\u{1B}")
            pty?.send(text)
            currentInput += text
            return true
        }

        return false
    }

    private func controlCharacter(for text: String) -> String? {
        guard let scalar = text.unicodeScalars.first else { return nil }
        let value = scalar.value
        if value == 91 { return "\u{1B}" } // Ctrl-[
        if value == 63 { return "\u{7F}" } // Ctrl-?
        guard value >= 64, value <= 126 else { return nil }
        return String(UnicodeScalar(value & 0x1F)!)
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
            if runtimeStates[existing.id] == nil {
                runtimeStates[existing.id] = TerminalRuntimeState(server: server)
            }
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
        runtimeStates[session.id] = TerminalRuntimeState(server: server)
        selectedSessionID = session.id
        appState.haptic(.light)
        keyboardActive = true
        connectPTY(sessionID: session.id, server: server)
    }

    private func connectPTY(sessionID: UUID, server: ServerProfile) {
        var state = runtimeStates[sessionID] ?? TerminalRuntimeState(server: server)
        state.host = server.host
        runtimeStates[sessionID] = state
        let pty = PTYSession()
        let appStateRef = appState
        pty.onOutput = { [appStateRef] text in
            guard let idx = appStateRef.terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }

            let controlResult = extractSysPulseControlMessages(from: text, sessionID: sessionID, server: server)
            var processed = sanitizeTerminalStream(controlResult.visibleText)
            processed = processed.replacingOccurrences(of: "\r\n", with: "\n")
            processed = processed.replacingOccurrences(of: "\r", with: "\n")
            guard !processed.isEmpty else { return }

            appStateRef.terminalSessions[idx].transcript = applyingBackspaces(
                processed,
                to: appStateRef.terminalSessions[idx].transcript
            )
        }
        let bridge = terminalBridgeStore.bridge(for: sessionID)
        pty.onData = { [weak bridge] bytes in
            bridge?.feed(bytes)
        }
        pty.onDisconnect = { [appStateRef] error in
            guard let idx = appStateRef.terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
            if let error {
                let message = "\n[Disconnected: \(error.localizedDescription)]\n"
                appStateRef.terminalSessions[idx].transcript += message
                bridge.feed(Array(message.utf8))
            } else {
                let message = "\n[Session ended]\n"
                appStateRef.terminalSessions[idx].transcript += message
                bridge.feed(Array(message.utf8))
            }
        }
        ptySessions[sessionID] = pty
        pty.connect(to: server, using: appStateRef.sshClient)
    }

    private func welcomeTranscript(for server: ServerProfile) -> String { "" }

    private static let cwdProbeCommand = "printf '\\033]777;cwd:%s;home:%s;host:%s\\007' \"$PWD\" \"$HOME\" \"$(hostname 2>/dev/null || uname -n)\"\n"

    private func append(_ text: String, to sessionID: UUID? = nil) {
        guard let id = sessionID ?? selectedSessionID ?? appState.terminalSessions.first?.id,
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        appState.terminalSessions[index].transcript += text
    }

    private func clearTranscript() {
        guard let id = selectedSessionID,
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        appState.terminalSessions[index].transcript = ""
        terminalBridgeStore.bridge(for: id).reset()
    }

    private func closeCurrentSession() {
        guard let id = selectedSessionID else { return }
        ptySessions[id]?.disconnect()
        ptySessions.removeValue(forKey: id)
        runtimeStates.removeValue(forKey: id)
        terminalBridgeStore.remove(id)
        appState.terminalSessions.removeAll { $0.id == id }
        selectedSessionID = appState.terminalSessions.first?.id
    }

    private func mirrorTerminalInput(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        for byte in bytes {
            switch byte {
            case 10, 13:
                let cmd = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cmd.isEmpty && commandHistory.last != cmd {
                    commandHistory.append(cmd)
                }
                currentInput = ""
            case 3, 21:
                currentInput = ""
            case 8, 127:
                if !currentInput.isEmpty { currentInput.removeLast() }
            case 32...126:
                currentInput.append(Character(UnicodeScalar(byte)))
            default:
                break
            }
        }
    }

    private func extractSysPulseControlMessages(from text: String, sessionID: UUID, server: ServerProfile) -> (visibleText: String, didUpdateState: Bool) {
        var output = ""
        var index = text.startIndex
        var didUpdateState = false

        while index < text.endIndex {
            if text[index] == "\u{1B}" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "]" {
                    var cursor = text.index(after: next)
                    var payload = ""
                    var consumed = false
                    while cursor < text.endIndex {
                        if text[cursor] == "\u{07}" {
                            consumed = true
                            cursor = text.index(after: cursor)
                            break
                        }
                        payload.append(text[cursor])
                        cursor = text.index(after: cursor)
                    }

                    if consumed, payload.hasPrefix("777;") {
                        applySysPulseControlPayload(String(payload.dropFirst(4)), sessionID: sessionID, server: server)
                        didUpdateState = true
                        index = cursor
                        continue
                    }
                }
            }

            output.append(text[index])
            index = text.index(after: index)
        }

        return (output, didUpdateState)
    }

    private func applySysPulseControlPayload(_ payload: String, sessionID: UUID, server: ServerProfile) {
        var state = runtimeStates[sessionID] ?? TerminalRuntimeState(server: server)
        for component in payload.split(separator: ";", omittingEmptySubsequences: false) {
            let parts = component.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1])
            switch key {
            case "cwd":
                state.absoluteDirectory = value
            case "home":
                state.homeDirectory = value.isEmpty ? nil : value
            case "host":
                state.host = value.isEmpty ? server.host : value
            default:
                break
            }
        }
        runtimeStates[sessionID] = state
    }
}

private struct TerminalRuntimeState {
    var host: String
    var absoluteDirectory: String
    var homeDirectory: String?

    init(server: ServerProfile) {
        self.host = server.host
        self.absoluteDirectory = "~"
        self.homeDirectory = nil
    }

    var displayDirectory: String {
        guard absoluteDirectory != "~" else { return "~" }
        guard let homeDirectory, !homeDirectory.isEmpty else { return absoluteDirectory }
        if absoluteDirectory == homeDirectory {
            return "~"
        }
        if absoluteDirectory.hasPrefix(homeDirectory + "/") {
            return "~/" + String(absoluteDirectory.dropFirst(homeDirectory.count + 1))
        }
        return absoluteDirectory
    }
}

private final class TerminalBridgeStore: ObservableObject {
    private var bridges: [UUID: TerminalFeedBridge] = [:]

    func bridge(for id: UUID) -> TerminalFeedBridge {
        if let bridge = bridges[id] { return bridge }
        let bridge = TerminalFeedBridge()
        bridges[id] = bridge
        return bridge
    }

    func remove(_ id: UUID) {
        bridges[id]?.reset()
        bridges.removeValue(forKey: id)
    }
}

private final class TerminalFeedBridge: ObservableObject {
    private var feedHandler: (([UInt8]) -> Void)?
    private var resetHandler: (() -> Void)?
    private var pending: [[UInt8]] = []

    func bind(feed: @escaping ([UInt8]) -> Void, reset: @escaping () -> Void) {
        feedHandler = feed
        resetHandler = reset
        guard !pending.isEmpty else { return }
        let buffered = pending
        pending.removeAll(keepingCapacity: true)
        buffered.forEach(feed)
    }

    func feed(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if let feedHandler {
            feedHandler(bytes)
        } else {
            pending.append(bytes)
        }
    }

    func reset() {
        pending.removeAll()
        if let resetHandler {
            resetHandler()
        } else {
            feedHandler?(Array("\u{1B}[2J\u{1B}[H".utf8))
        }
    }
}

private struct SwiftTermTerminalSurface: UIViewRepresentable {
    @ObservedObject var bridge: TerminalFeedBridge
    var fontSize: CGFloat
    var palette: TerminalThemePalette
    var onInput: ([UInt8]) -> Void
    var onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onResize: onResize)
    }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let view = SwiftTerm.TerminalView(
            frame: .zero,
            font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        )
        view.terminalDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.nativeBackgroundColor = .clear
        view.nativeForegroundColor = UIColor(palette.foreground)
        view.keyboardType = .asciiCapable
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.inputAccessoryView = nil
        view.changeScrollback(5000)
        bindBridge(to: view)
        return view
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.onInput = onInput
        context.coordinator.onResize = onResize
        uiView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        uiView.nativeForegroundColor = UIColor(palette.foreground)
        uiView.nativeBackgroundColor = .clear
        uiView.backgroundColor = .clear
        uiView.inputAccessoryView = nil
        bindBridge(to: uiView)
    }

    private func bindBridge(to terminalView: SwiftTerm.TerminalView) {
        bridge.bind(
            feed: { [weak terminalView] bytes in
                terminalView?.feed(byteArray: ArraySlice(bytes))
            },
            reset: { [weak terminalView] in
                terminalView?.feed(text: "\u{1B}[2J\u{1B}[H")
            }
        )
    }

    final class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        var onInput: ([UInt8]) -> Void
        var onResize: (Int, Int) -> Void

        init(onInput: @escaping ([UInt8]) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onResize = onResize
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            onInput(Array(data))
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
        }

        func bell(source: SwiftTerm.TerminalView) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.string = String(data: content, encoding: .utf8)
        }

        func clipboardRead(source: SwiftTerm.TerminalView) -> Data? {
            UIPasteboard.general.string?.data(using: .utf8)
        }

        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}

private func sanitizeTerminalStream(_ text: String) -> String {
    var output = ""
    var index = text.startIndex

    while index < text.endIndex {
        if text[index] == "\u{1B}" {
            let next = text.index(after: index)
            guard next < text.endIndex else { break }

            if text[next] == "[" {
                var cursor = text.index(after: next)
                var sequence = "\u{1B}["
                var final: Character?

                while cursor < text.endIndex {
                    let char = text[cursor]
                    sequence.append(char)
                    if let scalar = char.unicodeScalars.first,
                       scalar.value >= 0x40,
                       scalar.value <= 0x7E {
                        final = char
                        cursor = text.index(after: cursor)
                        break
                    }
                    cursor = text.index(after: cursor)
                }

                if final == "m" {
                    output += sequence
                }
                index = cursor
                continue
            }

            if text[next] == "]" {
                var cursor = text.index(after: next)
                while cursor < text.endIndex {
                    if text[cursor] == "\u{07}" {
                        cursor = text.index(after: cursor)
                        break
                    }
                    if text[cursor] == "\u{1B}" {
                        let afterEscape = text.index(after: cursor)
                        if afterEscape < text.endIndex, text[afterEscape] == "\\" {
                            cursor = text.index(after: afterEscape)
                            break
                        }
                    }
                    cursor = text.index(after: cursor)
                }
                index = cursor
                continue
            }

            index = text.index(after: next)
            continue
        }

        output.append(text[index])
        index = text.index(after: index)
    }

    if let regex = try? NSRegularExpression(pattern: #"(?m)^.*export TERM=xterm-256color.*PROMPT_COMMAND.*\n?"#) {
        output = regex.stringByReplacingMatches(
            in: output,
            range: NSRange(output.startIndex..., in: output),
            withTemplate: ""
        )
    }

    return output
}

private func applyingBackspaces(_ update: String, to existing: String) -> String {
    var result = existing
    for char in update {
        if char == "\u{08}" || char == "\u{7F}" {
            if !result.isEmpty {
                result.removeLast()
            }
        } else {
            result.append(char)
        }
    }
    return result
}

// MARK: - Keyboard input capture

private final class TerminalKeyView: UIView, UIKeyInput, UITextInputTraits {
    var onInsert: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?
    var onResign: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    // UITextInputTraits — stored vars, not overrides
    var keyboardType: UIKeyboardType = .asciiCapable
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no

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

private struct TerminalANSIText: View {
    var rawText: String
    var fontSize: CGFloat
    var palette: TerminalThemePalette

    var body: some View {
        Text(makeAttributedString())
            .font(.system(size: fontSize, weight: .regular, design: .monospaced))
            .foregroundStyle(palette.foreground)
    }

    private func makeAttributedString() -> AttributedString {
        var result = AttributedString()
        var style = ANSIStyle(color: palette.foreground, isBold: false)
        var buffer = ""
        var index = rawText.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            var run = AttributedString(buffer)
            run.foregroundColor = style.color
            if style.isBold {
                run.font = .system(size: fontSize, weight: .semibold, design: .monospaced)
            }
            result += run
            buffer.removeAll(keepingCapacity: true)
        }

        while index < rawText.endIndex {
            if rawText[index] == "\u{1B}" {
                let next = rawText.index(after: index)
                if next < rawText.endIndex, rawText[next] == "[" {
                    var cursor = rawText.index(after: next)
                    var parameterText = ""
                    var isSGR = false

                    while cursor < rawText.endIndex {
                        let char = rawText[cursor]
                        if char == "m" {
                            isSGR = true
                            cursor = rawText.index(after: cursor)
                            break
                        }
                        parameterText.append(char)
                        cursor = rawText.index(after: cursor)
                    }

                    if isSGR {
                        flush()
                        style.applySGR(parameterText, fallback: palette.foreground)
                        index = cursor
                        continue
                    }
                }
            }

            buffer.append(rawText[index])
            index = rawText.index(after: index)
        }

        flush()
        return result
    }
}

private struct ANSIStyle {
    var color: SwiftUI.Color
    var isBold: Bool

    mutating func applySGR(_ parameterText: String, fallback: SwiftUI.Color) {
        let codes = parameterText.isEmpty ? [0] : parameterText
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                color = fallback
                isBold = false
            case 1:
                isBold = true
            case 22:
                isBold = false
            case 30...37, 90...97:
                color = Self.color(for: code)
            case 39:
                color = fallback
            case 38:
                if index + 4 < codes.count, codes[index + 1] == 2 {
                    color = SwiftUI.Color(
                        red: Double(codes[index + 2]) / 255.0,
                        green: Double(codes[index + 3]) / 255.0,
                        blue: Double(codes[index + 4]) / 255.0
                    )
                    index += 4
                }
            default:
                break
            }
            index += 1
        }
    }

    private static func color(for code: Int) -> SwiftUI.Color {
        switch code {
        case 30: SwiftUI.Color(red: 0.32, green: 0.36, blue: 0.42)
        case 31: SwiftUI.Color(red: 1.0, green: 0.35, blue: 0.36)
        case 32: SwiftUI.Color(red: 0.42, green: 0.95, blue: 0.54)
        case 33: SwiftUI.Color(red: 1.0, green: 0.82, blue: 0.36)
        case 34: SwiftUI.Color(red: 0.38, green: 0.68, blue: 1.0)
        case 35: SwiftUI.Color(red: 0.88, green: 0.55, blue: 1.0)
        case 36: SwiftUI.Color(red: 0.38, green: 0.95, blue: 1.0)
        case 37: SwiftUI.Color(red: 0.86, green: 0.90, blue: 0.95)
        case 90: SwiftUI.Color(red: 0.45, green: 0.50, blue: 0.58)
        case 91: SwiftUI.Color(red: 1.0, green: 0.50, blue: 0.50)
        case 92: SwiftUI.Color(red: 0.55, green: 1.0, blue: 0.62)
        case 93: SwiftUI.Color(red: 1.0, green: 0.88, blue: 0.48)
        case 94: SwiftUI.Color(red: 0.50, green: 0.76, blue: 1.0)
        case 95: SwiftUI.Color(red: 0.96, green: 0.64, blue: 1.0)
        case 96: SwiftUI.Color(red: 0.55, green: 1.0, blue: 1.0)
        case 97: .white
        default: .primary
        }
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

    var background: [SwiftUI.Color] {
        switch theme {
        case .liquidDark: [SwiftUI.Color(red: 0.01, green: 0.02, blue: 0.06), SwiftUI.Color(red: 0.02, green: 0.05, blue: 0.09)]
        case .matrix: [.black, .green.opacity(0.18)]
        case .midnight: [SwiftUI.Color(red: 0.02, green: 0.02, blue: 0.08), SwiftUI.Color(red: 0.05, green: 0.05, blue: 0.18)]
        case .ice: [SwiftUI.Color(red: 0.90, green: 0.97, blue: 1.0), SwiftUI.Color(red: 0.70, green: 0.88, blue: 0.98)]
        case .solarized: [SwiftUI.Color(red: 0.00, green: 0.17, blue: 0.21), SwiftUI.Color(red: 0.03, green: 0.21, blue: 0.25)]
        case .neon: [.black, .purple.opacity(0.28)]
        case .classic: [.black, SwiftUI.Color(red: 0.05, green: 0.05, blue: 0.05)]
        case .raspberry: [SwiftUI.Color(red: 0.16, green: 0.02, blue: 0.08), SwiftUI.Color(red: 0.32, green: 0.04, blue: 0.14)]
        case .cyberGlass: [SwiftUI.Color(red: 0.02, green: 0.08, blue: 0.11), SwiftUI.Color(red: 0.08, green: 0.03, blue: 0.15)]
        case .terminalPro: [SwiftUI.Color(red: 0.02, green: 0.02, blue: 0.03), SwiftUI.Color(red: 0.10, green: 0.11, blue: 0.13)]
        }
    }

    var foreground: SwiftUI.Color {
        switch theme {
        case .ice: .black
        case .matrix: .green
        case .solarized: SwiftUI.Color(red: 0.51, green: 0.58, blue: 0.59)
        default: SwiftUI.Color(red: 0.62, green: 0.82, blue: 1.0)
        }
    }

    var glow: SwiftUI.Color {
        switch theme {
        case .matrix: .green
        case .raspberry: .pink
        case .ice: .cyan
        case .neon, .cyberGlass: .purple
        default: .cyan
        }
    }
}
