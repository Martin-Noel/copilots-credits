# Behavioral specification — `CopilotCreditsCore` module

Context: a macOS app tracks a user's GitHub Copilot "AI credits" consumption.
It queries `GET https://api.github.com/copilot_internal/user`, authenticates with the OAuth device flow,
keeps a local SQLite history and sends threshold alerts.

The `CopilotCreditsCore` module contains all the **pure** logic (no network, no UI). Its public
signatures live in `Sources/CopilotCreditsCore/`. This document describes what each element MUST do.

Conventions: a "day" = 86,400 seconds. Reset dates are in UTC.

---

## 1. `UsageParser.parse(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot`

Input: the JSON body of the `copilot_internal/user` response.

### Example (structure of a real response for a Copilot Business seat, fictitious values)
```json
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
```
Expected result for this example: `plan == "business"`, `entitlement == 1000`, `used ≈ 607.5`
(1000 − 392.5), `overage == 0`, `overagePermitted == true`, `unlimited == false`,
`resetDate == 2026-11-01T00:00:00Z`, `date == fetchedAt`.

### Rules
- AI credits are read **only** from `quota_snapshots.premium_interactions`.
  The `chat` and `completions` blocks are ignored.
- `entitlement` ← `entitlement` field (missing → 0).
- `overage` ← `overage_count` (missing → 0).
- `overagePermitted` ← `overage_permitted` (missing → false).
- `unlimited` ← `unlimited` (missing → false).
- `plan` ← root `copilot_plan` (missing → `"copilot"`).
- `date` ← `fetchedAt`.
- `resetDate` ← `quota_reset_date` in `yyyy-MM-dd` format, interpreted as **midnight UTC** on that day.
  Missing or malformed → `nil` (not an error).
- Computing `used` (credits consumed), in order of priority:
  1. if `quota_remaining` is present: `used = max(0, entitlement − max(quota_remaining, 0)) + overage`;
  2. otherwise if `remaining` is present: same formula with `remaining`;
  3. otherwise: `used = credits_used` (missing → 0).
  Reason: `quota_remaining` keeps decimals whereas `credits_used` is rounded.
- A negative `quota_remaining` is treated as 0.
- Unknown fields are ignored; numeric values may be integers or decimals in JSON.
- Missing `quota_snapshots`, or missing `premium_interactions` block → throws `UsageParserError.noPremiumQuota`.
- Invalid JSON (not JSON, or root is not an object) → throws an error (type not specified).

## 2. `UsageSnapshot` (computed values)

`UsageSnapshot` has a public memberwise initializer.

- `fractionUsed` = `used / entitlement`. Is **0** if `unlimited` is true or if `entitlement ≤ 0`.
  May exceed 1 (quota overrun).
- `remaining` = `max(0, entitlement − used)`.
- `cycleStart` = `resetDate` minus **one calendar month**, computed in the Gregorian calendar in UTC.
  `nil` if `resetDate` is `nil`.
  Example: reset `2026-11-01T00:00Z` → `2026-10-01T00:00Z`.
  End of month: reset `2026-03-31T00:00Z` → `2026-02-28T00:00Z` (day clamped to the last day of the month).
- `dailyRate(now:)` = `used / elapsedDays`, where `elapsedDays = (now − cycleStart) / 86400`.
  Returns `nil` if `cycleStart` is `nil` or if `elapsedDays < 0.5` (too early to extrapolate).
- `projectedUsage(now:)` = `dailyRate(now:) × cycleLengthInDays`, where
  `cycleLengthInDays = (resetDate − cycleStart) / 86400`. `nil` if `dailyRate(now:)` is `nil`.
  Example: cycle from Oct 1 to Nov 1 (31 days), `used = 1000`, `now` = Oct 11 00:00Z
  (10 days elapsed) → `dailyRate = 100`, `projectedUsage = 3100`.
- `budgetPerDay(now:)` = `remaining / daysLeft`, where `daysLeft = (resetDate − now) / 86400`.
  `nil` if `unlimited`, if `resetDate` is `nil`, or if `daysLeft ≤ 0`.
  Example: `entitlement 1000`, `used 400`, 10 days left → 60.

## 3. `AlertPolicy.thresholdToNotify(fraction:alreadyNotified:thresholds:) -> Double?`

