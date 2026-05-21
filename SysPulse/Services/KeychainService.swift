import Foundation
import LocalAuthentication
import Security

enum KeychainServiceError: LocalizedError {
    case encodingFailed
    case unexpectedData
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed: "Unable to encode secret."
        case .unexpectedData: "Unexpected keychain data."
        case .osStatus(let status): "Keychain error: \(status)"
        }
    }
}

final class KeychainService {
    static let shared = KeychainService()
    private let service = "com.yevheniipichkur.syspulse.credentials"

    private init() {}

    func saveSecret(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainServiceError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainServiceError.osStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainServiceError.osStatus(status)
        }
    }

    func readSecret(account: String, prompt: String? = nil) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        if let prompt {
            query[kSecUseOperationPrompt as String] = prompt
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainServiceError.osStatus(status)
        }
        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainServiceError.unexpectedData
        }
        return string
    }

    func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.osStatus(status)
        }
    }
}

enum BiometricUnlockResult: Hashable {
    case success
    case unavailable(String)
    case failed(String)
}

struct BiometricLockService {
    func unlock(reason: String = "Unlock saved server profiles") async -> BiometricUnlockResult {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return .unavailable(error?.localizedDescription ?? "Face ID or device passcode is not available.")
        }

        do {
            let didUnlock = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return didUnlock ? .success : .failed("Authentication failed.")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
