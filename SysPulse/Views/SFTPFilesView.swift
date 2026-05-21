import SwiftUI

struct SFTPFilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var isImportingSFTPFile = false
    @State private var downloadedSFTPFileURL: URL?
    @State private var pendingDeleteItem: SFTPRemoteItem?
    @State private var showingDeleteConfirmation = false

    private var server: ServerProfile? { appState.selectedServer }
    private var currentPath: String { appState.sftpPath(for: server) }
    private var allItems: [SFTPRemoteItem] { appState.sftpItems(for: server) }

    private var visibleItems: [SFTPRemoteItem] {
        guard !searchText.isEmpty else { return allItems }
        return allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if let server {
                    fileList(server: server)
                } else {
                    EmptyStateView(
                        title: "No server selected",
                        message: "Choose a server from the Servers tab to browse its files.",
                        symbol: "folder"
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let server { breadcrumb(server: server) }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    trailingToolbar
                }
            }
            .searchable(text: $searchText, isPresented: $isSearching, prompt: "Search files")
            .fileImporter(
                isPresented: $isImportingSFTPFile,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                guard let server,
                      let url = try? result.get().first else { return }
                appState.uploadSFTPFile(from: url, to: server)
            }
            .alert("Delete file?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { pendingDeleteItem = nil }
                Button("Delete", role: .destructive) {
                    if let item = pendingDeleteItem, let server {
                        appState.deleteSFTPItem(item, from: server)
                    }
                    pendingDeleteItem = nil
                }
            } message: {
                Text(pendingDeleteItem.map { appState.localized("Delete %@?", $0.name) } ?? "")
            }
        }
        .accessibilityIdentifier(AppTab.sftp.screenAccessibilityIdentifier)
        .onAppear {
            if let server, allItems.isEmpty {
                appState.refreshSFTPDirectory(for: server)
            }
        }
    }

    // MARK: - Subviews

    private func fileList(server: ServerProfile) -> some View {
        List {
            if downloadedSFTPFileURL != nil {
                downloadReadyRow
            }

            if currentPath != "." && currentPath != "/" && !isSearching {
                parentRow(server: server)
            }

            ForEach(visibleItems) { item in
                fileRow(item, server: server)
            }

            if visibleItems.isEmpty && !searchText.isEmpty {
                Text("No results for "\(searchText)"")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if allItems.isEmpty && searchText.isEmpty {
                EmptyStateView(
                    title: "Empty directory",
                    message: "This directory has no files.",
                    symbol: "folder"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .onAppear {
                    appState.refreshSFTPDirectory(for: server)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            appState.refreshSFTPDirectory(for: server)
        }
    }

    private var downloadReadyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Download ready")
                    .font(.subheadline.weight(.semibold))
                Text(downloadedSFTPFileURL?.lastPathComponent ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let url = downloadedSFTPFileURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
            Button {
                downloadedSFTPFileURL = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.green.opacity(0.08))
    }

    private func parentRow(server: ServerProfile) -> some View {
        Button {
            appState.openSFTPParent(for: server)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32, alignment: .center)
                Text("..")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .listRowSeparator(.visible)
    }

    private func fileRow(_ item: SFTPRemoteItem, server: ServerProfile) -> some View {
        Button {
            if item.isDirectory {
                appState.refreshSFTPDirectory(for: server, path: item.path)
            }
        } label: {
            HStack(spacing: 14) {
                fileIcon(for: item)
                    .frame(width: 32, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !item.permissions.isEmpty {
                        Text(item.permissions)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.modifiedAt)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !item.isDirectory && item.size > 0 {
                        Text(formatSize(item.size))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDeleteItem = item
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            if !item.isDirectory {
                Button {
                    Task {
                        downloadedSFTPFileURL = await appState.downloadSFTPFile(item, from: server)
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .tint(.blue)
            }
        }
        .listRowSeparator(.visible)
    }

    @ViewBuilder
    private func fileIcon(for item: SFTPRemoteItem) -> some View {
        switch item.kind {
        case .directory:
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(.blue)
        case .symlink:
            Image(systemName: "link")
                .font(.title3)
                .foregroundStyle(.cyan)
        case .file, .other:
            let (symbol, color) = iconInfo(for: item.name)
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
        }
    }

    private func iconInfo(for name: String) -> (String, Color) {
        let ext = name.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf":
            return ("doc.richtext.fill", .red)
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "svg":
            return ("photo", .orange)
        case "mp4", "mov", "avi", "mkv", "m4v":
            return ("film", .purple)
        case "mp3", "aac", "flac", "wav", "m4a":
            return ("music.note", .pink)
        case "zip", "tar", "gz", "bz2", "xz", "7z":
            return ("doc.zipper", .brown)
        case "deb", "rpm", "pkg":
            return ("shippingbox.fill", .brown)
        case "sh", "bash", "zsh", "fish":
            return ("terminal", .green)
        case "py":
            return ("chevron.left.forwardslash.chevron.right", .blue)
        case "js", "ts", "jsx", "tsx":
            return ("chevron.left.forwardslash.chevron.right", .yellow)
        case "swift":
            return ("swift", .orange)
        case "html", "htm":
            return ("globe", .teal)
        case "css", "scss", "sass":
            return ("paintbrush.fill", .teal)
        case "php":
            return ("chevron.left.forwardslash.chevron.right", .indigo)
        case "sql", "db", "sqlite", "sqlite3":
            return ("cylinder.fill", .blue)
        case "json", "yaml", "yml", "toml", "xml":
            return ("doc.text.fill", .teal)
        case "md", "txt":
            return ("doc.text", .secondary)
        case "log":
            return ("doc.text.magnifyingglass", .secondary)
        case "conf", "config", "ini", "env":
            return ("gearshape.fill", .gray)
        default:
            return ("doc.fill", .secondary)
        }
    }

    private func breadcrumb(server: ServerProfile) -> some View {
        let parts = breadcrumbParts
        return HStack(spacing: 3) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if index == parts.count - 1 {
                    Text(part)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                } else {
                    Button(part) {
                        let target = targetPath(for: index, parts: parts)
                        appState.refreshSFTPDirectory(for: server, path: target)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .buttonStyle(.plain)
                }
            }
        }
        .lineLimit(1)
    }

    private var breadcrumbParts: [String] {
        let p = currentPath
        if p == "." || p.isEmpty { return ["~"] }
        let components = p.components(separatedBy: "/").filter { !$0.isEmpty }
        if components.isEmpty { return ["/"] }
        if components.count <= 3 { return components }
        return ["…"] + Array(components.suffix(2))
    }

    private func targetPath(for index: Int, parts: [String]) -> String {
        let p = currentPath
        let components = p.components(separatedBy: "/").filter { !$0.isEmpty }
        guard !components.isEmpty else { return "." }
        let adjustedIndex = components.count - parts.count + index
        if adjustedIndex < 0 { return "." }
        let target = "/" + components.prefix(adjustedIndex + 1).joined(separator: "/")
        return target.isEmpty ? "/" : target
    }

    private var trailingToolbar: some View {
        HStack(spacing: 16) {
            Button {
                isImportingSFTPFile = true
            } label: {
                Image(systemName: "arrow.up.doc")
            }
            .accessibilityLabel("Upload file")

            Menu {
                if let server {
                    Button {
                        appState.refreshSFTPDirectory(for: server)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        appState.refreshSFTPDirectory(for: server, path: ".")
                    } label: {
                        Label("Go to Home", systemImage: "house")
                    }
                    Button {
                        appState.openSFTPParent(for: server)
                    } label: {
                        Label("Go Up", systemImage: "arrow.up")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }

            Button {
                isSearching = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
