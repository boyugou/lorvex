import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class AggregateMergeVersionFloorTests: XCTestCase {
  private let parentEarlier = "1711234567000_0000_aaaaaaaaaaaaaaaa"
  private let parentLater = "1711234568000_0000_bbbbbbbbbbbbbbbb"
  private let childFuture = "9000000000000_0000_cccccccccccccccc"
  private let ts = "2026-07-14T00:00:00.000Z"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func assertDominates(
    _ actual: String?, _ floor: String, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    XCTAssertGreaterThan(
      try Hlc.parse(try XCTUnwrap(actual, file: file, line: line)),
      try Hlc.parse(floor), file: file, line: line)
  }

  func testTagMergeChildFloorSurvivesRepointAndReplay() throws {
    try withDB { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, version, created_at, updated_at)
          VALUES ('00000000-0000-7000-8000-000000000002', 'Task', 'open', ?, ?, ?)
          """,
        arguments: [self.parentEarlier, self.ts, self.ts])
      for (id, name, version) in [
        ("00000000-0000-7000-8000-000000000001", "Shared", self.parentEarlier), ("ffffffff-ffff-7fff-8fff-ffffffffffff", "shared", self.parentLater),
      ] {
        try db.execute(
          sql: """
            INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
            VALUES (?, ?, 'shared', ?, ?, ?)
            """,
          arguments: [id, name, version, self.ts, self.ts])
      }
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, version, created_at)
          VALUES ('00000000-0000-7000-8000-000000000002', 'ffffffff-ffff-7fff-8fff-ffffffffffff', ?, ?)
          """,
        arguments: [self.childFuture, self.ts])

      _ = try ApplyTagMerge.merger.mergeKnownDuplicate(
        db, rows: [("00000000-0000-7000-8000-000000000001", self.parentEarlier), ("ffffffff-ffff-7fff-8fff-ffffffffffff", self.parentLater)],
        triggeringVersion: self.parentLater, applyTs: self.ts)

      let edgeVersion = try String.fetchOne(
        db, sql: "SELECT version FROM task_tags WHERE task_id = '00000000-0000-7000-8000-000000000002' AND tag_id = '00000000-0000-7000-8000-000000000001'")
      let rootVersion = try String.fetchOne(db, sql: "SELECT version FROM tags WHERE id = '00000000-0000-7000-8000-000000000001'")
      let tombstoneVersion = try String.fetchOne(
        db,
        sql: "SELECT version FROM sync_tombstones WHERE entity_type = 'tag' AND entity_id = 'ffffffff-ffff-7fff-8fff-ffffffffffff'")
      XCTAssertEqual(edgeVersion, self.childFuture)
      try self.assertDominates(rootVersion, self.parentLater)
      XCTAssertLessThan(
        try Hlc.parse(try XCTUnwrap(rootVersion)), try Hlc.parse(self.childFuture),
        "a child-only future HLC must not contaminate the deterministic parent merge stamp")
      XCTAssertEqual(rootVersion, tombstoneVersion)

      try ApplyTagMerge.merger.mergeDuplicate(
        db, justUpsertedId: "00000000-0000-7000-8000-000000000001", whereClause: "lookup_key = ?", whereArgs: ["shared"],
        triggeringVersion: try XCTUnwrap(rootVersion), applyTs: self.ts)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM task_tags WHERE task_id = '00000000-0000-7000-8000-000000000002' AND tag_id = '00000000-0000-7000-8000-000000000001'"),
        edgeVersion)
    }
  }

  func testHabitMergeFloorsChildrenAndPreservesNewerPolicyContent() throws {
    try withDB { db in
      for (id, lookup, version) in [
        ("00000000-0000-7000-8000-000000000001", "habit-a", self.parentEarlier), ("ffffffff-ffff-7fff-8fff-ffffffffffff", "habit-z", self.parentLater),
      ] {
        try db.execute(
          sql: """
            INSERT INTO habits
              (id, name, frequency_type, target_count, archived, lookup_key,
               version, created_at, updated_at)
            VALUES (?, 'Habit', 'daily', 1, 0, ?, ?, ?, ?)
            """,
          arguments: [id, lookup, version, self.ts, self.ts])
      }
      let completionFuture = "9000000000002_0000_dddddddddddddddd"
      let policyFuture = "9000000000001_0000_eeeeeeeeeeeeeeee"
      try db.execute(
        sql: """
          INSERT INTO habit_completions
            (habit_id, completed_date, value, note, version, created_at, updated_at)
          VALUES ('ffffffff-ffff-7fff-8fff-ffffffffffff', '2026-07-14', 2, 'later', ?, ?, ?)
          """,
        arguments: [completionFuture, self.ts, self.ts])
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_policies
            (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
          VALUES ('ffffffff-ffff-7fff-8fff-fffffffffff0', '00000000-0000-7000-8000-000000000001', '09:00', 1, ?, ?, ?),
                 ('00000000-0000-7000-8000-00000000000a', 'ffffffff-ffff-7fff-8fff-ffffffffffff', '09:00', 0, ?, ?, ?)
          """,
        arguments: [self.parentEarlier, self.ts, self.ts, policyFuture, self.ts, self.ts])

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [("00000000-0000-7000-8000-000000000001", self.parentEarlier), ("ffffffff-ffff-7fff-8fff-ffffffffffff", self.parentLater)],
        triggeringVersion: self.parentLater, applyTs: self.ts)

      let rootVersion = try String.fetchOne(db, sql: "SELECT version FROM habits WHERE id = '00000000-0000-7000-8000-000000000001'")
      let completionVersion = try String.fetchOne(
        db,
        sql: """
          SELECT version FROM habit_completions
           WHERE habit_id = '00000000-0000-7000-8000-000000000001' AND completed_date = '2026-07-14'
          """)
      let policy = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT id, habit_id, enabled, version FROM habit_reminder_policies
             WHERE habit_id = '00000000-0000-7000-8000-000000000001' AND reminder_time = '09:00'
            """))
      try self.assertDominates(rootVersion, self.parentLater)
      XCTAssertLessThan(
        try Hlc.parse(try XCTUnwrap(rootVersion)), try Hlc.parse(policyFuture),
        "child versions must not alter the habit root's deterministic merge stamp")
      XCTAssertEqual(completionVersion, completionFuture)
      XCTAssertEqual(policy["id"] as String, "00000000-0000-7000-8000-00000000000a", "min policy id survives")
      XCTAssertEqual(policy["habit_id"] as String, "00000000-0000-7000-8000-000000000001")
      XCTAssertEqual(policy["enabled"] as Int64, 0, "newer policy content survives")
      let policyVersion = policy["version"] as String
      try self.assertDominates(policyVersion, policyFuture)

      let policyDeath = try Tombstone.getTombstone(
        db, entityType: EntityName.habitReminderPolicy, entityId: "ffffffff-ffff-7fff-8fff-fffffffffff0")
      let policyRedirect = try EntityRedirect.get(
        db, sourceType: EntityName.habitReminderPolicy, sourceId: "ffffffff-ffff-7fff-8fff-fffffffffff0")
      XCTAssertEqual(policyRedirect?.targetId, "00000000-0000-7000-8000-00000000000a")
      XCTAssertEqual(policyDeath?.version, policyVersion)

      _ = try ApplyHabitMerge.mergeKnownDuplicateHabits(
        db, rows: [("00000000-0000-7000-8000-000000000001", try XCTUnwrap(rootVersion))],
        triggeringVersion: try XCTUnwrap(rootVersion), applyTs: self.ts)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM habit_completions
             WHERE habit_id = '00000000-0000-7000-8000-000000000001' AND completed_date = '2026-07-14'
            """),
        completionFuture)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM habit_reminder_policies
             WHERE habit_id = '00000000-0000-7000-8000-000000000001' AND reminder_time = '09:00'
            """),
        policyVersion)
    }
  }
}
