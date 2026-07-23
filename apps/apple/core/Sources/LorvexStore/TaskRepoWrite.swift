import Foundation
import GRDB
import LorvexDomain

/// Well-known ID for the schema-seeded default Inbox list.
public let inboxListId: String = "inbox"

/// Parameters for ``TaskRepo/Write/createTask(_:params:)``. Validation
/// (priority range, minutes range, date format) runs in
/// ``TaskCreateParams/validated()`` before the INSERT.
public struct TaskCreateParams: Sendable {
  public let id: String
  public let title: String
  public var body: String? = nil
  public var rawInput: String? = nil
  public var aiNotes: String? = nil
  public let status: String
  public var listId: String? = nil
  public var priority: Int64? = nil
  public var dueDate: String? = nil
  public var estimatedMinutes: Int64? = nil
  public var recurrence: String? = nil
  public var recurrenceGroupId: String? = nil
  public var canonicalOccurrenceDate: String? = nil
  public var plannedDate: String? = nil
  public var availableFrom: String? = nil
  public let version: String
  public let now: String

  public init(
    id: String,
    title: String,
    status: String,
    version: String,
    now: String,
    body: String? = nil,
    rawInput: String? = nil,
    aiNotes: String? = nil,
    listId: String? = nil,
    priority: Int64? = nil,
    dueDate: String? = nil,
    estimatedMinutes: Int64? = nil,
    recurrence: String? = nil,
    recurrenceGroupId: String? = nil,
    canonicalOccurrenceDate: String? = nil,
    plannedDate: String? = nil,
    availableFrom: String? = nil
  ) {
    self.id = id
    self.title = title
    self.status = status
    self.version = version
    self.now = now
    self.body = body
    self.rawInput = rawInput
    self.aiNotes = aiNotes
    self.listId = listId
    self.priority = priority
    self.dueDate = dueDate
    self.estimatedMinutes = estimatedMinutes
    self.recurrence = recurrence
    self.recurrenceGroupId = recurrenceGroupId
    self.canonicalOccurrenceDate = canonicalOccurrenceDate
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
  }

  /// Run per-field validation: priority range, estimated minutes range,
  /// and date format.
  public func validated() throws -> TaskCreateParams {
    guard TaskStatus.parse(status) != nil else {
      throw StoreError.validation(
        "Invalid task status '\(status)'. Expected one of: open, in_progress, completed, cancelled, someday")
    }
    if let p = priority {
      switch ValidationNumeric.validatePriority(p) {
      case .success: break
      case .failure(let e): throw StoreError.validation(e.description)
      }
    }
    if let m = estimatedMinutes {
      switch ValidationNumeric.validateEstimatedMinutes(m) {
      case .success: break
      case .failure(let e): throw StoreError.validation(e.description)
      }
    }
    if let d = dueDate {
      switch ValidationFormat.validateDateFormat(d) {
      case .success: break
      case .failure(let e): throw StoreError.validation(e.description)
      }
    }
    if let d = plannedDate {
      switch ValidationFormat.validateDateFormat(d) {
      case .success: break
      case .failure(let e): throw StoreError.validation(e.description)
      }
    }
    if let d = availableFrom {
      switch ValidationFormat.validateDateFormat(d) {
      case .success: break
      case .failure(let e): throw StoreError.validation(e.description)
      }
    }
    if let d = canonicalOccurrenceDate {
      switch ValidationFormat.validateDateFormat(d) {
      case .success: break
      case .failure(let e): throw StoreError.validation(e.description)
      }
    }
    return self
  }
}

/// Patch struct for ``TaskRepo/Write/applyTaskUpdate(_:patch:)``. Nullable
/// columns use ``Patch`` for explicit three-state semantics (`unset`
/// skip, `clear` SQL NULL, `set` write value). `listId` is the
/// exception: `Patch.clear` is rejected because normal tasks must remain
/// classified into a real list. Status transitions require a typed
/// `beforeStatus`.
public struct TaskUpdatePatch: Sendable {
  public let taskId: String
  public var title: String?
  public var body: Patch<String>
  public var rawInput: Patch<String>
  public var aiNotes: Patch<String>
  public var status: TaskStatus?
  public var listId: Patch<String>
  public var priority: Patch<Int64>
  public var estimatedMinutes: Patch<Int64>
  public var plannedDate: Patch<String>
  public var availableFrom: Patch<String>
  /// Trash-state column. `.set(ts)` archives, `.clear` restores,
  /// `.unset` skips.
  public var archivedAt: Patch<String>
  public let version: String
  public let now: String
  /// Current persisted status before this update. REQUIRED when
  /// `status` is set so transition metadata is computed from a typed
  /// value rather than a fallback.
  public var beforeStatus: TaskStatus?

