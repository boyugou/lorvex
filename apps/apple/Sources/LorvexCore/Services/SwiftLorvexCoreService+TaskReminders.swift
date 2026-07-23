import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import LorvexWorkflow

extension SwiftLorvexCoreService {
  // MARK: - Reminders

  public func addTaskReminder(taskID: LorvexTask.ID, reminderAt: String) async throws -> LorvexTask {
    try withWrite { db, hlc, deviceId in
      guard try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: taskID)) != nil else {
        throw LorvexCoreError.taskNotFound
      }
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      // Reuse the canonical child-insert (canonicalizes the RFC 3339 instant and
      // resolves the local-time anchor) so the row shape matches create-time.
      let reminderIds = try TaskCreateChildInserts.insertTaskReminders(
        db, hlc: hlc, taskId: taskID, reminders: [reminderAt])
      try self.enqueueUpserts(
        db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityIds: reminderIds)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "add_reminder", entityId: taskID,
          summary: "Added reminder to '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func removeTaskReminder(taskID: LorvexTask.ID, reminderID: TaskReminder.ID) async throws
    -> LorvexTask
  {
    try withWrite { db, hlc, deviceId in
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      let now = SyncTimestampFormat.syncTimestampNow()
      guard
        let reminderFloor = try String.fetchOne(
          db,
          sql: "SELECT version FROM task_reminders WHERE id = ? AND task_id = ?",
          arguments: [reminderID, taskID])
      else {
        return try SwiftLorvexTaskDeserializers.task(before)
      }
      let reminderVersion = try VersionFloor.mint(
        hlc: hlc,
        existingVersion: reminderFloor,
        entityType: EntityName.taskReminder,
        entityId: reminderID)
      try db.execute(
        sql: """
          UPDATE task_reminders SET cancelled_at = ?, version = ?
          WHERE id = ? AND task_id = ? AND version = ?
          """,
        arguments: [now, reminderVersion, reminderID, taskID, reminderFloor])
      guard db.changesCount > 0 else {
        let winner = try String.fetchOne(
          db, sql: "SELECT version FROM task_reminders WHERE id = ?", arguments: [reminderID])
        guard let winner else {
          throw StoreError.notFound(entity: EntityName.taskReminder, id: reminderID)
        }
        throw StoreError.versionSuperseded(
          entityType: EntityName.taskReminder,
          entityId: reminderID,
          attemptedVersion: reminderVersion,
          existingVersion: winner)
      }
      // The reminder row is cancelled (updated, not removed) → upsert envelope.
      try self.enqueueUpsert(
        db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityId: reminderID)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "remove_reminder", entityId: taskID,
          summary: "Removed reminder from '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }

  public func setTaskReminders(taskID: LorvexTask.ID, reminderAts: [String]) async throws
    -> LorvexTask
  {
    try withWrite { db, hlc, deviceId in
      guard try TaskRepo.Read.getTask(db, taskId: TaskId(trusted: taskID)) != nil else {
        throw LorvexCoreError.taskNotFound
      }
      let before = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      let now = SyncTimestampFormat.syncTimestampNow()
      // Replace-all: cancel every active reminder, then insert the new set via
      // the canonical child-insert helper.
      let activeRows = try Row.fetchAll(
        db,
        sql: """
          SELECT id, version FROM task_reminders
          WHERE task_id = ? AND cancelled_at IS NULL AND dismissed_at IS NULL
          ORDER BY id
          """,
        arguments: [taskID])
      var cancelledIds: [String] = []
      cancelledIds.reserveCapacity(activeRows.count)
      for row in activeRows {
        let reminderID: String = row["id"]
        let existingVersion: String = row["version"]
        let version = try VersionFloor.mint(
          hlc: hlc,
          existingVersion: existingVersion,
          entityType: EntityName.taskReminder,
          entityId: reminderID)
        try db.execute(
          sql: """
            UPDATE task_reminders SET cancelled_at = ?, version = ?
            WHERE id = ? AND task_id = ? AND version = ?
            """,
          arguments: [now, version, reminderID, taskID, existingVersion])
        guard db.changesCount > 0 else {
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
        cancelledIds.append(reminderID)
      }
      let insertedIds = try TaskCreateChildInserts.insertTaskReminders(
        db, hlc: hlc, taskId: taskID, reminders: reminderAts)
      // Cancelled rows are updated (not deleted) and inserted rows are new → both upsert.
      try self.enqueueUpserts(
        db, hlc: hlc, deviceId: deviceId, kind: .taskReminder,
        entityIds: cancelledIds + insertedIds)
      let after = try TaskResponse.loadEnrichedTaskJSON(db, taskId: TaskId(trusted: taskID))
      try self.writeChangelogRow(
        db,
        ChangelogEntry(
          operation: "set_reminders", entityId: taskID,
          summary: "Set reminders on '\(TaskResponse.taskTitle(after))'",
          before: before, after: after),
        deviceId: deviceId)
      return try SwiftLorvexTaskDeserializers.task(after)
    }
  }
}
