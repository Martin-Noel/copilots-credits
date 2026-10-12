import Foundation

public enum UsageParserError: Error, Equatable, LocalizedError {
    case noPremiumQuota

    public var errorDescription: String? {
        "Response has no premium_interactions block: unexpected format."
    }
}

/// Converts the JSON response of `copilot_internal/user` into a `UsageSnapshot`.
/// Kept separate from networking so it can be tested with fixtures.
public enum UsageParser {
    public static func parse(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        // AI credits are exposed under the legacy name "premium_interactions".
        guard let q = decoded.quotaSnapshots?["premium_interactions"] else {
            throw UsageParserError.noPremiumQuota
        }

        let entitlement = q.entitlement ?? 0
        let overage = q.overageCount ?? 0
        let used: Double
        if let rem = q.quotaRemaining ?? q.remaining {
            // quota_remaining keeps decimals, credits_used is rounded.
            used = max(0, entitlement - max(rem, 0)) + overage
        } else {
            used = q.creditsUsed ?? 0
        }

        return UsageSnapshot(
            date: fetchedAt,
            plan: decoded.copilotPlan ?? "copilot",
            used: used,
            entitlement: entitlement,
            overage: overage,
            overagePermitted: q.overagePermitted ?? false,
            unlimited: q.unlimited ?? false,
            resetDate: decoded.quotaResetDate.flatMap(parseResetDate)
        )
    }

    /// "2026-11-01" -> midnight UTC.
    /// Strict format: DateFormatter accepts "2026/11/01" even with isLenient = false.
    static func parseResetDate(_ s: String) -> Date? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.map(\.count) == [4, 2, 2],
              parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let comps = DateComponents(year: y, month: m, day: d)
        guard comps.isValidDate(in: Calendar.utc) else { return nil }
        return Calendar.utc.date(from: comps)
    }

    // MARK: - Raw format (all fields optional: the endpoint is undocumented)

    private struct Response: Decodable {
        let copilotPlan: String?
        let quotaResetDate: String?
        let quotaSnapshots: [String: Quota]?

        enum CodingKeys: String, CodingKey {
            case copilotPlan = "copilot_plan"
            case quotaResetDate = "quota_reset_date"
            case quotaSnapshots = "quota_snapshots"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            copilotPlan = try? c.decodeIfPresent(String.self, forKey: .copilotPlan)
            // A date of the wrong type must not fail the whole snapshot.
            quotaResetDate = try? c.decodeIfPresent(String.self, forKey: .quotaResetDate)
            quotaSnapshots = try c.decodeIfPresent([String: Quota].self, forKey: .quotaSnapshots)
        }
    }

    private struct Quota: Decodable {
        let entitlement: Double?
        let quotaRemaining: Double?
        let remaining: Double?
        let creditsUsed: Double?
        let overageCount: Double?
        let overagePermitted: Bool?
        let unlimited: Bool?

        enum CodingKeys: String, CodingKey {
            case entitlement
            case quotaRemaining = "quota_remaining"
            case remaining
            case creditsUsed = "credits_used"
            case overageCount = "overage_count"
            case overagePermitted = "overage_permitted"
            case unlimited
        }
    }
}
