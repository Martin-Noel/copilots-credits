import Foundation
import Testing
import CopilotCreditsCore

// MARK: - Floating point

/// Compare two doubles with an absolute tolerance.
func approx(_ a: Double, _ b: Double, tol: Double = 1e-6) -> Bool {
    return abs(a - b) <= tol
}

// MARK: - Dates (always UTC, never the machine time zone)

enum TestDates {
    static let utcTimeZone: TimeZone = TimeZone(identifier: "UTC")!

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utcTimeZone
        return calendar
    }

    /// Builds a UTC date from components.
    static func utc(_ year: Int, _ month: Int, _ day: Int,
                    _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = utcCalendar
        components.timeZone = utcTimeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let date = utcCalendar.date(from: components) else {
            preconditionFailure("Invalid test date \(year)-\(month)-\(day)")
        }
        return date
    }

    /// A fixed "fetchedAt" used by parser tests.
    static let fetchedAt: Date = Date(timeIntervalSince1970: 1_791_558_000) // arbitrary fixed instant

    static let day: TimeInterval = 86_400
}

// MARK: - Snapshot factory

func makeSnapshot(date: Date = TestDates.utc(2026, 10, 9, 12),
                  plan: String = "business",
                  used: Double = 0,
                  entitlement: Double = 7000,
                  overage: Double = 0,
                  overagePermitted: Bool = false,
                  unlimited: Bool = false,
                  resetDate: Date? = TestDates.utc(2026, 11, 1)) -> UsageSnapshot {
    return UsageSnapshot(date: date,
                         plan: plan,
                         used: used,
                         entitlement: entitlement,
                         overage: overage,
                         overagePermitted: overagePermitted,
                         unlimited: unlimited,
                         resetDate: resetDate)
}

// MARK: - Temporary directory for HistoryStore

struct TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopilotCreditsCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func path(_ components: String...) -> String {
        var result = url
        for component in components {
            result = result.appendingPathComponent(component)
        }
        return result.path
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - JSON fixtures

enum Fixtures {
    /// Example response from the spec (Copilot Business seat structure, fictitious values), verbatim.
    static let sampleResponse: String = """
    {
      "copilot_plan": "business",
      "quota_reset_date": "2026-11-01",
      "quota_snapshots": {
        "chat": {
          "overage_count": 0, "overage_permitted": false, "percent_remaining": 100.0,
          "quota_id": "chat", "quota_remaining": 0.0, "unlimited": true,
          "timestamp_utc": "2026-10-15T12:00:00.000Z", "has_quota": true, "quota_reset_at": 0,
          "token_based_billing": true, "credits_used": 0, "overage_entitlement": 0,
          "remaining": 0, "entitlement": 0
        },
        "completions": {
          "overage_count": 0, "overage_permitted": false, "percent_remaining": 100.0,
          "quota_id": "completions", "quota_remaining": 0.0, "unlimited": true,
          "timestamp_utc": "2026-10-15T12:00:00.000Z", "has_quota": true, "quota_reset_at": 0,
          "token_based_billing": true, "credits_used": 0, "overage_entitlement": 0,
          "remaining": 0, "entitlement": 0
        },
        "premium_interactions": {
          "overage_count": 0, "overage_permitted": true, "percent_remaining": 39.25,
          "quota_id": "premium_interactions", "quota_remaining": 392.5, "unlimited": false,
          "timestamp_utc": "2026-10-15T12:00:00.000Z", "has_quota": true, "quota_reset_at": 0,
          "token_based_billing": true, "credits_used": 608, "overage_entitlement": 0,
          "remaining": 392, "entitlement": 1000
        }
      }
    }
    """

    /// Builds a minimal response with only a `premium_interactions` block.
    /// - Parameters:
    ///   - premium: the inner fields of `premium_interactions` (without braces).
    ///   - rootFields: extra root fields (without trailing comma), e.g. `"copilot_plan": "pro"`.
    static func response(premium: String, rootFields: String = "") -> String {
        let prefix: String = rootFields.isEmpty ? "" : rootFields + ","
        return "{ \(prefix) \"quota_snapshots\": { \"premium_interactions\": { \(premium) } } }"
    }

    /// Real device code example from the spec.
    static let deviceCode: String = """
    {"device_code":"3584d83530557fdd1f46af8289938c8ef79f9dc5","user_code":"WDJB-MJHT",
     "verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
    """
}

func jsonData(_ json: String) -> Data {
    return Data(json.utf8)
}
