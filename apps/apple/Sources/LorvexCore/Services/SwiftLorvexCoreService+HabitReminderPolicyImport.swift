import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync

extension SwiftLorvexCoreService {
  public func importHabitReminderPolicy(
    habitID: String,
    policy: ExportHabitReminderPolicy
  ) async throws {
    try Self.validateImportedHabitReminderPolicy(habitID: habitID, policy: policy)
    try withWrite { db, hlc, deviceId in
      try self.upsertImportedHabitReminderPolicyInTx(
        db, hlc: hlc, deviceId: deviceId, habitID: habitID, policy: policy)
    }
  }

  /// Upsert one imported habit reminder policy and enqueue its sync envelope,
  /// inside the caller's transaction. The caller has already run
  /// ``validateImportedHabitReminderPolicy(habitID:policy:)``. Shared with the
  /// transactional habit-record importer so policies commit atomically with
  /// their parent habit.
  func upsertImportedHabitReminderPolicyInTx(
    _ db: Database, hlc: HlcSession, deviceId: String, habitID: String,
    policy: ExportHabitReminderPolicy
  ) throws {
    guard try Self.habitColumnRow(db, id: habitID) != nil else {
      throw LorvexCoreError.notFound(entity: .habit, id: habitID)
    }
    try Self.requireCanonicalImportedUUID(policy.id, field: "habit reminder policy ID")
    try Self.assertImportedChildIdentityCanWrite(
      db, table: "habit_reminder_policies", ownerColumn: "habit_id",
      expectedOwnerID: habitID, entityType: EntityName.habitReminderPolicy,
      entityID: policy.id, field: "habit reminder policy ID")
    let now = SyncTimestampFormat.syncTimestampNow()
    let createdAt = try Self.canonicalImportTimestamp(
      policy.createdAt, field: "habit reminder policy createdAt", fallback: now)
    let updatedAt = try Self.canonicalImportTimestamp(
      policy.updatedAt, field: "habit reminder policy updatedAt", fallback: createdAt)
    let existingVersion = try String.fetchOne(
      db, sql: "SELECT version FROM habit_reminder_policies WHERE id = ?", arguments: [policy.id])
    let version = try VersionFloor.mint(
      hlc: hlc, existingVersion: existingVersion,
      entityType: EntityName.habitReminderPolicy, entityId: policy.id)
    try db.execute(
      sql: """
        INSERT INTO habit_reminder_policies
          (id, habit_id, reminder_time, enabled, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          habit_id = excluded.habit_id,
          reminder_time = excluded.reminder_time,
          enabled = excluded.enabled,
          version = excluded.version,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at
        WHERE excluded.version > habit_reminder_policies.version
        """,
      arguments: [
        policy.id, habitID, policy.reminderTime, policy.enabled ? 1 : 0,
        version, createdAt, updatedAt,
      ])
    if db.changesCount == 0 {
      let observed = try String.fetchOne(
        db, sql: "SELECT version FROM habit_reminder_policies WHERE id = ?", arguments: [policy.id])
      guard let observed else {
        throw StoreError.invariant(
          "habit reminder policy '\(policy.id)' vanished during import")
      }
      throw StoreError.versionSuperseded(
        entityType: EntityName.habitReminderPolicy, entityId: policy.id,
        attemptedVersion: version, existingVersion: observed)
    }
    try self.enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .habitReminderPolicy, entityId: policy.id)
  }

  static func validateImportedHabitReminderPolicy(
    habitID: String,
    policy: ExportHabitReminderPolicy
  ) throws {
    guard !habitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A habit ID is required.")
    }
    guard !policy.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A habit reminder policy ID is required.")
    }
    if case .failure(let error) = ValidationFormat.validateTimeFormat(policy.reminderTime) {
      throw LorvexCoreError.unsupportedOperation(error.description)
    }
  }
}
