import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore

extension SwiftLorvexCoreService {
  public func importHabitCompletion(
    habitID: String,
    completion: ExportHabitCompletion
  ) async throws {
    try Self.validateImportedHabitCompletion(habitID: habitID, completion: completion)
    try withWrite { db, hlc, deviceId in
      try self.upsertImportedHabitCompletionInTx(
        db, hlc: hlc, deviceId: deviceId, habitID: habitID, completion: completion)
    }
  }

  /// Upsert one imported habit completion and enqueue its edge sync envelope,
  /// inside the caller's transaction. The caller has already run
  /// ``validateImportedHabitCompletion(habitID:completion:)``. Shared with the
  /// transactional habit-record importer so completions commit atomically with
  /// their parent habit.
  func upsertImportedHabitCompletionInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, habitID: String,
    completion: ExportHabitCompletion
  ) throws {
    guard try Self.habitColumnRow(db, id: habitID) != nil else {
      throw LorvexCoreError.notFound(entity: .habit, id: habitID)
    }
    let now = SyncTimestampFormat.syncTimestampNow()
    let createdAt = try Self.canonicalImportTimestamp(
      completion.createdAt, field: "habit completion createdAt", fallback: now)
    let updatedAt = try Self.canonicalImportTimestamp(
      completion.updatedAt, field: "habit completion updatedAt", fallback: createdAt)
    let entityId = "\(habitID):\(completion.completedDate)"
    let existingVersion = try String.fetchOne(
      db,
      sql: "SELECT version FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
      arguments: [habitID, completion.completedDate])
    let version = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityKind.habitCompletion.asString, entityId: entityId)
    try db.execute(
      sql: """
        INSERT INTO habit_completions
          (habit_id, completed_date, value, note, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(habit_id, completed_date) DO UPDATE SET
          value = excluded.value,
          note = excluded.note,
          version = excluded.version,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at
        WHERE excluded.version > habit_completions.version
        """,
      arguments: [
        habitID, completion.completedDate, completion.value, completion.note,
        version, createdAt, updatedAt,
      ])
    if db.changesCount == 0 {
      let observed = try String.fetchOne(
        db,
        sql: "SELECT version FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
        arguments: [habitID, completion.completedDate])
      guard let observed else {
        throw StoreError.invariant("habit completion '\(entityId)' vanished during import")
      }
      throw StoreError.versionSuperseded(
        entityType: EntityKind.habitCompletion.asString, entityId: entityId,
        attemptedVersion: version, existingVersion: observed)
    }
    try self.enqueueHabitCompletionUpsert(
      db, hlc: hlc, deviceId: deviceId, habitId: habitID,
      completedDate: completion.completedDate)
  }

  static func validateImportedHabitCompletion(
    habitID: String,
    completion: ExportHabitCompletion
  ) throws {
    guard !habitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A habit ID is required.")
    }
    if case .failure(let error) = IsoDate.parseIsoDate(completion.completedDate) {
      throw LorvexCoreError.unsupportedOperation(error.description)
    }
    guard completion.value > 0 else {
      throw LorvexCoreError.unsupportedOperation(
        "Habit completion value must be positive for \(habitID):\(completion.completedDate).")
    }
  }
}
