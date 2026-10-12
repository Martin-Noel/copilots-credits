import Foundation

/// The Copilot CLI stores several entries under the "copilot-cli" Keychain service.
/// The one holding the GitHub OAuth token is named exactly "https://github.com:<login>".
public enum CopilotCLIAccount {
    static let prefix = "https://github.com:"

    public static func select(from accounts: [String]) -> String? {
        accounts.first { account in
            guard account.hasPrefix(prefix) else { return false }
            let login = account.dropFirst(prefix.count)
            return !login.isEmpty && !login.contains(":")
        }
    }
}
