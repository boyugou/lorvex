import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Rich per-task JSON response returned by MCP write tools and consumed by
/// UI surfaces.
///
/// The wire shape is the 29 `TaskRow` columns plus five enrichment fields
/// appended after enrichment runs: `tags`, `depends_on`, `checklist_items`,
/// `lateness_state`, and `reminders`.
///
/// Deterministic key order: ``canonicalizeJSON(_:)`` sorts object keys into
/// UTF-8 byte order, so feeding the assembled ``JSONValue`` through it yields a
/// stable string. Callers that need a string render therefore route the
/// returned ``JSONValue`` through ``canonicalizeJSON(_:)``.
public enum TaskResponse {
  /// Load `taskId` from the database, encode the row into the canonical
  /// TaskRow JSON shape, then append the four enrichment derivations plus
  /// the active reminders array. Returns the assembled ``JSONValue``.
  ///
  /// Reminder ordering: sorted by `reminder_at` ascending. `reminder_at`
  /// is `NOT NULL` in the schema, so `nil` comparisons cannot arise and the
  /// sort is a plain ascending string compare over the column.
  ///
  /// Throws ``StoreError/notFound(entity:id:)`` when the row is missing.
  public static func loadEnrichedTaskJSON(
    _ db: Database, taskId: TaskId
  ) throws -> JSONValue {
    guard let row = try TaskRepo.Read.getTask(db, taskId: taskId) else {
      throw StoreError.notFound(entity: EntityKind.task.rawValue, id: taskId.asString)
    }
    var task = encodeTaskRow(row)
    try enrichTaskJSON(db, task: &task)
    return task
  }

  /// Batch variant. Equivalent to mapping ``loadEnrichedTaskJSON`` over the
  /// supplied ids; preserves caller order (and duplicates). Any missing id
  /// surfaces as ``StoreError/notFound(entity:id:)``.
  ///
  /// The rows are fetched in one `WHERE id IN (…)` round trip and enriched
  /// through ``loadEnrichedTasksJSON(_:rows:)``, so a batch of N ids costs a
  /// constant handful of queries rather than ~5N.
  public static func loadEnrichedTasksJSON(
    _ db: Database, taskIds: [String]
  ) throws -> [JSONValue] {
    if taskIds.isEmpty { return [] }
    let rowsById = try TaskRepo.Read.getTasksByIds(db, ids: taskIds)
    var ordered: [TaskRow] = []
    ordered.reserveCapacity(taskIds.count)
    for id in taskIds {
      guard let row = rowsById[id] else {
        throw StoreError.notFound(entity: EntityKind.task.rawValue, id: id)
      }
      ordered.append(row)
    }
    return try loadEnrichedTasksJSON(db, rows: ordered)
  }

  /// Enrich a list of already-fetched ``TaskRow``s into the canonical enriched
  /// task JSON shape, preserving the caller's row order.
  ///
  /// This is the batch primitive behind list / search / overview reads. It is
  /// equivalent to mapping ``loadEnrichedTaskJSON`` over each
  /// row's id, but avoids the per-row re-`getTask` (the rows are already in
  /// hand) and collapses the per-derived-field work into one pass:
  ///
  /// - tags / depends_on / checklist / lateness come from a single
  ///   ``TaskEnrichment/computeEnrichments(_:dates:today:)`` call over every
  ///   row — the same batch primitive the single-row path invokes with one
  ///   element, so per-task results are identical.
  /// - reminders come from one ``PayloadLoaders/loadTaskRemindersForTasks(_:taskIds:)``
  ///   scan, grouped per task and sorted by `reminder_at` exactly as the
  ///   single-row path sorts its per-task reminder list.
  ///
  /// The planned/due dates fed to lateness derivation are parsed from each
  /// row's encoded JSON (`planned_date` / `due_date`), matching the single-row
  /// path's derivation precisely.
  public static func loadEnrichedTasksJSON(
    _ db: Database, rows: [TaskRow]
  ) throws -> [JSONValue] {
    if rows.isEmpty { return [] }

    var encoded: [JSONValue] = []
    encoded.reserveCapacity(rows.count)
    var dateEntries: [TaskEnrichment.DateEntry] = []
    dateEntries.reserveCapacity(rows.count)
    var taskIds: [String] = []
    taskIds.reserveCapacity(rows.count)

    for row in rows {
      let task = encodeTaskRow(row)
      guard case .object(let map) = task,
        case .string(let taskId) = map["id"] ?? .null
      else {
        throw StoreError.invariant("task response JSON missing id")
      }
      taskIds.append(taskId)
      dateEntries.append(
        TaskEnrichment.DateEntry(
          taskId: taskId,
          plannedDate: parseYmd(map["planned_date"]),
          dueDate: parseYmd(map["due_date"])))
      encoded.append(task)
    }

    let today = try WorkflowTimezone.todayYmdForConn(db)
    let enrichments = try TaskEnrichment.computeEnrichments(
      db, dates: dateEntries, today: today)
    let remindersByTask = try PayloadLoaders.loadTaskRemindersForTasks(db, taskIds: taskIds)

    var out: [JSONValue] = []
    out.reserveCapacity(rows.count)
    for (task, taskId) in zip(encoded, taskIds) {
      guard case .object(var map) = task else {
        throw StoreError.invariant("task response JSON must be an object")
      }
      applyEnrichment(&map, enrichments[taskId] ?? Enrichment())
      map["reminders"] = sortedReminders(remindersByTask[taskId] ?? [])
      out.append(.object(map))
    }
    return out
  }

