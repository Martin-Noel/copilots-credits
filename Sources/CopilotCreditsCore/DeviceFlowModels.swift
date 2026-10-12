import Foundation

/// Response of POST https://github.com/login/device/code
public struct DeviceCode: Decodable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

public enum DeviceFlowPollOutcome: Equatable {
    case token(String)
    case pending
    case slowDown
}

public enum DeviceFlowError: Error, Equatable, LocalizedError {
    case expired
    case denied
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .expired: return "The code has expired. Please sign in again."
        case .denied: return "Authorization denied on GitHub (organization policy?)."
        case .unexpected(let msg): return "Could not connect to GitHub: \(msg)"
        }
    }
}

/// Interprets a response of POST https://github.com/login/oauth/access_token
/// while waiting for the code to be approved.
public enum DeviceFlowResponse {
    private struct Body: Decodable {
        let accessToken: String?
        let error: String?
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case error
            case errorDescription = "error_description"
        }
    }

    public static func interpret(_ data: Data) throws -> DeviceFlowPollOutcome {
        let body = try JSONDecoder().decode(Body.self, from: data)
        if let token = body.accessToken { return .token(token) }

        switch body.error {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "expired_token": throw DeviceFlowError.expired
        case "access_denied": throw DeviceFlowError.denied
        case let error?: throw DeviceFlowError.unexpected(body.errorDescription ?? error)
        case nil: throw DeviceFlowError.unexpected("response has neither token nor error")
        }
    }
}
