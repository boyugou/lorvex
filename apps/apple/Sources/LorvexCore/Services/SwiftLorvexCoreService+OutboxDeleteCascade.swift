import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import LorvexWorkflow

/// Pre-delete tombstone enqueues for `SwiftLorvexCoreService`'s outbox flush.
/// SQLite's `ON DELETE CASCADE` silently drops a parent's child/edge rows, and
/// the `OutboxEnqueue` engine ships no cascade tombstone helper for these tables,
/// so the surface scrapes the live rows and enqueues a DELETE per row via the
/// primitives in `+OutboxFlush.swift`. Every entry point MUST run BEFORE the
/// parent DELETE fires.
extension SwiftLorvexCoreService {

  // MARK: - Task permanent-delete child/edge tombstones

  /// Stamp DELETE envelopes for every child + edge row owned by `taskId` BEFORE
  /// the `tasks` DELETE fires its `ON DELETE CASCADE`, then return so the caller
  /// can enqueue the parent `task` delete.
  ///
  /// SQLite cascades silently drop `task_tags`, `task_dependencies`,
  /// `task_calendar_event_links`, `task_reminders`, and `task_checklist_items`
  /// on a parent delete; without an explicit pre-delete tombstone a peer that
  /// missed the parent delete would keep the orphaned child. The engine ships no
  /// `tombstoneXForTaskDelete` cascade helper for these (unlike the
  /// calendar-event / habit cascades), so the surface scrapes the rows and
  /// enqueues a DELETE per row here. MUST run BEFORE the parent `tasks` DELETE.
  func enqueueTaskDeleteCascade(
    _ db: Database, hlc: HlcSession, deviceId: String, taskId: String
  ) throws {
    // task_tags (composite PK {task_id}:{tag_id})
    let tagRows = try Row.fetchAll(
      db, sql: "SELECT task_id, tag_id, version, created_at FROM task_tags WHERE task_id = ?",
      arguments: [taskId])
    for row in tagRows {
      let tId: String = row["task_id"], tagId: String = row["tag_id"]
      let payload = PayloadLoaders.taskTagPayload(
        taskId: tId, tagId: tagId, version: row["version"], createdAt: row["created_at"])
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskTag, entityId: "\(tId):\(tagId)",
        payload: payload)
    }

    // task_dependencies (composite PK {task_id}:{depends_on_task_id}). The task
    // can be either side of an edge.
    let depRows = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, depends_on_task_id, version, created_at FROM task_dependencies
        WHERE task_id = ? OR depends_on_task_id = ?
        """,
      arguments: [taskId, taskId])
    for row in depRows {
      let tId: String = row["task_id"], depId: String = row["depends_on_task_id"]
      let payload = DependencyEdge.buildDeletePayload(
        taskId: tId, dependsOnTaskId: depId, version: row["version"],
        createdAt: row["created_at"])
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskDependency,
        entityId: DependencyEdge.encodeEntityId(taskId: tId, dependsOnTaskId: depId),
        payload: payload)
    }

    // task_calendar_event_links (composite PK {task_id}:{calendar_event_id}).
    let linkRows = try Row.fetchAll(
      db,
      sql: """
        SELECT task_id, calendar_event_id, created_at, updated_at, version
        FROM task_calendar_event_links WHERE task_id = ?
        """,
      arguments: [taskId])
    for row in linkRows {
      let tId: String = row["task_id"], eventId: String = row["calendar_event_id"]
      let payload = PayloadLoaders.taskCalendarEventLinkPayload(
        taskId: tId, calendarEventId: eventId, version: row["version"],
        createdAt: row["created_at"], updatedAt: row["updated_at"])
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskCalendarEventLink,
        entityId: "\(tId):\(eventId)", payload: payload)
    }

    // task_reminders (simple PK) — independent synced children.
    let reminderIds = try String.fetchAll(
      db, sql: "SELECT id FROM task_reminders WHERE task_id = ?", arguments: [taskId])
    for id in reminderIds {
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.taskReminder, entityId: id)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskReminder, entityId: id, payload: payload)
    }

    // task_checklist_items (simple PK) — independent synced children.
    let checklistIds = try String.fetchAll(
      db, sql: "SELECT id FROM task_checklist_items WHERE task_id = ?", arguments: [taskId])
    for id in checklistIds {
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.taskChecklistItem, entityId: id)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .taskChecklistItem, entityId: id, payload: payload)
    }
  }

  // MARK: - Habit permanent-delete child/edge tombstones

  /// Stamp DELETE envelopes for every `habit_completions` edge + every
  /// `habit_reminder_policies` child owned by `habitId` BEFORE the `habits`
  /// DELETE fires its `ON DELETE CASCADE`. MUST run BEFORE the parent DELETE.
  func enqueueHabitDeleteCascade(
    _ db: Database, hlc: HlcSession, deviceId: String, habitId: String
  ) throws {
    let completionRows = try Row.fetchAll(
      db,
      sql: """
        SELECT habit_id, completed_date, value, note, created_at, updated_at, version
        FROM habit_completions WHERE habit_id = ?
        """,
      arguments: [habitId])
    for row in completionRows {
      let hId: String = row["habit_id"], date: String = row["completed_date"]
      let payload = PayloadLoaders.habitCompletionPayload(
        habitId: hId, completedDate: date, value: row["value"], note: row["note"],
        version: row["version"], createdAt: row["created_at"], updatedAt: row["updated_at"])
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .habitCompletion, entityId: "\(hId):\(date)",
        payload: payload)
    }

    let policyIds = try String.fetchAll(
      db, sql: "SELECT id FROM habit_reminder_policies WHERE habit_id = ?", arguments: [habitId])
    for id in policyIds {
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.habitReminderPolicy, entityId: id)
      try enqueueDelete(
        db, hlc: hlc, deviceId: deviceId, kind: .habitReminderPolicy, entityId: id,
        payload: payload)
    }
  }
}
