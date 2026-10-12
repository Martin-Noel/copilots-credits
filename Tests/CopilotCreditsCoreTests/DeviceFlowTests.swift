import Foundation
import Testing
import CopilotCreditsCore

@Suite("OAuth device flow — DeviceCode")
struct DeviceCodeTests {

    @Test("Decoding the spec example")
    func decodeSpecExample() throws {
        let code = try JSONDecoder().decode(DeviceCode.self, from: jsonData(Fixtures.deviceCode))
        #expect(code.deviceCode == "3584d83530557fdd1f46af8289938c8ef79f9dc5")
        #expect(code.userCode == "WDJB-MJHT")
        #expect(code.verificationUri == "https://github.com/login/device")
        #expect(code.expiresIn == 900)
        #expect(code.interval == 5)
    }

    @Test("Extra fields are ignored")
    func decodeIgnoresExtraFields() throws {
        let json = """
        {"device_code":"abc","user_code":"ABCD-EFGH","verification_uri":"https://github.com/login/device",
         "verification_uri_complete":"https://github.com/login/device?user_code=ABCD-EFGH",
         "expires_in":600,"interval":10}
        """
        let code = try JSONDecoder().decode(DeviceCode.self, from: jsonData(json))
        #expect(code.deviceCode == "abc")
        #expect(code.userCode == "ABCD-EFGH")
        #expect(code.expiresIn == 600)
        #expect(code.interval == 10)
    }

    @Test("Equatable: two identical decodings are equal")
    func decodeEquatable() throws {
        let a = try JSONDecoder().decode(DeviceCode.self, from: jsonData(Fixtures.deviceCode))
        let b = try JSONDecoder().decode(DeviceCode.self, from: jsonData(Fixtures.deviceCode))
        #expect(a == b)
    }

    @Test("Missing required field → decoding error")
    func decodeMissingFieldThrows() {
        let json = """
        {"user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
        """
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(DeviceCode.self, from: jsonData(json))
        }
    }

    @Test("Invalid JSON → decoding error")
    func decodeInvalidJSONThrows() {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(DeviceCode.self, from: jsonData("not json"))
        }
    }
}

@Suite("OAuth device flow — DeviceFlowResponse.interpret")
struct DeviceFlowResponseTests {

    private func interpret(_ json: String) throws -> DeviceFlowPollOutcome {
        return try DeviceFlowResponse.interpret(jsonData(json))
    }

    /// Asserts that `json` makes `interpret` throw `DeviceFlowError.unexpected(_)`, with any message.
    /// Returns the message if so.
    @discardableResult
    private func expectUnexpected(_ json: String) -> String? {
        do {
            let outcome = try interpret(json)
            Issue.record("Expected DeviceFlowError.unexpected, got outcome \(outcome)")
            return nil
        } catch let error as DeviceFlowError {
            if case .unexpected(let message) = error {
                return message
            }
            Issue.record("Expected DeviceFlowError.unexpected, got \(error)")
            return nil
        } catch {
            Issue.record("Expected DeviceFlowError.unexpected, got non-DeviceFlowError \(error)")
            return nil
        }
    }

    // MARK: - Token

