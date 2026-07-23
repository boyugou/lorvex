import GRDB
import LorvexStore

enum NativeTaskGraphImportMaterialize {
  static func insert(_ snapshot: NativeTaskGraphSnapshot, into db: Database) throws {
    for task in snapshot.tasks {
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, body, raw_input, ai_notes, status, list_id, priority,
            due_date, estimated_minutes, recurrence, spawned_from,
            spawned_from_version, recurrence_group_id, recurrence_instance_key,
            canonical_occurrence_date, content_version, schedule_version,
            lifecycle_version, archive_version, recurrence_rollover_state,
            recurrence_successor_id, version, created_at, updated_at,
            completed_at, last_deferred_at, last_defer_reason, planned_date,
            available_from, defer_count, archived_at
          ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
          )
          """,
        arguments: [
          task.id, task.title, task.body, task.rawInput, task.aiNotes, task.status,
          task.listID, task.priority, task.dueDate, task.estimatedMinutes,
          task.recurrence, task.spawnedFrom, task.spawnedFromVersion?.description,
          task.recurrenceGroupID, task.recurrenceInstanceKey,
          task.canonicalOccurrenceDate, task.contentVersion.description,
          task.scheduleVersion.description, task.lifecycleVersion.description,
          task.archiveVersion.description, task.recurrenceRolloverState,
          task.recurrenceSuccessorID, task.version.description, task.createdAt,
          task.updatedAt, task.completedAt, task.lastDeferredAt,
          task.lastDeferReason, task.plannedDate, task.availableFrom,
          task.deferCount, task.archivedAt,
        ])
    }

    for row in snapshot.recurrenceExceptions {
      try db.execute(
        sql: "INSERT INTO task_recurrence_exceptions (task_id, exception_date) VALUES (?, ?)",
        arguments: [row.taskID, row.exceptionDate])
    }
    for row in snapshot.tagEdges {
      try db.execute(
        sql: "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES (?, ?, ?, ?)",
        arguments: [row.taskID, row.tagID, row.version.description, row.createdAt])
    }
    for row in snapshot.dependencyEdges {
      try db.execute(
        sql: """
          INSERT INTO task_dependencies (
            task_id, depends_on_task_id, version, created_at
          ) VALUES (?, ?, ?, ?)
          """,
        arguments: [
          row.taskID, row.dependsOnTaskID, row.version.description, row.createdAt,
        ])
    }
    for row in snapshot.checklistItems {
      try db.execute(
        sql: """
          INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          row.id, row.taskID, row.position, row.text, row.completedAt,
          row.version.description, row.createdAt, row.updatedAt,
        ])
    }
    for row in snapshot.reminders {
      try db.execute(
        sql: """
          INSERT INTO task_reminders (
            id, task_id, reminder_at, dismissed_at, cancelled_at, version,
            created_at, original_local_time, original_tz
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          row.id, row.taskID, row.reminderAt, row.dismissedAt, row.cancelledAt,
          row.version.description, row.createdAt, row.originalLocalTime,
          row.originalTimeZone,
        ])
    }

    // Restore shadows before the live rows are enqueued. The ordinary upsert
    // funnel then merges these opaque fields into its outbound envelope and
    // keeps their future payload-schema provenance instead of overwriting the
    // backup with a current-schema projection.
    for shadow in snapshot.payloadShadows.sorted(by: {
      ($0.entityType.asString, $0.entityID) < ($1.entityType.asString, $1.entityID)
    }) {
      try PayloadShadow.restoreShadow(
        db,
        row: PayloadShadow.Row(
          entityType: shadow.entityType,
          entityID: shadow.entityID,
          baseVersion: shadow.baseVersion.description,
          payloadSchemaVersion: Int(shadow.payloadSchemaVersion),
          rawPayloadJSON: shadow.rawPayloadJSON,
          sourceDeviceID: shadow.sourceDeviceID,
          updatedAt: shadow.updatedAt))
    }
  }
}
