import Foundation

enum DebugGateConfiguration {
    /// Raw text file in the public GitHub repo. Delete the file or empty it to disable the debug menu.
    static let passwordDocumentURL = URL(
        string: "https://raw.githubusercontent.com/yevheniipichkur/SysPulse/main/debug-gate.txt"
    )!
    static let unlockSessionDuration: TimeInterval = 24 * 60 * 60
}

enum DebugGatePasswordError: LocalizedError {
    case gateDisabled
    case fetchFailed(String)
    case wrongPassword

    var errorDescription: String? {
        switch self {
        case .gateDisabled:
            L10n.string("Debug menu is disabled. Add a password to debug-gate.txt in the SysPulse GitHub repo.")
        case .fetchFailed(let details):
            L10n.string("Could not load debug password: %@", details)
        case .wrongPassword:
            L10n.string("Incorrect debug password.")
        }
    }
}

struct DebugGatePasswordService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func verify(password: String) async throws {
        let expected = try await fetchExpectedPassword()
        let entered = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else { throw DebugGatePasswordError.wrongPassword }
        guard entered == expected else { throw DebugGatePasswordError.wrongPassword }
    }

    func fetchExpectedPassword() async throws -> String {
        var request = URLRequest(url: DebugGateConfiguration.passwordDocumentURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DebugGatePasswordError.fetchFailed("Invalid response")
        }
        if http.statusCode == 404 {
            throw DebugGatePasswordError.gateDisabled
        }
        guard (200...299).contains(http.statusCode) else {
            throw DebugGatePasswordError.fetchFailed("HTTP \(http.statusCode)")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw DebugGatePasswordError.fetchFailed("Invalid encoding")
        }

        let password = parsePassword(from: text)
        guard !password.isEmpty else {
            throw DebugGatePasswordError.gateDisabled
        }
        return password
    }

    private func parsePassword(from text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            return trimmed
        }
        return ""
    }
}
