import Foundation
import Testing
import CopilotCreditsCore

@Suite("CopilotCLIAccount — Keychain account selection")
struct CopilotCLIAccountTests {

    @Test("Spec example: the https://github.com:<login> account is selected")
    func specExample() {
        let accounts: [String] = [
            "https://github.com:mona-lisa_OCTO",
            "https://github.com:mona-lisa_OCTO:github",
            "Bearer",
        ]
        #expect(CopilotCLIAccount.select(from: accounts) == "https://github.com:mona-lisa_OCTO")
    }

    @Test("Spec example in another order: same result")
    func specExampleOtherOrder() {
        let accounts: [String] = [
            "Bearer",
            "https://github.com:mona-lisa_OCTO:github",
            "https://github.com:mona-lisa_OCTO",
        ]
        #expect(CopilotCLIAccount.select(from: accounts) == "https://github.com:mona-lisa_OCTO")
    }

    @Test("All permutations of the spec example give the same result")
    func allPermutations() {
        let a = "https://github.com:mona-lisa_OCTO"
        let b = "https://github.com:mona-lisa_OCTO:github"
        let c = "Bearer"
        let permutations: [[String]] = [
            [a, b, c], [a, c, b], [b, a, c], [b, c, a], [c, a, b], [c, b, a],
        ]
        for accounts in permutations {
            #expect(CopilotCLIAccount.select(from: accounts) == a, "\(accounts)")
        }
    }

    @Test("Several valid accounts: the first one is returned")
    func firstValidWins() {
        let accounts: [String] = [
            "Bearer",
            "https://github.com:alice",
            "https://github.com:bob",
        ]
        #expect(CopilotCLIAccount.select(from: accounts) == "https://github.com:alice")
        #expect(CopilotCLIAccount.select(from: Array(accounts.reversed())) == "https://github.com:bob")
    }

    @Test("Single valid account")
    func singleValid() {
        #expect(CopilotCLIAccount.select(from: ["https://github.com:octocat"]) == "https://github.com:octocat")
    }

    @Test("Logins with dashes, underscores, digits are accepted",
          arguments: ["https://github.com:a", "https://github.com:user-123", "https://github.com:Some_User_99"])
    func validLogins(account: String) {
        #expect(CopilotCLIAccount.select(from: [account]) == account)
    }

    @Test("Rejected accounts (spec examples and variants)",
          arguments: [
            "https://github.com:",              // empty login
            "https://github.com:a:b",           // login contains ':'
            "https://ghe.example.com:alice",    // other host
            "github.com:alice",                 // no scheme
            "Bearer",
            "",
            "http://github.com:alice",          // not https
            "https://github.com:alice:github",  // suffix with ':'
          ])
    func rejected(account: String) {
        #expect(CopilotCLIAccount.select(from: [account]) == nil)
    }

    @Test("Only rejected accounts → nil")
    func allRejected() {
        let accounts: [String] = [
            "https://github.com:",
            "https://github.com:a:b",
            "https://ghe.example.com:alice",
            "github.com:alice",
            "Bearer",
        ]
        #expect(CopilotCLIAccount.select(from: accounts) == nil)
    }

    @Test("Rejected accounts before a valid one: the valid one is returned")
    func rejectedThenValid() {
        let accounts: [String] = [
            "https://github.com:",
            "https://github.com:a:b",
            "https://ghe.example.com:alice",
            "github.com:alice",
            "Bearer",
            "https://github.com:carol",
        ]
        #expect(CopilotCLIAccount.select(from: accounts) == "https://github.com:carol")
    }

    @Test("Empty list → nil")
    func emptyList() {
        #expect(CopilotCLIAccount.select(from: []) == nil)
    }
}
