import GRDB
import LorvexDomain
import LorvexStore

extension ApplyTask {
  static func taskUpdateSQL(_ tieBreak: LwwTieBreak) -> String {
    """
    UPDATE tasks SET
                 title = :title,
                 body = CASE WHEN :body_present THEN :body ELSE tasks.body END,
                 raw_input = CASE WHEN :raw_input_present THEN :raw_input ELSE tasks.raw_input END,
                 ai_notes = CASE WHEN :ai_notes_present THEN :ai_notes ELSE tasks.ai_notes END,
                 status = :status,
                 list_id = :list_id,
                 priority = CASE WHEN :priority_present THEN :priority ELSE tasks.priority END,
                 due_date = CASE WHEN :due_date_present THEN :due_date ELSE tasks.due_date END,
                 estimated_minutes = CASE WHEN :estimated_minutes_present
                     THEN :estimated_minutes ELSE tasks.estimated_minutes END,
                 recurrence = CASE WHEN :recurrence_present
                     THEN :recurrence ELSE tasks.recurrence END,
                 spawned_from = CASE WHEN :spawned_from_present
                     THEN :spawned_from ELSE tasks.spawned_from END,
                 spawned_from_version = CASE WHEN :spawned_from_version_present
                     THEN :spawned_from_version ELSE tasks.spawned_from_version END,
                 recurrence_group_id = CASE WHEN :recurrence_group_id_present
                     THEN :recurrence_group_id ELSE tasks.recurrence_group_id END,
                 canonical_occurrence_date = CASE WHEN :canonical_occurrence_date_present
                     THEN :canonical_occurrence_date ELSE tasks.canonical_occurrence_date END,
                 created_at = :created_at,
                 updated_at = :updated_at,
                 completed_at = CASE WHEN :completed_at_present
                     THEN :completed_at ELSE tasks.completed_at END,
                 last_deferred_at = CASE WHEN :last_deferred_at_present
                     THEN :last_deferred_at ELSE tasks.last_deferred_at END,
                 last_defer_reason = CASE WHEN :last_defer_reason_present
                     THEN :last_defer_reason ELSE tasks.last_defer_reason END,
                 planned_date = CASE WHEN :planned_date_present
                     THEN :planned_date ELSE tasks.planned_date END,
                 available_from = CASE WHEN :available_from_present
                     THEN :available_from ELSE tasks.available_from END,
                 defer_count = CASE WHEN :defer_count_present
                     THEN :defer_count ELSE tasks.defer_count END,
                 recurrence_instance_key = CASE WHEN :recurrence_instance_key_present
                     THEN :recurrence_instance_key ELSE tasks.recurrence_instance_key END,
                 archived_at = CASE WHEN :archived_at_present
                     THEN :archived_at ELSE tasks.archived_at END,
                 content_version = :content_version,
                 schedule_version = :schedule_version,
                 lifecycle_version = :lifecycle_version,
                 archive_version = :archive_version,
                 recurrence_rollover_state = :recurrence_rollover_state,
                 recurrence_successor_id = CASE WHEN :recurrence_successor_id_present
                     THEN :recurrence_successor_id ELSE tasks.recurrence_successor_id END,
                 version = :version
             WHERE id = :id AND :version \(versionCmp(tieBreak)) version
    """
  }

  static let taskInsertSQL =
    """
    INSERT INTO tasks (id, title, body, raw_input, ai_notes,
                        status, list_id,
                        priority, due_date, estimated_minutes,
                        recurrence, spawned_from, spawned_from_version,
                        recurrence_group_id,
                        canonical_occurrence_date,
                        created_at, updated_at, completed_at, last_deferred_at,
                        last_defer_reason,
                        planned_date, available_from, defer_count, recurrence_instance_key,
                        content_version, schedule_version, lifecycle_version, archive_version,
                        recurrence_rollover_state, recurrence_successor_id, version, archived_at)
     VALUES (:id, :title, :body, :raw_input, :ai_notes,
             :status, :list_id,
             :priority, :due_date, :estimated_minutes,
             :recurrence, :spawned_from, :spawned_from_version,
             :recurrence_group_id,
             :canonical_occurrence_date,
             :created_at, :updated_at, :completed_at, :last_deferred_at,
             :last_defer_reason,
             :planned_date, :available_from, :defer_count, :recurrence_instance_key,
             :content_version, :schedule_version, :lifecycle_version, :archive_version,
             :recurrence_rollover_state, :recurrence_successor_id, :version, :archived_at)
    """

