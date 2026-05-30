import SwiftUI

struct LogBrowserView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    var server: ServerProfile

    @State private var logFiles: [String] = []
    @State private var selectedFile: String?
    @State private var fileContent = ""
    @State private var isLoadingFiles = false
    @State private var isLoadingContent = false
    @State private var errorMessage: String?
    @State private var lineCount = 200
    @State private var searchText = ""

    var body: some View {
        Group {
            if !appState.isProUnlocked {
                ProLockedBanner(feature: "Log Browser")
            } else {
                VStack(spacing: 12) {
                    GlassCard(cornerRadius: 22, padding: 0) {
                        sidebarContent
                    }
                    GlassCard(cornerRadius: 22, padding: 0) {
                        detailContent
                    }
                }
            }
        }
        .onAppear { loadLogFiles() }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(LocalizedStringKey("Log Files"), systemImage: "folder.badge.magnifyingglass")
                    .font(.headline)
                Spacer()
                Button(action: loadLogFiles) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isLoadingFiles ? 360 : 0))
                        .animation(isLoadingFiles ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoadingFiles)
                }
                .buttonStyle(.plain)
                .tint(.cyan)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isLoadingFiles {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if let error = errorMessage, logFiles.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(logFiles, id: \.self) { file in
                            Button {
                                selectedFile = file
                                loadContent(file: file)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .font(.caption)
                                        .foregroundStyle(selectedFile == file ? .cyan : .secondary)
                                    Text(file.components(separatedBy: "/").last ?? file)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    selectedFile == file
                                        ? Color.cyan.opacity(colorScheme == .dark ? 0.14 : 0.12)
                                        : Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            if let file = selectedFile {
                HStack(spacing: 10) {
                    Text(file.components(separatedBy: "/").last ?? file)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    lineCountPicker
                    Button(action: { loadContent(file: file) }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .tint(.cyan)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                TextField(LocalizedStringKey("Search logs…"), text: $searchText)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.04),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                if isLoadingContent {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ScrollView {
                        Text(filteredContent)
                            .font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 200)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.magnifyingglass")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.cyan.opacity(0.85))
                    Text(LocalizedStringKey("Select a log file"))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            }
        }
    }

    private var lineCountPicker: some View {
        Picker(LocalizedStringKey("Lines"), selection: $lineCount) {
            Text("100").tag(100)
            Text("200").tag(200)
            Text("500").tag(500)
            Text("1000").tag(1000)
        }
        .pickerStyle(.menu)
        .font(.caption)
        .onChange(of: lineCount) {
            if let file = selectedFile { loadContent(file: file) }
        }
    }

    private var filteredContent: String {
        guard !searchText.isEmpty else { return fileContent }
        let lines = fileContent.components(separatedBy: "\n")
        return lines.filter { $0.localizedCaseInsensitiveContains(searchText) }.joined(separator: "\n")
    }

    private func loadLogFiles() {
        isLoadingFiles = true
        errorMessage = nil
        Task {
            do {
                let cmd = "find /var/log -maxdepth 2 -name '*.log' -type f 2>/dev/null | sort | head -60"
                let output = try await appState.sshClient.run(cmd, on: server)
                let files = output.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                await MainActor.run {
                    logFiles = files
                    isLoadingFiles = false
                    if let first = files.first, selectedFile == nil {
                        selectedFile = first
                        loadContent(file: first)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = appState.connectionErrorMessage(error, server: server)
                    isLoadingFiles = false
                }
            }
        }
    }

    private func loadContent(file: String) {
        isLoadingContent = true
        fileContent = ""
        Task {
            do {
                let cmd = "tail -n \(lineCount) '\(file)' 2>/dev/null || echo '(empty or permission denied)'"
                let output = try await appState.sshClient.run(cmd, on: server)
                await MainActor.run {
                    fileContent = output
                    isLoadingContent = false
                }
            } catch {
                await MainActor.run {
                    fileContent = appState.connectionErrorMessage(error, server: server)
                    isLoadingContent = false
                }
            }
        }
    }
}
