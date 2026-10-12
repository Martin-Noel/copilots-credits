import Foundation

/// A usage snapshot, independent of the API format.
public struct UsageSnapshot: Equatable {
    public let date: Date
    public let plan: String
    public let used: Double
    public let entitlement: Double
    public let overage: Double
    public let overagePermitted: Bool
    public let unlimited: Bool
    public let resetDate: Date?

    public init(date: Date, plan: String, used: Double, entitlement: Double,
                overage: Double, overagePermitted: Bool, unlimited: Bool, resetDate: Date?) {
        self.date = date
        self.plan = plan
        self.used = used
        self.entitlement = entitlement
        self.overage = overage
        self.overagePermitted = overagePermitted
        self.unlimited = unlimited
        self.resetDate = resetDate
    }

    public var fractionUsed: Double {
        guard !unlimited, entitlement > 0 else { return 0 }
        return used / entitlement
    }

    public var remaining: Double { max(0, entitlement - used) }

    /// Cycle start: one calendar month (UTC) before the reset date.
    public var cycleStart: Date? {
        guard let resetDate else { return nil }
        return Calendar.utc.date(byAdding: .month, value: -1, to: resetDate)
    }

    /// Average pace since the start of the cycle (credits / day).
    public func dailyRate(now: Date = .now) -> Double? {
        guard let cycleStart else { return nil }
        let elapsedDays = now.timeIntervalSince(cycleStart) / 86_400
        guard elapsedDays >= 0.5 else { return nil } // too early to extrapolate
        return used / elapsedDays
    }

    /// Linear projection of usage at the reset date.
    public func projectedUsage(now: Date = .now) -> Double? {
        guard let rate = dailyRate(now: now), let cycleStart, let resetDate else { return nil }
        return rate * resetDate.timeIntervalSince(cycleStart) / 86_400
    }

    /// Credits per day that can still be used without exceeding the allocation.
    public func budgetPerDay(now: Date = .now) -> Double? {
        guard !unlimited, let resetDate else { return nil }
        let daysLeft = resetDate.timeIntervalSince(now) / 86_400
        guard daysLeft > 0 else { return nil }
        return remaining / daysLeft
    }
}

extension Calendar {
    static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}

extension Double {
    /// 4250 -> "4,250" (depending on the system locale)
    public var credits: String { formatted(.number.precision(.fractionLength(0))) }
}
