import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  public func importTaskChecklistItem(
    taskID: String,
    item: ExportChecklistItem
  ) async throws {
    let itemID = try Self.requiredTrimmed(item.id, field: "checklist id")
    let text = try Self.requiredTrimmed(item.text, field: "checklist text")
    let position = max(0, item.position ?? 0)
    let now = SyncTimestampFormat.syncTimestampNow()
    try withWrite { db, hlc, deviceId in
      guard try Self.taskExists(db, taskID: taskID) else { throw LorvexCoreError.taskNotFound }
      try self.upsertImportedChecklistItemRow(
        db, hlc: hlc, deviceId: deviceId, taskID: taskID, itemID: itemID, position: position,
        text: text, completedAt: item.completedAt, createdAt: item.createdAt ?? now,
        updatedAt: item.updatedAt ?? now)
    }
  }

  public func importTaskReminder(
    taskID: String,
    reminder: ExportTaskReminder
  ) async throws {
    let reminderID = try Self.requiredTrimmed(reminder.id, field: "reminder id")
    let reminderAt = try Self.requiredTrimmed(reminder.reminderAt, field: "reminderAt")
    let now = SyncTimestampFormat.syncTimestampNow()
    try withWrite { db, hlc, deviceId in
      guard try Self.taskExists(db, taskID: taskID) else { throw LorvexCoreError.taskNotFound }
      try self.upsertImportedReminderRow(
        db, hlc: hlc, deviceId: deviceId, taskID: taskID, reminderID: reminderID,
        reminderAt: reminderAt, dismissedAt: reminder.dismissedAt,
        cancelledAt: reminder.cancelledAt, createdAt: reminder.createdAt ?? now,
        originalLocalTime: reminder.originalLocalTime, originalTz: reminder.originalTz)
    }
  }

  /// Upsert one imported checklist row and enqueue its sync envelope inside the
  /// caller's transaction. The child has its own sync record; importing it does
  /// not manufacture an unrelated task-register write. Shared by
  /// ``importTaskChecklistItem(taskID:item:)`` and the transactional task-record
  /// importer so a checklist restore commits atomically with its parent task.
  func upsertImportedChecklistItemRow(
    _ db: Database, hlc: HlcSession, deviceId: String, taskID: String, itemID: String,
    position: Int, text: String, completedAt: String?, createdAt: String, updatedAt: String
  ) throws {
    try Self.requireCanonicalImportedUUID(itemID, field: "checklist ID")
    try Self.assertImportedChildIdentityCanWrite(
      db, table: "task_checklist_items", ownerColumn: "task_id",
      expectedOwnerID: taskID, entityType: EntityName.taskChecklistItem,
      entityID: itemID, field: "checklist ID")
    let canonicalCompletedAt = try Self.canonicalOptionalImportTimestamp(
      completedAt, field: "checklist completedAt")
    let canonicalCreatedAt = try Self.canonicalRequiredImportTimestamp(
      createdAt, field: "checklist createdAt")
    let canonicalUpdatedAt = try Self.canonicalRequiredImportTimestamp(
      updatedAt, field: "checklist updatedAt")
    let existingVersion = try String.fetchOne(
      db, sql: "SELECT version FROM task_checklist_items WHERE id = ?", arguments: [itemID])
    let version = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: existingVersion,
      entityType: EntityName.taskChecklistItem,
      entityId: itemID)
    try db.execute(
      sql: """
        INSERT INTO task_checklist_items (
          id, task_id, position, text, completed_at, version, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          task_id = excluded.task_id,
          position = excluded.position,
          text = excluded.text,
          completed_at = excluded.completed_at,
          version = excluded.version,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at
        WHERE excluded.version > task_checklist_items.version
        """,
      arguments: [
        itemID, taskID, position, text, canonicalCompletedAt,
        version, canonicalCreatedAt, canonicalUpdatedAt,
      ])
    if db.changesCount == 0 {
      let winner = try String.fetchOne(
        db, sql: "SELECT version FROM task_checklist_items WHERE id = ?", arguments: [itemID])
      guard let winner else {
        throw StoreError.notFound(entity: EntityName.taskChecklistItem, id: itemID)
      }
      throw StoreError.versionSuperseded(
        entityType: EntityName.taskChecklistItem,
        entityId: itemID,
        attemptedVersion: version,
        existingVersion: winner)
    }
    try self.enqueueUpsert(
      db, hlc: hlc, deviceId: deviceId, kind: .taskChecklistItem, entityId: itemID)
  }

  /// Upsert one imported reminder row and enqueue its sync envelope inside the
  /// caller's transaction. The child has its own sync record; importing it does
  /// not manufacture an unrelated task-register write. Shared by
  /// ``importTaskReminder(taskID:reminder:)`` and the transactional task-record
  /// importer so a reminder restore commits atomically with its parent task.
  func upsertImportedReminderRow(
    _ db: Database, hlc: HlcSession, deviceId: String, taskID: String, reminderID: String,
    reminderAt: String, dismissedAt: String?, cancelledAt: String?, createdAt: String,
    originalLocalTime: String?, originalTz: String?
  ) throws {
    try Self.requireCanonicalImportedUUID(reminderID, field: "reminder ID")
    try Self.assertImportedChildIdentityCanWrite(
      db, table: "task_reminders", ownerColumn: "task_id",
      expectedOwnerID: taskID, entityType: EntityName.taskReminder,
      entityID: reminderID, field: "reminder ID")
    let canonicalReminderAt = try Self.canonicalRequiredImportTimestamp(
      reminderAt, field: "reminderAt")
    let canonicalDismissedAt = try Self.canonicalOptionalImportTimestamp(
      dismissedAt, field: "reminder dismissedAt")
    let canonicalCancelledAt = try Self.canonicalOptionalImportTimestamp(
      cancelledAt, field: "reminder cancelledAt")
    let canonicalCreatedAt = try Self.canonicalRequiredImportTimestamp(
      createdAt, field: "reminder createdAt")
    if canonicalDismissedAt == nil, canonicalCancelledAt == nil {
      guard
        let statusRaw = try String.fetchOne(
          db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [taskID])
      else {
        throw StoreError.notFound(entity: EntityName.task, id: taskID)
      }
      guard let status = TaskStatus.parse(statusRaw) else {
        throw StoreError.invariant("task \(taskID) has unknown status '\(statusRaw)'")
      }
      guard status.isActive else {
        throw StoreError.validation(
          "an active imported reminder cannot belong to terminal task \(taskID)")
      }
    }
    let existingVersion = try String.fetchOne(
      db, sql: "SELECT version FROM task_reminders WHERE id = ?", arguments: [reminderID])
    let version = try VersionFloor.mint(
      hlc: hlc,
      existingVersion: existingVersion,
      entityType: EntityName.taskReminder,
      entityId: reminderID)
    try db.execute(
      sql: """
        INSERT INTO task_reminders (
          id, task_id, reminder_at, dismissed_at, cancelled_at, version,
          created_at, original_local_time, original_tz
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          task_id = excluded.task_id,
          reminder_at = excluded.reminder_at,
          dismissed_at = excluded.dismissed_at,
          cancelled_at = excluded.cancelled_at,
          version = excluded.version,
          created_at = excluded.created_at,
          original_local_time = excluded.original_local_time,
          original_tz = excluded.original_tz
        WHERE excluded.version > task_reminders.version
        """,
      arguments: [
        reminderID, taskID, canonicalReminderAt, canonicalDismissedAt, canonicalCancelledAt,
        version, canonicalCreatedAt, originalLocalTime, originalTz,
      ])
    if db.changesCount == 0 {
      let winner = try String.fetchOne(
        db, sql: "SELECT version FROM task_reminders WHERE id = ?", arguments: [reminderID])
      guard let winner else {
        throw StoreError.notFound(entity: EntityName.taskReminder, id: reminderID)
      }
      throw StoreError.versionSuperseded(
        entityType: EntityName.taskReminder,
        entityId: reminderID,
        attemptedVersion: version,
        existingVersion: winner)
    }
    try self.enqueueUpsert(db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityId: reminderID)
  }

  static func requiredTrimmed(_ raw: String?, field: String) throws -> String {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
      throw LorvexCoreError.unsupportedOperation("A \(field) is required.")
    }
    return trimmed
  }

  static func taskExists(_ db: Database, taskID: String) throws -> Bool {
    (try Int.fetchOne(db, sql: "SELECT 1 FROM tasks WHERE id = ?", arguments: [taskID])) != nil
  }
}