    @Test("access_token present → .token (spec example)")
    func tokenSpecExample() throws {
        let outcome = try interpret(#"{"access_token":"ghu_abc","token_type":"bearer","scope":"read:user"}"#)
        #expect(outcome == DeviceFlowPollOutcome.token("ghu_abc"))
    }

    @Test("access_token alone → .token")
    func tokenOnly() throws {
        let outcome = try interpret(#"{"access_token":"gho_xyz"}"#)
        #expect(outcome == DeviceFlowPollOutcome.token("gho_xyz"))
    }

    @Test("access_token takes priority over an error field",
          arguments: ["authorization_pending", "slow_down", "expired_token", "access_denied", "weird"])
    func tokenWinsOverError(errorValue: String) throws {
        let json = #"{"access_token":"ghu_win","error":"\#(errorValue)","error_description":"ignored"}"#
        let outcome = try interpret(json)
        #expect(outcome == DeviceFlowPollOutcome.token("ghu_win"))
    }

    // MARK: - Pending / slow down

    @Test("error = authorization_pending → .pending")
    func pending() throws {
        let outcome = try interpret(#"{"error":"authorization_pending","error_description":"The authorization request is still pending.","error_uri":"https://docs.github.com"}"#)
        #expect(outcome == DeviceFlowPollOutcome.pending)
    }

    @Test("error = authorization_pending without description → .pending")
    func pendingWithoutDescription() throws {
        #expect(try interpret(#"{"error":"authorization_pending"}"#) == DeviceFlowPollOutcome.pending)
    }

    @Test("error = slow_down → .slowDown")
    func slowDown() throws {
        let outcome = try interpret(#"{"error":"slow_down","error_description":"Too many requests.","interval":10}"#)
        #expect(outcome == DeviceFlowPollOutcome.slowDown)
    }

    @Test("error = slow_down without description → .slowDown")
    func slowDownWithoutDescription() throws {
        #expect(try interpret(#"{"error":"slow_down"}"#) == DeviceFlowPollOutcome.slowDown)
    }

    // MARK: - Terminal errors

    @Test("error = expired_token → DeviceFlowError.expired")
    func expired() {
        #expect(throws: DeviceFlowError.expired) {
            _ = try DeviceFlowResponse.interpret(jsonData(#"{"error":"expired_token","error_description":"The device code has expired."}"#))
        }
        #expect(throws: DeviceFlowError.expired) {
            _ = try DeviceFlowResponse.interpret(jsonData(#"{"error":"expired_token"}"#))
        }
    }

    @Test("error = access_denied → DeviceFlowError.denied")
    func denied() {
        #expect(throws: DeviceFlowError.denied) {
            _ = try DeviceFlowResponse.interpret(jsonData(#"{"error":"access_denied","error_description":"The user has denied your application access."}"#))
        }
        #expect(throws: DeviceFlowError.denied) {
            _ = try DeviceFlowResponse.interpret(jsonData(#"{"error":"access_denied"}"#))
        }
    }

    @Test("Other error with error_description → .unexpected(description) (spec example)")
    func unexpectedWithDescription() {
        #expect(throws: DeviceFlowError.unexpected("The client_id is not valid.")) {
            _ = try DeviceFlowResponse.interpret(jsonData(#"{"error":"incorrect_client_credentials","error_description":"The client_id is not valid."}"#))
        }
    }

    @Test("Other error without error_description → .unexpected(error) (spec example)")
    func unexpectedWithoutDescription() {
        #expect(throws: DeviceFlowError.unexpected("weird")) {
            _ = try DeviceFlowResponse.interpret(jsonData(#"{"error":"weird"}"#))
        }
    }

    @Test("Other GitHub error codes → .unexpected(code) without description",
          arguments: ["unsupported_grant_type", "incorrect_device_code", "device_flow_disabled"])
    func otherErrorCodes(code: String) {
        #expect(throws: DeviceFlowError.unexpected(code)) {
            _ = try DeviceFlowResponse.interpret(jsonData(#"{"error":"\#(code)"}"#))
        }
    }

    @Test("Neither access_token nor error ({}) → DeviceFlowError.unexpected(_)")
    func emptyObjectIsUnexpected() {
        expectUnexpected("{}")
    }

    @Test("Neither access_token nor error (unknown fields) → DeviceFlowError.unexpected(_)")
    func unrelatedFieldsAreUnexpected() {
        expectUnexpected(#"{"token_type":"bearer","scope":"read:user"}"#)
    }

    // MARK: - Invalid JSON

    @Test("Invalid JSON → an error is thrown",
          arguments: ["", "not json", "{\"access_token\":", "<html>502 Bad Gateway</html>"])
    func invalidJSONThrows(json: String) {
        #expect(throws: (any Error).self) {
            _ = try DeviceFlowResponse.interpret(jsonData(json))
        }
    }
}