  static func executeTaskUpdate(
    _ db: Database, row: TaskRow, tieBreak: LwwTieBreak
  ) throws {
    let args: StatementArguments = [
      "id": row.entityId, "title": row.title,
      "body": row.body, "body_present": row.bodyPresent,
      "raw_input": row.rawInput, "raw_input_present": row.rawInputPresent,
      "ai_notes": row.aiNotes, "ai_notes_present": row.aiNotesPresent,
      "status": row.status, "list_id": row.listId,
      "priority": row.priority, "priority_present": row.priorityPresent,
      "due_date": row.dueDate, "due_date_present": row.dueDatePresent,
      "estimated_minutes": row.estimatedMinutes,
      "estimated_minutes_present": row.estimatedMinutesPresent,
      "recurrence": row.recurrence, "recurrence_present": row.recurrencePresent,
      "spawned_from": row.spawnedFrom, "spawned_from_present": row.spawnedFromPresent,
      "spawned_from_version": row.spawnedFromVersion,
      "spawned_from_version_present": row.spawnedFromVersionPresent,
      "recurrence_group_id": row.recurrenceGroupId,
      "recurrence_group_id_present": row.recurrenceGroupIdPresent,
      "canonical_occurrence_date": row.canonicalOccurrenceDate,
      "canonical_occurrence_date_present": row.canonicalOccurrenceDatePresent,
      "created_at": row.createdAt, "updated_at": row.updatedAt,
      "completed_at": row.completedAt, "completed_at_present": row.completedAtPresent,
      "last_deferred_at": row.lastDeferredAt,
      "last_deferred_at_present": row.lastDeferredAtPresent,
      "last_defer_reason": row.lastDeferReason,
      "last_defer_reason_present": row.lastDeferReasonPresent,
      "planned_date": row.plannedDate, "planned_date_present": row.plannedDatePresent,
      "available_from": row.availableFrom, "available_from_present": row.availableFromPresent,
      "defer_count": row.deferCount, "defer_count_present": row.deferCountPresent,
      "recurrence_instance_key": row.recurrenceInstanceKey,
      "recurrence_instance_key_present": row.recurrenceInstanceKeyPresent,
      "content_version": row.contentVersion, "schedule_version": row.scheduleVersion,
      "lifecycle_version": row.lifecycleVersion, "archive_version": row.archiveVersion,
      "recurrence_rollover_state": row.recurrenceRolloverState,
      "recurrence_successor_id": row.recurrenceSuccessorId,
      "recurrence_successor_id_present": row.recurrenceSuccessorIdPresent,
      "version": row.version,
      "archived_at": row.archivedAt, "archived_at_present": row.archivedAtPresent,
    ]
    do { try db.execute(sql: taskUpdateSQL(tieBreak), arguments: args) }
    catch { throw try classifyTaskWriteError(db, row: row, error: error) }
  }

  static func writeReconciledTask(_ db: Database, row: TaskSyncRow) throws {
    try executeTaskUpdate(db, row: row.asApplyRow(), tieBreak: .allowEqual)
    try RecurrenceExceptionsRepo.replaceTaskExceptionsFromJSON(
      db, taskId: row.id, json: row.recurrenceExceptions)
  }

  private static func executeTaskInsertRaw(_ db: Database, row: TaskRow) throws {
    let args: StatementArguments = [
      "id": row.entityId, "title": row.title, "body": row.body,
      "raw_input": row.rawInput, "ai_notes": row.aiNotes, "status": row.status,
      "list_id": row.listId, "priority": row.priority, "due_date": row.dueDate,
      "estimated_minutes": row.estimatedMinutes, "recurrence": row.recurrence,
      "spawned_from": row.spawnedFrom, "spawned_from_version": row.spawnedFromVersion,
      "recurrence_group_id": row.recurrenceGroupId,
      "canonical_occurrence_date": row.canonicalOccurrenceDate,
      "created_at": row.createdAt, "updated_at": row.updatedAt,
      "completed_at": row.completedAt, "last_deferred_at": row.lastDeferredAt,
      "last_defer_reason": row.lastDeferReason, "planned_date": row.plannedDate,
      "available_from": row.availableFrom, "defer_count": row.deferCount,
      "recurrence_instance_key": row.recurrenceInstanceKey,
      "content_version": row.contentVersion, "schedule_version": row.scheduleVersion,
      "lifecycle_version": row.lifecycleVersion, "archive_version": row.archiveVersion,
      "recurrence_rollover_state": row.recurrenceRolloverState,
      "recurrence_successor_id": row.recurrenceSuccessorId,
      "version": row.version, "archived_at": row.archivedAt,
    ]
    try db.execute(sql: taskInsertSQL, arguments: args)
  }

  static func executeTaskInsert(_ db: Database, row: TaskRow) throws -> Bool {
    do {
      try executeTaskInsertRaw(db, row: row)
      return db.changesCount > 0
    } catch { throw try classifyTaskWriteError(db, row: row, error: error) }
  }

  private static func classifyTaskWriteError(
    _ db: Database, row: TaskRow, error: Error
  ) throws -> ApplyError {
    guard let databaseError = error as? DatabaseError,
      databaseError.isUniqueConstraintViolation,
      let instanceKey = row.recurrenceInstanceKey,
      !instanceKey.isEmpty
    else { return ApplyError.lift(error) }
    let claimant: String?
    do {
      claimant = try String.fetchOne(
        db, sql: "SELECT id FROM tasks WHERE recurrence_instance_key = ?",
        arguments: [instanceKey])
    } catch { throw ApplyError.lift(error) }
    guard let claimant, claimant != row.entityId else {
      return ApplyError.lift(error)
    }
    return .invalidPayload(
      "task \(row.entityId) conflicts with recurrence_instance_key \(instanceKey) "
        + "already claimed by task \(claimant)")
  }
}
