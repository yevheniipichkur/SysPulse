import Foundation

enum JumpHostDirectoryListingParser {
    static func parse(output: String, basePath: String) -> [SFTPRemoteItem] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        var items: [SFTPRemoteItem] = []
        for lineSub in lines {
            let line = String(lineSub)
            guard line.hasPrefix("d") || line.hasPrefix("-") || line.hasPrefix("l") else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 8 else { continue }
            let permissions = String(parts[0])
            let size = Int64(parts[4]) ?? 0
            let datePart = parts[5...6].joined(separator: " ")
            let name = parts.dropFirst(7).joined(separator: " ")
            guard name != "." && name != ".." else { continue }
            let isDirectory = permissions.hasPrefix("d")
            let kind: SFTPRemoteItemKind = isDirectory ? .directory : (permissions.hasPrefix("l") ? .symlink : .file)
            let path = joinedPath(directory: basePath, name: name)
            items.append(
                SFTPRemoteItem(
                    name: name,
                    path: path,
                    kind: kind,
                    size: size,
                    modifiedAt: datePart,
                    permissions: permissions
                )
            )
        }
        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func joinedPath(directory: String, name: String) -> String {
        guard directory != "/" else { return "/\(name)" }
        guard directory != "." else { return name }
        return directory.hasSuffix("/") ? "\(directory)\(name)" : "\(directory)/\(name)"
    }
}
