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
    @State private var isSelectionMode = false
    @State private var selectedItemIDs: Set<String> = []
    @State private var showingBulkDeleteConfirmation = false

    private var server: ServerProfile? { appState.selectedServer }
    private var currentPath: String { appState.sftpPath(for: server) }
    private var allItems: [SFTPRemoteItem] { appState.sftpItems(for: server) }
    private var isLoading: Bool { appState.isSFTPLoading(for: server) }
    private var loadError: String? { appState.sftpError(for: server) }
    private var activeAnimation: Animation? {
        SysPulseMotion.softSpring(disabled: appState.shouldReduceMotion)
    }

    private var visibleItems: [SFTPRemoteItem] {
        guard !searchText.isEmpty else { return allItems }
        return allItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedItems: [SFTPRemoteItem] {
        allItems.filter { selectedItemIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if let server {
                    filesSurface(server: server)
                } else {
                    ActionEmptyStateView(
                        title: "No server selected",
                        message: "Choose a server from the Servers tab to browse its files.",
                        symbol: "folder",
                        actionTitle: "Open Servers",
                        actionSymbol: "server.rack"
                    ) {
                        appState.selectedTab = .servers
                    }
                    .padding(.horizontal, SysPulseDesign.pagePadding)
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
            .alert("Delete selected items?", isPresented: $showingBulkDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let server {
                        appState.deleteSFTPItems(selectedItems, from: server)
                    }
                    selectedItemIDs.removeAll()
                    isSelectionMode = false
                }
            } message: {
                Text(appState.localized("Delete %d selected items?", selectedItemIDs.count))
            }
        }
        .translucentNavigationChrome()
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
            selectedItemIDs.removeAll()
            isSelectionMode = false
        }
        .onChange(of: isLoading) { _, isLoading in
            if !isLoading {
                pendingNavigationPath = nil
            }
        }
        .onChange(of: currentPath) { _, _ in
            selectedItemIDs.removeAll()
            isSelectionMode = false
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

                if let loadError, !loadError.isEmpty, !allItems.isEmpty {
                    sftpConnectionIssueCard(message: loadError, server: server)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isSelectionMode {
                    selectionBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if isLoading && allItems.isEmpty {
                    skeletonList
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if let loadError, !loadError.isEmpty, allItems.isEmpty {
                    sftpConnectionIssueCard(message: loadError, server: server)
                        .frame(maxWidth: .infinity, minHeight: 300)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else if visibleItems.isEmpty {
                    emptyCard
                        .frame(maxWidth: .infinity, minHeight: 320)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            fileCard(item, server: server)
                                .listItemEntrance(index: index, disabled: appState.shouldReduceMotion)
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
                    Text(server.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text("SFTP Files")
                        Text(verbatim: "·")
                        Text("\(server.username)@\(server.host)")
                            .font(.caption.monospaced())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .layoutPriority(1)

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
                        RefreshGlyph(isRefreshing: isLoading, disabled: appState.shouldReduceMotion)
                        .frame(width: 34, height: 34)
                    }
                    .buttonStyle(PressableGlassButtonStyle(cornerRadius: 14, verticalPadding: 0, horizontalPadding: 0))
                    .accessibilityLabel("Refresh Files")
                }
            }
        }
    }

    private func pathCard(server: ServerProfile) -> some View {
        GlassCard(cornerRadius: 22, padding: 13) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: currentPath == "/" ? "externaldrive.connected.to.line.below" : "folder")
                        .font(.headline)
                        .foregroundStyle(.cyan)
                        .frame(width: 36, height: 36)
                        .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Remote Path")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(isLoading ? appState.localized("Loading contents...") : appState.localized("%d items", allItems.count))
                            .font(.caption2)
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

                ScrollView(.horizontal) {
                    HStack(spacing: 7) {
                        SwiftUI.ForEach(addressCrumbs, id: \.id) { (crumb: SFTPAddressCrumb) in
                            if crumb.id > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                navigate(to: crumb.target, server: server)
                            } label: {
                                Text(crumb.title)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .foregroundStyle(crumb.isLast ? Color.primary : SysPulseDesign.actionStart)
                                    .padding(.horizontal, 9)
                                    .frame(height: 28)
                                    .background(
                                        (crumb.isLast ? SysPulseDesign.actionStart.opacity(0.12) : Color.white.opacity(0.05)),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(crumb.isLast)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
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

    private var skeletonList: some View {
        LazyVStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { index in
                skeletonFileRow(index: index)
            }
        }
        .padding(.top, 2)
    }

    private func skeletonFileRow(index: Int) -> some View {
        GlassCard(cornerRadius: 18, padding: 0) {
            HStack(spacing: 12) {
                SFTPShimmerBlock(
                    width: 42,
                    height: 42,
                    cornerRadius: 14,
                    isAnimated: !appState.shouldReduceMotion
                )

                VStack(alignment: .leading, spacing: 8) {
                    SFTPShimmerBlock(
                        width: CGFloat([132, 176, 118, 154, 204, 142, 188, 126][index % 8]),
                        height: 13,
                        cornerRadius: 6,
                        isAnimated: !appState.shouldReduceMotion
                    )
                    SFTPShimmerBlock(
                        width: CGFloat([76, 96, 68, 112, 84, 126, 92, 72][index % 8]),
                        height: 9,
                        cornerRadius: 5,
                        isAnimated: !appState.shouldReduceMotion
                    )
                }

                Spacer(minLength: 0)

                SFTPShimmerBlock(
                    width: 20,
                    height: 20,
                    cornerRadius: 7,
                    isAnimated: !appState.shouldReduceMotion
                )
            }
            .padding(13)
        }
        .allowsHitTesting(false)
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

    private func sftpConnectionIssueCard(message: String, server: ServerProfile) -> some View {
        GlassCard(cornerRadius: 22, padding: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Connection issue")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button {
                    appState.refreshSFTPDirectory(for: server)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PressableGlassButtonStyle(tint: .orange, cornerRadius: 13, verticalPadding: 0, horizontalPadding: 0))
                .accessibilityLabel("Try Again")
            }
        }
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

    private var selectionBar: some View {
        GlassCard(cornerRadius: 18, padding: 12) {
            HStack(spacing: 10) {
                Label(appState.localized("%d selected", selectedItemIDs.count), systemImage: "checkmark.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SysPulseDesign.actionStart)
                Spacer()
                Button("Select all") {
                    selectedItemIDs = Set(visibleItems.map(\.id))
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.plain)
                Button("Delete Selected", role: .destructive) {
                    showingBulkDeleteConfirmation = true
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.plain)
                .disabled(selectedItemIDs.isEmpty)
            }
        }
    }

    private func fileCard(_ item: SFTPRemoteItem, server: ServerProfile) -> some View {
        let isSelected = selectedItemIDs.contains(item.id)
        return GlassCard(cornerRadius: 20, padding: 0) {
            HStack(spacing: 12) {
                Button {
                    if isSelectionMode {
                        toggleSelection(item)
                    } else if item.isDirectory {
                        navigate(to: item.path, server: server)
                    }
                } label: {
                    HStack(spacing: 12) {
                        if isSelectionMode {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(isSelected ? .cyan : .secondary)
                                .transition(.opacity.combined(with: .scale(scale: 0.88)))
                        }

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
                            .disabled(isSelectionMode)
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
                        .disabled(isSelectionMode)

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
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.cyan.opacity(0.55), lineWidth: 1.5)
                    .transition(.opacity)
            }
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

    private var addressParts: [String] {
        let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." || trimmed == "~" {
            return ["~"]
        }
        let components = trimmed.components(separatedBy: "/").filter { !$0.isEmpty }
        if trimmed.hasPrefix("/") {
            return ["/"] + components
        }
        return components.isEmpty ? ["~"] : components
    }

    private func addressTarget(for index: Int) -> String {
        let trimmed = currentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = addressParts
        guard parts.indices.contains(index) else { return currentPath }
        if parts[index] == "~" { return "." }
        if parts[index] == "/" { return "/" }
        if trimmed.hasPrefix("/") {
            let components = parts.filter { $0 != "/" }
            let target = "/" + components.prefix(index).joined(separator: "/")
            return target == "/" ? "/" : target
        }
        return parts.prefix(index + 1).joined(separator: "/")
    }

    private var addressCrumbs: [SFTPAddressCrumb] {
        let parts = addressParts
        return parts.indices.map { index in
            SFTPAddressCrumb(
                id: index,
                title: parts[index],
                target: addressTarget(for: index),
                isLast: index == parts.count - 1
            )
        }
    }

    private func navigate(to path: String, server: ServerProfile) {
        guard path != currentPath else { return }
        selectedItemIDs.removeAll()
        isSelectionMode = false
        pathHistory.append(currentPath)
        pendingNavigationPath = path
        searchText = ""
        appState.haptic(.light)
        appState.refreshSFTPDirectory(for: server, path: path)
    }

    private func navigateBack(server: ServerProfile) {
        guard let previous = pathHistory.popLast() else { return }
        selectedItemIDs.removeAll()
        isSelectionMode = false
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
                    .foregroundStyle(SysPulseDesign.actionStart)
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
            if server != nil {
                Button(isSelectionMode ? "Done" : "Select") {
                    withOptionalAnimation {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedItemIDs.removeAll()
                        }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }

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

    private func toggleSelection(_ item: SFTPRemoteItem) {
        withOptionalAnimation {
            if selectedItemIDs.contains(item.id) {
                selectedItemIDs.remove(item.id)
            } else {
                selectedItemIDs.insert(item.id)
            }
        }
        appState.haptic(.light)
    }

    private func withOptionalAnimation(_ updates: () -> Void) {
        if appState.shouldReduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86), updates)
        }
    }
}

private struct SFTPAddressCrumb: Identifiable {
    let id: Int
    let title: String
    let target: String
    let isLast: Bool
}

private struct SFTPShimmerBlock: View {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat
    var isAnimated: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .frame(width: width, height: height)
            .overlay {
                if isAnimated {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        GeometryReader { proxy in
                            let phase = context.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 1.25) / 1.25
                            let shimmerWidth = max(proxy.size.width * 0.68, 24)
                            let travel = proxy.size.width + shimmerWidth * 2

                            LinearGradient(
                                colors: [.clear, .white.opacity(0.22), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: shimmerWidth)
                            .offset(x: -shimmerWidth + CGFloat(phase) * travel)
                        }
                    }
                    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
    }
}
