import GRDB
import LorvexStore
import XCTest

@testable import LorvexWorkflow

/// Ports `habit_reminder_ops/tests.rs`. The two Rust cases that install a
/// rusqlite authorizer to force a SELECT to fail
/// (`upsert_surfaces_habit_lookup_failures`,
/// `upsert_surfaces_existing_policy_lookup_failures`) are intentionally not
/// ported: GRDB exposes no equivalent statement authorizer hook, so there is no
/// way to provoke the SQL-error branch without a real I/O failure. The branch
/// itself is a plain `try` that propagates a thrown `DatabaseError`.
final class HabitReminderOpsTests: XCTestCase {
  private static let dummyVersion = "0000000000000_0000_0000000000000001"
  private static let v2 = "0000000000000_0000_0000000000000002"
  private static let v3 = "0000000000000_0000_0000000000000003"

  private func seedHabit(_ db: Database, id: String, name: String) throws {
    try db.execute(
      sql: "INSERT INTO habits (id, name, version, created_at, updated_at) "
        + "VALUES (?, ?, '0000000000000_0000_0000000000000000', ?, ?)",
      arguments: [id, name, "2026-03-29T00:00:00Z", "2026-03-29T00:00:00Z"])
  }

  private func upsert(
    _ db: Database, policyId: String? = nil, habitId: String, time: String, enabled: Bool,
    version: String = dummyVersion, now: String = "2026-03-29T09:00:00Z"
  ) throws -> HabitReminderOps.HabitReminderPolicyRow {
    try HabitReminderOps.upsertHabitReminderPolicy(
      db,
      params: .init(
        policyId: policyId, habitId: habitId, reminderTime: time, enabled: enabled,
        version: version, now: now))
  }

  func testUpsertCreatesNewPolicy() throws {
    let store = try WorkflowTestSupport.freshStore()
    let policy = try store.writer.write { db -> HabitReminderOps.HabitReminderPolicyRow in
      try seedHabit(db, id: "h1", name: "Meditate")
      return try upsert(db, habitId: "h1", time: "08:00", enabled: true)
    }
    XCTAssertEqual(policy.habitId, "h1")
    XCTAssertEqual(policy.habitName, "Meditate")
    XCTAssertEqual(policy.reminderTime, "08:00")
    XCTAssertTrue(policy.enabled)
  }

  func testUpsertUpdatesExistingPolicy() throws {
    let store = try WorkflowTestSupport.freshStore()
    let updated = try store.writer.write { db -> HabitReminderOps.HabitReminderPolicyRow in
      try seedHabit(db, id: "h1", name: "Meditate")
      let created = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      return try upsert(
        db, policyId: created.id, habitId: "h1", time: "09:30", enabled: false,
        version: Self.v2, now: "2026-03-29T10:00:00Z")
    }
    XCTAssertEqual(updated.reminderTime, "09:30")
    XCTAssertFalse(updated.enabled)
  }

  func testUpsertRejectsNonDominatingVersionWithObservedFloor() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      let created = try upsert(db, habitId: "h1", time: "08:00", enabled: true)

      XCTAssertThrowsError(
        try upsert(
          db, policyId: created.id, habitId: "h1", time: "09:30", enabled: false,
          version: Self.dummyVersion, now: "2026-03-29T10:00:00Z")
      ) { error in
        guard
          case let StoreError.versionSuperseded(
            entityType, entityId, attemptedVersion, existingVersion) = error
        else {
          return XCTFail("expected versionSuperseded, got \(error)")
        }
        XCTAssertEqual(entityType, "habit_reminder_policy")
        XCTAssertEqual(entityId, created.id)
        XCTAssertEqual(attemptedVersion, Self.dummyVersion)
        XCTAssertEqual(existingVersion, Self.dummyVersion)
      }

