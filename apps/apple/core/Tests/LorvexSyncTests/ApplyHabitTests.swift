import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity `#[test]` cases for the `habit` aggregate delete cascade-
/// gate (Rust `aggregate/habit/tests.rs`).
final class ApplyHabitTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  // MARK: - habit delete cascade gate

  func testHabitDeleteCascadeDoesNotRunWhenByteCompareFallbackRejectsLegacyVersion() throws {
    try withDB { db in
      let habitId = "00000000-0000-7000-8000-000000003001"
      let canonicalEnvelopeVersion = "1711234599000_0000_dec0000200000002"
      let legacyLocalVersion = "v1"

      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO habits (id, name, frequency_type, target_count, archived,
                                lookup_key, version, created_at, updated_at)
            VALUES (?, 'Read', 'daily', 1, 0, 'read', ?,
                    '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
            """,
          arguments: [habitId, legacyLocalVersion])
      }

      let completionDate = "2026-04-01"
      try db.execute(
        sql: """
          INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
          VALUES (?, ?, 1, ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [habitId, completionDate, canonicalEnvelopeVersion])
      let policyId = "00000000-0000-7000-8000-000000003002"
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled, version,
                                               created_at, updated_at)
          VALUES (?, ?, '09:00', 1, ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [policyId, habitId, canonicalEnvelopeVersion])

      let outcome = try ApplyHabit.applyHabitDelete(
        db, entityId: habitId, version: canonicalEnvelopeVersion,
        applyTs: "2026-04-01T00:00:00.000Z")
      guard case .rejected = outcome else {
        return XCTFail("byte-compare fallback must surface as rejected, got \(outcome)")
      }

      let parentCount = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM habits WHERE id = ?", arguments: [habitId])
      XCTAssertEqual(parentCount, 1, "parent habit must survive the rejected delete")

      let completionEdgeId = "\(habitId):\(completionDate)"
      let completionTs = try Int64.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EdgeName.habitCompletion, completionEdgeId])
      XCTAssertEqual(
        completionTs, 0,
        "habit_completion cascade tombstone must NOT be written on rejected parent delete")

      let policyTs = try Int64.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.habitReminderPolicy, policyId])
      XCTAssertEqual(
        policyTs, 0,
        "habit_reminder_policy cascade tombstone must NOT be written on rejected parent delete")
    }
  }

  /// Cross-device reorder sync: a peer's habit upsert carrying a new `position`
  /// converges locally; a later upsert that omits the key (an older peer) still
  /// applies, falling back to the schema DEFAULT.
  func testApplyHabitUpsertSyncsPosition() throws {
    try withDB { db in
      let habitId = "00000000-0000-7000-8000-000000004900"
      try ApplyHabit.applyHabitUpsert(
        db, entityId: habitId,
        payload: """
          {"name":"Read","frequency_type":"daily","target_count":1,\
          "position":4,"created_at":"2026-04-01T00:00:00.000Z",\
          "updated_at":"2026-04-01T00:00:00.000Z"}
          """,
        version: "1711234560000_0000_dec0000100000001", tieBreak: .rejectEqual,
        applyTs: "2026-04-01T00:00:00.000Z")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT position FROM habits WHERE id = ?", arguments: [habitId]),
        4, "peer habit position must converge locally")

      try ApplyHabit.applyHabitUpsert(
        db, entityId: habitId,
        payload: """
          {"name":"Read","frequency_type":"daily","target_count":1,\
          "created_at":"2026-04-01T00:00:00.000Z","updated_at":"2026-04-02T00:00:00.000Z"}
          """,
        version: "1711234569000_0000_dec0000100000001", tieBreak: .rejectEqual,
        applyTs: "2026-04-02T00:00:00.000Z")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT position FROM habits WHERE id = ?", arguments: [habitId]),
        4, "BH-5: an absent position preserves the existing order, never resets to 0")
    }
  }

  func testHabitUpsertThenDeleteCascadesChildTombstones() throws {
    try withDB { db in
      let habitId = "00000000-0000-7000-8000-000000004001"
      let vSeed = "1711234560000_0000_dec0000100000001"
      let vDelete = "1711234569000_0000_dec0000100000001"

      try ApplyHabit.applyHabitUpsert(
        db, entityId: habitId,
        payload: """
          {"name":"Read","frequency_type":"daily","target_count":1,\
          "created_at":"2026-04-01T00:00:00.000Z","updated_at":"2026-04-01T00:00:00.000Z"}
          """,
        version: vSeed, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
      let storedKey = try String.fetchOne(
        db, sql: "SELECT lookup_key FROM habits WHERE id = ?", arguments: [habitId])
      XCTAssertEqual(storedKey, "read", "lookup_key re-derived from validated name")

      let completionDate = "2026-04-01"
      try db.execute(
        sql: """
          INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, updated_at)
          VALUES (?, ?, 1, ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [habitId, completionDate, vSeed])
      let policyId = "00000000-0000-7000-8000-000000004002"
      try db.execute(
        sql: """
          INSERT INTO habit_reminder_policies (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
          VALUES (?, ?, '09:00', 1, ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [policyId, habitId, vSeed])

      let outcome = try ApplyHabit.applyHabitDelete(
        db, entityId: habitId, version: vDelete, applyTs: "2026-04-01T01:00:00.000Z")
      XCTAssertEqual(outcome, .applied)

      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM habits WHERE id = ?", arguments: [habitId]),
        0, "parent habit deleted")
      // Cascade tombstones written ahead of FK CASCADE.
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
          arguments: [EdgeName.habitCompletion, "\(habitId):\(completionDate)"]),
        1, "habit_completion cascade tombstone written")
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.habitReminderPolicy, policyId]),
        1, "habit_reminder_policy cascade tombstone written")
    }
  }

  // MARK: - typed cadence apply + habit_weekdays rebuild

  private func weekdaysOf(_ db: Database, _ habitId: String) throws -> [Int64] {
    try Int64.fetchAll(
      db, sql: "SELECT weekday FROM habit_weekdays WHERE habit_id = ? ORDER BY weekday ASC",
      arguments: [habitId])
  }

  private func upsert(_ db: Database, id: String, version: String, payloadBody: String) throws {
    try ApplyHabit.applyHabitUpsert(
      db, entityId: id,
      payload: """
        {"name":"Read",\(payloadBody),"created_at":"2026-04-01T00:00:00.000Z",\
        "updated_at":"2026-04-01T00:00:00.000Z"}
        """,
      version: version, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
  }

  func testApplyWeeklyRebuildsHabitWeekdaysFromPayload() throws {
    try withDB { db in
      let id = "00000000-0000-7000-8000-00000000e001"
      // Weekdays travel inside the payload (Monday-first 0=Mon, 2=Wed, 4=Fri).
      try upsert(
        db, id: id, version: "1711234560000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"weekly","weekdays":[0,2,4],"target_count":1"#)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT frequency_type FROM habits WHERE id = ?", arguments: [id]),
        "weekly")
      XCTAssertEqual(try weekdaysOf(db, id), [0, 2, 4], "habit_weekdays rebuilt from payload")

      // A later upsert with a different weekday set fully replaces the child.
      try upsert(
        db, id: id, version: "1711234569000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"weekly","weekdays":[1],"target_count":1"#)
      XCTAssertEqual(try weekdaysOf(db, id), [1], "weekday set replaced, not merged")
    }
  }

  func testApplyMonthlyStoresDayOfMonthAndNoWeekdays() throws {
    try withDB { db in
      let id = "00000000-0000-7000-8000-00000000e002"
      try upsert(
        db, id: id, version: "1711234560000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"monthly","day_of_month":15,"target_count":1"#)
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT day_of_month FROM habits WHERE id = ?", arguments: [id]),
        15)
      XCTAssertTrue(try weekdaysOf(db, id).isEmpty, "monthly cadence pins no weekdays")
    }
  }

  func testApplyTimesPerWeekStoresPerPeriodTarget() throws {
    try withDB { db in
      let id = "00000000-0000-7000-8000-00000000e003"
      try upsert(
        db, id: id, version: "1711234560000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"times_per_week","per_period_target":3,"target_count":1"#)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT per_period_target FROM habits WHERE id = ?", arguments: [id]),
        3)
      XCTAssertTrue(try weekdaysOf(db, id).isEmpty)
    }
  }

  func testSwitchingWeeklyToDailyClearsWeekdays() throws {
    try withDB { db in
      let id = "00000000-0000-7000-8000-00000000e004"
      try upsert(
        db, id: id, version: "1711234560000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"weekly","weekdays":[0,2],"target_count":1"#)
      XCTAssertEqual(try weekdaysOf(db, id), [0, 2])
      try upsert(
        db, id: id, version: "1711234569000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"daily","target_count":1"#)
      XCTAssertTrue(try weekdaysOf(db, id).isEmpty, "daily cadence clears the weekday child")
    }
  }

  func testApplyRejectsOutOfRangeWeekday() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try upsert(
          db, id: "00000000-0000-7000-8000-00000000e005",
          version: "1711234560000_0000_dec0000100000001",
          payloadBody: #""frequency_type":"weekly","weekdays":[7],"target_count":1"#))
    }
  }

  // MARK: - milestone_target enqueue → apply round-trip

  func testMilestoneTargetRoundTripsEnqueueToApply() throws {
    let habitId = "00000000-0000-7000-8000-00000000e011"

    // Enqueue side: serialize a habit row that carries a milestone target the
    // same way the outbox does — read the row into the sync payload.
    let source = try SyncTestSupport.freshStore()
    let payloadStr = try source.writer.write { db -> String in
      try db.execute(
        sql: """
          INSERT INTO habits (id, name, frequency_type, per_period_target, target_count,
                              milestone_target, archived, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Read', 'monthly', 1, 1, 250, 0, 'read',
                  '1711234560000_0000_dec0000100000001',
                  '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [habitId])
      let payload = try XCTUnwrap(PayloadLoaders.loadHabitSyncPayload(db, habitId: habitId))
      guard case let .object(map) = payload else {
        XCTFail("expected object payload")
        return ""
      }
      XCTAssertEqual(map["milestone_target"], .int(250))
      return try SyncCanonicalize.canonicalizeJSON(payload)
    }

    // Apply side: a fresh peer applies the serialized envelope and preserves it.
    let dest = try SyncTestSupport.freshStore()
    try dest.writer.write { db in
      try ApplyHabit.applyHabitUpsert(
        db, entityId: habitId, payload: payloadStr,
        version: "1711234560000_0000_dec0000100000001", tieBreak: .rejectEqual,
        applyTs: "2026-04-01T00:00:00.000Z")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT milestone_target FROM habits WHERE id = ?", arguments: [habitId]),
        250)
    }
  }

  func testApplyStoresMilestoneTargetFromPayload() throws {
    try withDB { db in
      let id = "00000000-0000-7000-8000-00000000e012"
      try upsert(
        db, id: id, version: "1711234560000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"daily","target_count":1,"milestone_target":66"#)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT milestone_target FROM habits WHERE id = ?", arguments: [id]),
        66)
    }
  }

  func testApplyLeavesMilestoneTargetNullWhenAbsent() throws {
    try withDB { db in
      let id = "00000000-0000-7000-8000-00000000e013"
      try upsert(
        db, id: id, version: "1711234560000_0000_dec0000100000001",
        payloadBody: #""frequency_type":"daily","target_count":1"#)
      XCTAssertNil(
        try Int64.fetchOne(
          db, sql: "SELECT milestone_target FROM habits WHERE id = ?", arguments: [id]))
    }
  }

  func testApplyRejectsNonPositiveMilestoneTarget() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try upsert(
          db, id: "00000000-0000-7000-8000-00000000e014",
          version: "1711234560000_0000_dec0000100000001",
          payloadBody: #""frequency_type":"daily","target_count":1,"milestone_target":0"#))
    }
  }

}
