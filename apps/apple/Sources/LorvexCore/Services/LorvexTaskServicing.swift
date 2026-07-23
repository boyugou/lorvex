import Foundation

/// The full task service surface: task reads, mutations, checklist items,
/// reminder writes, recurrence, archive/trash, and batch operations in a single
/// protocol, composed with the id-preserving import surface
/// ``LorvexTaskImporting``. `SwiftLorvexCoreService` is the sole conformer;
/// `SwiftLorvexCoreService.inMemory()` backs previews and tests.
public protocol LorvexTaskServicing: LorvexTaskImporting {
  // MARK: - Reads
  //
  // Read-only task access: snapshots, single-task loads, listings/search, the
  // dependency graph, and the reminder read surface. No method in this section
  // mutates.

  func loadToday() async throws -> TodaySnapshot

  func loadTask(id: LorvexTask.ID) async throws -> LorvexTask

  /// Returns the task's recent defer events, newest first, derived from the
  /// append-only `ai_changelog` (single `defer_task` and `batch_defer_tasks`
  /// writes). Read-only; `limit` bounds the returned count. Conformers that do
  /// not track a changelog return an empty array (see the extension default).
  func deferHistory(taskID: LorvexTask.ID, limit: Int) async throws -> [TaskDeferHistoryEntry]

  /// Returns the dependency graph rooted at `rootTaskID` (or the full graph
  /// when nil). `listID` scopes to a single list; `includeInactive` adds
  /// completed/cancelled tasks to the result.
  func getDependencyGraph(
    rootTaskID: LorvexTask.ID?,
    listID: LorvexList.ID?,
    includeInactive: Bool
  ) async throws -> DependencyGraph

  /// Returns open tasks whose `planned_date` falls within the next `daysAhead`
  /// days, ordered by planned_date ascending.
  func getUpcomingTasks(daysAhead: Int, limit: Int) async throws -> [LorvexTask]

  /// The paginated form of ``getUpcomingTasks(daysAhead:limit:)``: the same
  /// planned-date window, but with `offset` and a real `totalMatching`/
  /// `truncated` computed from the underlying count query rather than from
  /// however many rows a single unpaginated fetch happened to return. Callers
  /// that need to page through more than one `limit`-sized window (e.g. the
  /// MCP `get_upcoming_tasks` tool) must use this rather than fetching
  /// `limit + offset` rows from ``getUpcomingTasks(daysAhead:limit:)`` and
  /// slicing locally, which under-counts `totalMatching` and can misreport
  /// `truncated` once the window holds more rows than fit in one fetch.
  func getUpcomingTaskPage(daysAhead: Int, limit: Int, offset: Int) async throws -> TaskPageResult

  /// Returns open tasks in the canonical Today pool, preserving core pagination
  /// and task ordering without the dashboard snapshot cap.
  func getTodayTasks(limit: Int, offset: Int) async throws -> TaskPageResult

  /// Date-anchored sibling used when one logical operation also reads focus or
  /// other day-scoped state. The caller captures the product day once, then all
  /// reads use that same day even if product midnight passes between awaits.
  func getTodayTasks(date: String, limit: Int, offset: Int) async throws -> TaskPageResult

  /// Uncapped canonical task data for the widget snapshot's numeric stats: the
  /// full actionable (open + in_progress) set and the recently-completed set,
  /// read in one transaction. Decouples the widget's counts from the top-N
  /// dashboard pool (``TodaySnapshot/tasks``) so overdue / due-today / focus /
  /// per-list / completed-today counts reflect the whole workload rather than a
  /// priority-capped slice. See ``WidgetStatsSource``.
  func loadWidgetStatsSource() async throws -> WidgetStatsSource

  /// Returns tasks with a scheduled due date inside the inclusive calendar
  /// window, ordered by the canonical task order.
  func getScheduledTasks(from: String, to: String, limit: Int) async throws -> [LorvexTask]

