import Foundation
import Testing
import CopilotCreditsCore

@Suite("UsageParser — parsing copilot_internal/user")
struct UsageParserTests {

    private func parse(_ json: String, fetchedAt: Date = TestDates.fetchedAt) throws -> UsageSnapshot {
        return try UsageParser.parse(jsonData(json), fetchedAt: fetchedAt)
    }

    // MARK: - Spec example

    @Test("Spec example (Business): all expected fields")
    func specExample() throws {
        let snapshot = try parse(Fixtures.sampleResponse)
        #expect(snapshot.plan == "business")
        #expect(approx(snapshot.entitlement, 1000))
        #expect(approx(snapshot.used, 607.5))
        #expect(approx(snapshot.overage, 0))
        #expect(snapshot.overagePermitted == true)
        #expect(snapshot.unlimited == false)
        #expect(snapshot.resetDate == TestDates.utc(2026, 11, 1))
        #expect(snapshot.date == TestDates.fetchedAt)
    }

    @Test("date always equals fetchedAt")
    func dateIsFetchedAt() throws {
        let other = Date(timeIntervalSince1970: 1_234_567_890.5)
        let snapshot = try parse(Fixtures.sampleResponse, fetchedAt: other)
        #expect(snapshot.date == other)
    }

    // MARK: - Only premium_interactions is read

    @Test("The chat and completions blocks are ignored")
    func chatAndCompletionsIgnored() throws {
        let json = """
        {
          "copilot_plan": "pro",
          "quota_snapshots": {
            "chat": { "entitlement": 99999, "quota_remaining": 1, "overage_count": 50,
                      "overage_permitted": false, "unlimited": true, "credits_used": 88888 },
            "completions": { "entitlement": 55555, "quota_remaining": 2, "overage_count": 60,
                             "overage_permitted": false, "unlimited": true, "credits_used": 77777 },
            "premium_interactions": { "entitlement": 300, "quota_remaining": 200,
                                      "overage_count": 0, "overage_permitted": true, "unlimited": false }
          }
        }
        """
        let snapshot = try parse(json)
        #expect(approx(snapshot.entitlement, 300))
        #expect(approx(snapshot.used, 100))
        #expect(approx(snapshot.overage, 0))
        #expect(snapshot.overagePermitted == true)
        #expect(snapshot.unlimited == false)
    }

