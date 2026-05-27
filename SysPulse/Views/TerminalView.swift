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
    @State private var transcriptSearchSelection = 0
    @State private var sessionConnectionStates: [UUID: TerminalConnectionState] = [:]
    @State private var pendingTerminalCommandConfirmation: TerminalCommandConfirmation?
    @State private var isTerminalCommandConfirmationPresented = false
    @StateObject private var terminalBridgeStore = TerminalBridgeStore()
    @FocusState private var isTranscriptSearchFieldFocused: Bool

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

    private var terminalPalette: TerminalThemePalette {
        TerminalThemePalette(theme: appState.effectiveTerminalTheme)
    }

    private var transcriptSearchQuery: String {
        terminalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var transcriptSearchMatches: [TerminalSearchMatch] {
        let query = terminalSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty,
              let transcript = selectedSession?.transcript else { return [] }
        let matches = transcript
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line -> TerminalSearchMatch? in
                let text = plainTerminalSearchText(String(line))
                guard text.localizedCaseInsensitiveContains(query) else { return nil }
                return TerminalSearchMatch(lineNumber: index + 1, text: text.isEmpty ? " " : text)
            }
        return Array(matches.suffix(80))
    }

    private var selectedTranscriptSearchMatch: TerminalSearchMatch? {
        guard transcriptSearchMatches.indices.contains(transcriptSearchSelection) else { return transcriptSearchMatches.first }
        return transcriptSearchMatches[transcriptSearchSelection]
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
        .onChange(of: terminalSearchText) { _, _ in
            transcriptSearchSelection = 0
        }
        .onChange(of: transcriptSearchMatches.count) { _, count in
            if count == 0 {
                transcriptSearchSelection = 0
            } else {
                transcriptSearchSelection = min(transcriptSearchSelection, count - 1)
            }
        }
        .alert("Confirm remote command", isPresented: $isTerminalCommandConfirmationPresented) {
            Button("Cancel", role: .cancel) {
                pendingTerminalCommandConfirmation = nil
            }
            if let confirmation = pendingTerminalCommandConfirmation {
                Button(appState.localized("Run on %@", confirmation.serverName), role: .destructive) {
                    confirmPendingTerminalCommand(confirmation)
                }
            }
        } message: {
            if let confirmation = pendingTerminalCommandConfirmation {
                Text(terminalSafetyMessage(for: confirmation))
            }
        }
        .accessibilityIdentifier(AppTab.terminal.screenAccessibilityIdentifier)
    }

    private var terminalCanvas: some View {
        let palette = terminalPalette

        return VStack(spacing: 0) {
            topChrome(palette: palette)

            if let server = sessionServer {
                activeServerBar(server: server, palette: palette)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
                        handleTerminalInput(outboundBytes)
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
            TerminalConnectionBadge(state: activeConnectionState, palette: palette)

            Text(sessionServer == nil ? "SysPulse SSH" : activePrompt.trimmingCharacters(in: .whitespaces))
                .font(.caption.monospaced())
                .foregroundStyle(palette.chromeForeground)
                .lineLimit(1)

            Spacer()

            Button {
                reconnectCurrentSession()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.chromeForeground)
            .accessibilityLabel(Text("Reconnect"))

            Button {
                updateWithMotion {
                    isTranscriptSearchPresented.toggle()
                    if !isTranscriptSearchPresented {
                        terminalSearchText = ""
                        isTranscriptSearchFieldFocused = false
                    } else {
                        transcriptSearchSelection = 0
                    }
                }
                if isTranscriptSearchPresented {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(120))
                        isTranscriptSearchFieldFocused = true
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isTranscriptSearchPresented ? palette.accent : palette.chromeForeground)
            .accessibilityLabel(Text("Search transcript"))

            Button {
                UIPasteboard.general.string = selectedSession?.transcript ?? ""
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.chromeForeground)
            .accessibilityLabel(Text("Copy transcript"))

            Button {
                clearTranscript()
            } label: {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.chromeForeground)
            .accessibilityLabel(Text("Clear transcript"))
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(palette.chromeBackground)
    }

    private func activeServerBar(server: ServerProfile, palette: TerminalThemePalette) -> some View {
        let serverAccent = Color(hex: server.accentHex)
        return HStack(spacing: 10) {
            Image(systemName: server.displayIcon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(serverAccent)
                .frame(width: 34, height: 34)
                .background(serverAccent.opacity(palette.isLight ? 0.12 : 0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Active server")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.secondaryControlForeground)
                Text(server.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.controlForeground)
                    .lineLimit(1)
                Text("\(server.username)@\(server.host)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(palette.secondaryControlForeground)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(activeConnectionState.color)
                        .frame(width: 7, height: 7)
                    Text(activeConnectionState.title)
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(palette.controlForeground)

                HStack(spacing: 4) {
                    Text("Session")
                    Text(selectedSession?.title ?? server.name)
                        .lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(palette.secondaryControlForeground)
            }
            .frame(maxWidth: 118, alignment: .trailing)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(palette.activeControlBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(serverAccent.opacity(palette.isLight ? 0.40 : 0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(appState.localized("Active server: %@", server.name)))
    }

    private func transcriptSearchPanel(palette: TerminalThemePalette) -> some View {
        let matches = transcriptSearchMatches
        let selectedMatch = selectedTranscriptSearchMatch

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.searchAccent)

                    TextField("Search transcript", text: $terminalSearchText)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(palette.controlForeground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isTranscriptSearchFieldFocused)
                        .submitLabel(.search)
                        .accessibilityLabel(Text("Search transcript"))

                    if !terminalSearchText.isEmpty {
                        Button {
                            terminalSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(palette.secondaryControlForeground)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear search"))
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 40)
                .background(palette.searchFieldBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(palette.searchStroke, lineWidth: 1)
                }
            }

            if !transcriptSearchQuery.isEmpty {
                if matches.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption.weight(.bold))
                        Text("No matching lines")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(palette.secondaryControlForeground)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(palette.searchRowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    HStack(spacing: 8) {
                        if let selectedMatch {
                            Label(appState.localized("Line %d", selectedMatch.lineNumber), systemImage: "line.3.horizontal")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(palette.searchAccent)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        Spacer(minLength: 4)

                        Text(appState.localized("%d matches", matches.count))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.secondaryControlForeground)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(palette.searchBadgeBackground, in: Capsule())
                            .accessibilityHidden(true)

                        TerminalSearchIconButton(systemName: "chevron.up", accessibilityLabel: "Previous match", palette: palette, isDisabled: matches.isEmpty) {
                            moveTranscriptSearchSelection(-1)
                        }

                        TerminalSearchIconButton(systemName: "chevron.down", accessibilityLabel: "Next match", palette: palette, isDisabled: matches.isEmpty) {
                            moveTranscriptSearchSelection(1)
                        }

                        TerminalSearchIconButton(systemName: "doc.on.doc", accessibilityLabel: "Copy selected match", palette: palette, isDisabled: selectedMatch == nil) {
                            copySelectedTranscriptSearchMatch()
                        }
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                                Button {
                                    transcriptSearchSelection = index
                                } label: {
                                    TerminalSearchMatchRow(
                                        match: match,
                                        isSelected: index == transcriptSearchSelection,
                                        palette: palette
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(appState.localized("Line %d: %@", match.lineNumber, match.text)))
                            }
                        }
                    }
                    .frame(maxHeight: 154)
                }
            }
        }
        .padding(10)
        .background(palette.searchPanelBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.searchStroke, lineWidth: 1)
        }
    }

    private func moveTranscriptSearchSelection(_ delta: Int) {
        let count = transcriptSearchMatches.count
        guard count > 0 else {
            transcriptSearchSelection = 0
            return
        }
        transcriptSearchSelection = (transcriptSearchSelection + delta + count) % count
        appState.haptic(.light)
    }

    private func copySelectedTranscriptSearchMatch() {
        guard let selectedTranscriptSearchMatch else { return }
        UIPasteboard.general.string = selectedTranscriptSearchMatch.text
        appState.haptic(.light)
    }

    private var bottomConsole: some View {
        let palette = terminalPalette

        return VStack(spacing: 8) {
            connectionBar
            terminalSessionStrip
            if keyboardActive { historySuggestions }
            keyboardAccessory
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay {
                    Rectangle()
                        .fill(palette.consoleBackground)
                }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(palette.controlStroke)
                .frame(height: 1)
        }
        .animation(SysPulseMotion.quickSpring(disabled: appState.shouldReduceMotion), value: currentInput)
    }

    private var connectionBar: some View {
        let palette = terminalPalette

        return HStack(spacing: 8) {
            TerminalIconButton(systemName: "chevron.left", accessibilityLabel: "Back to servers", palette: palette) {
                leaveTerminal(to: .servers)
            }

            Menu {
                if appState.serverProfiles.isEmpty {
                    Button("Add Server") { leaveTerminal(to: .servers) }
                } else {
                    ForEach(appState.serverProfiles) { server in
                        Button {
                            selectTerminalServer(server)
                        } label: {
                            Label("\(server.name) · \(server.host)", systemImage: server.displayIcon)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let sessionServer {
                        Image(systemName: sessionServer.displayIcon)
                            .foregroundStyle(Color(hex: sessionServer.accentHex))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sessionServer.name)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                            Text(sessionServer.host)
                                .font(.caption2.monospaced())
                                .foregroundStyle(palette.secondaryControlForeground)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Image(systemName: "network")
                        Text(appState.localized("No saved servers"))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(palette.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.controlStroke, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.controlForeground)

            TerminalIconButton(systemName: "plus", accessibilityLabel: "New session", palette: palette) {
                if let server = appState.selectedServer {
                    createSession(for: server)
                } else {
                    leaveTerminal(to: .servers)
                }
            }

            TerminalIconButton(systemName: "doc.on.clipboard", accessibilityLabel: "Paste", palette: palette) {
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
                        .foregroundStyle(palette.controlForeground)
                        .background(palette.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(palette.controlStroke, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Terminal history"))
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
                    .foregroundStyle(palette.controlForeground)
                    .background(palette.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.controlStroke, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var terminalSessionStrip: some View {
        let palette = terminalPalette

        return Group {
            if !visibleTerminalSessions.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(visibleTerminalSessions) { session in
                                TerminalSessionPill(
                                    title: session.title,
                                    isActive: session.id == activeSessionID,
                                    state: sessionConnectionStates[session.id] ?? (ptySessions[session.id] == nil ? .disconnected : .connected),
                                    palette: palette,
                                    close: {
                                        closeSession(session.id)
                                    }
                                ) {
                                    selectSession(session)
                                    keyboardActive = true
                                    focusActiveTerminal()
                                }
                                .id(session.id)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear {
                        if let activeSessionID {
                            proxy.scrollTo(activeSessionID, anchor: .center)
                        }
                    }
                    .onChange(of: activeSessionID) { _, newID in
                        guard let newID else { return }
                        if appState.shouldReduceMotion {
                            proxy.scrollTo(newID, anchor: .center)
                        } else {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // Shows recent commands or prefix-filtered history when typing
    private var historySuggestions: some View {
        let palette = terminalPalette
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
                            .foregroundStyle(palette.controlForeground)
                            .background(palette.controlBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(palette.controlStroke, lineWidth: 1)
                            }
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
        let palette = terminalPalette

        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(activePrompt)
                    .foregroundStyle(palette.prompt)
                Text(currentInput + "█")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(palette.controlForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
            .font(.system(size: 15, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.controlStroke, lineWidth: 1)
            }
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
            .foregroundStyle(palette.controlForeground)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(palette.controlBackground, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(palette.controlStroke, lineWidth: 1)
            }
            .buttonStyle(.plain)
        }
    }

    private var keyboardAccessory: some View {
        let palette = terminalPalette

        return ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(["esc", "tab", "ctrl", "alt", "/", "|", "~", "-", "^C", "^X", "^O", "↑", "↓", "←", "→"], id: \.self) { key in
                    Button {
                        insertAccessory(key)
                    } label: {
                        Text(key)
                            .font(.caption.weight(.bold))
                            .frame(width: key.count > 2 ? 44 : 34)
                    }
                    .buttonStyle(TerminalKeyStyle(isActive: keyIsLatched(key), palette: palette))
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

    private func handleTerminalInput(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        if let confirmation = terminalCommandConfirmation(for: bytes) {
            pendingTerminalCommandConfirmation = confirmation
            isTerminalCommandConfirmationPresented = true
            appState.haptic(.rigid)
            return
        }
        mirrorTerminalInput(bytes)
        activePTY?.send(bytes)
    }

    private func terminalCommandConfirmation(for bytes: [UInt8]) -> TerminalCommandConfirmation? {
        guard pendingTerminalCommandConfirmation == nil,
              let server = sessionServer,
              let command = terminalCommandCandidate(beforeSubmitting: bytes) else {
            return nil
        }

        let analysis = CommandSafetyAnalyzer().analyze(command)
        guard analysis.requiresConfirmation else { return nil }
        return TerminalCommandConfirmation(
            serverName: server.name,
            command: command,
            reasons: analysis.reasons.map { appState.localized($0) },
            bytes: bytes
        )
    }

    private func terminalCommandCandidate(beforeSubmitting bytes: [UInt8]) -> String? {
        var candidate = currentInput
        for byte in bytes {
            switch byte {
            case 10, 13:
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            case 3, 21:
                return nil
            case 8, 127:
                if !candidate.isEmpty { candidate.removeLast() }
            case 32...126:
                candidate.append(Character(UnicodeScalar(byte)))
            default:
                continue
            }
        }
        return nil
    }

    private func terminalSafetyMessage(for confirmation: TerminalCommandConfirmation) -> String {
        var lines = [
            appState.localized("Server: %@", confirmation.serverName),
            appState.localized("Command: %@", confirmation.command)
        ]
        if !confirmation.reasons.isEmpty {
            lines.append(appState.localized("Risk: %@", confirmation.reasons.joined(separator: ", ")))
        }
        lines.append(appState.localized("This command will run remotely over SSH."))
        return lines.joined(separator: "\n")
    }

    private func confirmPendingTerminalCommand(_ confirmation: TerminalCommandConfirmation) {
        pendingTerminalCommandConfirmation = nil
        isTerminalCommandConfirmationPresented = false
        mirrorTerminalInput(confirmation.bytes)
        activePTY?.send(confirmation.bytes)
        keyboardActive = true
        focusActiveTerminal()
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
                let message = "\n[Disconnected: \(appStateRef.connectionErrorMessage(error, server: server))]\n"
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
        let didChangeSession = selectedSessionID != session.id
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
        if didChangeSession {
            resetTerminalInputState()
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

    private func resetTerminalInputState() {
        currentInput = ""
        controlModifierActive = false
        altModifierActive = false
        transcriptSearchSelection = 0
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

private struct TerminalCommandConfirmation: Identifiable {
    let id = UUID()
    var serverName: String
    var command: String
    var reasons: [String]
    var bytes: [UInt8]
}

private struct TerminalSearchMatch: Identifiable, Equatable {
    var lineNumber: Int
    var text: String

    var id: String { "\(lineNumber)-\(text)" }
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

private struct TerminalSearchMatchRow: View {
    var match: TerminalSearchMatch
    var isSelected: Bool
    var palette: TerminalThemePalette

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(match.lineNumber)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(isSelected ? palette.accent : palette.secondaryControlForeground)
                .frame(width: 44, alignment: .trailing)

            Text(match.text)
                .font(.caption.monospaced())
                .foregroundStyle(palette.foreground)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            isSelected ? palette.searchSelectedRowBackground : palette.searchRowBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? palette.searchAccent.opacity(0.38) : palette.searchStroke.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct TerminalSearchIconButton: View {
    var systemName: String
    var accessibilityLabel: LocalizedStringKey
    var palette: TerminalThemePalette
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.caption.weight(.bold))
                .foregroundStyle(isDisabled ? palette.secondaryControlForeground.opacity(0.55) : palette.controlForeground)
                .frame(width: 30, height: 30)
                .background(palette.searchButtonBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(palette.searchStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(accessibilityLabel))
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

private let terminalReplayResetSequence = "\u{1B}c\u{1B}[2J\u{1B}[H"

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
            feedHandler?(Array(terminalReplayResetSequence.utf8))
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
                feedHandler(Array(terminalReplayResetSequence.utf8))
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
                terminalView?.feed(text: terminalReplayResetSequence)
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

private func plainTerminalSearchText(_ text: String) -> String {
    var output = ""
    var index = text.startIndex

    while index < text.endIndex {
        if text[index] == "\u{1B}" {
            let next = text.index(after: index)
            guard next < text.endIndex else { break }

            if text[next] == "[" {
                var cursor = text.index(after: next)
                while cursor < text.endIndex {
                    if let scalar = text[cursor].unicodeScalars.first,
                       scalar.value >= 0x40,
                       scalar.value <= 0x7E {
                        cursor = text.index(after: cursor)
                        break
                    }
                    cursor = text.index(after: cursor)
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
    var palette: TerminalThemePalette

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
        .foregroundStyle(palette.chromeForeground)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(palette.badgeBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(state.color.opacity(palette.isLight ? 0.34 : 0.26), lineWidth: 1)
        }
    }
}

private struct TerminalSessionPill: View {
    var title: String
    var isActive: Bool
    var state: TerminalConnectionState
    var palette: TerminalThemePalette
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
                .foregroundStyle(isActive ? palette.controlForeground : palette.secondaryControlForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(state.title))

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(palette.secondaryControlForeground)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close session"))
        }
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .frame(height: 32)
        .background(isActive ? palette.activeControlBackground : palette.controlBackground, in: Capsule())
        .overlay {
            Capsule()
                .stroke(isActive ? palette.accent.opacity(0.68) : palette.controlStroke, lineWidth: isActive ? 1.4 : 1)
        }
        .overlay(alignment: .bottom) {
            if isActive {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 28, height: 2)
                    .offset(y: 1)
            }
        }
    }
}

private struct TerminalKeyStyle: ButtonStyle {
    var isActive: Bool = false
    var palette: TerminalThemePalette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 30)
            .padding(.horizontal, 5)
            .foregroundStyle(isActive ? palette.accent : palette.controlForeground)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.controlBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(palette.accent.opacity(configuration.isPressed ? 0.22 : isActive ? 0.16 : 0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(configuration.isPressed || isActive ? palette.accent.opacity(0.38) : palette.controlStroke, lineWidth: 1)
                    }
            )
            .scaleEffect(configuration.isPressed ? 0.91 : 1.0)
            .animation(.easeOut(duration: 0.07), value: configuration.isPressed)
    }
}

private struct TerminalIconButton: View {
    var systemName: String
    var accessibilityLabel: LocalizedStringKey
    var palette: TerminalThemePalette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.callout.weight(.bold))
                .foregroundStyle(palette.controlForeground)
                .frame(width: 38, height: 38)
                .background(palette.controlBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(palette.controlStroke, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct TerminalThemePalette {
    var theme: TerminalTheme

    var isLight: Bool {
        theme == .ice
    }

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
        case .ice:
            SwiftUI.Color(red: 0.02, green: 0.08, blue: 0.12)
        case .matrix:
            SwiftUI.Color(red: 0.66, green: 1.0, blue: 0.58)
        case .solarized:
            SwiftUI.Color(red: 0.84, green: 0.89, blue: 0.82)
        case .raspberry:
            SwiftUI.Color(red: 1.0, green: 0.80, blue: 0.90)
        case .terminalPro:
            SwiftUI.Color(red: 0.86, green: 0.91, blue: 0.98)
        default:
            SwiftUI.Color(red: 0.76, green: 0.90, blue: 1.0)
        }
    }

    var chromeForeground: SwiftUI.Color {
        isLight ? SwiftUI.Color(red: 0.03, green: 0.10, blue: 0.15) : foreground
    }

    var controlForeground: SwiftUI.Color {
        isLight ? SwiftUI.Color(red: 0.02, green: 0.08, blue: 0.12) : SwiftUI.Color.white.opacity(0.94)
    }

    var secondaryControlForeground: SwiftUI.Color {
        isLight ? SwiftUI.Color.black.opacity(0.66) : SwiftUI.Color.white.opacity(0.66)
    }

    var accent: SwiftUI.Color {
        switch theme {
        case .ice:
            SwiftUI.Color(red: 0.02, green: 0.36, blue: 0.78)
        case .matrix:
            SwiftUI.Color(red: 0.28, green: 1.0, blue: 0.38)
        case .solarized:
            SwiftUI.Color(red: 0.55, green: 0.74, blue: 0.74)
        case .raspberry:
            .pink
        case .neon, .cyberGlass:
            .purple
        default:
            .cyan
        }
    }

    var prompt: SwiftUI.Color {
        switch theme {
        case .ice:
            SwiftUI.Color(red: 0.02, green: 0.32, blue: 0.72)
        case .solarized:
            SwiftUI.Color(red: 0.70, green: 0.82, blue: 0.66)
        default:
            accent
        }
    }

    var chromeBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.white.opacity(0.72) : SwiftUI.Color.black.opacity(0.28)
    }

    var consoleBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.white.opacity(0.82) : SwiftUI.Color.black.opacity(0.44)
    }

    var controlBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.white.opacity(0.90) : SwiftUI.Color.white.opacity(0.09)
    }

    var activeControlBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.white.opacity(0.98) : accent.opacity(0.16)
    }

    var inputBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.white.opacity(0.96) : SwiftUI.Color.black.opacity(0.36)
    }

    var badgeBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.white.opacity(0.76) : SwiftUI.Color.white.opacity(0.08)
    }

    var controlStroke: SwiftUI.Color {
        isLight ? SwiftUI.Color.black.opacity(0.16) : SwiftUI.Color.white.opacity(0.16)
    }

    var searchAccent: SwiftUI.Color {
        switch theme {
        case .neon, .cyberGlass:
            SwiftUI.Color(red: 0.62, green: 0.82, blue: 1.0)
        case .raspberry:
            SwiftUI.Color(red: 1.0, green: 0.73, blue: 0.84)
        default:
            accent
        }
    }

    var searchPanelBackground: SwiftUI.Color {
        switch theme {
        case .ice:
            SwiftUI.Color.white.opacity(0.94)
        case .matrix:
            SwiftUI.Color.black.opacity(0.78)
        case .classic:
            SwiftUI.Color.black.opacity(0.86)
        default:
            SwiftUI.Color.black.opacity(0.46)
        }
    }

    var searchFieldBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.black.opacity(0.045) : SwiftUI.Color.white.opacity(0.075)
    }

    var searchButtonBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.white.opacity(0.88) : SwiftUI.Color.white.opacity(0.08)
    }

    var searchBadgeBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.black.opacity(0.055) : SwiftUI.Color.white.opacity(0.07)
    }

    var searchRowBackground: SwiftUI.Color {
        isLight ? SwiftUI.Color.black.opacity(0.035) : SwiftUI.Color.white.opacity(0.045)
    }

    var searchSelectedRowBackground: SwiftUI.Color {
        searchAccent.opacity(isLight ? 0.12 : 0.18)
    }

    var searchStroke: SwiftUI.Color {
        isLight ? SwiftUI.Color.black.opacity(0.11) : SwiftUI.Color.white.opacity(0.12)
    }

    var glow: SwiftUI.Color {
        switch theme {
        case .matrix: accent
        case .raspberry: .pink
        case .ice: accent
        case .neon, .cyberGlass: .purple
        default: .cyan
        }
    }
}
