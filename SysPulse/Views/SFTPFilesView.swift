import SwiftUI
import UniformTypeIdentifiers

struct SFTPFilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var isImportingSFTPFile = false
    @State private var downloadedSFTPFileURL: URL?
    @State private var pendingDeleteItem: SFTPRemoteItem?
    @State private var showingDeleteConfirmation = false
    @State private var pathHistory: [String] = []
    @State private var pendingNavigationPath: String?

    private var server: ServerProfile? { appState.selectedServer }
    private var currentPath: String { appState.sftpPath(for: server) }
    private var allItems: [SFTPRemoteItem] { appState.sftpItems(for: server) }
    private var isLoading: Bool { appState.isSFTPLoading(for: server) }
    private var activeAnimation: Animation? {
        appState.areUITestAnimationsDisabled ? nil : .spring(response: 0.34, dampingFraction: 0.86)
    }

    private var visibleItems: [SFTPRemoteItem] {
        guard !searchText.isEmpty else { return allItems }
        return allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if let server {
                    filesSurface(server: server)
                } else {
                    EmptyStateView(
                        title: "No server selected",
                        message: "Choose a server from the Servers tab to browse its files.",
                        symbol: "folder"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let server, allItems.isEmpty, !isLoading {
                appState.refreshSFTPDirectory(for: server)
            }
        }
        .onChange(of: server?.id) { _, _ in
            pathHistory.removeAll()
            searchText = ""
            downloadedSFTPFileURL = nil
            pendingNavigationPath = nil
        }
        .onChange(of: isLoading) { _, isLoading in
            if !isLoading {
                pendingNavigationPath = nil
            }
        }
    }

    // MARK: - Surface

    private func filesSurface(server: ServerProfile) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                sftpHeader(server: server)

                if downloadedSFTPFileURL != nil {
                    downloadReadyCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                pathCard(server: server)

                if isLoading && allItems.isEmpty {
                    loadingCard
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if visibleItems.isEmpty {
                    emptyCard
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleItems) { item in
                            fileCard(item, server: server)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            }
            .padding(.horizontal, SysPulseDesign.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 26)
            .animation(activeAnimation, value: currentPath)
            .animation(activeAnimation, value: visibleItems)
            .animation(activeAnimation, value: isLoading)
            .animation(activeAnimation, value: pendingNavigationPath)
        }
        .refreshable {
            appState.refreshSFTPDirectory(for: server)
        }
        .overlay(alignment: .top) {
            if isLoading && !allItems.isEmpty {
                loadingBanner
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .simultaneousGesture(swipeBackGesture(server: server))
    }

    private func sftpHeader(server: ServerProfile) -> some View {
        GlassCard(cornerRadius: 28, padding: 16) {
            HStack(spacing: 14) {
                Image(systemName: "folder.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 50, height: 50)
                    .background(.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("SFTP Files")
                        .font(.title3.weight(.bold))
                    Text("\(server.username)@\(server.host)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        isImportingSFTPFile = true
                    } label: {
                        Image(systemName: "arrow.up.doc")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14, verticalPadding: 0, horizontalPadding: 0))
                    .accessibilityLabel("Upload File")

                    Button {
                        appState.refreshSFTPDirectory(for: server)
                    } label: {
                        ZStack {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14, verticalPadding: 0, horizontalPadding: 0))
                    .accessibilityLabel("Refresh Files")
                }
            }
        }
    }

    private func pathCard(server: ServerProfile) -> some View {
        GlassCard(cornerRadius: 20, padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: currentPath == "/" ? "externaldrive.connected.to.line.below" : "folder")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                    .frame(width: 34, height: 34)
                    .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(currentPath.isEmpty ? "." : currentPath)
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                    Text(isLoading ? appState.localized("Opening folder...") : appState.localized("%d items", allItems.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    navigate(to: ".", server: server)
                } label: {
                    navigationButtonIcon(symbol: "house", path: ".")
                }
                .buttonStyle(PressableGlassButtonStyle(cornerRadius: 13, verticalPadding: 0, horizontalPadding: 0))
                .disabled(currentPath == "." || currentPath == "~")
                .accessibilityLabel("Go to Home")

                Button {
                    navigate(to: parentPath, server: server)
                } label: {
                    navigationButtonIcon(symbol: "arrow.uturn.left", path: parentPath)
                }
                .buttonStyle(PressableGlassButtonStyle(cornerRadius: 13, verticalPadding: 0, horizontalPadding: 0))
                .disabled(currentPath == "." || currentPath == "/")
                .accessibilityLabel("Go Up")
            }
        }
    }

    private var downloadReadyCard: some View {
        GlassCard(cornerRadius: 20, padding: 13) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
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
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 13, verticalPadding: 0, horizontalPadding: 0))
                }

                Button {
                    downloadedSFTPFileURL = nil
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(PressableGlassButtonStyle(tint: .gray, cornerRadius: 13, verticalPadding: 0, horizontalPadding: 0))
            }
        }
    }

    private var loadingCard: some View {
        GlassCard(cornerRadius: 28, padding: 24) {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                VStack(spacing: 6) {
                    Text("Opening folder...")
                        .font(.headline)
                    Text(currentPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var loadingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Opening folder...")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 260)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
    }

    private var emptyCard: some View {
        GlassCard(cornerRadius: 28, padding: 0) {
            EmptyStateView(
                title: searchText.isEmpty ? "Empty directory" : "No results",
                message: searchText.isEmpty ? "This directory has no files." : "Try a different search term.",
                symbol: searchText.isEmpty ? "folder.badge.questionmark" : "magnifyingglass"
            )
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .center)
        }
    }

    private func fileCard(_ item: SFTPRemoteItem, server: ServerProfile) -> some View {
        GlassCard(cornerRadius: 20, padding: 0) {
            HStack(spacing: 12) {
                Button {
                    if item.isDirectory {
                        navigate(to: item.path, server: server)
                    }
                } label: {
                    HStack(spacing: 12) {
                        fileIcon(for: item)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            HStack(spacing: 7) {
                                Text(item.kind.titleKey)
                                if !item.permissions.isEmpty {
                                    Text(item.permissions)
                                        .font(.caption2.monospaced())
                                }
                                if !item.isDirectory && item.size > 0 {
                                    Text(formatSize(item.size))
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .trailing, spacing: 4) {
                    if !item.modifiedAt.isEmpty {
                        Text(item.modifiedAt)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        if !item.isDirectory {
                            Button {
                                Task {
                                    downloadedSFTPFileURL = await appState.downloadSFTPFile(item, from: server)
                                }
                            } label: {
                                Image(systemName: "arrow.down.circle")
                                    .frame(width: 30, height: 30)
                            }
                            .buttonStyle(PressableGlassButtonStyle(cornerRadius: 12, verticalPadding: 0, horizontalPadding: 0))
                            .accessibilityLabel("Download")
                        }

                        Button(role: .destructive) {
                            pendingDeleteItem = item
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(PressableGlassButtonStyle(tint: .red, cornerRadius: 12, verticalPadding: 0, horizontalPadding: 0))
                        .accessibilityLabel("Delete")

                        if item.isDirectory {
                            if pendingNavigationPath == item.path, isLoading {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 20)
                                    .transition(.opacity)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
            }
            .padding(13)
        }
        .contextMenu {
            if item.isDirectory {
                Button {
                    navigate(to: item.path, server: server)
                } label: {
                    Label("Open", systemImage: "folder")
                }
            } else {
                Button {
                    Task {
                        downloadedSFTPFileURL = await appState.downloadSFTPFile(item, from: server)
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }

            Button(role: .destructive) {
                pendingDeleteItem = item
                showingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func fileIcon(for item: SFTPRemoteItem) -> some View {
        let info = iconInfo(for: item)
        Image(systemName: info.symbol)
            .font(.headline.weight(.semibold))
            .foregroundStyle(info.color)
            .frame(width: 42, height: 42)
            .background(info.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func iconInfo(for item: SFTPRemoteItem) -> (symbol: String, color: Color) {
        if item.kind == .directory { return ("folder.fill", .blue) }
        if item.kind == .symlink { return ("link", .cyan) }

        let ext = item.name.components(separatedBy: ".").last?.lowercased() ?? ""
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
        case "py", "js", "ts", "jsx", "tsx", "php":
            return ("chevron.left.forwardslash.chevron.right", .blue)
        case "swift":
            return ("swift", .orange)
        case "html", "htm":
            return ("globe", .teal)
        case "css", "scss", "sass":
            return ("paintbrush.fill", .teal)
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

    // MARK: - Navigation

    private var parentPath: String {
        let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/", trimmed != "." else { return "." }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let slashIndex = normalized.lastIndex(of: "/") else { return "." }
        if slashIndex == normalized.startIndex { return "/" }
        return String(normalized[..<slashIndex])
    }

    private func navigate(to path: String, server: ServerProfile) {
        guard path != currentPath else { return }
        pathHistory.append(currentPath)
        pendingNavigationPath = path
        searchText = ""
        appState.haptic(.light)
        appState.refreshSFTPDirectory(for: server, path: path)
    }

    private func navigateBack(server: ServerProfile) {
        guard let previous = pathHistory.popLast() else { return }
        pendingNavigationPath = previous
        searchText = ""
        appState.haptic(.light)
        appState.refreshSFTPDirectory(for: server, path: previous)
    }

    @ViewBuilder
    private func navigationButtonIcon(symbol: String, path: String) -> some View {
        if pendingNavigationPath == path, isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: 32, height: 32)
                .transition(.opacity)
        } else {
            Image(systemName: symbol)
                .frame(width: 32, height: 32)
                .transition(.opacity)
        }
    }

    private func swipeBackGesture(server: ServerProfile) -> some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onEnded { value in
                guard value.translation.width > 90,
                      abs(value.translation.height) < 55 else { return }
                navigateBack(server: server)
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
                        navigate(to: targetPath(for: index, parts: parts), server: server)
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
        return ["..."] + Array(components.suffix(2))
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
            .accessibilityLabel("Upload File")

            Menu {
                if let server {
                    Button {
                        appState.refreshSFTPDirectory(for: server)
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button {
                        navigate(to: ".", server: server)
                    } label: {
                        Label("Go to Home", systemImage: "house")
                    }
                    Button {
                        navigate(to: parentPath, server: server)
                    } label: {
                        Label("Go Up", systemImage: "arrow.uturn.left")
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
