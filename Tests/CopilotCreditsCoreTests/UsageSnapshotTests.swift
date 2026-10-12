import Foundation
import Testing
import CopilotCreditsCore

struct CycleStartCase: Sendable, CustomTestStringConvertible {
    let reset: Date
    let expectedStart: Date
    let label: String
    var testDescription: String { label }
}

@Suite("UsageSnapshot — computed values")
struct UsageSnapshotTests {

    // MARK: - Init / Equatable

    @Test("The memberwise initializer keeps all fields")
    func memberwiseInit() {
        let date = TestDates.utc(2026, 10, 9, 14, 37, 2)
        let reset = TestDates.utc(2026, 11, 1)
        let snapshot = UsageSnapshot(date: date, plan: "pro", used: 12.5, entitlement: 300,
                                     overage: 3, overagePermitted: true, unlimited: false, resetDate: reset)
        #expect(snapshot.date == date)
        #expect(snapshot.plan == "pro")
        #expect(approx(snapshot.used, 12.5))
        #expect(approx(snapshot.entitlement, 300))
        #expect(approx(snapshot.overage, 3))
        #expect(snapshot.overagePermitted == true)
        #expect(snapshot.unlimited == false)
        #expect(snapshot.resetDate == reset)
    }

    @Test("Equatable: same fields → equal, different field → different")
    func equatable() {
        let a = makeSnapshot(used: 10)
        let b = makeSnapshot(used: 10)
        let c = makeSnapshot(used: 11)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - fractionUsed

    @Test("fractionUsed = used / entitlement")
    func fractionUsedBasic() {
        let snapshot = makeSnapshot(used: 607.5, entitlement: 1000)
        #expect(approx(snapshot.fractionUsed, 607.5 / 1000))
    }

    @Test("fractionUsed = 0 when used = 0")
    func fractionUsedZero() {
        #expect(approx(makeSnapshot(used: 0, entitlement: 300).fractionUsed, 0))
    }

    @Test("fractionUsed = 1 exactly at quota")
    func fractionUsedExactlyOne() {
        #expect(approx(makeSnapshot(used: 300, entitlement: 300).fractionUsed, 1.0))
    }

    @Test("fractionUsed may exceed 1")
    func fractionUsedAboveOne() {
        let snapshot = makeSnapshot(used: 8400, entitlement: 7000)
        #expect(approx(snapshot.fractionUsed, 1.2))
    }

    @Test("fractionUsed = 0 if unlimited")
    func fractionUsedUnlimited() {
        let snapshot = makeSnapshot(used: 500, entitlement: 300, unlimited: true)
        #expect(snapshot.fractionUsed == 0)
    }

    @Test("fractionUsed = 0 if entitlement ≤ 0", arguments: [0.0, -1.0, -300.0])
    func fractionUsedNonPositiveEntitlement(entitlement: Double) {
        let snapshot = makeSnapshot(used: 50, entitlement: entitlement)
        #expect(snapshot.fractionUsed == 0)
    }

    // MARK: - remaining

    @Test("remaining = entitlement − used")
    func remainingBasic() {
        #expect(approx(makeSnapshot(used: 4000, entitlement: 7000).remaining, 3000))
        #expect(approx(makeSnapshot(used: 607.5, entitlement: 1000).remaining, 392.5))
    }

    @Test("remaining clamped to 0 on overrun")
    func remainingClampedToZero() {
        #expect(makeSnapshot(used: 8000, entitlement: 7000).remaining == 0)
        #expect(makeSnapshot(used: 10, entitlement: 0).remaining == 0)
    }

    @Test("remaining = 0 exactly at quota")
    func remainingAtQuota() {
        #expect(approx(makeSnapshot(used: 300, entitlement: 300).remaining, 0))
    }

    // MARK: - cycleStart

    static let cycleStartCases: [CycleStartCase] = [
        CycleStartCase(reset: TestDates.utc(2026, 11, 1), expectedStart: TestDates.utc(2026, 10, 1),
                       label: "2026-11-01 → 2026-10-01 (spec example)"),
        CycleStartCase(reset: TestDates.utc(2026, 3, 31), expectedStart: TestDates.utc(2026, 2, 28),
                       label: "2026-03-31 → 2026-02-28 (end of month, spec example)"),
        CycleStartCase(reset: TestDates.utc(2028, 3, 31), expectedStart: TestDates.utc(2028, 2, 29),
                       label: "2028-03-31 → 2028-02-29 (end of month, leap year)"),
        CycleStartCase(reset: TestDates.utc(2026, 5, 31), expectedStart: TestDates.utc(2026, 4, 30),
                       label: "2026-05-31 → 2026-04-30 (30-day month)"),
        CycleStartCase(reset: TestDates.utc(2027, 1, 1), expectedStart: TestDates.utc(2026, 12, 1),
                       label: "2027-01-01 → 2026-12-01 (year change)"),
        CycleStartCase(reset: TestDates.utc(2026, 3, 1), expectedStart: TestDates.utc(2026, 2, 1),
                       label: "2026-03-01 → 2026-02-01"),
        CycleStartCase(reset: TestDates.utc(2026, 10, 15), expectedStart: TestDates.utc(2026, 9, 15),
                       label: "2026-10-15 → 2026-09-15 (mid-month)"),
    ]

    @Test("cycleStart = resetDate − 1 calendar month (UTC)", arguments: UsageSnapshotTests.cycleStartCases)
    func cycleStart(testCase: CycleStartCase) throws {
        let snapshot = makeSnapshot(resetDate: testCase.reset)
        let start = try #require(snapshot.cycleStart)
        #expect(start == testCase.expectedStart)
    }

    @Test("cycleStart nil if resetDate nil")
    func cycleStartNilWithoutReset() {
        #expect(makeSnapshot(resetDate: nil).cycleStart == nil)
    }

    // MARK: - dailyRate

    @Test("dailyRate: spec example (10 days elapsed, used 1000 → 100)")
    func dailyRateExample() throws {
        let snapshot = makeSnapshot(used: 1000, resetDate: TestDates.utc(2026, 11, 1))
        let rate = try #require(snapshot.dailyRate(now: TestDates.utc(2026, 10, 11)))
        #expect(approx(rate, 100))
    }

    @Test("dailyRate: fractional elapsed days")
    func dailyRateFractionalDays() throws {
        let snapshot = makeSnapshot(used: 250, resetDate: TestDates.utc(2026, 11, 1))
        // 2.5 days after 2026-10-01T00:00Z
        let now = TestDates.utc(2026, 10, 3, 12)
        let rate = try #require(snapshot.dailyRate(now: now))
        #expect(approx(rate, 100))
    }

    @Test("dailyRate nil if resetDate nil")
    func dailyRateNilWithoutReset() {
        let snapshot = makeSnapshot(used: 1000, resetDate: nil)
        #expect(snapshot.dailyRate(now: TestDates.utc(2026, 10, 11)) == nil)
    }

    @Test("dailyRate nil just below the 0.5-day threshold")
    func dailyRateJustBelowThreshold() {
        let snapshot = makeSnapshot(used: 100, resetDate: TestDates.utc(2026, 11, 1))
        let now = TestDates.utc(2026, 10, 1).addingTimeInterval(43_200 - 1)
        #expect(snapshot.dailyRate(now: now) == nil)
    }

    @Test("dailyRate nil at the very start of the cycle (0 days elapsed)")
    func dailyRateAtCycleStart() {
        let snapshot = makeSnapshot(used: 100, resetDate: TestDates.utc(2026, 11, 1))
        #expect(snapshot.dailyRate(now: TestDates.utc(2026, 10, 1)) == nil)
    }

    @Test("dailyRate defined at exactly 0.5 day (only \"< 0.5\" returns nil)")
    func dailyRateExactlyAtThreshold() throws {
        let snapshot = makeSnapshot(used: 100, resetDate: TestDates.utc(2026, 11, 1))
        let now = TestDates.utc(2026, 10, 1, 12)
        let rate = try #require(snapshot.dailyRate(now: now))
        #expect(approx(rate, 200))
    }

    @Test("dailyRate defined just above the 0.5-day threshold")
    func dailyRateJustAboveThreshold() throws {
        let snapshot = makeSnapshot(used: 100, resetDate: TestDates.utc(2026, 11, 1))
        let elapsed: TimeInterval = 43_200 + 1
        let now = TestDates.utc(2026, 10, 1).addingTimeInterval(elapsed)
        let rate = try #require(snapshot.dailyRate(now: now))
        #expect(approx(rate, 100 / (elapsed / 86_400)))
    }

    @Test("dailyRate nil if now is before the cycle start")
    func dailyRateBeforeCycleStart() {
        let snapshot = makeSnapshot(used: 100, resetDate: TestDates.utc(2026, 11, 1))
        #expect(snapshot.dailyRate(now: TestDates.utc(2026, 9, 20)) == nil)
    }

    @Test("dailyRate = 0 when used = 0 (past the threshold)")
    func dailyRateZeroUsage() throws {
        let snapshot = makeSnapshot(used: 0, resetDate: TestDates.utc(2026, 11, 1))
        let rate = try #require(snapshot.dailyRate(now: TestDates.utc(2026, 10, 5)))
        #expect(approx(rate, 0))
    }

    // MARK: - projectedUsage

    @Test("projectedUsage: spec example (31-day cycle, used 1000, 10 days elapsed → 3100)")
    func projectedUsageExample() throws {
        let snapshot = makeSnapshot(used: 1000, resetDate: TestDates.utc(2026, 11, 1))
        let projection = try #require(snapshot.projectedUsage(now: TestDates.utc(2026, 10, 11)))
        #expect(approx(projection, 3100))
    }

    @Test("projectedUsage: February cycle (28 days)")
    func projectedUsageFebruaryCycle() throws {
        // reset 2026-03-01 → cycleStart 2026-02-01 → 28-day cycle
        let snapshot = makeSnapshot(used: 280, resetDate: TestDates.utc(2026, 3, 1))
        // 14 days elapsed → 20/day → 560
        let projection = try #require(snapshot.projectedUsage(now: TestDates.utc(2026, 2, 15)))
        #expect(approx(projection, 560))
    }

    @Test("projectedUsage: end-of-month cycle (Mar 31 → Feb 28, 31 days)")
    func projectedUsageEndOfMonthCycle() throws {
        // reset 2026-03-31 → cycleStart 2026-02-28 → 31-day cycle
        let snapshot = makeSnapshot(used: 500, resetDate: TestDates.utc(2026, 3, 31))
        // 5 days elapsed → 100/day → 3100
        let projection = try #require(snapshot.projectedUsage(now: TestDates.utc(2026, 3, 5)))
        #expect(approx(projection, 3100))
    }

    @Test("projectedUsage nil if resetDate nil")
    func projectedUsageNilWithoutReset() {
        let snapshot = makeSnapshot(used: 1000, resetDate: nil)
        #expect(snapshot.projectedUsage(now: TestDates.utc(2026, 10, 11)) == nil)
    }

    @Test("projectedUsage nil if too early in the cycle (dailyRate nil)")
    func projectedUsageNilTooEarly() {
        let snapshot = makeSnapshot(used: 1000, resetDate: TestDates.utc(2026, 11, 1))
        let now = TestDates.utc(2026, 10, 1).addingTimeInterval(43_200 - 1)
        #expect(snapshot.projectedUsage(now: now) == nil)
    }

    @Test("projectedUsage consistent with dailyRate × cycle length")
    func projectedUsageConsistentWithDailyRate() throws {
        let snapshot = makeSnapshot(used: 1234.5, resetDate: TestDates.utc(2026, 11, 1))
        let now = TestDates.utc(2026, 10, 17, 6, 30)
        let rate = try #require(snapshot.dailyRate(now: now))
        let projection = try #require(snapshot.projectedUsage(now: now))
        #expect(approx(projection, rate * 31, tol: 1e-6))
    }

    // MARK: - budgetPerDay

    @Test("budgetPerDay: spec example (1000, used 400, 10 days left → 60)")
    func budgetPerDayExample() throws {
        let reset = TestDates.utc(2026, 11, 1)
        let snapshot = makeSnapshot(used: 400, entitlement: 1000, resetDate: reset)
        let now = reset.addingTimeInterval(-10 * TestDates.day)
        let budget = try #require(snapshot.budgetPerDay(now: now))
        #expect(approx(budget, 60))
    }

    @Test("budgetPerDay: fractional days left")
    func budgetPerDayFractionalDays() throws {
        let reset = TestDates.utc(2026, 11, 1)
        let snapshot = makeSnapshot(used: 6000, entitlement: 7000, resetDate: reset)
        let now = reset.addingTimeInterval(-2.5 * TestDates.day)
        let budget = try #require(snapshot.budgetPerDay(now: now))
        #expect(approx(budget, 400))
    }

    @Test("budgetPerDay = 0 if the quota is already exceeded")
    func budgetPerDayOverQuota() throws {
        let reset = TestDates.utc(2026, 11, 1)
        let snapshot = makeSnapshot(used: 8000, entitlement: 7000, resetDate: reset)
        let budget = try #require(snapshot.budgetPerDay(now: reset.addingTimeInterval(-5 * TestDates.day)))
        #expect(approx(budget, 0))
    }

    @Test("budgetPerDay nil if unlimited")
    func budgetPerDayNilUnlimited() {
        let reset = TestDates.utc(2026, 11, 1)
        let snapshot = makeSnapshot(used: 10, entitlement: 7000, unlimited: true, resetDate: reset)
        #expect(snapshot.budgetPerDay(now: reset.addingTimeInterval(-10 * TestDates.day)) == nil)
    }

    @Test("budgetPerDay nil if resetDate nil")
    func budgetPerDayNilWithoutReset() {
        let snapshot = makeSnapshot(used: 4000, entitlement: 7000, resetDate: nil)
        #expect(snapshot.budgetPerDay(now: TestDates.utc(2026, 10, 22)) == nil)
    }

    @Test("budgetPerDay nil if daysLeft = 0 (now == resetDate)")
    func budgetPerDayNilAtReset() {
        let reset = TestDates.utc(2026, 11, 1)
        let snapshot = makeSnapshot(used: 4000, entitlement: 7000, resetDate: reset)
        #expect(snapshot.budgetPerDay(now: reset) == nil)
    }

    @Test("budgetPerDay nil if now is after resetDate")
    func budgetPerDayNilAfterReset() {
        let reset = TestDates.utc(2026, 11, 1)
        let snapshot = makeSnapshot(used: 4000, entitlement: 7000, resetDate: reset)
        #expect(snapshot.budgetPerDay(now: reset.addingTimeInterval(3600)) == nil)
    }
}
