import CopilotCreditsCore
import Foundation

/// GitHub OAuth "device flow" (networking part): the app shows a code, the user
/// approves it on github.com/login/device, and the app gets its own token.
/// Response interpretation lives in CopilotCreditsCore.DeviceFlowResponse.
enum DeviceFlow {
    /// Public client ID of the GitHub Copilot OAuth app (the official plugins' one).
    /// Required: copilot_internal only accepts tokens issued for this app.
    static let clientID = "Iv1.b507a08c87ecfe98"

    static func start() async throws -> DeviceCode {
        let data = try await post("https://github.com/login/device/code",
                                  ["client_id": clientID, "scope": "read:user"])
        return try JSONDecoder().decode(DeviceCode.self, from: data)
    }

    /// Polls GitHub until the code is approved. Cancellable via the parent Task.
    static func waitForToken(_ code: DeviceCode) async throws -> String {
        var interval = max(code.interval, 5)
        let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let data = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            switch try DeviceFlowResponse.interpret(data) {
            case .token(let token): return token
            case .pending: continue
            case .slowDown: interval += 5 // GitHub asks us to slow down
            }
        }
        throw DeviceFlowError.expired
    }

    private static func post(_ url: String, _ params: [String: String]) async throws -> Data {
        var req = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await CopilotAPI.session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw DeviceFlowError.unexpected("HTTP \(status)") }
        return data
    }
}