  public init(
    taskId: String,
    version: String,
    now: String,
    title: String? = nil,
    body: Patch<String> = .unset,
    rawInput: Patch<String> = .unset,
    aiNotes: Patch<String> = .unset,
    status: TaskStatus? = nil,
    listId: Patch<String> = .unset,
    priority: Patch<Int64> = .unset,
    estimatedMinutes: Patch<Int64> = .unset,
    plannedDate: Patch<String> = .unset,
    availableFrom: Patch<String> = .unset,
    archivedAt: Patch<String> = .unset,
    beforeStatus: TaskStatus? = nil
  ) {
    self.taskId = taskId
    self.version = version
    self.now = now
    self.title = title
    self.body = body
    self.rawInput = rawInput
    self.aiNotes = aiNotes
    self.status = status
    self.listId = listId
    self.priority = priority
    self.estimatedMinutes = estimatedMinutes
    self.plannedDate = plannedDate
    self.availableFrom = availableFrom
    self.archivedAt = archivedAt
    self.beforeStatus = beforeStatus
  }
}

extension TaskRepo {
  /// Write-side mutations against the `tasks` table.
  ///
  /// Each method takes a GRDB ``Database`` first. HLC `version` strings
  /// are caller-supplied (LorvexWorkflow's mutation executor owns
  /// stamping); the repo is a pure SQL surface.
  public enum Write {

    // MARK: - Create

    /// Insert a new task row and return the inserted ``TaskRow``.
    ///
    /// Defaults `list_id` to ``inboxListId`` when omitted. The
    /// `RETURNING` clause materializes the canonical row in one
    /// round-trip — callers do not need a follow-up
    /// ``Read/getTask(_:taskId:)`` to see the schema-computed
    /// `priority_effective`.
    @discardableResult
    public static func createTask(
      _ db: Database, params: TaskCreateParams
    ) throws -> TaskRow {
      let params = try params.validated()
      let resolvedListId = params.listId ?? inboxListId

      let sql = """
        INSERT INTO tasks \
        (id, title, body, raw_input, ai_notes, status, list_id, priority, \
         due_date, estimated_minutes, \
         recurrence, recurrence_group_id, canonical_occurrence_date, \
         planned_date, available_from, content_version, schedule_version, \
         lifecycle_version, archive_version, recurrence_rollover_state, \
         version, created_at, updated_at, \
         completed_at, last_deferred_at, defer_count) \
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \
                ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, 0) \
        RETURNING \(TaskRepo.taskColumns)
        """
      let args: StatementArguments = [
        params.id, params.title, params.body, params.rawInput,
        params.aiNotes, params.status, resolvedListId,
        params.priority, params.dueDate,
        params.estimatedMinutes,
        params.recurrence, params.recurrenceGroupId,
        params.canonicalOccurrenceDate, params.plannedDate, params.availableFrom,
        params.version, params.version, params.version, params.version,
        params.recurrence != nil && TaskStatus.parse(params.status)?.isTerminal == true
          ? TaskRecurrenceRolloverState.ended.rawValue
          : TaskRecurrenceRolloverState.none.rawValue,
        params.version, params.now, params.now,
        params.status == StatusName.completed ? params.now : nil,
      ]
      guard let row = try Row.fetchOne(db, sql: sql, arguments: args) else {
        throw StoreError.invariant("createTask: INSERT RETURNING produced no row for id=\(params.id)")
      }
      return try TaskRepo.rowToTaskRow(row)
    }

    // MARK: - Update

