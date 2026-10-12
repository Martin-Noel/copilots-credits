import Foundation
import SQLite3

public struct HistoryPoint: Identifiable, Equatable {
    public let date: Date
    public let used: Double
    public var id: Date { date }

    public init(date: Date, used: Double) {
        self.date = date
        self.used = used
    }
}

/// The API only returns a point-in-time snapshot: the app builds the history
/// by recording each snapshot in a local SQLite database.
public final class HistoryStore {
    private var db: OpaquePointer?

    /// ~/Library/Application Support/CopilotCredits/history.sqlite
    public static var defaultPath: String {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CopilotCredits/history.sqlite")
            .path
    }

    public init(path: String) {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return
        }
        let created = sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS snapshots (
                ts          REAL PRIMARY KEY,  -- epoch secondes
                used        REAL NOT NULL,
                entitlement REAL NOT NULL,
                overage     REAL NOT NULL DEFAULT 0,
                reset_ts    REAL
            );
            """, nil, nil, nil)
        if created != SQLITE_OK {
            sqlite3_close(db)
            db = nil
        }
    }

    deinit { sqlite3_close(db) }

    public func insert(_ s: UsageSnapshot) {
        guard let db else { return }
        let sql = "INSERT OR REPLACE INTO snapshots (ts, used, entitlement, overage, reset_ts) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, s.date.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, s.used)
        sqlite3_bind_double(stmt, 3, s.entitlement)
        sqlite3_bind_double(stmt, 4, s.overage)
        if let reset = s.resetDate {
            sqlite3_bind_double(stmt, 5, reset.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        sqlite3_step(stmt)
    }

    public func points(since: Date) -> [HistoryPoint] {
        guard let db else { return [] }
        let sql = "SELECT ts, used FROM snapshots WHERE ts >= ? ORDER BY ts"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
        var result: [HistoryPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(HistoryPoint(
                date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                used: sqlite3_column_double(stmt, 1)
            ))
        }
        return result
    }
}
