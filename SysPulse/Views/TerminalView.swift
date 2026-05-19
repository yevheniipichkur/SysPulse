import SwiftUI
import UIKit

struct TerminalView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSessionID: UUID?
    @State private var commandLine = ""
    @State private var searchText = ""
    @FocusState private var inputFocused: Bool

    private var selectedSession: TerminalSession? {
        if let selectedSessionID {
            return appState.terminalSessions.first { $0.id == selectedSessionID }
        }
        return appState.terminalSessions.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 14) {
                    PageHeader(
                        title: "Terminal",
                        subtitle: "Secure SSH sessions with command history.",
                        actionSymbol: "plus"
                    ) {
                        createSession()
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
                    .padding(.top, 8)

                    sessionTabs
                        .padding(.horizontal, SysPulseDesign.pagePadding)

                    TextField("Search terminal output", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, SysPulseDesign.pagePadding)

                    terminalSurface
                        .padding(.horizontal, SysPulseDesign.pagePadding)

                    keyboardAccessory
                        .padding(.horizontal, SysPulseDesign.pagePadding)

                    commandInput
                        .padding(.horizontal, SysPulseDesign.pagePadding)
                }
            }
        }
        .onAppear {
            selectedSessionID = selectedSessionID ?? appState.terminalSessions.first?.id
        }
    }

    private var sessionTabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(appState.terminalSessions) { session in
                    Button {
                        selectedSessionID = session.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(session.isActive ? .green : .secondary)
                                .frame(width: 7, height: 7)
                            Text(session.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(selectedSessionID == session.id ? .thinMaterial : .ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var terminalSurface: some View {
        let palette = TerminalThemePalette(theme: appState.settings.terminalTheme)
        return GlassCard(cornerRadius: 26, padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(.red.opacity(0.85)).frame(width: 11, height: 11)
                    Circle().fill(.yellow.opacity(0.85)).frame(width: 11, height: 11)
                    Circle().fill(.green.opacity(0.85)).frame(width: 11, height: 11)
                    Spacer()
                    Text(selectedSession?.title ?? "No Session")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = selectedSession?.transcript ?? ""
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    Button {
                        clearTranscript()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.white.opacity(0.05))

                if selectedSession == nil {
                    EmptyStateView(
                        title: "No terminal session",
                        message: "Create a session or select a server to connect.",
                        symbol: "terminal"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(highlightedTranscript)
                                .font(.system(size: CGFloat(appState.settings.terminalFontSize), weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.foreground)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .id("bottom")
                        }
                        .onChange(of: selectedSession?.transcript ?? "") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 360, maxHeight: .infinity)
            .background(
                LinearGradient(colors: palette.background, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(palette.glow.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: palette.glow.opacity(0.22), radius: 24)
        }
    }

    private var commandInput: some View {
        HStack(spacing: 10) {
            TextField("Command", text: $commandLine)
                .font(.system(size: CGFloat(appState.settings.terminalFontSize), design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .onSubmit(runCommand)

            Button(action: runCommand) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            .disabled(commandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var keyboardAccessory: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(["Esc", "Tab", "Ctrl", "Alt", "←", "→", "↑", "↓", "/", "|", "~"], id: \.self) { key in
                    Button {
                        insertAccessory(key)
                    } label: {
                        Text(key)
                            .font(.caption.weight(.bold))
                            .frame(width: 46, height: 34)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    clearTranscript()
                } label: {
                    Image(systemName: "clear")
                        .frame(width: 46, height: 34)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    commandLine += UIPasteboard.general.string ?? ""
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 46, height: 34)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var highlightedTranscript: String {
        guard !searchText.isEmpty else { return selectedSession?.transcript ?? "" }
        return selectedSession?.transcript.replacingOccurrences(of: searchText, with: "[\(searchText)]") ?? ""
    }

    private func createSession() {
        let server = appState.selectedServer
        let session = TerminalSession(
            serverID: server?.id,
            title: server?.name ?? "Local Demo",
            transcript: "SysPulse Terminal\nDemo Mode ready.\n"
        )
        appState.terminalSessions.append(session)
        selectedSessionID = session.id
    }

    private func runCommand() {
        let text = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let server = appState.selectedServer else {
            append("$ \(text)\nNo server selected.\n")
            commandLine = ""
            return
        }

        append("$ \(text)\n")
        commandLine = ""
        Task {
            do {
                let output = try await appState.sshClient.run(text, on: server)
                await MainActor.run {
                    append("\(output)\n")
                }
            } catch {
                await MainActor.run {
                    append("Error: \(error.localizedDescription)\n")
                }
            }
        }
    }

    private func append(_ text: String) {
        guard let id = selectedSessionID ?? appState.terminalSessions.first?.id,
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

    private func insertAccessory(_ key: String) {
        switch key {
        case "Tab": commandLine += "\t"
        case "Esc": commandLine += "\u{1b}"
        case "←", "→", "↑", "↓": break
        default: commandLine += key
        }
        inputFocused = true
    }
}

private struct TerminalThemePalette {
    var theme: TerminalTheme

    var background: [Color] {
        switch theme {
        case .liquidDark: [Color(red: 0.03, green: 0.05, blue: 0.08), Color(red: 0.02, green: 0.08, blue: 0.10)]
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
        default: Color(red: 0.86, green: 0.96, blue: 1.0)
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