    @Test("The premium_interactions block alone is enough (no chat or completions)")
    func premiumOnlyIsEnough() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300, \"quota_remaining\": 50"))
        #expect(approx(snapshot.entitlement, 300))
        #expect(approx(snapshot.used, 250))
    }

    // MARK: - Defaults

    @Test("Empty premium_interactions block: all default values")
    func emptyPremiumBlockDefaults() throws {
        let snapshot = try parse(Fixtures.response(premium: ""))
        #expect(approx(snapshot.entitlement, 0))
        #expect(approx(snapshot.overage, 0))
        #expect(snapshot.overagePermitted == false)
        #expect(snapshot.unlimited == false)
        #expect(approx(snapshot.used, 0))
        #expect(snapshot.plan == "copilot")
        #expect(snapshot.resetDate == nil)
        #expect(snapshot.date == TestDates.fetchedAt)
    }

    @Test("copilot_plan missing → \"copilot\"")
    func missingPlanDefaultsToCopilot() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300, \"quota_remaining\": 300"))
        #expect(snapshot.plan == "copilot")
    }

    @Test("copilot_plan present is used as is")
    func planIsRead() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300",
                                                   rootFields: "\"copilot_plan\": \"individual_pro\""))
        #expect(snapshot.plan == "individual_pro")
    }

    @Test("entitlement missing → 0")
    func missingEntitlement() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"credits_used\": 12, \"unlimited\": false"))
        #expect(approx(snapshot.entitlement, 0))
    }

    @Test("overage_count missing → 0")
    func missingOverage() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300, \"quota_remaining\": 100"))
        #expect(approx(snapshot.overage, 0))
        #expect(approx(snapshot.used, 200))
    }

    @Test("overage_permitted missing → false, present → read")
    func overagePermitted() throws {
        let absent = try parse(Fixtures.response(premium: "\"entitlement\": 300"))
        #expect(absent.overagePermitted == false)
        let presentTrue = try parse(Fixtures.response(premium: "\"entitlement\": 300, \"overage_permitted\": true"))
        #expect(presentTrue.overagePermitted == true)
        let presentFalse = try parse(Fixtures.response(premium: "\"entitlement\": 300, \"overage_permitted\": false"))
        #expect(presentFalse.overagePermitted == false)
    }

    @Test("unlimited missing → false, present → read")
    func unlimited() throws {
        let absent = try parse(Fixtures.response(premium: "\"entitlement\": 300"))
        #expect(absent.unlimited == false)
        let presentTrue = try parse(Fixtures.response(premium: "\"entitlement\": 0, \"unlimited\": true"))
        #expect(presentTrue.unlimited == true)
    }

    @Test("overage_count is read")
    func overageIsRead() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300, \"quota_remaining\": 0, \"overage_count\": 25"))
        #expect(approx(snapshot.overage, 25))
    }

    // MARK: - used computation priority

    @Test("Priority 1: quota_remaining wins over remaining and credits_used")
    func quotaRemainingHasPriority() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 1000, "quota_remaining": 300.5, "remaining": 100, "credits_used": 50
            """))
        #expect(approx(snapshot.used, 699.5))
    }

    @Test("Priority 2: remaining used if quota_remaining is missing (wins over credits_used)")
    func remainingUsedWhenNoQuotaRemaining() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 1000, "remaining": 400, "credits_used": 10
            """))
        #expect(approx(snapshot.used, 600))
    }

    @Test("Priority 3: credits_used if neither quota_remaining nor remaining")
    func creditsUsedFallback() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 1000, "credits_used": 123
            """))
        #expect(approx(snapshot.used, 123))
    }

    @Test("Priority 3: decimal credits_used is kept")
    func creditsUsedDecimalFallback() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 1000, \"credits_used\": 42.25"))
        #expect(approx(snapshot.used, 42.25))
    }

    @Test("None of quota_remaining / remaining / credits_used → used = 0")
    func nothingMeansZero() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 1000"))
        #expect(approx(snapshot.used, 0))
    }

    @Test("Negative quota_remaining treated as 0")
    func negativeQuotaRemaining() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 1000, \"quota_remaining\": -50"))
        #expect(approx(snapshot.used, 1000))
    }

    @Test("Negative quota_remaining + overage: used = entitlement + overage")
    func negativeQuotaRemainingWithOverage() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 1000, "quota_remaining": -12.5, "overage_count": 30
            """))
        #expect(approx(snapshot.used, 1030))
    }

    @Test("Overage is added to used (quota_remaining branch)")
    func overageAddedWithQuotaRemaining() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 300, "quota_remaining": 0, "overage_count": 25, "overage_permitted": true
            """))
        #expect(approx(snapshot.used, 325))
        #expect(approx(snapshot.overage, 25))
    }

    @Test("Overage is added to used (remaining branch)")
    func overageAddedWithRemaining() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 300, "remaining": 0, "overage_count": 5
            """))
        #expect(approx(snapshot.used, 305))
    }

    @Test("quota_remaining > entitlement: consumed part is clamped to 0")
    func quotaRemainingAboveEntitlement() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 100, "quota_remaining": 150
            """))
        #expect(approx(snapshot.used, 0))
    }

    @Test("quota_remaining > entitlement with overage: used = overage")
    func quotaRemainingAboveEntitlementWithOverage() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 100, "quota_remaining": 150, "overage_count": 7
            """))
        #expect(approx(snapshot.used, 7))
    }

    @Test("Negative remaining: max(remaining, 0) formula also applied")
    func negativeRemaining() throws {
        let snapshot = try parse(Fixtures.response(premium: """
            "entitlement": 500, "remaining": -20
            """))
        #expect(approx(snapshot.used, 500))
    }

    // MARK: - Numbers: int or decimal, unknown fields

    @Test("Integer or decimal numeric values are accepted")
    func intOrDecimalNumbers() throws {
        let intOnly = try parse(Fixtures.response(premium: "\"entitlement\": 1000, \"quota_remaining\": 392, \"overage_count\": 1"))
        #expect(approx(intOnly.entitlement, 1000))
        #expect(approx(intOnly.used, 609))
        #expect(approx(intOnly.overage, 1))

        let decimals = try parse(Fixtures.response(premium: "\"entitlement\": 1000.0, \"quota_remaining\": 392.75, \"overage_count\": 2.0"))
        #expect(approx(decimals.entitlement, 1000))
        #expect(approx(decimals.used, 609.25))
        #expect(approx(decimals.overage, 2))
    }

    @Test("Unknown fields ignored (root and premium block)")
    func unknownFieldsIgnored() throws {
        let json = """
        {
          "copilot_plan": "business",
          "some_new_root_field": {"nested": [1, 2, 3]},
          "analytics_tracking_id": "abc",
          "quota_snapshots": {
            "premium_interactions": {
              "entitlement": 300, "quota_remaining": 100,
              "brand_new_field": "x", "another": [true, false], "obj": {"a": 1}
            },
            "future_quota": { "entitlement": 1 }
          }
        }
        """
        let snapshot = try parse(json)
        #expect(snapshot.plan == "business")
        #expect(approx(snapshot.entitlement, 300))
        #expect(approx(snapshot.used, 200))
    }

    // MARK: - Reset date

    @Test("quota_reset_date interpreted as midnight UTC")
    func resetDateIsMidnightUTC() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300",
                                                   rootFields: "\"quota_reset_date\": \"2026-03-31\""))
        let reset = try #require(snapshot.resetDate)
        #expect(reset == TestDates.utc(2026, 3, 31))
        let comps = TestDates.utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reset)
        #expect(comps.year == 2026)
        #expect(comps.month == 3)
        #expect(comps.day == 31)
        #expect(comps.hour == 0)
        #expect(comps.minute == 0)
        #expect(comps.second == 0)
    }

    @Test("quota_reset_date missing → nil, no error")
    func missingResetDate() throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300"))
        #expect(snapshot.resetDate == nil)
    }

    @Test("Malformed quota_reset_date → nil, no error",
          arguments: ["", "not a date", "2026/11/01", "01-11-2026", "November 1, 2026"])
    func malformedResetDate(value: String) throws {
        let snapshot = try parse(Fixtures.response(premium: "\"entitlement\": 300, \"quota_remaining\": 100",
                                                   rootFields: "\"quota_reset_date\": \"\(value)\""))
        #expect(snapshot.resetDate == nil)
        // The rest of the parsing is unaffected.
        #expect(approx(snapshot.used, 200))
    }

    // MARK: - Errors

    @Test("quota_snapshots missing → UsageParserError.noPremiumQuota")
    func missingQuotaSnapshots() {
        let json = """
        { "copilot_plan": "business", "quota_reset_date": "2026-11-01" }
        """
        #expect(throws: UsageParserError.noPremiumQuota) {
            _ = try UsageParser.parse(jsonData(json), fetchedAt: TestDates.fetchedAt)
        }
    }

    @Test("Empty quota_snapshots → UsageParserError.noPremiumQuota")
    func emptyQuotaSnapshots() {
        let json = """
        { "copilot_plan": "business", "quota_snapshots": {} }
        """
        #expect(throws: UsageParserError.noPremiumQuota) {
            _ = try UsageParser.parse(jsonData(json), fetchedAt: TestDates.fetchedAt)
        }
    }

    @Test("premium_interactions missing (chat/completions present) → UsageParserError.noPremiumQuota")
    func missingPremiumInteractions() {
        let json = """
        {
          "copilot_plan": "business",
          "quota_snapshots": {
            "chat": { "entitlement": 0, "unlimited": true, "quota_remaining": 0 },
            "completions": { "entitlement": 0, "unlimited": true, "quota_remaining": 0 }
          }
        }
        """
        #expect(throws: UsageParserError.noPremiumQuota) {
            _ = try UsageParser.parse(jsonData(json), fetchedAt: TestDates.fetchedAt)
        }
    }

    @Test("Empty root object → UsageParserError.noPremiumQuota")
    func emptyRootObject() {
        #expect(throws: UsageParserError.noPremiumQuota) {
            _ = try UsageParser.parse(jsonData("{}"), fetchedAt: TestDates.fetchedAt)
        }
    }

    @Test("Invalid JSON or non-object root → an error is thrown",
          arguments: ["", "not json", "{\"copilot_plan\": ", "[1, 2, 3]", "[]", "42", "\"hello\"", "null"])
    func invalidJSONThrows(json: String) {
        #expect(throws: (any Error).self) {
            _ = try UsageParser.parse(jsonData(json), fetchedAt: TestDates.fetchedAt)
        }
    }
}