      let unchanged = try XCTUnwrap(
        HabitReminderOps.loadPolicyById(db, policyId: created.id))
      XCTAssertEqual(unchanged.reminderTime, "08:00")
      XCTAssertTrue(unchanged.enabled)
    }
  }

  func testUpsertRejectsInvalidTime() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      XCTAssertThrowsError(try upsert(db, habitId: "h1", time: "25:00", enabled: true)) {
        XCTAssertTrue("\($0)".contains("invalid reminder_time"))
      }
    }
  }

  func testUpsertRejectsMissingHabit() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(try upsert(db, habitId: "missing", time: "08:00", enabled: true)) {
        guard case StoreError.notFound(let entity, let id) = $0 else {
          return XCTFail("expected notFound, got \($0)")
        }
        XCTAssertEqual(entity, "habit")
        XCTAssertEqual(id, "missing")
      }
    }
  }

  func testUpsertRejectsEmptyHabitId() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(try upsert(db, habitId: "   ", time: "08:00", enabled: true)) {
        XCTAssertTrue("\($0)".contains("habit_id must not be empty"))
      }
    }
  }

  func testUpsertAllowsMultipleSlotsForOneHabit() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      let first = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      let second = try upsert(
        db, habitId: "h1", time: "18:30", enabled: false, version: Self.v2,
        now: "2026-03-29T09:05:00Z")
      XCTAssertNotEqual(first.id, second.id)
      let count = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM habit_reminder_policies WHERE habit_id = 'h1'")
      XCTAssertEqual(count, 2)
    }
  }

  func testUpsertRejectsDuplicateTimeForSameHabit() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      _ = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      XCTAssertThrowsError(
        try upsert(
          db, habitId: "h1", time: "08:00", enabled: false, version: Self.v2,
          now: "2026-03-29T09:05:00Z")
      ) {
        XCTAssertTrue("\($0)".contains("already has a reminder slot at 08:00"))
      }
    }
  }

  func testUpsertRejectsCrossHabitSlotUpdates() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      try seedHabit(db, id: "h2", name: "Read")
      let created = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      XCTAssertThrowsError(
        try upsert(
          db, policyId: created.id, habitId: "h2", time: "09:00", enabled: false,
          version: Self.v2, now: "2026-03-29T10:00:00Z")
      ) {
        XCTAssertTrue("\($0)".contains("belongs to a different habit"))
      }
    }
  }

  func testUpsertRejectsDuplicateTimeOnUpdate() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      _ = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      let second = try upsert(
        db, habitId: "h1", time: "18:30", enabled: true, version: Self.v2,
        now: "2026-03-29T09:05:00Z")
      XCTAssertThrowsError(
        try upsert(
          db, policyId: second.id, habitId: "h1", time: "08:00", enabled: false,
          version: Self.v3, now: "2026-03-29T10:00:00Z")
      ) {
        XCTAssertTrue("\($0)".contains("already has a reminder slot at 08:00"))
      }
    }
  }

  func testUpsertTreatsBlankIdAsNewSlot() throws {
    let store = try WorkflowTestSupport.freshStore()
    let created = try store.writer.write { db -> HabitReminderOps.HabitReminderPolicyRow in
      try seedHabit(db, id: "h1", name: "Meditate")
      return try upsert(db, policyId: "   ", habitId: "h1", time: "07:15", enabled: true)
    }
    XCTAssertFalse(created.id.trimmingCharacters(in: .whitespaces).isEmpty)
    XCTAssertEqual(created.reminderTime, "07:15")
  }

  func testDeleteExistingPolicy() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      let created = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      let result = try HabitReminderOps.deleteHabitReminderPolicy(db, policyId: created.id)
      XCTAssertTrue(result.deleted)
      let count = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM habit_reminder_policies WHERE id = ?",
        arguments: [created.id])
      XCTAssertEqual(count, 0)
    }
  }

  func testDeleteNonexistentPolicyReturnsFalse() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      let result = try HabitReminderOps.deleteHabitReminderPolicy(db, policyId: "nonexistent")
      XCTAssertFalse(result.deleted)
    }
  }

  func testListPoliciesOrdered() throws {
    let store = try WorkflowTestSupport.freshStore()
    let policies = try store.writer.write { db -> [HabitReminderOps.HabitReminderPolicyRow] in
      try seedHabit(db, id: "h1", name: "Zzz Sleep")
      try seedHabit(db, id: "h2", name: "Aaa Meditate")
      _ = try upsert(db, habitId: "h1", time: "22:00", enabled: true)
      _ = try upsert(
        db, habitId: "h2", time: "06:00", enabled: true, version: Self.v2,
        now: "2026-03-29T09:05:00Z")
      return try HabitReminderOps.listAllPolicies(db)
    }
    XCTAssertEqual(policies.count, 2)
    XCTAssertEqual(policies[0].habitName, "Aaa Meditate")
    XCTAssertEqual(policies[1].habitName, "Zzz Sleep")
  }

  // MARK: - Armed record replace

  private func armedAt(_ db: Database, _ policyId: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT last_armed_at FROM habit_reminder_delivery_state WHERE policy_id = ?",
      arguments: [policyId])
  }

  func testReplaceArmedStampsMappedAndClearsUnmapped() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      let p1 = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      let p2 = try upsert(
        db, habitId: "h1", time: "20:00", enabled: true, version: Self.v2,
        now: "2026-03-29T09:05:00Z")

      try HabitReminderOps.replaceHabitRemindersArmed(
        db,
        armedThroughByPolicy: [
          p1.id: "2026-03-30T08:00:00.000Z", p2.id: "2026-03-30T20:00:00.000Z",
        ],
        now: "2026-03-29T10:00:00.000Z")
      XCTAssertEqual(try armedAt(db, p1.id), "2026-03-30T08:00:00.000Z")
      XCTAssertEqual(try armedAt(db, p2.id), "2026-03-30T20:00:00.000Z")

      // Next pass drops p2's OS request (budgeted out): its stamp clears,
      // p1's advances.
      try HabitReminderOps.replaceHabitRemindersArmed(
        db, armedThroughByPolicy: [p1.id: "2026-03-31T08:00:00.000Z"],
        now: "2026-03-30T10:00:00.000Z")
      XCTAssertEqual(try armedAt(db, p1.id), "2026-03-31T08:00:00.000Z")
      XCTAssertNil(try armedAt(db, p2.id))
    }
  }

  func testReplaceArmedWithEmptyMapClearsAllAndKeepsDeliveredStamp() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try seedHabit(db, id: "h1", name: "Meditate")
      let p1 = try upsert(db, habitId: "h1", time: "08:00", enabled: true)
      try HabitReminderOps.replaceHabitRemindersArmed(
        db, armedThroughByPolicy: [p1.id: "2026-03-30T08:00:00.000Z"],
        now: "2026-03-29T10:00:00.000Z")
      try HabitReminderOps.markHabitReminderDelivered(
        db, policyId: p1.id, deliveredAt: "2026-03-30T08:00:00.000Z",
        now: "2026-03-30T08:05:00.000Z")

      // Permission revoked: the replace pass arms nothing, the armed stamp
      // clears, but the historical delivered stamp survives for the debounce.
      try HabitReminderOps.replaceHabitRemindersArmed(
        db, armedThroughByPolicy: [:], now: "2026-03-30T09:00:00.000Z")
      XCTAssertNil(try armedAt(db, p1.id))
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT last_delivered_at FROM habit_reminder_delivery_state WHERE policy_id = ?",
          arguments: [p1.id]),
        "2026-03-30T08:00:00.000Z")
    }
  }
}
