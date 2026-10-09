import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Skipped days for habits over the pure-Swift core.
///
/// A skip sets one habit aside for one day: the day is excused, so it is neither
/// kept nor missed. Each skip is one `habit_skips` row keyed by the habit and the
/// date, synced as a composite edge like a completion. A day holds a check-in or a
/// skip, never both: skipping a day that already has a check-in is rejected, and
/// checking in on a skipped day removes the skip in the same transaction.
extension SwiftLorvexCoreService {

  public func skipHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot {
    try Self.validateCompletionDate(date)
    return try withWrite { db, hlc, deviceId in
      _ = try Self.activeHabitRow(db, id: id)
      guard try Self.habitValueOnDate(db, habitId: id, date: date) == 0 else {
        throw LorvexCoreError.validation(
          field: "date",
          message:
            "The habit was already checked in on \(date). Undo the check-in before skipping the day."
        )
      }
      guard try !Self.habitIsSkipped(db, habitId: id, date: date) else {
        return try Self.loadHabitsSnapshot(db, date: date)
      }
      let version = try VersionFloor.mint(
        hlc: hlc, existingVersion: nil,
        entityType: EntityKind.habitSkip.asString, entityId: "\(id):\(date)")
      let now = SyncTimestampFormat.syncTimestampNow()
      try db.execute(
        sql: """
          INSERT INTO habit_skips (habit_id, skipped_date, version, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [id, date, version, now, now])
      try self.enqueueHabitSkipUpsert(
        db, hlc: hlc, deviceId: deviceId, habitId: id, skippedDate: date)
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "skip", entityType: EntityName.habit, entityId: id,
          summary: "Habit skip: \(id) on \(date)"),
        deviceId: deviceId)
      return try Self.loadHabitsSnapshot(db, date: date)
    }
  }

  public func unskipHabit(id: LorvexHabit.ID, date: String) async throws -> HabitCatalogSnapshot {
    try Self.validateCompletionDate(date)
    return try withWrite { db, hlc, deviceId in
      _ = try Self.activeHabitRow(db, id: id)
      guard
        try self.removeHabitSkipInTx(db, hlc: hlc, deviceId: deviceId, habitId: id, date: date)
      else { return try Self.loadHabitsSnapshot(db, date: date) }
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "unskip", entityType: EntityName.habit, entityId: id,
          summary: "Habit unskip: \(id) on \(date)"),
        deviceId: deviceId)
      return try Self.loadHabitsSnapshot(db, date: date)
    }
  }

  /// Delete the habit's skip row for `date` and enqueue its sync delete, inside
  /// the caller's transaction. Returns whether a row existed. A check-in calls
  /// this so the day it lands on stops being excused.
  @discardableResult
  func removeHabitSkipInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, habitId: String, date: String
  ) throws -> Bool {
    guard
      let existing = try Row.fetchOne(
        db,
        sql: """
          SELECT version, created_at, updated_at FROM habit_skips
          WHERE habit_id = ? AND skipped_date = ?
          """,
        arguments: [habitId, date])
    else { return false }
    let existingVersion: String = existing["version"]
    let payload = PayloadLoaders.habitSkipPayload(
      habitId: habitId, skippedDate: date, version: existingVersion,
      createdAt: existing["created_at"], updatedAt: existing["updated_at"])
    try db.execute(
      sql: "DELETE FROM habit_skips WHERE habit_id = ? AND skipped_date = ?",
      arguments: [habitId, date])
    let entityId = "\(habitId):\(date)"
    let deleteVersion = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityKind.habitSkip.asString, entityId: entityId)
    try OutboxEnqueue.enqueuePayloadDelete(
      db,
      entityType: EntityKind.habitSkip.asString,
      entityId: entityId,
      payload: payload,
      context: OutboxWriteContext(version: deleteVersion, deviceId: deviceId))
    return true
  }
}
