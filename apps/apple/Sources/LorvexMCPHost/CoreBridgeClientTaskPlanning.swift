import Foundation
import LorvexDomain
import LorvexCore
import MCP

extension CoreBridgeClient {
  func batchDeferTasks(
    taskIDs: [String],
    untilDate: String,
    reason: String?,
    structuredReason: String?
  ) async throws -> Value {
    let date = try Self.requirePlannedDate(untilDate)
    let structured = try Self.normalizedDeferReason(structuredReason)
    // The structured category goes to each task's `last_defer_reason` column; the
    // free-text `reason` is persisted (as `note`) onto the shared batch changelog
    // row, where each task's `get_task` `defer_history` surfaces it — matching the
    // single `defer_task`.
    let result = try await service.batchDeferTasks(
      ids: taskIDs, until: date, reason: structured, note: reason)
    let note = Self.deferDetailNote(reason: reason)
    // `changedTasks` is enriched inside the defer transaction, so a concurrent
    // delete cannot drop a deferred task from `results`.
    return .object([
      "results": Self.taskValues(from: result.changedTasks),
      "count": .int(result.changedTasks.count),
      "skipped": Self.skippedObjects(
        result.skipped, reason: "not found or already completed/cancelled"),
      "defer_note": note.map(Value.string) ?? .null,
    ])
  }

  func moveTaskToList(id: String, listID: String) async throws -> Value {
    let task = try await service.moveTask(id: id, toListID: listID)
    return Self.taskValue(from: task)
  }

