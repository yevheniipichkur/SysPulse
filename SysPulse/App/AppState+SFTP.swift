import Foundation
import SwiftData

extension AppState {
    func sftpBookmarks(for server: ServerProfile, favoritesOnly: Bool = false) -> [SFTPPathBookmark] {
        guard let modelContext else { return [] }
        let serverID = server.id
        let descriptor: FetchDescriptor<SFTPPathBookmark>
        if favoritesOnly {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.serverID == serverID && $0.isFavorite },
                sortBy: [SortDescriptor(\.label, order: .forward)]
            )
        } else {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.serverID == serverID },
                sortBy: [SortDescriptor(\.lastVisitedAt, order: .reverse)]
            )
        }
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func recordSFTPVisit(path: String, server: ServerProfile, label: String? = nil) {
        guard let modelContext else { return }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let serverID = server.id
        let descriptor = FetchDescriptor<SFTPPathBookmark>(
            predicate: #Predicate { $0.serverID == serverID && $0.path == trimmed }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.lastVisitedAt = .now
            if let label, !label.isEmpty { existing.label = label }
        } else {
            modelContext.insert(
                SFTPPathBookmark(serverID: serverID, path: trimmed, label: label ?? trimmed, isFavorite: false)
            )
        }
        try? modelContext.save()
    }

    func toggleSFTPBookmarkFavorite(_ bookmark: SFTPPathBookmark) {
        bookmark.isFavorite.toggle()
        try? modelContext?.save()
    }

    func addSFTPFavorite(path: String, server: ServerProfile, label: String = "") {
        guard let modelContext else { return }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let serverID = server.id
        let descriptor = FetchDescriptor<SFTPPathBookmark>(
            predicate: #Predicate { $0.serverID == serverID && $0.path == trimmed }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.isFavorite = true
            existing.label = label.isEmpty ? trimmed : label
        } else {
            modelContext.insert(
                SFTPPathBookmark(serverID: serverID, path: trimmed, label: label.isEmpty ? trimmed : label, isFavorite: true)
            )
        }
        try? modelContext.save()
    }

    func beginSFTPOperation(
        kind: SFTPOperationKind,
        fileName: String,
        server: ServerProfile,
        remotePath: String
    ) -> UUID {
        let operation = SFTPOperation(
            serverID: server.id,
            kind: kind,
            fileName: fileName,
            remotePath: remotePath,
            status: .running,
            message: localized("Waiting for server...")
        )
        var operations = sftpOperationsByServer[server.id] ?? []
        operations.insert(operation, at: 0)
        sftpOperationsByServer[server.id] = Array(operations.prefix(8))
        return operation.id
    }

    func finishSFTPOperation(
        _ operationID: UUID,
        serverID: UUID,
        status: SFTPOperationStatus,
        message: String
    ) {
        guard var operations = sftpOperationsByServer[serverID],
              let index = operations.firstIndex(where: { $0.id == operationID }) else {
            return
        }
        operations[index].status = status
        operations[index].message = message
        operations[index].completedAt = status == .running ? nil : .now
        sftpOperationsByServer[serverID] = Array(operations.prefix(8))
    }

    func refreshSFTPDirectory(for server: ServerProfile? = nil, path: String? = nil) {
        guard let targetServer = server ?? selectedServer else {
            postStatus(localized("Select a server before running commands."))
            return
        }

        let targetPath = path ?? sftpPath(for: targetServer)
        postStatus(localized("Loading SFTP directory %@...", targetPath))
        sftpErrorByServer.removeValue(forKey: targetServer.id)
        if path != nil {
            sftpPathByServer[targetServer.id] = targetPath
            sftpItemsByServer[targetServer.id] = []
        }
        let loadToken = UUID()
        sftpLoadTokensByServer[targetServer.id] = loadToken
        sftpLoadingServerIDs.insert(targetServer.id)
        Task {
            do {
                let listing = try await sftpService.listDirectory(
                    at: targetPath,
                    server: targetServer,
                    jumpHost: jumpHost(for: targetServer),
                    via: sshClient
                )
                await MainActor.run {
                    guard sftpLoadTokensByServer[targetServer.id] == loadToken else { return }
                    sftpPathByServer[targetServer.id] = listing.path
                    sftpItemsByServer[targetServer.id] = listing.items
                    sftpLoadTokensByServer.removeValue(forKey: targetServer.id)
                    sftpLoadingServerIDs.remove(targetServer.id)
                    sftpErrorByServer.removeValue(forKey: targetServer.id)
                    recordSFTPVisit(path: listing.path, server: targetServer)
                    postStatus(localized("Loaded %d SFTP items from %@.", listing.items.count, listing.path))
                }
            } catch {
                await MainActor.run {
                    guard sftpLoadTokensByServer[targetServer.id] == loadToken else { return }
                    let message = connectionErrorMessage(error, server: targetServer)
                    sftpLoadTokensByServer.removeValue(forKey: targetServer.id)
                    sftpLoadingServerIDs.remove(targetServer.id)
                    sftpErrorByServer[targetServer.id] = message
                    postStatus(localized("SFTP failed for %@: %@", targetServer.name, message))
                }
            }
        }
    }

    func openSFTPParent(for server: ServerProfile) {
        refreshSFTPDirectory(for: server, path: sftpService.parentPath(of: sftpPath(for: server)))
    }

    func uploadSFTPFile(from url: URL, to server: ServerProfile) {
        if jumpHost(for: server) != nil {
            postStatus(
                localized("SFTP upload through a jump host is not supported yet. Use Terminal or a direct connection."),
                style: .info
            )
            return
        }
        let fileName = url.lastPathComponent
        let directory = sftpPath(for: server)
        let operationID = beginSFTPOperation(kind: .upload, fileName: fileName, server: server, remotePath: directory)
        let didStartAccess = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let message = localized("Could not read the local file: %@", error.localizedDescription)
            finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
            postStatus(message, style: .error)
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
            return
        }
        if didStartAccess { url.stopAccessingSecurityScopedResource() }

        postStatus(localized("Uploading %@ via SFTP...", fileName))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Uploading to %@...", directory))
        sftpErrorByServer.removeValue(forKey: server.id)
        Task {
            do {
                try await sftpService.upload(data, named: fileName, to: directory, server: server, via: sshClient)
                await MainActor.run {
                    sftpErrorByServer.removeValue(forKey: server.id)
                    finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Uploaded %@.", fileName))
                    postStatus(localized("Uploaded %@ via SFTP.", fileName))
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    let message = connectionErrorMessage(error, server: server)
                    sftpErrorByServer[server.id] = message
                    finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
                    postStatus(localized("SFTP failed for %@: %@", server.name, message))
                }
            }
        }
    }

    func downloadSFTPFile(_ item: SFTPRemoteItem, from server: ServerProfile) async -> URL? {
        if jumpHost(for: server) != nil, item.isDirectory {
            postStatus(localized("Directory download through jump host is not supported."), style: .info)
            return nil
        }
        let operationID = beginSFTPOperation(kind: .download, fileName: item.name, server: server, remotePath: item.path)
        postStatus(localized("Downloading %@ via SFTP...", item.name))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Downloading from %@...", item.path))
        sftpErrorByServer.removeValue(forKey: server.id)
        do {
            let data = try await sftpService.download(
                item,
                server: server,
                jumpHost: jumpHost(for: server),
                via: sshClient
            )
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(item.name)
            try data.write(to: url, options: .atomic)
            sftpErrorByServer.removeValue(forKey: server.id)
            finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Download ready."))
            postStatus(localized("Downloaded %@ via SFTP.", item.name))
            return url
        } catch {
            let message = connectionErrorMessage(error, server: server)
            sftpErrorByServer[server.id] = message
            finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
            postStatus(localized("SFTP failed for %@: %@", server.name, message))
            return nil
        }
    }

    func deleteSFTPItem(_ item: SFTPRemoteItem, from server: ServerProfile) {
        if jumpHost(for: server) != nil {
            postStatus(localized("SFTP delete through jump host is not supported yet."), style: .info)
            return
        }
        let operationID = beginSFTPOperation(kind: .delete, fileName: item.name, server: server, remotePath: item.path)
        postStatus(localized("Deleting %@ via SFTP...", item.name))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Deleting from %@...", item.path))
        sftpErrorByServer.removeValue(forKey: server.id)
        Task {
            do {
                try await sftpService.delete(item, server: server, via: sshClient)
                await MainActor.run {
                    sftpErrorByServer.removeValue(forKey: server.id)
                    finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Deleted %@.", item.name))
                    postStatus(localized("Deleted %@ via SFTP.", item.name))
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    let message = connectionErrorMessage(error, server: server)
                    sftpErrorByServer[server.id] = message
                    finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
                    postStatus(localized("SFTP failed for %@: %@", server.name, message))
                }
            }
        }
    }

    func deleteSFTPItems(_ items: [SFTPRemoteItem], from server: ServerProfile) {
        guard !items.isEmpty else { return }
        if jumpHost(for: server) != nil {
            postStatus(localized("Bulk delete through jump host is not supported yet."), style: .info)
            return
        }
        let operationTitle = localized("%d items", items.count)
        let operationID = beginSFTPOperation(kind: .delete, fileName: operationTitle, server: server, remotePath: sftpPath(for: server))
        postStatus(localized("Deleting %d SFTP items...", items.count))
        finishSFTPOperation(operationID, serverID: server.id, status: .running, message: localized("Deleting %d items...", items.count))
        sftpErrorByServer.removeValue(forKey: server.id)
        Task {
            do {
                for item in items {
                    try await sftpService.delete(item, server: server, via: sshClient)
                }
                await MainActor.run {
                    sftpErrorByServer.removeValue(forKey: server.id)
                    finishSFTPOperation(operationID, serverID: server.id, status: .succeeded, message: localized("Deleted %d items.", items.count))
                    postStatus(localized("Deleted %d SFTP items.", items.count))
                    refreshSFTPDirectory(for: server)
                }
            } catch {
                await MainActor.run {
                    let message = connectionErrorMessage(error, server: server)
                    sftpErrorByServer[server.id] = message
                    finishSFTPOperation(operationID, serverID: server.id, status: .failed, message: message)
                    postStatus(localized("SFTP failed for %@: %@", server.name, message))
                }
            }
        }
    }
}