Decides whether a threshold notification should be sent. `thresholds` defaults to
`AlertPolicy.defaultThresholds == [0.8, 1.0]`.

- Among the thresholds `t` such that `fraction >= t`, take the **largest**.
- Return it only if it is strictly greater than `alreadyNotified` (the highest threshold already
  notified during this cycle, 0 if none). Otherwise `nil`.
- No threshold reached → `nil`.
- Examples (default thresholds):
  | fraction | alreadyNotified | result |
  |---|---|---|
  | 0.5  | 0   | nil |
  | 0.8  | 0   | 0.8 (reaching the threshold exactly counts) |
  | 0.85 | 0   | 0.8 |
  | 0.85 | 0.8 | nil |
  | 1.2  | 0   | 1.0 (jumps straight to the highest) |
  | 1.0  | 0.8 | 1.0 |
  | 1.5  | 1.0 | nil |
- Works with a custom threshold list, not necessarily sorted.

## 4. OAuth device flow

### `DeviceCode` (decodable)
Decoded from the JSON response of `POST https://github.com/login/device/code`, e.g.:
```json
{"device_code":"3584d83530557fdd1f46af8289938c8ef79f9dc5","user_code":"WDJB-MJHT",
 "verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
```
→ `deviceCode`, `userCode`, `verificationUri`, `expiresIn` (Int), `interval` (Int).

### `DeviceFlowResponse.interpret(_ data: Data) throws -> DeviceFlowPollOutcome`
Interprets a JSON response from `POST https://github.com/login/oauth/access_token` while waiting:
- `access_token` present → `.token(value)` (takes priority over any `error` field);
  e.g. `{"access_token":"ghu_abc","token_type":"bearer","scope":"read:user"}` → `.token("ghu_abc")`;
- `"error":"authorization_pending"` → `.pending`;
- `"error":"slow_down"` → `.slowDown`;
- `"error":"expired_token"` → throws `DeviceFlowError.expired`;
- `"error":"access_denied"` → throws `DeviceFlowError.denied`;
- any other `error` value → throws `DeviceFlowError.unexpected(message)` where `message` is
  `error_description` if present, otherwise the `error` value;
  e.g. `{"error":"incorrect_client_credentials","error_description":"The client_id is not valid."}`
  → `.unexpected("The client_id is not valid.")`; `{"error":"weird"}` → `.unexpected("weird")`;
- neither `access_token` nor `error` (e.g. `{}`) → throws `DeviceFlowError.unexpected(_)` (free-form message);
- invalid JSON → throws an error (type not specified).

## 5. `CopilotCLIAccount.select(from accounts: [String]) -> String?`

The Copilot CLI stores its secrets in the macOS Keychain under the `copilot-cli` service, with several
account names. The one holding the GitHub OAuth token has the exact form `https://github.com:<login>`.

- Returns the **first** account of the form `https://github.com:<login>` where `<login>` is non-empty and
  contains no `:`.
- Otherwise `nil`.
- Example: `["https://github.com:mona-lisa_OCTO", "https://github.com:mona-lisa_OCTO:github", "Bearer"]`
  → `"https://github.com:mona-lisa_OCTO"`. Order may vary: with
  `["Bearer", "https://github.com:mona-lisa_OCTO:github", "https://github.com:mona-lisa_OCTO"]`
  the result is the same.
- Rejected: `"https://github.com:"` (empty login), `"https://github.com:a:b"`,
  `"https://ghe.example.com:alice"` (other host), `"github.com:alice"` (no scheme), `"Bearer"`.
- Empty list → `nil`.

## 6. `HistoryStore` (SQLite history)

- `init(path:)` opens or creates a SQLite database at the given path; missing parent folders are created.
- `insert(_:)` records a snapshot: its `date` and its `used` (other fields may be stored,
  they are not read back through the public API).
- Two snapshots with the **same `date`**: the second replaces the first (a single point, with the most recent `used`).
- `points(since:)` returns the `HistoryPoint(date, used)` whose `date >= since`, sorted by **ascending**
  date, regardless of insertion order. Dates are restored with at least millisecond precision.
- Persistence: a new instance opened on the same path sees the snapshots already inserted.
- Unusable path (e.g. an existing file is used as a parent folder): no crash;
  `insert` does nothing and `points(since:)` returns `[]`.