    /// Apply a dynamic UPDATE to a task row.
    ///
    /// Always sets `version` and `updated_at`; other columns are
    /// included only when their patch field carries a change. When
    /// `status` is set, the metadata columns produced by
    /// ``statusTransitionColumns(oldStatus:newStatus:now:)`` are
    /// folded in through ``StatusTransitionSql``.
    ///
    /// LWW gate: `?version > tasks.version`. Throws
    /// ``StoreError/staleVersion`` when the gate rejects the write —
    /// the helper does NOT probe for existence, so an absent row and a
    /// stale miss are indistinguishable.
    public static func applyTaskUpdate(
      _ db: Database, patch: TaskUpdatePatch
    ) throws {
      var setClauses: [String] = ["updated_at = ?", "version = ?"]
      var bindings: [(any DatabaseValueConvertible)?] = [patch.now, patch.version]
      var assignedColumns: Set<String> = ["updated_at", "version"]
      var contentRegisterChanged = false
      var scheduleRegisterChanged = false
      var lifecycleRegisterChanged = false
      var archiveRegisterChanged = false
      var recurrenceLifecycleCoupling = false
      let explicitPatchColumns: Set<String> =
        patch.plannedDate.isSetOrClear ? ["planned_date"] : []

      func appendSetValue(_ column: String, _ value: (any DatabaseValueConvertible)?) {
        guard assignedColumns.insert(column).inserted else { return }
        setClauses.append("\(column) = ?")
        bindings.append(value)
      }

      func appendSetNull(_ column: String) {
        guard assignedColumns.insert(column).inserted else { return }
        setClauses.append("\(column) = NULL")
      }

      if let title = patch.title {
        appendSetValue("title", title)
        contentRegisterChanged = true
      }
      if patch.body.isSetOrClear {
        appendSetValue("body", patch.body.asBindValue)
        contentRegisterChanged = true
      }
      if patch.rawInput.isSetOrClear {
        appendSetValue("raw_input", patch.rawInput.asBindValue)
        contentRegisterChanged = true
      }
      if patch.aiNotes.isSetOrClear {
        appendSetValue("ai_notes", patch.aiNotes.asBindValue)
        contentRegisterChanged = true
      }
      if let status = patch.status {
        guard let before = patch.beforeStatus else {
          throw StoreError.invariant(
            "status update for task \(patch.taskId) is missing typed before_status")
        }
        appendSetValue("status", status.rawValue)
        lifecycleRegisterChanged = true
        recurrenceLifecycleCoupling = before.isTerminal != status.isTerminal
        if status.isTerminal {
          assignedColumns.insert("recurrence_rollover_state")
          assignedColumns.insert("recurrence_successor_id")
          setClauses.append(
            "recurrence_rollover_state = CASE WHEN recurrence IS NULL THEN 'none' ELSE 'ended' END")
          setClauses.append("recurrence_successor_id = NULL")
        } else if before.isTerminal {
          assignedColumns.insert("recurrence_rollover_state")
          assignedColumns.insert("recurrence_successor_id")
          setClauses.append(
            "recurrence_rollover_state = CASE "
              + "WHEN recurrence_rollover_state = 'authorized' THEN 'revoked' "
              + "WHEN recurrence_rollover_state = 'ended' THEN 'none' "
              + "ELSE recurrence_rollover_state END")
          setClauses.append(
            "recurrence_successor_id = CASE "
              + "WHEN recurrence_rollover_state = 'authorized' THEN recurrence_successor_id "
              + "WHEN recurrence_rollover_state = 'ended' THEN NULL "
              + "ELSE recurrence_successor_id END")
        }
        for action in statusTransitionColumns(
          oldStatus: before, newStatus: status, now: patch.now)
        {
          switch action {
          case .setText(let col, let val):
            guard !explicitPatchColumns.contains(col) else { continue }
            appendSetValue(col, val)
            if col != "completed_at" { scheduleRegisterChanged = true }
          case .setNull(let col):
            guard !explicitPatchColumns.contains(col) else { continue }
            appendSetNull(col)
            if col != "completed_at" { scheduleRegisterChanged = true }
          case .setInt(let col, let val):
            guard !explicitPatchColumns.contains(col) else { continue }
            appendSetValue(col, val)
            scheduleRegisterChanged = true
          }
        }
      }
      switch patch.listId {
      case .unset: break
      case .clear:
        throw StoreError.validation(
          "tasks must belong to a real list. Choose a list instead of clearing list_id.")
      case .set(let listId):
        try TaskClassification.validateTaskListExists(
          db, listId: ListId(trusted: listId))
        appendSetValue("list_id", listId)
        contentRegisterChanged = true
      }
      if patch.priority.isSetOrClear {
        appendSetValue("priority", patch.priority.asBindValue)
        contentRegisterChanged = true
      }
      if patch.estimatedMinutes.isSetOrClear {
        appendSetValue("estimated_minutes", patch.estimatedMinutes.asBindValue)
        scheduleRegisterChanged = true
      }
      if patch.plannedDate.isSetOrClear {
        appendSetValue("planned_date", patch.plannedDate.asBindValue)
        scheduleRegisterChanged = true
      }
      if patch.availableFrom.isSetOrClear {
        appendSetValue("available_from", patch.availableFrom.asBindValue)
        scheduleRegisterChanged = true
      }
      if patch.archivedAt.isSetOrClear {
        appendSetValue("archived_at", patch.archivedAt.asBindValue)
        archiveRegisterChanged = true
      }

      if contentRegisterChanged {
        appendSetValue("content_version", patch.version)
      }
      if scheduleRegisterChanged {
        appendSetValue("schedule_version", patch.version)
      } else if recurrenceLifecycleCoupling {
        assignedColumns.insert("schedule_version")
        setClauses.append(
          "schedule_version = CASE WHEN recurrence IS NOT NULL THEN ? ELSE schedule_version END")
        bindings.append(patch.version)
      }
      if lifecycleRegisterChanged {
        appendSetValue("lifecycle_version", patch.version)
      }
      if archiveRegisterChanged {
        appendSetValue("archive_version", patch.version)
      }

      try LwwOps.executeUpdate(
        db,
        table: "tasks",
        entity: EntityName.task,
        id: patch.taskId,
        version: patch.version,
        setClauses: setClauses,
        bindings: bindings)
    }

