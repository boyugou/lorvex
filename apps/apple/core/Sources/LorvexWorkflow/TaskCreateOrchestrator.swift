import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Canonical task-create orchestrator.
///
/// Pipeline:
///
/// 1. Optionally drop `rawInput` when the `record_raw_input` preference
///    disables capture.
/// 2. ``TaskCreatePrepared/prepareTaskInsert(_:hlc:id:now:input:deviceId:)``
///    validates + normalizes every field and produces a
///    ``PreparedTaskInsert``.
/// 3. The row + its tag / reminder / dependency-edge children are written
///    and accumulated into ``CreateTaskSyncEffects``.
/// 4. When `completed: true`,
///    ``LifecycleTransitions/applyCompletionTransition(_:taskId:now:reminderVersion:handler:)``
///    runs immediately and any spawned successor / focus rewire / cancelled
///    reminder is folded into the effects envelope.
/// 5. Final payload is the enriched task JSON + optional next-occurrence +
///    newly-unblocked dependents + optional intake advice.
///
/// The orchestrator presumes the caller has opened a write transaction
/// around the call (so all child inserts + the optional completion lifecycle
/// commit atomically). Takes `Database` (mid-txn) + `HlcSession` and does no
/// txn / changelog / idempotency wrapping itself — those layers live in the
/// calling write surface.
public enum TaskCreate {
  /// Execute a task-create call.
  ///
  /// - `id`: optional explicit id. When `nil`, a fresh UUID is minted.
  /// - `recurrenceHandler`: dependency-injection seam for tests; defaults
  ///   to the production ``LifecycleRecurrenceSpawnHandler``.
  public static func createTask(
    _ db: Database,
    hlc: HlcSession,
    input rawInput: CreateTaskInput,
    recurrenceHandler: RecurrenceSpawnHandler = LifecycleRecurrenceSpawnHandler()
  ) throws -> CreateTaskResult {
    var input = rawInput.task
    let id = rawInput.id ?? EntityID.newEntityIDString()
    let typedTaskId = TaskId(trusted: id)
    let includeAdvice = rawInput.includeAdvice
    let shouldComplete = input.completed ?? false

    if !input.rawInput.isUnset {
      let allow = try shouldStoreRawInput(db)
      if !allow { input.rawInput = .unset }
    }
    let reminders = input.reminders
    let now = SyncTimestampFormat.syncTimestampNow()
    let prepared = try TaskCreatePrepared.prepareTaskInsert(
      db, hlc: hlc, id: id, now: now, input: input)
    try prepared.executeInsert(db)

    var syncEffects = CreateTaskSyncEffects()
    let tagEffects = try TaskCreateChildInserts.insertTaskTags(
      db, hlc: hlc, taskId: typedTaskId, tags: prepared.tags)
    syncEffects.tagUpsertIds.append(contentsOf: tagEffects.tagUpsertIds)
    syncEffects.taskTagEdgeUpsertIds.append(contentsOf: tagEffects.taskTagEdgeUpsertIds)
    syncEffects.reminderUpsertIds.append(
      contentsOf: try TaskCreateChildInserts.insertTaskReminders(
        db, hlc: hlc, taskId: id, reminders: reminders))
    syncEffects.dependencyEdgeUpsertIds.append(
      contentsOf: try TaskCreateChildInserts.insertDependencyEdges(
        db, hlc: hlc, taskId: typedTaskId, dependsOn: prepared.dependsOn))
    syncEffects.taskUpsertIds.append(id)

    var nextOccurrence: JSONValue = .null
    var newlyUnblockedIds: [String] = []
    if shouldComplete {
      let reminderVersion = hlc.nextVersionString()
      let completion = try LifecycleTransitions.applyCompletionTransition(
        db, taskId: typedTaskId, now: now,
        reminderVersion: reminderVersion,
        handler: recurrenceHandler)
      syncEffects.cancelledReminderIds.append(
        contentsOf: completion.cancelledReminderIds)
      if let successorIdString = completion.spawnedSuccessorId {
        let successorTyped = TaskId(trusted: successorIdString)
        syncEffects.focusRewireAudits.append(
          CreateTaskFocusRewireAudit(
            parentTaskId: typedTaskId,
            successorId: successorTyped,
            focusScheduleDates: completion.rewiredFocusScheduleDates,
            currentFocusDates: completion.rewiredCurrentFocusDates))
        let successor = try TaskResponse.loadEnrichedTaskJSON(
          db, taskId: successorTyped)
        nextOccurrence = successor
        syncEffects.spawnedSuccessors.append(
          CreateTaskSpawnedSuccessor(
            successorId: successorTyped,
            summary: "Spawned recurrence successor from pre-completed create",
            afterTask: successor))
      }
      syncEffects.spawnedSuccessorTagEdges.append(
        contentsOf: completion.spawnedSuccessorTagEdges)
      syncEffects.spawnedSuccessorChecklistItemIds.append(
        contentsOf: completion.spawnedSuccessorChecklistItemIds)
      syncEffects.spawnedSuccessorReminderIds.append(
        contentsOf: completion.spawnedSuccessorReminderIds)
      syncEffects.rewiredFocusScheduleDates.append(
        contentsOf: completion.rewiredFocusScheduleDates)
      syncEffects.rewiredCurrentFocusDates.append(
        contentsOf: completion.rewiredCurrentFocusDates)
      newlyUnblockedIds = try findActiveTasksDependingOn(db, taskId: typedTaskId)
    }

    let task = try TaskResponse.loadEnrichedTaskJSON(db, taskId: typedTaskId)
    let newlyUnblocked = try TaskResponse.loadEnrichedTasksJSON(
      db, taskIds: newlyUnblockedIds)
    let advice: [JSONValue] =
      includeAdvice
      ? try TaskCreateAdvice.buildTaskIntakeAdvice(db, task: task) : []
    let summary = try TaskCreatePrepared.buildCreateSummary(
      db, prepared: prepared, completed: shouldComplete)
    let payload: JSONValue = .object([
      "task": task,
      "next_occurrence": nextOccurrence,
      "newly_unblocked": .array(newlyUnblocked),
      "advice": .array(advice),
    ])

    return CreateTaskResult(
      taskId: typedTaskId,
      task: task,
      advice: advice,
      payload: payload,
      summary: summary,
      syncEffects: syncEffects)
  }

