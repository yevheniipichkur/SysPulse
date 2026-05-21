import Foundation
import Citadel
import NIOCore

enum SFTPFileTransferError: LocalizedError {
    case fileTooLarge(Int)
    case notAFile

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maxMB):
            L10n.string("SFTP upload is limited to %d MB.", maxMB)
        case .notAFile:
            L10n.string("Select a file to download.")
        }
    }
}

struct SFTPDirectoryListing {
    var path: String
    var items: [SFTPRemoteItem]
}

struct SFTPFileTransferService {
    private let maxUploadBytes = 100 * 1024 * 1024  // 100 MB

    func listDirectory(at path: String, server: ServerProfile, via sshClient: SSHClientProtocol) async throws -> SFTPDirectoryListing {
        let client = try await sshClient.makeCitadelClient(for: server)
        defer { Task { try? await client.close() } }
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }

        let resolved = try await resolvedPath(sftp: sftp, path: path)
        let components = try await sftp.listDirectory(atPath: resolved)
        let items = components
            .filter { $0.filename != "." && $0.filename != ".." }
            .map { c in SFTPRemoteItem(
                name: c.filename,
                path: joinedPath(directory: resolved, name: c.filename),
                kind: itemKind(from: c.attributes),
                size: Int64(c.attributes.size ?? 0),
                modifiedAt: formattedDate(c.attributes.modifyDate),
                permissions: permissionsString(from: c.attributes.permissions)
            )}
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        return SFTPDirectoryListing(path: resolved, items: items)
    }

    func upload(_ data: Data, named fileName: String, to directory: String, server: ServerProfile, via sshClient: SSHClientProtocol) async throws {
        let maxMB = maxUploadBytes / 1024 / 1024
        guard data.count <= maxUploadBytes else { throw SFTPFileTransferError.fileTooLarge(maxMB) }
        let safeFileName = sanitizedFileName(fileName)
        let remotePath = joinedPath(directory: directory.isEmpty ? "." : directory, name: safeFileName)

        let client = try await sshClient.makeCitadelClient(for: server)
        defer { Task { try? await client.close() } }
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }

        let file = try await sftp.openFile(filePath: remotePath, flags: [.write, .create, .truncate])
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        do {
            try await file.write(buffer, at: 0)
            try await file.close()
        } catch {
            try? await file.close()
            throw error
        }
    }

    func download(_ item: SFTPRemoteItem, server: ServerProfile, via sshClient: SSHClientProtocol) async throws -> Data {
        guard !item.isDirectory else { throw SFTPFileTransferError.notAFile }

        let client = try await sshClient.makeCitadelClient(for: server)
        defer { Task { try? await client.close() } }
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }

        let file = try await sftp.openFile(filePath: item.path, flags: .read)
        do {
            var buffer = try await file.readAll(from: 0)
            try await file.close()
            return Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
        } catch {
            try? await file.close()
            throw error
        }
    }

    func delete(_ item: SFTPRemoteItem, server: ServerProfile, via sshClient: SSHClientProtocol) async throws {
        let client = try await sshClient.makeCitadelClient(for: server)
        defer { Task { try? await client.close() } }
        let sftp = try await client.openSFTP()
        defer { Task { try? await sftp.close() } }

        if item.isDirectory {
            try await sftp.removeDirectory(atPath: item.path)
        } else {
            try await sftp.removeFile(atPath: item.path)
        }
    }

    func parentPath(of path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "/", trimmed != "." else { return "." }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let slashIndex = normalized.lastIndex(of: "/") else { return "." }
        if slashIndex == normalized.startIndex { return "/" }
        return String(normalized[..<slashIndex])
    }

    // MARK: - Private

    private func resolvedPath(sftp: SFTPClient, path: String) async throws -> String {
        let target = path.isEmpty || path == "." ? "." : path
        let components = try await sftp.realPath(atPath: target)
        return components.first?.filename ?? target
    }

    private func itemKind(from attributes: SFTPFileAttributes) -> SFTPRemoteItemKind {
        guard let perms = attributes.permissions else { return .other }
        switch perms.rawValue & 0xF000 {
        case 0o040000: return .directory
        case 0o120000: return .symlink
        case 0o100000: return .file
        default: return .other
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private func permissionsString(from permissions: SFTPFilePermissions?) -> String {
        guard let p = permissions else { return "----------" }
        let m = p.rawValue
        let t: Character
        switch m & 0xF000 {
        case 0o040000: t = "d"
        case 0o120000: t = "l"
        case 0o100000: t = "-"
        default: t = "?"
        }
        let bits: [(UInt32, Character)] = [
            (0o000400, "r"), (0o000200, "w"), (0o000100, "x"),
            (0o000040, "r"), (0o000020, "w"), (0o000010, "x"),
            (0o000004, "r"), (0o000002, "w"), (0o000001, "x"),
        ]
        return String([t] + bits.map { (bit, c) in (m & bit) != 0 ? c : "-" })
    }

    private func joinedPath(directory: String, name: String) -> String {
        guard directory != "/" else { return "/\(name)" }
        guard directory != "." else { return name }
        return directory.hasSuffix("/") ? "\(directory)\(name)" : "\(directory)/\(name)"
    }

    private func sanitizedFileName(_ fileName: String) -> String {
        let name = fileName.split(separator: "/").last.map(String.init) ?? "upload.bin"
        return name.isEmpty ? "upload.bin" : name
    }
}
