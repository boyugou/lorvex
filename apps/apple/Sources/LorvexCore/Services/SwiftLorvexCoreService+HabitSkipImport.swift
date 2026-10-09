import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore

extension SwiftLorvexCoreService {
  public func importHabitSkip(habitID: String, skip: ExportHabitSkip) async throws {
    try Self.validateImportedHabitSkip(habitID: habitID, skip: skip)
    try withWrite { db, hlc, deviceId in
      try self.upsertImportedHabitSkipInTx(
        db, hlc: hlc, deviceId: deviceId, habitID: habitID, skip: skip)
    }
  }

  /// Upsert one imported skipped day and enqueue its edge sync envelope, inside
  /// the caller's transaction. The caller has already run
  /// ``validateImportedHabitSkip(habitID:skip:)``. Shared with the transactional
  /// habit-record importer so skipped days commit atomically with their parent
  /// habit.
  func upsertImportedHabitSkipInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, habitID: String, skip: ExportHabitSkip
  ) throws {
    guard try Self.habitColumnRow(db, id: habitID) != nil else {
      throw LorvexCoreError.notFound(entity: .habit, id: habitID)
    }
    let now = SyncTimestampFormat.syncTimestampNow()
    let createdAt = try Self.canonicalImportTimestamp(
      skip.createdAt, field: "habit skip createdAt", fallback: now)
    let updatedAt = try Self.canonicalImportTimestamp(
      skip.updatedAt, field: "habit skip updatedAt", fallback: createdAt)
    let entityId = "\(habitID):\(skip.skippedDate)"
    let existingVersion = try String.fetchOne(
      db,
      sql: "SELECT version FROM habit_skips WHERE habit_id = ? AND skipped_date = ?",
      arguments: [habitID, skip.skippedDate])
    let version = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityKind.habitSkip.asString, entityId: entityId)
    try db.execute(
      sql: """
        INSERT INTO habit_skips (habit_id, skipped_date, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(habit_id, skipped_date) DO UPDATE SET
          version = excluded.version,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at
        WHERE excluded.version > habit_skips.version
        """,
      arguments: [habitID, skip.skippedDate, version, createdAt, updatedAt])
    if db.changesCount == 0 {
      let observed = try String.fetchOne(
        db,
        sql: "SELECT version FROM habit_skips WHERE habit_id = ? AND skipped_date = ?",
        arguments: [habitID, skip.skippedDate])
      guard let observed else {
        throw StoreError.invariant("habit skip '\(entityId)' vanished during import")
      }
      throw StoreError.versionSuperseded(
        entityType: EntityKind.habitSkip.asString, entityId: entityId,
        attemptedVersion: version, existingVersion: observed)
    }
    try self.enqueueHabitSkipUpsert(
      db, hlc: hlc, deviceId: deviceId, habitId: habitID, skippedDate: skip.skippedDate)
  }

  static func validateImportedHabitSkip(habitID: String, skip: ExportHabitSkip) throws {
    guard !habitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A habit ID is required.")
    }
    if case .failure(let error) = IsoDate.parseIsoDate(skip.skippedDate) {
      throw LorvexCoreError.unsupportedOperation(error.description)
    }
  }
}