  /// Read the `record_raw_input` preference; defaults to `true` when absent.
  public static func shouldStoreRawInput(_ db: Database) throws -> Bool {
    guard
      let raw = try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?1",
        arguments: [PreferenceKeys.prefRecordRawInput])
    else { return true }
    guard let parsed = parseJsonBoolPreference(raw) else {
      throw StoreError.validation(
        "\(PreferenceKeys.prefRecordRawInput) preference must be a JSON boolean")
    }
    return parsed
  }

  /// Parse a JSON-boolean preference value. Returns `nil` if the value is
  /// not exactly `true` / `false` after whitespace trimming.
  static func parseJsonBoolPreference(_ raw: String) -> Bool? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    switch trimmed {
    case "true": return true
    case "false": return false
    default: return nil
    }
  }

  /// IDs of active tasks (status in {open, in_progress, someday}, not archived) that
  /// depend on `taskId`.
  static func findActiveTasksDependingOn(
    _ db: Database, taskId: TaskId
  ) throws -> [String] {
    let sql =
      "SELECT td.task_id FROM task_dependencies td "
      + "JOIN tasks t ON t.id = td.task_id "
      + "WHERE td.depends_on_task_id = ?1 "
      + "  AND t.status IN (\(StatusName.activeStatusSqlList)) "
      + "  AND t.archived_at IS NULL"
    return try String.fetchAll(db, sql: sql, arguments: [taskId.asString])
  }
}