  /// Convenience: extract the `title` string from an enriched task
  /// payload, defaulting to `"task"` when missing or non-string.
  public static func taskTitle(_ task: JSONValue) -> String {
    if case .object(let map) = task, case .string(let s) = map["title"] ?? .null {
      return s
    }
    return "task"
  }

  // -------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------

  /// Encode a ``TaskRow`` into the canonical key/value object for the task
  /// JSON shape, deterministic once routed through ``canonicalizeJSON(_:)``.
  ///
  /// Keys mirror the `TaskRow` fields across `TaskCore`,
  /// `TaskScheduling`, `TaskRecurrenceState`, and
  /// `TaskLifecycleState`. The insertion order is irrelevant because
  /// ``canonicalizeJSON(_:)`` sorts by UTF-8 byte order.
  static func encodeTaskRow(_ row: TaskRow) -> JSONValue {
    var obj: [String: JSONValue] = [:]

    // -- TaskCore ----------------------------------------------------
    obj["id"] = .string(row.core.id)
    obj["title"] = .string(row.core.title)
    obj["body"] = stringOrNull(row.core.body)
    obj["raw_input"] = stringOrNull(row.core.rawInput)
    obj["ai_notes"] = stringOrNull(row.core.aiNotes)
    obj["status"] = .string(row.core.status)
    obj["list_id"] = .string(row.core.listId)
    obj["priority"] = intOrNull(row.core.priority)
    obj["version"] = .string(row.core.version)
    obj["created_at"] = .string(row.core.createdAt)
    obj["updated_at"] = .string(row.core.updatedAt)

    // -- TaskScheduling ---------------------------------------------
    obj["due_date"] = stringOrNull(row.scheduling.dueDate?.asString)
    obj["estimated_minutes"] = intOrNull(row.scheduling.estimatedMinutes)
    obj["planned_date"] = stringOrNull(row.scheduling.plannedDate?.asString)
    obj["available_from"] = stringOrNull(row.scheduling.availableFrom?.asString)
    obj["defer_count"] = .int(row.scheduling.deferCount)
    obj["last_deferred_at"] = stringOrNull(row.scheduling.lastDeferredAt)
    obj["last_defer_reason"] = stringOrNull(row.scheduling.lastDeferReason)

    // -- TaskRecurrenceState ----------------------------------------
    obj["recurrence"] = stringOrNull(row.recurrence.recurrence)
    // `recurrence_exceptions` is stored as a raw JSON array string
    // (or NULL). Embed the parsed JSON so the output renders as an
    // actual array, not a quoted string. Malformed JSON falls back
    // to the raw string to preserve diagnostic visibility.
    if let raw = row.recurrence.recurrenceExceptions {
      obj["recurrence_exceptions"] = JSONValue.parse(raw) ?? .string(raw)
    } else {
      obj["recurrence_exceptions"] = .null
    }
    obj["spawned_from"] = stringOrNull(row.recurrence.spawnedFrom)
    obj["recurrence_group_id"] = stringOrNull(row.recurrence.recurrenceGroupId)
    obj["canonical_occurrence_date"] =
      stringOrNull(row.recurrence.canonicalOccurrenceDate?.asString)
    obj["recurrence_instance_key"] = stringOrNull(row.recurrence.recurrenceInstanceKey)

    // -- TaskLifecycleState -----------------------------------------
    obj["completed_at"] = stringOrNull(row.lifecycle.completedAt)
    obj["archived_at"] = stringOrNull(row.lifecycle.archivedAt)

    return .object(obj)
  }