    // MARK: - Delete

    /// LWW-gated hard DELETE of a task row by id.
    ///
    /// Bypasses the Trash (`archived_at`) lifecycle. Cascading child
    /// tables (`task_tags`, `task_dependencies`, `task_checklist_items`,
    /// …) are removed by FK `ON DELETE CASCADE`. Returns `1` on a
    /// successful delete, `0` when the row was absent; throws
    /// ``StoreError/staleVersion`` when the row exists but the gate
    /// rejected the write.
    @discardableResult
    public static func hardDeleteTaskLww(
      _ db: Database, taskId: TaskId, version: String
    ) throws -> Int {
      try LwwOps.executeDeleteById(
        db,
        table: "tasks",
        entity: EntityName.task,
        id: taskId.rawValue,
        version: version)
    }

    // MARK: - Duplicate

    /// Clone an existing task into a fresh row. Resets `status` to
    /// `open`, clears `raw_input` / `completed_at` / `last_deferred_at` /
    /// `planned_date`, and zeros `defer_count`. `available_from`
    /// (defer-until) IS copied so a clone of a hidden task stays hidden
    /// until the same date. `recurrence_exceptions` is intentionally NOT
    /// copied: EXDATEs belong to the original series.
    ///
    /// Returns the inserted ``TaskRow``.
    @discardableResult
    public static func duplicateTask(
      _ db: Database,
      source: TaskRow,
      newId: String,
      newTitle: String,
      recurrenceGroupId: String?,
      canonicalOccurrenceDate: String?,
      version: String,
      now: String
    ) throws -> TaskRow {
      let sql = """
        INSERT INTO tasks \
        (id, title, body, raw_input, ai_notes, status, list_id, priority, \
         due_date, estimated_minutes, \
         recurrence, recurrence_group_id, canonical_occurrence_date, \
         planned_date, available_from, content_version, schedule_version, \
         lifecycle_version, archive_version, recurrence_rollover_state, \
         version, created_at, updated_at, \
         completed_at, last_deferred_at, defer_count) \
        VALUES (?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, \
                ?, ?, ?, NULL, ?, ?, ?, ?, ?, 'none', ?, ?, ?, NULL, NULL, 0) \
        RETURNING \(TaskRepo.taskColumns)
        """
      let args: StatementArguments = [
        newId,
        newTitle,
        source.core.body,
        source.core.aiNotes,
        StatusName.open,
        source.core.listId,
        source.core.priority,
        source.scheduling.dueDate?.asString,
        source.scheduling.estimatedMinutes,
        source.recurrence.recurrence,
        recurrenceGroupId,
        canonicalOccurrenceDate,
        source.scheduling.availableFrom?.asString,
        version,
        version,
        version,
        version,
        version,
        now,
        now,
      ]
      guard let row = try Row.fetchOne(db, sql: sql, arguments: args) else {
        throw StoreError.invariant(
          "duplicateTask: INSERT RETURNING produced no row for id=\(newId)")
      }
      return try TaskRepo.rowToTaskRow(row)
    }
  }
}
