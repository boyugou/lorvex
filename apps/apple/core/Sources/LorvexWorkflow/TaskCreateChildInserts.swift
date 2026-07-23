import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Child-row fan-out after a task row is created: reminders, dependency
/// edges, tag edges. Each helper accumulates into the orchestrator's
/// ``CreateTaskSyncEffects``.
public enum TaskCreateChildInserts {
  /// Insert task-reminder rows. Returns the IDs of the inserted reminders
  /// in input order.
  public static func insertTaskReminders(
    _ db: Database, hlc: HlcSession, taskId: String, reminders: [String]?
  ) throws -> [String] {
    guard let reminders else { return [] }
    guard !reminders.isEmpty else { return [] }
    guard
      let statusRaw = try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?1", arguments: [taskId])
    else {
      throw StoreError.notFound(entity: EntityName.task, id: taskId)
    }
    guard let status = TaskStatus.parse(statusRaw) else {
      throw StoreError.invariant("task \(taskId) has unknown status '\(statusRaw)'")
    }
    guard status.isActive else {
      throw StoreError.validation(
        "active reminders cannot be added to terminal task \(taskId)")
    }
    var timestamps: [String] = []
    timestamps.reserveCapacity(reminders.count)
    for raw in reminders {
      guard let canon = SyncTimestampFormat.canonicalizeRfc3339Instant(raw) else {
        throw StoreError.validation(
          "Invalid reminder timestamp '\(raw)'. Must be a valid RFC 3339 datetime "
            + "(e.g. 2025-12-01T09:00:00Z).")
      }
      timestamps.append(canon)
    }
    let now = SyncTimestampFormat.syncTimestampNow()
    var createdIds: [String] = []
    createdIds.reserveCapacity(timestamps.count)
    for timestamp in timestamps {
      let reminderId = EntityID.newEntityIDString()
      let version = hlc.nextVersionString()
      let (originalLocalTime, originalTz) = try ReminderAnchor
        .resolveTaskReminderLocalAnchor(db, reminderAtRfc3339: timestamp)
      try db.execute(
        sql:
          "INSERT INTO task_reminders "
          + "(id, task_id, reminder_at, original_local_time, original_tz, version, created_at) "
          + "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        arguments: [
          reminderId, taskId, timestamp, originalLocalTime, originalTz, version, now,
        ])
      createdIds.append(reminderId)
    }
    return createdIds
  }

  /// Insert dependency edges (`taskId → dependsOn`). Returns the
  /// `"task:dep"` upsert keys for each edge.
  public static func insertDependencyEdges(
    _ db: Database, hlc: HlcSession, taskId: TaskId, dependsOn: [String]
  ) throws -> [String] {
    if dependsOn.isEmpty { return [] }
    let version = hlc.nextVersionString()
    let now = SyncTimestampFormat.syncTimestampNow()
    let dependsOnTyped = dependsOn.map { TaskId(trusted: $0) }
    try TaskRepo.Dependencies.insertDependencyEdgesBatchInner(
      db, taskId: taskId, dependsOnIds: dependsOnTyped,
      version: version, now: now)
    return dependsOn.map { "\(taskId.asString):\($0)" }
  }

  /// Insert tag edges. Resolves-or-creates each tag, then writes the
  /// `task_tags` edge row. Returns both newly-created tag IDs and the
  /// `"task:tag"` edge upsert keys.
  public static func insertTaskTags(
    _ db: Database, hlc: HlcSession, taskId: TaskId, tags: [String]
  ) throws -> TaskTagSyncEffects {
    if tags.isEmpty { return TaskTagSyncEffects() }
    let now = SyncTimestampFormat.syncTimestampNow()
    var effects = TaskTagSyncEffects()
    for tag in tags {
      let tagVersion = hlc.nextVersionString()
      let (tagId, created) = try TagRepo.resolveOrCreateTag(
        db, displayName: tag, version: tagVersion, now: now)
      if created {
        effects.tagUpsertIds.append(tagId)
      }
      let edgeVersion = hlc.nextVersionString()
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) "
          + "VALUES (?1, ?2, ?3, ?4)",
        arguments: [taskId.asString, tagId, edgeVersion, now])
      effects.taskTagEdgeUpsertIds.append("\(taskId.asString):\(tagId)")
    }
    return effects
  }
}
