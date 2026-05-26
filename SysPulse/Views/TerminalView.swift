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
    @State private var terminalSurfaceVisible = false
    @State private var terminalSearchText = ""
    @State private var isTranscriptSearchPresented = false
    @State private var sessionConnectionStates: [UUID: TerminalConnectionState] = [:]
    @StateObject private var terminalBridgeStore = TerminalBridgeStore()

    private var selectedServerID: UUID? {
        appState.selectedServer?.id
    }

    private var visibleTerminalSessions: [TerminalSession] {
        guard let selectedServerID else {
            return appState.terminalSessions
        }
        return appState.terminalSessions.filter { $0.serverID == selectedServerID }
    }

    private var selectedSession: TerminalSession? {
        if let selectedSessionID,
           let session = appState.terminalSessions.first(where: { $0.id == selectedSessionID }),
           selectedServerID == nil || session.serverID == selectedServerID {
            return session
        }
        return visibleTerminalSessions.first
    }

    private var sessionServer: ServerProfile? {
        if let serverID = selectedSession?.serverID,
           let server = appState.serverProfiles.first(where: { $0.id == serverID }) {
            return server
        }
        return appState.selectedServer
    }

    private var isConnected: Bool {
        if appState.isScreenshotMode {
            return selectedSession != nil
        }
        guard let id = activeSessionID else { return false }
        return ptySessions[id] != nil
    }

    private var activeConnectionState: TerminalConnectionState {
        guard let activeSessionID else {
            return .disconnected
        }
        if let state = sessionConnectionStates[activeSessionID] {
            return state
        }
        return isConnected ? .connected : .disconnected
    }

    private var activePTY: PTYSession? {
        activeSessionID.flatMap { ptySessions[$0] }
    }

    private var activeSessionID: UUID? {
        selectedSession?.id
    }

    private var activePrompt: String {
        guard let server = sessionServer,
              let sessionID = activeSessionID else {
            return "$ "
        }
        let state = runtimeStates[sessionID] ?? TerminalRuntimeState(server: server)
        let marker = server.username == "root" ? "#" : "$"
        return "\(server.username)@\(state.host):\(state.displayDirectory) \(marker) "
    }

    private var transcriptSearchMatches: [String] {
        let query = terminalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let transcript = selectedSession?.transcript else { return [] }
        return transcript
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.localizedCaseInsensitiveContains(query) }
            .suffix(12)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            AppBackground()
                .ignoresSafeArea()

            terminalCanvas
                .opacity(appState.shouldReduceMotion || terminalSurfaceVisible ? 1 : 0.001)
                .scaleEffect(appState.shouldReduceMotion || terminalSurfaceVisible ? 1 : 0.985, anchor: .bottom)
                .offset(y: appState.shouldReduceMotion || terminalSurfaceVisible ? 0 : 14)
                .blur(radius: appState.shouldReduceMotion || terminalSurfaceVisible ? 0 : 4)
                .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: terminalSurfaceVisible)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomConsole
        }
        .onAppear {
            setTerminalSurfaceVisible(true)
            ensureSessionForSelectedServer()
            guard !appState.isScreenshotMode else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(appState.shouldReduceMotion ? 0.05 : 0.5))
                keyboardActive = true
                focusActiveTerminal()
            }
        }
        .onChange(of: appState.selectedServer?.id) {
            ensureSessionForSelectedServer()
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            guard newTab == .terminal else {
                setTerminalSurfaceVisible(false)
                return
            }
            setTerminalSurfaceVisible(true)
            guard !appState.isScreenshotMode else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(appState.shouldReduceMotion ? 0.05 : 0.35))
                keyboardActive = true
                focusActiveTerminal()
            }
        }
        .accessibilityIdentifier(AppTab.terminal.screenAccessibilityIdentifier)
    }

    private var terminalCanvas: some View {
        let palette = TerminalThemePalette(theme: appState.effectiveTerminalTheme)

        return VStack(spacing: 0) {
            topChrome(palette: palette)

            if isTranscriptSearchPresented {
                transcriptSearchPanel(palette: palette)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
                        let outboundBytes = transformedTerminalInput(bytes)
                        mirrorTerminalInput(outboundBytes)
                        activePTY?.send(outboundBytes)
                    },
                    onResize: { cols, rows in
                        ptySessions[session.id]?.resize(cols: cols, rows: rows)
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(session.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    keyboardActive = true
                    focusActiveTerminal()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: palette.background, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        .animation(SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion), value: isTranscriptSearchPresented)
    }

    private func topChrome(palette: TerminalThemePalette) -> some View {
        HStack(spacing: 10) {
            TerminalConnectionBadge(state: activeConnectionState)

            Text(sessionServer == nil ? "SysPulse SSH" : activePrompt.trimmingCharacters(in: .whitespaces))
                .font(.caption.monospaced())
                .foregroundStyle(palette.foreground.opacity(0.82))
                .lineLimit(1)

            Spacer()

            Button {
                reconnectCurrentSession()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.foreground.opacity(0.82))
            .accessibilityLabel("Reconnect")

            Button {
                updateWithMotion {
                    isTranscriptSearchPresented.toggle()
                    if !isTranscriptSearchPresented {
                        terminalSearchText = ""
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isTranscriptSearchPresented ? .cyan : palette.foreground.opacity(0.82))
            .accessibilityLabel("Search transcript")

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

    private func transcriptSearchPanel(palette: TerminalThemePalette) -> some View {
        GlassCard(cornerRadius: 18, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.cyan)
                    TextField("Search transcript", text: $terminalSearchText)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !terminalSearchText.isEmpty {
                        Button {
                            terminalSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !terminalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if transcriptSearchMatches.isEmpty {
                        Text("No matching lines")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(transcriptSearchMatches.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(palette.foreground.opacity(0.86))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var bottomConsole: some View {
        VStack(spacing: 8) {
            connectionBar
            terminalSessionStrip
            if keyboardActive { historySuggestions }
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
        .animation(SysPulseMotion.quickSpring(disabled: appState.shouldReduceMotion), value: currentInput)
    }

    private var connectionBar: some View {
        HStack(spacing: 8) {
            TerminalIconButton(systemName: "chevron.left") {
                leaveTerminal(to: .servers)
            }

            Menu {
                if appState.serverProfiles.isEmpty {
                    Button("Add Server") { leaveTerminal(to: .servers) }
                } else {
                    ForEach(appState.serverProfiles) { server in
                        Button("\(server.name) · \(server.host)") {
                            selectTerminalServer(server)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "network")
                    Text(sessionServer?.host ?? appState.localized("No saved servers"))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            TerminalIconButton(systemName: "plus") {
                if let server = appState.selectedServer {
                    createSession(for: server)
                } else {
                    leaveTerminal(to: .servers)
                }
            }

            TerminalIconButton(systemName: "doc.on.clipboard") {
                guard let text = UIPasteboard.general.string else { return }
                sendRawToActivePTY(Array(text.utf8), mirrorInput: true)
                keyboardActive = true
                focusActiveTerminal()
            }

            if !commandHistory.isEmpty {
                Menu {
                    ForEach(commandHistory.reversed().prefix(12), id: \.self) { command in
                        Button(command) {
                            applySuggestion(command)
                        }
                    }
                    Divider()
                    Button("Clear terminal history", role: .destructive) {
                        updateWithMotion {
                            commandHistory.removeAll()
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Terminal history")
            }

            Menu {
                if visibleTerminalSessions.isEmpty {
                    Button("New session") {
                        if let server = appState.selectedServer {
                            createSession(for: server)
                        }
                    }
                } else {
                    ForEach(visibleTerminalSessions) { session in
                        Button(session.title) {
                            selectSession(session)
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

    private var terminalSessionStrip: some View {
        Group {
            if !visibleTerminalSessions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(visibleTerminalSessions) { session in
                            TerminalSessionPill(
                                title: session.title,
                                isActive: session.id == activeSessionID,
                                state: sessionConnectionStates[session.id] ?? (ptySessions[session.id] == nil ? .disconnected : .connected),
                                close: {
                                    closeSession(session.id)
                                }
                            ) {
                                selectSession(session)
                                keyboardActive = true
                                focusActiveTerminal()
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // Shows recent commands or prefix-filtered history when typing
    private var historySuggestions: some View {
        let suggestions = currentInput.isEmpty ? [] : Array(
            commandHistory.reversed()
                .filter { $0.hasPrefix(currentInput) && $0 != currentInput }
                .prefix(6)
        )

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
                .transition(.opacity.combined(with: .move(edge: .bottom)))
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
            .onTapGesture {
                keyboardActive = true
                focusActiveTerminal()
            }

            Button("Paste") {
                guard let text = UIPasteboard.general.string else { return }
                sendRawToActivePTY(Array(text.utf8), mirrorInput: true)
                keyboardActive = true
                focusActiveTerminal()
            }
            .font(.caption.weight(.bold))
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
                    .buttonStyle(TerminalKeyStyle(isActive: keyIsLatched(key)))
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Input handling

    private func applySuggestion(_ cmd: String) {
        // ctrl-U clears current line on server, then we type the suggestion
        sendRawToActivePTY([0x15], mirrorInput: false)
        sendRawToActivePTY(Array(cmd.utf8), mirrorInput: false)
        currentInput = cmd
        keyboardActive = true
        focusActiveTerminal()
    }

    private func insertAccessory(_ key: String) {
        switch key {
        case "↑":
            if let previous = commandHistory.last {
                applySuggestion(previous)
            }
        case "↓":
            sendRawToActivePTY([0x15], mirrorInput: false)
            currentInput = ""
        case "←":
            sendRawToActivePTY(Array("\u{1B}[D".utf8), mirrorInput: false)
        case "→":
            sendRawToActivePTY(Array("\u{1B}[C".utf8), mirrorInput: false)
        case "^C":
            sendRawToActivePTY([0x03], mirrorInput: true)
            currentInput = ""
            controlModifierActive = false
            altModifierActive = false
        case "^X":
            sendRawToActivePTY([0x18], mirrorInput: true)
            controlModifierActive = false
            altModifierActive = false
        case "^O":
            sendRawToActivePTY([0x0F], mirrorInput: true)
            controlModifierActive = false
            altModifierActive = false
        case "tab":
            sendRawToActivePTY([0x09], mirrorInput: true)
        case "esc":
            sendRawToActivePTY([0x1B], mirrorInput: true)
        case "ctrl":
            controlModifierActive.toggle()
            if controlModifierActive { altModifierActive = false }
        case "alt":
            altModifierActive.toggle()
            if altModifierActive { controlModifierActive = false }
        default:
            if applyPendingModifier(to: key) {
                break
            }
            currentInput += key
            sendRawToActivePTY(Array(key.utf8), mirrorInput: false)
        }
        keyboardActive = true
        focusActiveTerminal()
    }

    private func keyIsLatched(_ key: String) -> Bool {
        (key == "ctrl" && controlModifierActive) || (key == "alt" && altModifierActive)
    }

    private func applyPendingModifier(to text: String) -> Bool {
        guard controlModifierActive || altModifierActive else { return false }
        defer {
            controlModifierActive = false
            altModifierActive = false
        }

        if controlModifierActive, let control = controlCharacter(for: text) {
            sendRawToActivePTY(Array(control.utf8), mirrorInput: true)
            if control == "\u{03}" || control == "\u{15}" {
                currentInput = ""
            }
            return true
        }

        if altModifierActive {
            sendRawToActivePTY([0x1B], mirrorInput: false)
            sendRawToActivePTY(Array(text.utf8), mirrorInput: true)
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

    private func transformedTerminalInput(_ bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return bytes }
        guard controlModifierActive || altModifierActive else { return bytes }
        defer {
            controlModifierActive = false
            altModifierActive = false
        }

        if controlModifierActive,
           bytes.count == 1,
           let controlByte = controlByte(for: bytes[0]) {
            return [controlByte]
        }

        if altModifierActive {
            return [0x1B] + bytes
        }

        return bytes
    }

    private func controlByte(for byte: UInt8) -> UInt8? {
        switch byte {
        case 32:
            return 0x00
        case 63:
            return 0x7F
        case 64...95:
            return byte & 0x1F
        case 97...122:
            return (byte - 96) & 0x1F
        default:
            return nil
        }
    }

    private func sendRawToActivePTY(_ bytes: [UInt8], mirrorInput: Bool) {
        guard !bytes.isEmpty,
              let server = sessionServer ?? appState.selectedServer else { return }

        if selectedSession == nil {
            createSession(for: server)
        }

        let sessionID = activeSessionID
        guard let sessionID else { return }
        if selectedSessionID == nil {
            selectedSessionID = sessionID
        }

        if ptySessions[sessionID] == nil {
            append("[Reconnecting PTY…]\n", to: sessionID)
            connectPTY(sessionID: sessionID, server: server)
        }

        if mirrorInput {
            mirrorTerminalInput(bytes)
        }
        ptySessions[sessionID]?.send(bytes)
    }

    private func focusActiveTerminal() {
        guard let id = activeSessionID else { return }
        terminalBridgeStore.bridge(for: id).focus()
    }

    // MARK: - Session management

    private func ensureSessionForSelectedServer() {
        guard let server = appState.selectedServer else {
            if selectedSessionID == nil {
                selectedSessionID = appState.terminalSessions.first?.id
            }
            return
        }
        ensureSession(for: server)
    }

    private func ensureSession(for server: ServerProfile) {
        if let existing = appState.terminalSessions.first(where: { $0.serverID == server.id }) {
            selectSession(existing, updateSelectedServer: false)
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
        updateWithMotion {
            appState.terminalSessions.append(session)
            runtimeStates[session.id] = TerminalRuntimeState(server: server)
            selectedSessionID = session.id
        }
        refreshVisibleTerminal(for: session)
        appState.haptic(.light)
        if !appState.isScreenshotMode {
            keyboardActive = true
        }
        connectPTY(sessionID: session.id, server: server)
    }

    private func connectPTY(sessionID: UUID, server: ServerProfile) {
        var state = runtimeStates[sessionID] ?? TerminalRuntimeState(server: server)
        state.host = server.host
        runtimeStates[sessionID] = state
        sessionConnectionStates[sessionID] = .connecting
        if appState.isScreenshotMode {
            let transcript = appState.screenshotTerminalTranscript(for: server)
            if let index = appState.terminalSessions.firstIndex(where: { $0.id == sessionID }) {
                appState.terminalSessions[index].transcript = transcript
            }
            let bridge = terminalBridgeStore.bridge(for: sessionID)
            bridge.reset()
            bridge.feed(Array(transcript.utf8))
            sessionConnectionStates[sessionID] = .connected
            return
        }
        let pty = PTYSession()
        let appStateRef = appState
        pty.onOutput = { [appStateRef] text in
            guard let idx = appStateRef.terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }

            let controlResult = extractSysPulseControlMessages(from: text, sessionID: sessionID, server: server)
            var processed = sanitizeTerminalStream(controlResult.visibleText)
            processed = processed.replacingOccurrences(of: "\r\n", with: "\n")
            processed = processed.replacingOccurrences(of: "\r", with: "\n")
            guard !processed.isEmpty else { return }

            sessionConnectionStates[sessionID] = .connected
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
            sessionConnectionStates[sessionID] = .disconnected
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
        guard let id = sessionID ?? activeSessionID,
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        appState.terminalSessions[index].transcript += text
    }

    private func clearTranscript() {
        guard let id = activeSessionID,
              let index = appState.terminalSessions.firstIndex(where: { $0.id == id }) else { return }
        updateWithMotion {
            appState.terminalSessions[index].transcript = ""
        }
        terminalBridgeStore.bridge(for: id).reset()
    }

    private func closeCurrentSession() {
        guard let id = activeSessionID else { return }
        closeSession(id)
    }

    private func closeSession(_ id: UUID) {
        ptySessions[id]?.disconnect()
        ptySessions.removeValue(forKey: id)
        runtimeStates.removeValue(forKey: id)
        sessionConnectionStates.removeValue(forKey: id)
        terminalBridgeStore.remove(id)
        updateWithMotion {
            appState.terminalSessions.removeAll { $0.id == id }
            if selectedSessionID == id {
                selectedSessionID = visibleTerminalSessions.first?.id
                if let selectedSession {
                    refreshVisibleTerminal(for: selectedSession)
                }
            }
        }
    }

    private func selectTerminalServer(_ server: ServerProfile) {
        updateWithMotion {
            appState.select(server, tab: .terminal)
        }
        ensureSession(for: server)
    }

    private func selectSession(_ session: TerminalSession, updateSelectedServer: Bool = true) {
        updateWithMotion {
            selectedSessionID = session.id
            if updateSelectedServer,
               let serverID = session.serverID,
               let server = appState.serverProfiles.first(where: { $0.id == serverID }) {
                appState.selectedServer = server
            }
        }
        if let serverID = session.serverID,
           let server = appState.serverProfiles.first(where: { $0.id == serverID }),
           runtimeStates[session.id] == nil {
            runtimeStates[session.id] = TerminalRuntimeState(server: server)
        }
        refreshVisibleTerminal(for: session)
    }

    private func refreshVisibleTerminal(for session: TerminalSession) {
        terminalBridgeStore.bridge(for: session.id).replaceVisibleContent(with: Array(session.transcript.utf8))
    }

    private func reconnectCurrentSession() {
        guard let sessionID = activeSessionID,
              let server = sessionServer else {
            return
        }
        ptySessions[sessionID]?.disconnect()
        ptySessions.removeValue(forKey: sessionID)
        let bridge = terminalBridgeStore.bridge(for: sessionID)
        bridge.reset()
        let message = "[Reconnecting...]\n"
        append(message, to: sessionID)
        bridge.feed(Array(message.utf8))
        appState.haptic(.light)
        connectPTY(sessionID: sessionID, server: server)
    }

    private func leaveTerminal(to tab: AppTab) {
        guard !appState.shouldReduceMotion else {
            appState.selectedTab = tab
            return
        }
        withAnimation(.easeOut(duration: 0.14)) {
            terminalSurfaceVisible = false
            keyboardActive = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.11))
            appState.selectedTab = tab
        }
    }

    private func setTerminalSurfaceVisible(_ isVisible: Bool) {
        updateWithMotion {
            terminalSurfaceVisible = isVisible
        }
    }

    private func updateWithMotion(_ updates: () -> Void) {
        if appState.shouldReduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88), updates)
        }
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

private enum TerminalConnectionState: Equatable {
    case connecting
    case connected
    case disconnected

    var title: LocalizedStringKey {
        switch self {
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnected: "Offline"
        }
    }

    var color: SwiftUI.Color {
        switch self {
        case .connecting: .orange
        case .connected: .green
        case .disconnected: .secondary
        }
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
    private var focusHandler: (() -> Void)?
    private var pending: [[UInt8]] = []
    private var pendingReplacement: [UInt8]?
    private var pendingFocus = false
    private var isReadyForOutput = false

    func bind(
        feed: @escaping ([UInt8]) -> Void,
        reset: @escaping () -> Void,
        focus: @escaping () -> Void
    ) {
        feedHandler = feed
        resetHandler = reset
        focusHandler = focus
        isReadyForOutput = false
        if pendingFocus {
            pendingFocus = false
            focus()
        }
    }

    func markReadyForOutput() {
        isReadyForOutput = true
        flushPendingIfPossible()
    }

    func feed(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if isReadyForOutput, let feedHandler {
            feedHandler(bytes)
        } else {
            pending.append(bytes)
        }
    }

    func replaceVisibleContent(with bytes: [UInt8]) {
        pendingReplacement = bytes
        isReadyForOutput = false
    }

    func reset() {
        pendingReplacement = nil
        pending.removeAll()
        if let resetHandler {
            resetHandler()
        } else {
            feedHandler?(Array("\u{1B}[2J\u{1B}[H".utf8))
        }
    }

    func focus() {
        if let focusHandler {
            focusHandler()
        } else {
            pendingFocus = true
        }
    }

    private func flushPendingIfPossible() {
        guard isReadyForOutput, let feedHandler else { return }
        if let pendingReplacement {
            if let resetHandler {
                resetHandler()
            } else {
                feedHandler(Array("\u{1B}[2J\u{1B}[H".utf8))
            }
            if !pendingReplacement.isEmpty {
                feedHandler(pendingReplacement)
            }
            self.pendingReplacement = nil
        }
        guard !pending.isEmpty else { return }
        let buffered = pending
        pending.removeAll(keepingCapacity: true)
        buffered.forEach(feedHandler)
    }
}

private struct SwiftTermTerminalSurface: UIViewRepresentable {
    @ObservedObject var bridge: TerminalFeedBridge
    var fontSize: CGFloat
    var palette: TerminalThemePalette
    var onInput: ([UInt8]) -> Void
    var onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(bridge: bridge, onInput: onInput, onResize: onResize)
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
        context.coordinator.bridge = bridge
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
            },
            focus: { [weak terminalView] in
                DispatchQueue.main.async {
                    _ = terminalView?.becomeFirstResponder()
                }
            }
        )
        scheduleOutputReadinessFallback(for: terminalView)
    }

    private func scheduleOutputReadinessFallback(for terminalView: SwiftTerm.TerminalView) {
        let outputBridge = bridge
        DispatchQueue.main.async { [weak terminalView, weak outputBridge] in
            guard let terminalView,
                  terminalView.bounds.width >= 180,
                  terminalView.bounds.height >= 120 else { return }
            outputBridge?.markReadyForOutput()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak terminalView, weak outputBridge] in
            guard let terminalView,
                  terminalView.bounds.width >= 180,
                  terminalView.bounds.height >= 120 else { return }
            outputBridge?.markReadyForOutput()
        }
    }

    final class Coordinator: NSObject, SwiftTerm.TerminalViewDelegate {
        weak var bridge: TerminalFeedBridge?
        var onInput: ([UInt8]) -> Void
        var onResize: (Int, Int) -> Void

        init(bridge: TerminalFeedBridge, onInput: @escaping ([UInt8]) -> Void, onResize: @escaping (Int, Int) -> Void) {
            self.bridge = bridge
            self.onInput = onInput
            self.onResize = onResize
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            if newCols >= 24, newRows >= 8 {
                bridge?.markReadyForOutput()
            }
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

// MARK: - Sub-views

private struct TerminalConnectionBadge: View {
    var state: TerminalConnectionState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
                .shadow(color: state.color.opacity(0.65), radius: state == .connected ? 5 : 0)
            Text(state.title)
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.white.opacity(0.06), in: Capsule())
        .overlay {
            Capsule()
                .stroke(state.color.opacity(0.20), lineWidth: 1)
        }
    }
}

private struct TerminalSessionPill: View {
    var title: String
    var isActive: Bool
    var state: TerminalConnectionState
    var close: () -> Void
    var action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(state.color)
                        .frame(width: 7, height: 7)
                    Text(title)
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(isActive ? .primary : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(height: 32)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(isActive ? SwiftUI.Color.cyan.opacity(0.45) : SwiftUI.Color.white.opacity(0.10), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Capsule()
                    .fill(.cyan)
                    .frame(width: 28, height: 2)
                    .offset(y: 1)
            }
        }
    }
}

private struct TerminalKeyStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 30)
            .padding(.horizontal, 5)
            .foregroundStyle(isActive ? .cyan : .primary)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(.cyan.opacity(configuration.isPressed ? 0.22 : isActive ? 0.16 : 0.04))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(.white.opacity(configuration.isPressed || isActive ? 0.24 : 0.10), lineWidth: 1)
                    }
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
                .foregroundStyle(.primary)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(PressableGlassButtonStyle(cornerRadius: 12, verticalPadding: 0, horizontalPadding: 0))
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
