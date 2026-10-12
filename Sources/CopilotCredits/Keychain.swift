import CopilotCreditsCore
import Foundation
import Security

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound:
            return tr("Aucun token Copilot CLI trouvé dans le Trousseau.",
                      "No Copilot CLI token found in the Keychain.")
        case .status(let s):
            let msg = (SecCopyErrorMessageString(s, nil) as String?) ?? tr("erreur inconnue", "unknown error")
            return tr("Trousseau : \(msg) (\(s))", "Keychain: \(msg) (\(s))")
        }
    }
}

/// The token is never written to disk in clear: only to the macOS Keychain.
enum Keychain {
    static let service = "fr.martinnoel.copilot-credits"
    static let account = "github-oauth-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ token: String) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var attrs = baseQuery
        attrs[kSecValueData as String] = Data(token.utf8)
        attrs[kSecAttrLabel as String] = "Copilot Credits – GitHub token"
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func load() -> String? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Reads the OAuth token stored by the Copilot CLI (service "copilot-cli",
    /// account "https://github.com:<login>"). macOS will ask for permission.
    static func readCopilotCLIToken() throws -> String {
        // 1. List the accounts: attributes only, no prompt.
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "copilot-cli",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &out)
        guard listStatus == errSecSuccess, let items = out as? [[String: Any]] else {
            throw listStatus == errSecItemNotFound ? KeychainError.notFound : KeychainError.status(listStatus)
        }

        let accounts = items.compactMap { $0[kSecAttrAccount as String] as? String }
        guard let account = CopilotCLIAccount.select(from: accounts) else { throw KeychainError.notFound }

        // 2. Read that account's secret.
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "copilot-cli",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var data: CFTypeRef?
        let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &data)
        guard readStatus == errSecSuccess,
              let d = data as? Data,
              let token = String(data: d, encoding: .utf8) else {
            throw KeychainError.status(readStatus)
        }
        return token
    }
}