  /// Returns open tasks currently hidden by a future `available_from`
  /// (defer-until) and not yet overdue — the "Scheduled" section, ordered
  /// `available_from ASC` then the canonical task key. Distinct from
  /// ``getScheduledTasks(from:to:limit:)``, which is the calendar due-window
  /// read; a hidden task surfaces here at query time until its `available_from`
  /// day arrives (or its deadline passes, at which point overdue-wins moves it
  /// into the day surfaces instead).
  func getHiddenScheduledTasks(limit: Int, offset: Int) async throws -> TaskPageResult

  /// Lists tasks through the core query path. Supported statuses are `all`,
  /// `open`, `completed`, `cancelled`, and `someday`; `priority` is 1, 2, or 3.
  func listTasks(
    status: String,
    listID: LorvexList.ID?,
    priority: Int?,
    text: String?,
    limit: Int,
    offset: Int
  ) async throws -> TaskPageResult

  /// Lists tasks through the richer MCP-friendly query path. This is the main
  /// task-context primitive for review/planning agents.
  func listTasks(query: TaskListQueryRequest) async throws -> TaskPageResult

  /// Searches tasks using the core text index/fallback semantics. Supported
  /// statuses are `all`, `open`, `completed`, `cancelled`, and `someday`.
  func searchTasks(query: String, status: String, limit: Int, offset: Int) async throws
    -> TaskSearchResult

  /// Returns tasks surfaced by the core as deferred, preserving core pagination
  /// and list scoping semantics.
  func getDeferredTasks(listID: LorvexList.ID?, limit: Int, offset: Int) async throws
    -> TaskPageResult

  /// Returns task reminders whose `reminder_at` is before `asOf` (defaults to
  /// now when nil) and have not been dismissed or cancelled.
  func getDueTaskReminders(asOf: String?, limit: Int) async throws -> [TaskReminderWithTask]

  /// Returns pending reminders whose `reminder_at` falls within the next
  /// `hoursAhead` hours, ordered by reminder_at ascending.
  func getUpcomingTaskReminders(hoursAhead: Int, limit: Int) async throws -> [TaskReminderWithTask]

  /// Returns open tasks that have at least one pending future reminder within
  /// the next `hoursAhead` hours, ordered by the first matching reminder time.
  func getTasksWithUpcomingReminders(hoursAhead: Int, limit: Int) async throws -> [LorvexTask]

  /// Deterministic intake nudges for a task that already exists (missing
  /// estimate, missing planned date, likely-duplicate title). Read-only. The
  /// extension default returns no advice so conformers that don't compute it
  /// (test stubs) need no change.
  func taskIntakeAdvice(id: LorvexTask.ID) async throws -> [TaskIntakeAdviceItem]

  // MARK: - Mutations
  //
  // Core task lifecycle mutations: create, edit, status transitions, defer, and
  // free-text body / AI-context writes.

  func createTask(title: String, notes: String) async throws -> LorvexTask

  func createTask(_ draft: TaskCreateDraft) async throws -> LorvexTask

