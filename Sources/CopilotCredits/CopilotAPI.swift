import CopilotCreditsCore
import Foundation

enum CopilotAPIError: LocalizedError {
    case unauthorized
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return tr("Token refusé par GitHub (401/403). Reconnectez-vous.",
                                          "Token rejected by GitHub (401/403). Please sign in again.")
        case .http(let code): return tr("GitHub a répondu HTTP \(code).", "GitHub responded with HTTP \(code).")
        }
    }
}

/// Networking only; JSON interpretation lives in CopilotCreditsCore.UsageParser.
enum CopilotAPI {
    /// Internal endpoint used by the Copilot extensions (VS Code, JetBrains…).
    /// Undocumented: it may change without notice.
    static let usageURL = URL(string: "https://api.github.com/copilot_internal/user")!

    /// Some Copilot endpoints filter on User-Agent; we identify as the extension.
    static let userAgent = "GitHubCopilotChat/0.26.7"

    /// Session with no disk cache or cookies: URLSession.shared stored responses
    /// (including the one carrying the OAuth token) in clear under ~/Library/Caches.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    static func fetchUsage(token: String) async throws -> UsageSnapshot {
        var req = URLRequest(url: usageURL, timeoutInterval: 15)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        switch status {
        case 200..<300: return try UsageParser.parse(data, fetchedAt: .now)
        case 401, 403: throw CopilotAPIError.unauthorized
        default: throw CopilotAPIError.http(status)
        }
    }

    /// Account name, for display. Non-blocking if it fails.
    static func fetchLogin(token: String) async -> String? {
        struct User: Decodable { let login: String }
        var req = URLRequest(url: URL(string: "https://api.github.com/user")!, timeoutInterval: 15)
        req.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let result = try? await session.data(for: req),
              let user = try? JSONDecoder().decode(User.self, from: result.0) else { return nil }
        return user.login
    }
}