  func batchCreateTasks(tasks taskInputs: [Value], includeAdvice: Bool) async throws -> Value {
    // Validate-and-collect per item: a bad row (empty title, unparseable date,
    // missing list, absent dependency, duplicate original_id) is reported in
    // `skipped` and the rest still land — essential for restoring a large
    // exported dataset where a single stale cross-reference must not abort the
    // whole batch. Each row carries the full single-create surface (original_id
    // / status / historical timestamps / checklist). Parse failures are caught
    // here; every parsed row goes to the service in ONE transaction with one
    // savepoint per row, so a keyed call's idempotency claim is exact — a crash
    // before commit applies nothing and frees the key, a crash after commit
    // applied the whole batch.
    var created: [LorvexTask] = []
    var skipped: [Value] = []
    var specs: [TaskRecordCreateSpec] = []
    var adviceRows: [Value] = []
    created.reserveCapacity(taskInputs.count)
    specs.reserveCapacity(taskInputs.count)
    for (index, input) in taskInputs.enumerated() {
      let object = input.objectValue ?? [:]
      let ref =
        Self.importOriginalID(object["original_id"])
        ?? object["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        ?? "tasks[\(index)]"
      guard
        let title = object["title"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
        !title.isEmpty
      else {
        skipped.append(Self.batchSkip(id: ref, reason: "A non-empty title is required."))
        continue
      }
      do {
        specs.append(try taskRecordSpec(arguments: object, title: title, reference: ref))
      } catch {
        skipped.append(Self.batchSkip(id: ref, reason: ToolRegistry.errorMessage(for: error)))
      }
    }
    try StrictArgumentArray.requireUnique(
      specs.compactMap(\.originalID), field: "tasks.original_id")
    for outcome in try await mcpMutations.batchCreateTaskRecordsForMcp(
      specs, includeAdvice: includeAdvice)
    {
      switch outcome {
      case .created(let task, let advice):
        created.append(task)
        if includeAdvice {
          adviceRows.append(.object([
            "task_id": .string(task.id),
            "advice": .array(advice.map(Self.adviceValue(from:))),
          ]))
        }
      case .failed(let reference, let error):
        skipped.append(
          Self.batchSkip(id: reference, reason: ToolRegistry.errorMessage(for: error)))
      }
    }
    let adviceValue: Value = includeAdvice ? .array(adviceRows) : .null
    // Partial-success shape shared with the sibling batch tools: `results` holds
    // the new task objects, `count` their number, and `skipped` the per-item
    // failures as `[{id, reason}]`.
    return .object([
      "results": Self.taskValues(from: created),
      "count": .int(created.count),
      "skipped": .array(skipped),
      "advice": adviceValue,
    ])
  }

  /// One `{id, reason}` entry for a batch tool's `skipped` array. `id` is the
  /// row's best available handle — its `original_id`, else its title, else an
  /// index reference — so a caller can match the failure back to the input.
  static func batchSkip(id: String, reason: String) -> Value {
    .object(["id": .string(id), "reason": .string(reason)])
  }

  private static func adviceValue(from item: TaskIntakeAdviceItem) -> Value {
    var object: [String: Value] = [
      "code": .string(item.code),
      "severity": .string(item.severity),
      "message": .string(item.message),
    ]
    if !item.relatedTaskIDs.isEmpty {
      object["related_task_ids"] = .array(item.relatedTaskIDs.map(Value.string))
    }
    return .object(object)
  }

  func batchUpdateTasks(updates: [Value]) async throws -> Value {
    let drafts: [TaskUpdateDraft] = try updates.map { update in
      let object = update.objectValue ?? [:]
      guard let id = object["id"]?.stringValue, !id.isEmpty else {
        throw LorvexCoreError.unsupportedOperation("Every update requires an id.")
      }
      let title = try Self.optionalNonEmptyTitle(from: object, key: "title")
      // `tags` wins over `tags_set` when both are present — the same precedence
      // create uses, so the two aliases resolve consistently across all tools.
      let tagsValue = object["tags"] ?? object["tags_set"]
      return TaskUpdateDraft(
        id: id,
        title: title,
        notes: object.keys.contains("notes")
          ? (try StrictScalarArguments.optionalString(object["notes"], field: "notes") ?? "")
          : nil,
        priority: try Self.priority(from: object["priority"]),
        estimatedMinutes: try Self.intPatch(from: object, key: "estimated_minutes"),
        dueDate: try Self.datePatch(from: object, key: "due_date"),
        plannedDate: try Self.datePatch(from: object, key: "planned_date"),
        availableFrom: try Self.datePatch(from: object, key: "available_from"),
        tags: try StrictArgumentArray.optionalStrings(tagsValue, field: "tags"),
        dependsOn: try StrictArgumentArray.optionalStrings(
          object["depends_on"], field: "depends_on"))
    }
    try StrictArgumentArray.requireUnique(drafts.map(\.id), field: "updates.id")
    let updated = try await service.batchUpdateTasks(drafts)
    // Partial-success shape shared with the sibling batch tools: `results` holds
    // the patched task objects, `count` their number, `skipped` per-item
    // failures (empty today; reserved so future per-item failures stay additive).
    return .object([
      "results": Self.taskValues(from: updated),
      "count": .int(updated.count),
      "skipped": .array([]),
    ])
  }

  /// Decode an MCP `priority` argument (1, 2, or 3) into a `Priority`.
  ///
  /// Returns `nil` when the field is absent or null — the caller supplies its
  /// own default (`.p2` on create) or keeps the existing value (on update).
  /// Throws a clean validation error when the field is present but not 1/2/3,
  /// instead of silently coercing to `.p2`. This mirrors the reject-clean
  /// handling of `event_type`, `frequency_type`, and structured defer reasons.
  static func priority(from value: Value?) throws -> LorvexTask.Priority? {
    guard let value, value != .null else { return nil }
    switch value.intValue {
    case 1: return .p1
    case 2: return .p2
    case 3: return .p3
    default:
      let shown =
        value.intValue.map(String.init)
        ?? value.stringValue.map { "\"\($0)\"" } ?? "non-integer"
      throw ValidationError.invalidFormat(
        field: "priority", expected: "1 (P1), 2 (P2), or 3 (P3)", actual: shown)
    }
  }

  private static func optionalNonEmptyTitle(
    from object: [String: Value], key: String
  ) throws -> String? {
    guard object.keys.contains(key) else { return nil }
    let title = try StrictScalarArguments.optionalString(object[key], field: key) ?? ""
    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw LorvexCoreError.emptyTitle
    }
    return title
  }

  /// Three-state patch for an integer column, rejecting wrong-typed input rather
  /// than silently clearing it. Absent key → `.unset` (leave untouched); JSON
  /// `null` → `.clear`; a JSON integer → `.set`. Any other JSON type (a string,
  /// double, bool, array, or object) throws ``ValidationError/invalidFormat``,
  /// matching the reject-clean handling of ``priority(from:)`` — a
  /// `{"estimated_minutes":"30"}` string-for-int is a client error, not a
  /// request to wipe the field.
  static func intPatch(from object: [String: Value], key: String) throws -> Patch<Int> {
    guard let value = object[key] else { return .unset }
    if value.isNull { return .clear }
    guard let int = value.intValue else {
      throw ValidationError.invalidFormat(
        field: key, expected: "an integer or null", actual: describePatchValue(value))
    }
    return .set(int)
  }

  /// Three-state patch for a date column, rejecting wrong-typed input rather than
  /// silently clearing it. Absent key → `.unset`; JSON `null` or an empty string
  /// → `.clear`; a `YYYY-MM-DD` string → `.set` (a malformed date string throws).
  /// A non-string, non-null value (e.g. `{"due_date":20260415}`) throws
  /// ``ValidationError/invalidFormat`` instead of erasing the field.
  static func datePatch(from object: [String: Value], key: String) throws -> Patch<Date> {
    guard let value = object[key] else { return .unset }
    if value.isNull { return .clear }
    guard let raw = value.stringValue else {
      throw ValidationError.invalidFormat(
        field: key, expected: "a YYYY-MM-DD date string, empty string, or null",
        actual: describePatchValue(value))
    }
    // An empty string clears; a non-empty string must parse (throws otherwise).
    if let date = try resolveOptionalPlannedDate(raw) {
      return .set(date)
    }
    return .clear
  }

  /// Three-state patch for a free-text string column, rejecting wrong-typed input
  /// rather than silently clearing it. Absent key → `.unset` (leave untouched);
  /// JSON `null` → `.clear`; a present string → `.set`. Any other JSON type
  /// throws ``ValidationError/invalidFormat`` so an omitted field is never
  /// force-written back with a stale value and a mistyped one is never wiped.
  static func stringPatch(from object: [String: Value], key: String) throws -> Patch<String> {
    guard let value = object[key] else { return .unset }
    if value.isNull { return .clear }
    guard let string = value.stringValue else {
      throw ValidationError.invalidFormat(
        field: key, expected: "a string or null", actual: describePatchValue(value))
    }
    return .set(string)
  }

  /// Render a wrong-typed patch value for a validation error's `actual` field,
  /// matching the quoting style ``priority(from:)`` uses (strings quoted, scalars
  /// bare). Never called for a JSON `null` — callers special-case that to
  /// `.clear` before reaching here.
  private static func describePatchValue(_ value: Value) -> String {
    if let string = value.stringValue { return "\"\(string)\"" }
    if let int = value.intValue { return String(int) }
    if let double = value.doubleValue { return String(double) }
    if let bool = value.boolValue { return String(bool) }
    if value.arrayValue != nil { return "an array" }
    if value.objectValue != nil { return "an object" }
    return "an unsupported value"
  }
}