  /// Patch a task's editable fields. `dueDate` (external deadline) and
  /// `plannedDate` (intended work day) are independent columns: passing one
  /// leaves the other untouched only insofar as the caller routes the patch —
  /// the write surface sets each from its own argument, so `dueDate: nil`
  /// clears the deadline and `plannedDate: nil` clears the planned day.
  func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID]
  ) async throws -> LorvexTask

  /// Overload of the above that also patches `raw_input`. `rawInput` is the
  /// fully-resolved final value for the column: `nil` clears it, a string
  /// sets it. Callers that don't manage `raw_input` should use the overload
  /// above, which leaves the column untouched.
  func updateTask(
    id: LorvexTask.ID,
    title: String,
    notes: String,
    priority: LorvexTask.Priority,
    estimatedMinutes: Int?,
    dueDate: Date?,
    plannedDate: Date?,
    availableFrom: Date?,
    tags: [String],
    dependsOn: [LorvexTask.ID],
    rawInput: String?
  ) async throws -> LorvexTask

  /// Patch a single task using per-field ``Patch`` semantics: a field left
  /// `nil` / `.unset` in the draft is not written at all, so a concurrent
  /// writer's change to a column this call omits is preserved rather than
  /// clobbered with a stale read-back. This is the lost-update-safe entry the
  /// singular `update_task` MCP tool routes through; it mirrors
  /// ``batchUpdateTasks(_:)`` for one task and records an `update` changelog
  /// row. Returns the full updated task.
  func updateTask(_ draft: TaskUpdateDraft) async throws -> LorvexTask

  func completeTask(id: LorvexTask.ID) async throws -> TodaySnapshot

  func cancelTask(id: LorvexTask.ID) async throws -> TodaySnapshot

  func reopenTask(id: LorvexTask.ID) async throws -> TodaySnapshot

  /// Start a task: `open → in_progress` (put the "started" marker on). Idempotent
  /// when already in_progress; rejects a non-open source and a dependency-blocked
  /// start. Returns a fresh `TodaySnapshot`.
  func startTask(id: LorvexTask.ID) async throws -> TodaySnapshot

  /// Pause a task: `in_progress → open` (un-start / mis-click recovery). Idempotent
  /// when already open; leaves `planned_date` / `defer_count` intact. Returns a
  /// fresh `TodaySnapshot`.
  func pauseTask(id: LorvexTask.ID) async throws -> TodaySnapshot

  /// Status-transition siblings of ``completeTask(id:)`` / ``cancelTask(id:)`` /
  /// ``reopenTask(id:)`` / ``deferTask(id:until:reason:)`` that return the full
  /// mutated task captured inside the write transaction, instead of a fresh
  /// `TodaySnapshot`. The MCP host (a separate process) routes through these so
  /// the enriched return can never be dropped by a concurrent delete in the
  /// gap between the write committing and a post-commit read-back.
  func completeTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask

  func cancelTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask

  func reopenTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask

  /// `…ReturningTask` siblings of ``startTask(id:)`` / ``pauseTask(id:)`` that
  /// return the full mutated task captured inside the write transaction. The MCP
  /// host routes `start_task` / `pause_task` through these.
  func startTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask

  func pauseTaskReturningTask(id: LorvexTask.ID) async throws -> LorvexTask

  /// Defer to a future work day and return the full updated task. `reason`, when
  /// supplied, is a `DeferReason` category written to `last_defer_reason`;
  /// `note` is optional free-text detail persisted only onto the defer's
  /// `ai_changelog` row (surfaced read-only via `get_task`'s `defer_history`),
  /// never onto `ai_notes`. Both are captured per-defer on the changelog.
  func deferTaskReturningTask(id: LorvexTask.ID, until date: Date, reason: String?, note: String?)
    async throws -> LorvexTask

  /// Move a task into the GTD Someday/Maybe bucket (`status = 'someday'`),
  /// leaving its `list_id` and other fields intact. Status is orthogonal to
  /// list membership. Returns the full updated task.
  func markTaskSomeday(id: LorvexTask.ID) async throws -> LorvexTask

  /// Defer a task to a future work day, leaving status open and incrementing
  /// `defer_count`. `reason`, when supplied, is a `DeferReason` category written
  /// to the `last_defer_reason` column for pattern tracking; `note` is optional
  /// free-text detail persisted onto the defer's `ai_changelog` row (surfaced
  /// read-only via `get_task`'s `defer_history`), never onto `ai_notes`.
  func deferTask(id: LorvexTask.ID, until date: Date, reason: String?, note: String?) async throws
    -> TodaySnapshot

  func appendToTaskBody(taskID: LorvexTask.ID, additionalNotes: String) async throws -> LorvexTask

  /// Replace the task's assistant-maintained context block. Passing an empty
  /// string clears the block.
  func setTaskAINotes(taskID: LorvexTask.ID, notes: String) async throws -> LorvexTask

  // MARK: - Checklist
  //
  // Per-task checklist item CRUD + reordering.

  func addTaskChecklistItem(taskID: LorvexTask.ID, text: String) async throws -> LorvexTask

  func updateTaskChecklistItem(itemID: TaskChecklistItem.ID, text: String) async throws
    -> LorvexTask

  func toggleTaskChecklistItem(itemID: TaskChecklistItem.ID, completed: Bool) async throws
    -> LorvexTask

  func removeTaskChecklistItem(itemID: TaskChecklistItem.ID) async throws -> LorvexTask

  func reorderTaskChecklistItems(taskID: LorvexTask.ID, itemIDs: [TaskChecklistItem.ID])
    async throws -> LorvexTask

  // MARK: - Reminders (writes)
  //
  // Task reminder writes + delivery-state reconciliation. (Reminder reads are in
  // the Reads section above.)

  func addTaskReminder(taskID: LorvexTask.ID, reminderAt: String) async throws -> LorvexTask

  func removeTaskReminder(taskID: LorvexTask.ID, reminderID: TaskReminder.ID) async throws
    -> LorvexTask

  func setTaskReminders(taskID: LorvexTask.ID, reminderAts: [String]) async throws -> LorvexTask

  /// Mark every currently-due task reminder that was actually armed (scheduled
  /// time elapsed, live, not already delivered, and previously reported armed
  /// via ``replaceArmedTaskReminders(reminderIDs:asOf:)``) as delivered as of
  /// `asOf`. The deterministic device-local analog of an OS delivery callback —
  /// run on the reschedule cadence so
  /// ``getDueTaskReminders(asOf:limit:)`` stops re-surfacing
  /// reminders the OS has already shown. A reminder that was never armed
  /// (budgeted out of the notification cap, authorization denied, or an `add`
  /// failure) stays `pending`, so a genuine miss is never recorded as a
  /// delivery. Returns how many were newly marked.
  @discardableResult
  func markDueTaskRemindersDelivered(asOf: Date) async throws -> Int

  /// Replace this device's armed-reminder record with exactly the reminder ids
  /// the scheduler reported as armed on this reschedule pass, stamping
  /// `last_armed_at` for them and clearing it for every other still-pending
  /// reminder (whose OS request the replace pass just dropped — budgeted out,
  /// authorization denied, or an `add` failure). The stamp therefore mirrors
  /// the currently pending `UNUserNotificationCenter` request set.
  /// ``markDueTaskRemindersDelivered(asOf:)`` only ever transitions an elapsed
  /// reminder to `delivered` while this stamp is present, so a dropped or
  /// never-armed reminder is never mistaken for a delivered one.
  func replaceArmedTaskReminders(reminderIDs: [String], asOf: Date) async throws

  // MARK: - Recurrence
  //
  // Task recurrence rule + per-occurrence exception management.

  func setTaskRecurrence(taskID: LorvexTask.ID, rule: TaskRecurrenceRule) async throws -> LorvexTask

  func removeTaskRecurrence(taskID: LorvexTask.ID) async throws -> LorvexTask

  func addTaskRecurrenceException(taskID: LorvexTask.ID, exceptionDate: String) async throws
    -> LorvexTask

  func removeTaskRecurrenceException(taskID: LorvexTask.ID, exceptionDate: String) async throws
    -> LorvexTask

  // MARK: - Archive / trash
  //
  // Reversible (archive/unarchive) and irreversible (delete) task removal.

  /// Permanently removes the task and all its child data (checklist items,
  /// reminders, recurrence rules, dependencies). Requires the task to already be
  /// archived; the MCP host's permanent-delete tool relies on that two-step so a
  /// single AI call cannot destroy live data (issue #2363). Also the path that
  /// applies a remote-delete tombstone received from CloudKit. UI permanent
  /// delete uses `permanentlyDeleteTask`, which folds in the archive.
  func deleteTask(id: LorvexTask.ID) async throws

  /// Archive (if needed) and permanently delete a task in one transaction — the
  /// human-confirmed UI Trash action. Unlike `deleteTask` it does not require a
  /// prior archive (the destructive confirmation in the UI is the deliberate
  /// step the MCP two-step otherwise enforces). Irreversible; for reversible
  /// removal use `cancelTask`, which preserves the row.
  func permanentlyDeleteTask(id: LorvexTask.ID) async throws

  /// Move a task to the Trash by stamping `archived_at` — a reversible soft
  /// delete. The row stays present; restore it with `unarchiveTask` or remove
  /// it for good with `deleteTask`, which requires this archive first (the
  /// two-step that stops a single AI call from destroying live data, issue
  /// #2363). Throws if the task is missing or already archived. Returns the
  /// archived task.
  func archiveTask(id: LorvexTask.ID) async throws -> LorvexTask

  /// Restore a Trashed task by clearing `archived_at`. Inverse of
  /// `archiveTask`. Throws if the task is missing or not currently archived.
  /// Returns the restored task.
  func unarchiveTask(id: LorvexTask.ID) async throws -> LorvexTask

  // MARK: - Batch operations
  //
  // Multi-task operations applied as a unit.

  func batchCompleteTasks(ids: [LorvexTask.ID]) async throws -> TaskBatchLifecycleResult

  func batchReopenTasks(ids: [LorvexTask.ID]) async throws -> TaskBatchLifecycleResult

  func batchCreateTasks(_ drafts: [TaskCreateDraft]) async throws -> [LorvexTask]

  func batchUpdateTasks(_ drafts: [TaskUpdateDraft]) async throws -> [LorvexTask]

  func batchMoveTasks(ids: [LorvexTask.ID], toListID listID: LorvexList.ID) async throws
    -> TaskBatchMoveResult

  /// Defer multiple tasks to the same future work day. `reason`, when supplied,
  /// is a `DeferReason` category written to each task's `last_defer_reason`.
  /// `note`, when supplied, is the free-text detail; it and `reason` are stamped
  /// onto the shared batch changelog row (surfaced read-only in each task's
  /// `get_task` `defer_history`), mirroring the single `defer_task`.
  func batchDeferTasks(ids: [LorvexTask.ID], until date: Date, reason: String?, note: String?)
    async throws -> TaskBatchLifecycleResult

  /// Cancel all open/someday tasks in a list. `statuses` nil defaults to
  /// [.open, .someday]. Returns the full cancelled tasks (empty when nothing
  /// matched the filter), each enriched and captured inside the cancel
  /// transaction so a concurrent delete cannot drop a task the batch cancelled.
  func batchCancelTasksInList(
    listID: LorvexList.ID, statuses: [String]?, cancelSeries: Bool
  ) async throws -> [LorvexTask]

  /// Cancel the addressed active tasks in one write transaction. Missing or
  /// already-terminal ids are reported as skipped.
  func batchCancelTasks(ids: [LorvexTask.ID], cancelSeries: Bool) async throws
    -> TaskBatchCancelByIdResult
}

extension LorvexTaskServicing {
  public func taskIntakeAdvice(id: LorvexTask.ID) async throws -> [TaskIntakeAdviceItem] { [] }

  public func deferHistory(taskID: LorvexTask.ID, limit: Int) async throws
    -> [TaskDeferHistoryEntry]
  { [] }

  public func listTasks(query: TaskListQueryRequest) async throws -> TaskPageResult {
    try await listTasks(
      status: query.status,
      listID: query.listID,
      priority: query.priority,
      text: query.text,
      limit: query.limit,
      offset: query.offset)
  }

  public func getTodayTasks(date: String, limit: Int, offset: Int) async throws
    -> TaskPageResult
  {
    // Compatibility for lightweight preview/test conformers. The production
    // SQLite service overrides this with a truly date-scoped query.
    try await getTodayTasks(limit: limit, offset: offset)
  }
}
