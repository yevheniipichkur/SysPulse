import SwiftUI

struct LogBrowserView: View {
    @EnvironmentObject private var appState: AppState

    var server: ServerProfile

    @State private var logFiles: [String] = []
    @State private var selectedFile: String?
    @State private var fileContent = ""
    @State private var isLoadingFiles = false
    @State private var isLoadingContent = false
    @State private var errorMessage: String?
    @State private var lineCount = 200
    @State private var searchText = ""

    private let logDirectories = ["/var/log", "/var/log/apt", "/var/log/nginx", "/var/log/mysql"]

    var body: some View {
        ZStack {
            AppBackground()

            if !appState.isProUnlocked {
                VStack {
                    Spacer()
                    ProLockedBanner(feature: "Log Browser")
                    Spacer()
                }
                .padding(.horizontal, SysPulseDesign.pagePadding)
            } else {
                VStack(spacing: 0) {
                    sidebarContent
                        .frame(maxHeight: 220)
                    Divider().opacity(0.2)
                    detailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { loadLogFiles() }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log Files")
                    .font(.headline)
                Spacer()
                Button(action: loadLogFiles) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isLoadingFiles ? 360 : 0))
                        .animation(isLoadingFiles ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoadingFiles)
                }
                .tint(.cyan)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isLoadingFiles {
                ProgressView()
                    .padding()
            } else if let error = errorMessage, logFiles.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(logFiles, id: \.self) { file in
                            Button {
                                selectedFile = file
                                loadContent(file: file)
                            } label: {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(file.components(separatedBy: "/").last ?? file)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    selectedFile == file ? Color.cyan.opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            if let file = selectedFile {
                // Toolbar
                HStack {
                    Text(file.components(separatedBy: "/").last ?? file)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    lineCountPicker
                    Button(action: { loadContent(file: file) }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(.cyan)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Search bar
                TextField("Search logs…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                Divider().opacity(0.2)

                if isLoadingContent {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    ScrollView {
                        Text(filteredContent)
                            .font(.caption2.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .textSelection(.enabled)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a log file")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var lineCountPicker: some View {
        Picker("Lines", selection: $lineCount) {
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

    // MARK: - Data loading

    private func loadLogFiles() {
        isLoadingFiles = true
        errorMessage = nil
        Task {
            do {
                // List .log files in /var/log
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

