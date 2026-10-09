import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Convergence coverage for the `habit_skip` composite edge: per-edge
/// last-writer-wins by the edge's own version, tombstone protection against a
/// stale re-upsert, and the re-pointing of a merged duplicate habit's skips.
final class ApplyHabitSkipTests: XCTestCase {

  // winnerHabit < loserHabit lexicographically → min-id merge keeps the winner.
  private let winnerHabit = "00000000-0000-7000-8000-000000000001"
  private let loserHabit = "00000000-0000-7000-8000-000000000002"
  private let date = "2026-04-01"
  private let otherDate = "2026-04-02"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func habitEnvelope(_ id: String, _ version: String) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "name": .string("Cardio"),
        "frequency_type": .string("daily"),
        "target_count": .int(1),
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .habit, entityId: id, operation: .upsert, version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: payload,
      deviceId: "device-remote")
  }

  private func skipEnvelope(
    _ habitId: String, on day: String, version: String, createdAt: String = "2026-04-01T08:00:00Z"
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "habit_id": .string(habitId),
        "skipped_date": .string(day),
        "created_at": .string(createdAt),
        "updated_at": .string(createdAt),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .habitSkip, entityId: "\(habitId):\(day)", operation: .upsert,
      version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "device-remote")
  }

  private func skipDeleteEnvelope(
    _ habitId: String, on day: String, version: String
  ) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .habitSkip, entityId: "\(habitId):\(day)", operation: .delete,
      version: try Hlc.parse(version), payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{}", deviceId: "device-remote")
  }

  private func apply(_ db: Database, _ envelope: SyncEnvelope) throws {
    let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
    if case let .deferred(reason) = result {
      try PendingInboxDrain.enqueueDeferred(db, envelope: envelope, reason: reason)
    }
  }

  /// `skipped_date → created_at` for one habit.
  private func createdAtBySkippedDate(_ db: Database, habit: String) throws -> [String: String] {
    var rows: [String: String] = [:]
    for row in try Row.fetchAll(
      db, sql: "SELECT skipped_date, created_at FROM habit_skips WHERE habit_id = ?",
      arguments: [habit])
    {
      rows[row["skipped_date"]] = row["created_at"] as String
    }
    return rows
  }

  private func versionBySkippedDate(_ db: Database, habit: String) throws -> [String: String] {
    var rows: [String: String] = [:]
    for row in try Row.fetchAll(
      db, sql: "SELECT skipped_date, version FROM habit_skips WHERE habit_id = ?",
      arguments: [habit])
    {
      rows[row["skipped_date"]] = row["version"] as String
    }
    return rows
  }

  private let habitVersion = "1711000001000_0000_1111000011110000"

  // MARK: - Per-edge last-writer-wins

  func testNewerUpsertReplacesAndOlderUpsertIsIgnored() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.apply(db, try self.habitEnvelope(self.winnerHabit, self.habitVersion))
      try self.apply(
        db,
        try self.skipEnvelope(
          self.winnerHabit, on: self.date, version: "1711000005000_0000_aaaa0000aaaa0000",
          createdAt: "2026-04-01T08:00:00Z"))
      try self.apply(
        db,
        try self.skipEnvelope(
          self.winnerHabit, on: self.date, version: "1711000002000_0000_bbbb0000bbbb0000",
          createdAt: "2026-04-01T09:00:00Z"))
      XCTAssertEqual(
        try self.createdAtBySkippedDate(db, habit: self.winnerHabit),
        [self.date: "2026-04-01T08:00:00.000Z"],
        "an older edge must not overwrite the newer one")

      try self.apply(
        db,
        try self.skipEnvelope(
          self.winnerHabit, on: self.date, version: "1711000009000_0000_cccc0000cccc0000",
          createdAt: "2026-04-01T10:00:00Z"))
      XCTAssertEqual(
        try self.createdAtBySkippedDate(db, habit: self.winnerHabit),
        [self.date: "2026-04-01T10:00:00.000Z"])
    }
  }

  // MARK: - Delete

  func testDeleteRemovesTheSkipBlocksAStaleUpsertAndAllowsANewerOne() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let vSkip = "1711000002000_0000_aaaa0000aaaa0000"
      let vDelete = "1711000004000_0000_bbbb0000bbbb0000"
      let vAgain = "1711000006000_0000_cccc0000cccc0000"
      try self.apply(db, try self.habitEnvelope(self.winnerHabit, self.habitVersion))
      try self.apply(db, try self.skipEnvelope(self.winnerHabit, on: self.date, version: vSkip))
      try self.apply(
        db, try self.skipDeleteEnvelope(self.winnerHabit, on: self.date, version: vDelete))
      XCTAssertEqual(try self.createdAtBySkippedDate(db, habit: self.winnerHabit), [:])

      try self.apply(db, try self.skipEnvelope(self.winnerHabit, on: self.date, version: vSkip))
      XCTAssertEqual(
        try self.createdAtBySkippedDate(db, habit: self.winnerHabit), [:],
        "a skip older than the delete must not come back")

      try self.apply(db, try self.skipEnvelope(self.winnerHabit, on: self.date, version: vAgain))
      XCTAssertEqual(
        Array(try self.createdAtBySkippedDate(db, habit: self.winnerHabit).keys), [self.date],
        "skipping the day again after the delete is a newer decision and must apply")
    }
  }

  // MARK: - Duplicate-habit merge

  /// A duplicate habit's skips re-point onto the merge winner as a union, each
  /// keeping the version it was authored with, so a stale edge that arrives after
  /// the merge cannot regress a re-pointed skip.
  func testMergeRepointsTheLosersSkipsAndKeepsTheirAuthoredVersions() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let vFirst = "1711000009000_0000_3333000033330000"
      let vSecond = "1711000008000_0000_4444000044440000"
      try self.apply(db, try self.habitEnvelope(self.loserHabit, self.habitVersion))
      try self.apply(
        db,
        try self.skipEnvelope(
          self.loserHabit, on: self.date, version: vFirst, createdAt: "2026-04-01T08:00:00Z"))
      try self.apply(
        db, try self.skipEnvelope(self.loserHabit, on: self.otherDate, version: vSecond))
      // The incoming winner habit (smaller id) collides on lookup key and merges
      // the loser into it.
      try self.apply(db, try self.habitEnvelope(self.winnerHabit, self.habitVersion))

      XCTAssertEqual(
        try self.versionBySkippedDate(db, habit: self.winnerHabit),
        [self.date: vFirst, self.otherDate: vSecond],
        "both skipped days re-point onto the winner with their authored versions")
      XCTAssertEqual(try self.versionBySkippedDate(db, habit: self.loserHabit), [:])

      // A stale pre-merge edge: newer than the merge stamp, older than the
      // re-pointed skip's own version.
      try self.apply(
        db,
        try self.skipEnvelope(
          self.winnerHabit, on: self.date, version: "1711000005000_0000_5555000055550000",
          createdAt: "2026-04-01T23:00:00Z"))
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(
        try self.createdAtBySkippedDate(db, habit: self.winnerHabit)[self.date],
        "2026-04-01T08:00:00.000Z",
        "a stale edge must not overwrite a re-pointed skip whose version dominates it")
    }
  }

  /// The same day skipped on both duplicates keeps the row with the greater
  /// authored version, whichever habit it was authored against.
  func testMergeKeepsTheGreaterVersionWhenBothHabitsSkippedTheSameDay() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.apply(db, try self.habitEnvelope(self.winnerHabit, self.habitVersion))
      try self.apply(
        db,
        try self.skipEnvelope(
          self.winnerHabit, on: self.date, version: "1711000002000_0000_aaaa0000aaaa0000",
          createdAt: "2026-04-01T08:00:00Z"))
      // A second habit with the same name merges into the winner (smaller id),
      // carrying a newer skip for the same day.
      try self.apply(db, try self.habitEnvelope(self.loserHabit, self.habitVersion))
      try self.apply(
        db,
        try self.skipEnvelope(
          self.loserHabit, on: self.date, version: "1711000007000_0000_bbbb0000bbbb0000",
          createdAt: "2026-04-01T12:00:00Z"))
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)

      XCTAssertEqual(
        try self.createdAtBySkippedDate(db, habit: self.winnerHabit),
        [self.date: "2026-04-01T12:00:00.000Z"])
      XCTAssertEqual(try self.createdAtBySkippedDate(db, habit: self.loserHabit), [:])
    }
  }
}