  /// Mutate `task` in place by appending the five enrichment slots
  /// `tags`, `depends_on`, `checklist_items`, `lateness_state`, and
  /// `reminders`.
  static func enrichTaskJSON(_ db: Database, task: inout JSONValue) throws {
    guard case .object(var map) = task else {
      throw StoreError.invariant("task response JSON must be an object")
    }
    guard case .string(let taskId) = map["id"] ?? .null else {
      throw StoreError.invariant("task response JSON missing id")
    }

    let today = try WorkflowTimezone.todayYmdForConn(db)

    let plannedDate = parseYmd(map["planned_date"])
    let dueDate = parseYmd(map["due_date"])

    let enrichments = try TaskEnrichment.computeEnrichments(
      db,
      dates: [
        TaskEnrichment.DateEntry(
          taskId: taskId, plannedDate: plannedDate, dueDate: dueDate)
      ],
      today: today)
    applyEnrichment(&map, enrichments[taskId] ?? Enrichment())

    let reminders = try PayloadLoaders.loadTaskRemindersForTask(db, taskId: taskId)
    map["reminders"] = sortedReminders(reminders)

    task = .object(map)
  }

  /// Fold the four ``Enrichment`` derivations (`tags`, `depends_on`,
  /// `checklist_items`, `lateness_state`) into a task response object in place.
  /// A `nil` derivation lowers to JSON `null`. Shared by the single-row and
  /// batch enrichment paths so both produce the identical wire shape.
  static func applyEnrichment(_ map: inout [String: JSONValue], _ enrichment: Enrichment) {
    map["tags"] = enrichment.tags.map { tags in
      .array(tags.map(JSONValue.string))
    } ?? .null
    map["depends_on"] = enrichment.dependsOn.map { ids in
      .array(ids.map(JSONValue.string))
    } ?? .null
    map["checklist_items"] = enrichment.checklistItems.map { items in
      .array(items.map(checklistItemJSON))
    } ?? .null
    map["lateness_state"] = enrichment.lateness.map { state in
      .string(state.rawValue)
    } ?? .null
  }

  /// Sort a task's `(reminderId, payload)` tuples by `reminder_at` ascending
  /// and render the `reminders` JSON array. `reminder_at` is a NOT NULL column
  /// (schema), so every row has a string; a missing key sorts before non-nil.
  /// Shared by the single-row and batch enrichment paths.
  static func sortedReminders(_ reminders: [(String, JSONValue)]) -> JSONValue {
    // The enriched `reminders` array is active-only: a soft-removed reminder
    // carries `cancelled_at` (and a fired one `dismissed_at`). The payload loader
    // returns every row — including those — because the sync seed needs them, so
    // the active filter lives here, at the view boundary.
    let active = reminders.filter { isActiveReminder($0.1) }
    let sorted = active.sorted { left, right in
      let leftAt = reminderAtString(left.1)
      let rightAt = reminderAtString(right.1)
      switch (leftAt, rightAt) {
      case (nil, nil): return false
      case (nil, _): return true
      case (_, nil): return false
      case let (l?, r?): return l < r
      }
    }
    return .array(sorted.map { $0.1 })
  }

  // -- helpers ------------------------------------------------------

  private static func stringOrNull(_ s: String?) -> JSONValue {
    s.map(JSONValue.string) ?? .null
  }
  private static func intOrNull(_ n: Int64?) -> JSONValue {
    n.map(JSONValue.int) ?? .null
  }

  private static func parseYmd(_ value: JSONValue?) -> IsoDate.YMD? {
    guard let value, case .string(let s) = value else { return nil }
    switch IsoDate.parseIsoDate(s) {
    case .success(let ymd): return ymd
    case .failure: return nil
    }
  }

  private static func reminderAtString(_ payload: JSONValue) -> String? {
    if case .object(let map) = payload, case .string(let s) = map["reminder_at"] ?? .null {
      return s
    }
    return nil
  }

  /// A reminder is active (and thus shown in the enriched task) only while
  /// neither `cancelled_at` (soft-removed) nor `dismissed_at` (already fired) is
  /// set. A missing key counts as null/active.
  private static func isActiveReminder(_ payload: JSONValue) -> Bool {
    guard case .object(let map) = payload else { return true }
    func isUnset(_ key: String) -> Bool {
      switch map[key] {
      case .none, .some(.null): return true
      default: return false
      }
    }
    return isUnset("cancelled_at") && isUnset("dismissed_at")
  }

  private static func checklistItemJSON(_ item: ChecklistItemData) -> JSONValue {
    var obj: [String: JSONValue] = [:]
    obj["id"] = .string(item.id)
    obj["task_id"] = .string(item.taskId)
    obj["position"] = .int(item.position)
    obj["text"] = .string(item.text)
    obj["completed_at"] = item.completedAt.map(JSONValue.string) ?? .null
    obj["version"] = .string(item.version)
    obj["created_at"] = .string(item.createdAt)
    obj["updated_at"] = .string(item.updatedAt)
    return .object(obj)
  }
}
