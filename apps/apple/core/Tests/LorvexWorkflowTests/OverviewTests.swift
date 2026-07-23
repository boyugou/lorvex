import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import XCTest

@testable import LorvexWorkflow

/// `overview/` has no `#[test]` cases of its own. These seed-and-query cases
/// exercise the ported stats aggregate, the section loaders, the streak walk,
/// and the per-connection streak cache `loadOverviewSnapshot` consults
/// (`OverviewStreakCache`).
final class OverviewTests: XCTestCase {
  /// Bump `local_change_seq` the way the production writer does, so a cache
  /// keyed on the counter sees the change.
  private func bumpLocalChangeSeq(_ db: Database) throws {
    try db.execute(
      sql: "INSERT INTO local_counters (name, value, updated_at) VALUES (?, 1, ?) "
        + "ON CONFLICT(name) DO UPDATE SET value = local_counters.value + 1, updated_at = excluded.updated_at",
      arguments: [OverviewStreakCache.localChangeSeqKey, Int64(1_748_217_600_000)])
  }

  /// UTC `completed_at` timestamp at 08:00 on the day `daysAgo` before the real
  /// current date. `loadOverviewSnapshot` derives `today` from the live clock,
  /// so cache tests must seed completions relative to "now".
  private func completedAtDaysAgo(_ daysAgo: Int) -> String {
    let day = Date().addingTimeInterval(Double(-daysAgo) * 86_400)
    var cal = Foundation.Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day], from: day)
    return String(format: "%04d-%02d-%02dT08:00:00.000Z", c.year!, c.month!, c.day!)
  }

  private func setTimezone(_ db: Database, _ tz: String) throws {
    // The timezone preference is stored as a canonical JSON string (quoted).
    try db.execute(
      sql: "INSERT INTO preferences (key, value, version, updated_at) "
        + "VALUES ('timezone', ?, '0000000000000_0000_0000000000000001', ?) "
        + "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      arguments: ["\"\(tz)\"", "2026-03-29T00:00:00Z"])
  }

  private func seedTask(
    _ db: Database, id: String, status: String, dueDate: String? = nil,
    completedAt: String? = nil, listId: String = "inbox"
  ) throws {
    try db.execute(
      sql: "INSERT INTO tasks (id, title, status, list_id, due_date, completed_at, "
        + "version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?, ?, '0000000000000_0000_0000000000000001', ?, ?)",
      arguments: [
        id, "t-\(id)", status, listId, dueDate, completedAt,
        "2026-03-29T00:00:00Z", "2026-03-29T00:00:00Z",
      ])
  }

  func testStatsCountByStatus() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { wdb in
      try setTimezone(wdb, "UTC")
      try seedTask(wdb, id: "o1", status: "open")
      try seedTask(wdb, id: "o2", status: "open")
      try seedTask(wdb, id: "s1", status: "someday")
      try seedTask(wdb, id: "c1", status: "completed", completedAt: "2020-01-01T00:00:00.000Z")
    }
    let stats = try store.writer.read { db -> Overview.Stats in
      try Overview.loadOverviewStatsForBounds(
        db, today: "2026-05-26", todayStartUtc: "2026-05-26T00:00:00.000Z",
        todayEndUtc: "2026-05-27T00:00:00.000Z",
        reviewWindowStartUtc: "2026-05-20T00:00:00.000Z",
        reviewWindowEndUtc: "2026-05-27T00:00:00.000Z",
        prevWeekStartUtc: "2026-05-13T00:00:00.000Z")
    }
    XCTAssertEqual(stats.openCount, 2)
    XCTAssertEqual(stats.somedayCount, 1)
    XCTAssertEqual(stats.completedToday, 0)
  }

  func testSnapshotComposesSections() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setTimezone(db, "UTC")
      try seedTask(db, id: "o1", status: "open")
      try seedTask(db, id: "o2", status: "open")
    }
    let snapshot = try store.writer.read { db in
      try Overview.loadOverviewSnapshot(db, limits: .app())
    }
    XCTAssertEqual(snapshot.stats.openCount, 2)
    // The schema seeds the `inbox` list; it should appear with an open count.
    XCTAssertTrue(snapshot.lists.contains { $0.id == "inbox" })
    XCTAssertNil(snapshot.currentFocus)
    XCTAssertEqual(snapshot.habits.count, 0)
  }

  func testStreakCountsContiguousDays() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { wdb in
      // Three contiguous days ending today (UTC).
      try seedTask(wdb, id: "d0", status: "completed", completedAt: "2026-05-26T08:00:00.000Z")
      try seedTask(wdb, id: "d1", status: "completed", completedAt: "2026-05-25T08:00:00.000Z")
      try seedTask(wdb, id: "d2", status: "completed", completedAt: "2026-05-24T08:00:00.000Z")
      // Gap, then an older day that should not extend the streak.
      try seedTask(wdb, id: "d4", status: "completed", completedAt: "2026-05-22T08:00:00.000Z")
    }
    let streak = try store.writer.read { db -> Overview.CompletionStreak in
      try Overview.queryCompletionStreak(db, today: "2026-05-26", timezoneName: "UTC")
    }
    XCTAssertTrue(streak.activeToday)
    XCTAssertEqual(streak.count, 3)
  }

  func testStreakInactiveWhenNoRecentCompletion() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { wdb in
      try seedTask(wdb, id: "old", status: "completed", completedAt: "2026-05-01T08:00:00.000Z")
    }
    let streak = try store.writer.read { db -> Overview.CompletionStreak in
      try Overview.queryCompletionStreak(db, today: "2026-05-26", timezoneName: "UTC")
    }
    XCTAssertFalse(streak.activeToday)
    XCTAssertEqual(streak.count, 0)
  }

  // MARK: - Streak cache invalidation

  func testStreakCacheLocalChangeSeqKeyMatchesRuntimeKey() {
    XCTAssertEqual(OverviewStreakCache.localChangeSeqKey, LocalChangeSeq.key)
  }

  /// A write between two `loadOverviewSnapshot` reads (which bumps
  /// `local_change_seq`) must bust the cache: the second snapshot reflects the
  /// new completion rather than returning the stale streak.
  func testSnapshotStreakCacheBustsOnWrite() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setTimezone(db, "UTC")
      // Yesterday only — streak of 1 ending yesterday, not active today.
      try seedTask(db, id: "y", status: "completed", completedAt: completedAtDaysAgo(1))
      try bumpLocalChangeSeq(db)
    }
    let first = try store.writer.read { db in
      try Overview.loadOverviewSnapshot(db, limits: .app())
    }
    XCTAssertEqual(first.stats.completionStreak, 1)
    XCTAssertFalse(first.stats.streakActiveToday)

    // Complete a task today and bump the seq, as the production writer does.
    try store.writer.write { db in
      try self.seedTask(db, id: "t", status: "completed", completedAt: self.completedAtDaysAgo(0))
      try self.bumpLocalChangeSeq(db)
    }
    let second = try store.writer.read { db in
      try Overview.loadOverviewSnapshot(db, limits: .app())
    }
    // Stale would still report streak=1, inactive. The bust gives 2, active.
    XCTAssertEqual(second.stats.completionStreak, 2)
    XCTAssertTrue(second.stats.streakActiveToday)
  }

  /// With no intervening write (no `local_change_seq` bump), a mutation made
  /// out-of-band is intentionally NOT observed — proving the snapshot actually
  /// served the cached streak rather than recomputing every call. (Production
  /// never mutates without bumping the seq; this asserts the cache is live.)
  func testSnapshotStreakServedFromCacheWithoutSeqBump() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setTimezone(db, "UTC")
      try seedTask(db, id: "y", status: "completed", completedAt: completedAtDaysAgo(1))
      try bumpLocalChangeSeq(db)
    }
    let first = try store.writer.read { db in
      try Overview.loadOverviewSnapshot(db, limits: .app())
    }
    XCTAssertEqual(first.stats.completionStreak, 1)

    // Mutate WITHOUT bumping the seq — the cache key is unchanged.
    try store.writer.write { db in
      try self.seedTask(db, id: "t", status: "completed", completedAt: self.completedAtDaysAgo(0))
    }
    let second = try store.writer.read { db in
      try Overview.loadOverviewSnapshot(db, limits: .app())
    }
    XCTAssertEqual(second.stats.completionStreak, 1, "cache should serve the prior streak")
    XCTAssertFalse(second.stats.streakActiveToday)
  }

  /// Two distinct stores in the same process must not share a cache slot even
  /// at the same `local_change_seq` — the key is per-connection.
  func testStreakCacheIsolatedPerStore() throws {
    let storeA = try WorkflowTestSupport.freshStore()
    let storeB = try WorkflowTestSupport.freshStore()
    try storeA.writer.write { db in
      try setTimezone(db, "UTC")
      try seedTask(db, id: "a", status: "completed", completedAt: completedAtDaysAgo(0))
      try bumpLocalChangeSeq(db)  // seq = 1
    }
    try storeB.writer.write { db in
      try setTimezone(db, "UTC")
      // No completions; seq also 1 — same coarse key components as A.
      try bumpLocalChangeSeq(db)  // seq = 1
    }
    let a = try storeA.writer.read { try Overview.loadOverviewSnapshot($0, limits: .app()) }
    let b = try storeB.writer.read { try Overview.loadOverviewSnapshot($0, limits: .app()) }
    XCTAssertEqual(a.stats.completionStreak, 1)
    XCTAssertEqual(b.stats.completionStreak, 0, "store B must not read store A's cached streak")
  }

  /// Sequential stores (open → snapshot → drop → repeat) must not inherit a
  /// prior store's cached streak even when the freed connection's address is
  /// reused: the cache key is weak-referenced to the `Database`, so a dropped
  /// store's slot is gone. Each iteration seeds a distinct streak length and
  /// asserts its own value at the same `local_change_seq`.
  func testStreakCacheDoesNotLeakAcrossSequentialStores() throws {
    for length in 1...4 {
      try autoreleasepool {
        let store = try WorkflowTestSupport.freshStore()
        try store.writer.write { db in
          try self.setTimezone(db, "UTC")
          // `length` contiguous completed days ending today.
          for d in 0..<length {
            try self.seedTask(
              db, id: "s\(d)", status: "completed", completedAt: self.completedAtDaysAgo(d))
          }
          try self.bumpLocalChangeSeq(db)  // seq = 1 every iteration
        }
        let snap = try store.writer.read { try Overview.loadOverviewSnapshot($0, limits: .app()) }
        XCTAssertEqual(
          snap.stats.completionStreak, Int64(length),
          "iteration \(length) must compute its own streak, not a freed store's")
      }
    }
  }
}
