import Foundation
import Testing
import CopilotCreditsCore

@Suite("HistoryPoint")
struct HistoryPointTests {

    @Test("init keeps date and used; id == date")
    func initAndId() {
        let date = TestDates.utc(2026, 10, 9, 14, 37, 2)
        let point = HistoryPoint(date: date, used: 607.5)
        #expect(point.date == date)
        #expect(approx(point.used, 607.5))
        #expect(point.id == date)
    }

    @Test("Equatable")
    func equatable() {
        let date = TestDates.utc(2026, 10, 9)
        #expect(HistoryPoint(date: date, used: 1) == HistoryPoint(date: date, used: 1))
        #expect(HistoryPoint(date: date, used: 1) != HistoryPoint(date: date, used: 2))
    }
}

@Suite("HistoryStore — SQLite history")
struct HistoryStoreTests {

    private static let distantPast: Date = Date(timeIntervalSince1970: 0)

    // MARK: - Creation

    @Test("New empty database → points(since:) == []")
    func emptyStore() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        #expect(store.points(since: HistoryStoreTests.distantPast).isEmpty)
        #expect(store.points(since: Date.distantPast).isEmpty)
    }

    @Test("Missing parent folders are created")
    func createsParentDirectories() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let path = tmp.path("a", "b", "c", "history.sqlite")
        let store = HistoryStore(path: path)
        let date = TestDates.utc(2026, 10, 9, 12)
        store.insert(makeSnapshot(date: date, used: 42))

        var isDirectory: ObjCBool = false
        let parent = tmp.path("a", "b", "c")
        #expect(FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(FileManager.default.fileExists(atPath: path))

        let points = store.points(since: HistoryStoreTests.distantPast)
        #expect(points.count == 1)
    }

    // MARK: - Insert / read

    @Test("insert then points: date and used are returned")
    func insertAndRead() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let date = TestDates.utc(2026, 10, 9, 14, 37, 2)
        store.insert(makeSnapshot(date: date, used: 607.5))

        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 1)
        #expect(approx(points[0].date.timeIntervalSince1970, date.timeIntervalSince1970, tol: 1e-3))
        #expect(approx(points[0].used, 607.5))
    }

    @Test("Other snapshot fields don't prevent reading (unlimited, nil reset, overage...)")
    func insertVariousSnapshots() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let d1 = TestDates.utc(2026, 10, 1, 8)
        let d2 = TestDates.utc(2026, 10, 2, 8)
        store.insert(makeSnapshot(date: d1, plan: "copilot", used: 0, entitlement: 0,
                                  overage: 0, overagePermitted: false, unlimited: true, resetDate: nil))
        store.insert(makeSnapshot(date: d2, plan: "business", used: 7100, entitlement: 7000,
                                  overage: 100, overagePermitted: true, unlimited: false,
                                  resetDate: TestDates.utc(2026, 11, 1)))
        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 2)
        #expect(approx(points[0].used, 0))
        #expect(approx(points[1].used, 7100))
    }

    // MARK: - Replace on same date

    @Test("Two snapshots with the same date: the second replaces the first")
    func sameDateReplaces() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let date = TestDates.utc(2026, 10, 9, 12)
        store.insert(makeSnapshot(date: date, used: 10))
        store.insert(makeSnapshot(date: date, used: 20))

        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 1)
        #expect(approx(points[0].used, 20))
    }

    @Test("Same-date replacement leaves other points untouched")
    func sameDateReplacesOnlyThatPoint() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let d1 = TestDates.utc(2026, 10, 1)
        let d2 = TestDates.utc(2026, 10, 2)
        let d3 = TestDates.utc(2026, 10, 3)
        store.insert(makeSnapshot(date: d1, used: 1))
        store.insert(makeSnapshot(date: d2, used: 2))
        store.insert(makeSnapshot(date: d3, used: 3))
        store.insert(makeSnapshot(date: d2, used: 22.5))

        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 3)
        #expect(approx(points[0].used, 1))
        #expect(approx(points[1].used, 22.5))
        #expect(approx(points[2].used, 3))
    }

    @Test("Same-date replacement: the most recent value wins even if smaller")
    func sameDateReplaceWithSmallerValue() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let date = TestDates.utc(2026, 10, 9, 12)
        store.insert(makeSnapshot(date: date, used: 500))
        store.insert(makeSnapshot(date: date, used: 100))
        store.insert(makeSnapshot(date: date, used: 300))

        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 1)
        #expect(approx(points[0].used, 300))
    }

    // MARK: - Sorting

    @Test("points(since:) sorted by ascending date regardless of insertion order")
    func sortedAscending() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let d1 = TestDates.utc(2026, 10, 1, 9)
        let d2 = TestDates.utc(2026, 10, 2, 9)
        let d3 = TestDates.utc(2026, 10, 3, 9)
        let d4 = TestDates.utc(2026, 10, 4, 9)
        store.insert(makeSnapshot(date: d3, used: 30))
        store.insert(makeSnapshot(date: d1, used: 10))
        store.insert(makeSnapshot(date: d4, used: 40))
        store.insert(makeSnapshot(date: d2, used: 20))

        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 4)
        let expectedDates: [Date] = [d1, d2, d3, d4]
        let expectedUsed: [Double] = [10, 20, 30, 40]
        for i in 0..<4 {
            #expect(approx(points[i].date.timeIntervalSince1970, expectedDates[i].timeIntervalSince1970, tol: 1e-3))
            #expect(approx(points[i].used, expectedUsed[i]))
        }
        for i in 1..<points.count {
            #expect(points[i - 1].date < points[i].date)
        }
    }

    // MARK: - since filter

    @Test("since filter: date >= since, bound included")
    func sinceFilterInclusive() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let d1 = TestDates.utc(2026, 10, 1)
        let d2 = TestDates.utc(2026, 10, 5)
        let d3 = TestDates.utc(2026, 10, 9)
        store.insert(makeSnapshot(date: d1, used: 1))
        store.insert(makeSnapshot(date: d2, used: 2))
        store.insert(makeSnapshot(date: d3, used: 3))

        let fromD2 = store.points(since: d2)
        try #require(fromD2.count == 2)
        #expect(approx(fromD2[0].used, 2))
        #expect(approx(fromD2[1].used, 3))
    }

    @Test("since just after a point excludes it")
    func sinceJustAfterExcludes() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let d1 = TestDates.utc(2026, 10, 1)
        let d2 = TestDates.utc(2026, 10, 5)
        store.insert(makeSnapshot(date: d1, used: 1))
        store.insert(makeSnapshot(date: d2, used: 2))

        let points = store.points(since: d1.addingTimeInterval(1))
        try #require(points.count == 1)
        #expect(approx(points[0].used, 2))
    }

    @Test("since just before a point includes it")
    func sinceJustBeforeIncludes() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let d1 = TestDates.utc(2026, 10, 1)
        store.insert(makeSnapshot(date: d1, used: 1))

        #expect(store.points(since: d1.addingTimeInterval(-1)).count == 1)
    }

    @Test("since after all points → []")
    func sinceAfterAll() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        store.insert(makeSnapshot(date: TestDates.utc(2026, 10, 1), used: 1))
        store.insert(makeSnapshot(date: TestDates.utc(2026, 10, 2), used: 2))

        #expect(store.points(since: TestDates.utc(2026, 10, 3)).isEmpty)
    }

    @Test("since before all points → all")
    func sinceBeforeAll() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        store.insert(makeSnapshot(date: TestDates.utc(2026, 10, 1), used: 1))
        store.insert(makeSnapshot(date: TestDates.utc(2026, 10, 2), used: 2))

        #expect(store.points(since: TestDates.utc(2026, 9, 1)).count == 2)
    }

    // MARK: - Persistence

    @Test("Persistence: a new instance on the same path sees the snapshots")
    func persistenceAcrossInstances() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let path = tmp.path("data", "history.sqlite")
        let d1 = TestDates.utc(2026, 10, 1, 10)
        let d2 = TestDates.utc(2026, 10, 2, 10)

        do {
            let first = HistoryStore(path: path)
            first.insert(makeSnapshot(date: d2, used: 200))
            first.insert(makeSnapshot(date: d1, used: 100))
        }

        let second = HistoryStore(path: path)
        let points = second.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 2)
        #expect(approx(points[0].date.timeIntervalSince1970, d1.timeIntervalSince1970, tol: 1e-3))
        #expect(approx(points[0].used, 100))
        #expect(approx(points[1].date.timeIntervalSince1970, d2.timeIntervalSince1970, tol: 1e-3))
        #expect(approx(points[1].used, 200))
    }

    @Test("Persistence: same-date replacement across two instances")
    func persistenceReplaceAcrossInstances() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let path = tmp.path("history.sqlite")
        let date = TestDates.utc(2026, 10, 1, 10)

        do {
            let first = HistoryStore(path: path)
            first.insert(makeSnapshot(date: date, used: 100))
        }
        do {
            let second = HistoryStore(path: path)
            second.insert(makeSnapshot(date: date, used: 150))
        }

        let third = HistoryStore(path: path)
        let points = third.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 1)
        #expect(approx(points[0].used, 150))
    }

    // MARK: - Precision

    @Test("Dates are restored with at least millisecond precision")
    func millisecondPrecision() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let date = Date(timeIntervalSince1970: 1_791_558_000.123)
        store.insert(makeSnapshot(date: date, used: 7))

        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 1)
        let delta: Double = abs(points[0].date.timeIntervalSince1970 - date.timeIntervalSince1970)
        #expect(delta <= 0.001, "delta = \(delta) s")
    }

    @Test("Two dates a few milliseconds apart stay two distinct, ordered points")
    func millisecondDistinctPoints() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let store = HistoryStore(path: tmp.path("history.sqlite"))
        let base: TimeInterval = 1_791_558_000.100
        let early = Date(timeIntervalSince1970: base)
        let late = Date(timeIntervalSince1970: base + 0.010)
        store.insert(makeSnapshot(date: late, used: 2))
        store.insert(makeSnapshot(date: early, used: 1))

        let points = store.points(since: HistoryStoreTests.distantPast)
        try #require(points.count == 2)
        #expect(approx(points[0].used, 1))
        #expect(approx(points[1].used, 2))
        #expect(points[0].date < points[1].date)
    }

    // MARK: - Unusable path

    @Test("Unusable path (file used as parent folder): no crash, insert is a no-op, points empty")
    func unusablePath() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let blocker = tmp.path("blocker")
        let created = FileManager.default.createFile(atPath: blocker, contents: Data("not a directory".utf8))
        try #require(created)

        let store = HistoryStore(path: tmp.path("blocker", "sub", "history.sqlite"))
        store.insert(makeSnapshot(date: TestDates.utc(2026, 10, 1), used: 1))
        store.insert(makeSnapshot(date: TestDates.utc(2026, 10, 2), used: 2))

        #expect(store.points(since: HistoryStoreTests.distantPast).isEmpty)
        #expect(store.points(since: Date.distantPast).isEmpty)
    }

    @Test("Unusable path (file used directly as the database's parent folder)")
    func unusablePathDirectParent() throws {
        let tmp = try TempDir()
        defer { tmp.remove() }
        let blocker = tmp.path("blocker")
        let created = FileManager.default.createFile(atPath: blocker, contents: Data("x".utf8))
        try #require(created)

        let store = HistoryStore(path: tmp.path("blocker", "history.sqlite"))
        store.insert(makeSnapshot(date: TestDates.utc(2026, 10, 1), used: 1))
        #expect(store.points(since: HistoryStoreTests.distantPast).isEmpty)
    }
}
