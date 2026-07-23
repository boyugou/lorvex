import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Normalized + validated task update patch. Downstream effect
/// modules read this without re-validating.
public struct PreparedTaskUpdate: Sendable {
  public var newStatus: String?
  public var newDependsOn: [String]?
  public var changedDeps: Bool
  public var newTags: [String]?
  public var changedTags: Bool
  public var newRecurrence: Patch<String>
  public var pendingDueDatePatch: Patch<String>
  public var title: String?
  public var body: Patch<String>
  public var rawInput: Patch<String>
  public var aiNotes: Patch<String>
  public var listId: Patch<String>
  public var priority: Patch<Int64>
  public var estimatedMinutes: Patch<Int64>
  public var plannedDate: Patch<String>
  public var availableFrom: Patch<String>
  public var beforeStatus: TaskStatus
}

/// Input normalization + cross-field validation for a single-row task
/// update.
public enum TaskUpdatePreparation {
  /// Codepoint cap for `ai_notes` (``ValidationLimits/maxAiNotesLength``).
  public static let maxAiNotesLength: Int = ValidationLimits.maxAiNotesLength

  public static func prepareTaskUpdate(
    _ db: Database,
    update: TaskUpdateInput,
    beforeStatus: String
  ) throws -> PreparedTaskUpdate {
    try validateTaskIdShape(update.id, fieldName: "id")
    let listIdPatch = try rejectClearStringPatch(
      update.listId,
      fieldName: "list_id",
      message:
        "Tasks must belong to a real list. Choose a list instead of clearing list_id.")
    try validateListExists(db, listId: listIdPatch.value)

    let normalizedStatus: String?
    switch update.status {
    case .unset:
      normalizedStatus = nil
    case .clear:
      throw StoreError.validation(
        "status cannot be cleared. Expected one of: open, in_progress, completed, cancelled, someday")
    case .set(let value):
      normalizedStatus = try normalizeStatus(value)
    }

    // A `.set` carries a concrete priority; `normalizeTaskPriority` validates it
    // to 1...3 (throwing otherwise), so it always maps straight through to `.set`.
    let normalizedPriority: Patch<UInt8>
    switch update.priority {
    case .set(let value):
      _ = try TaskCreatePrepared.normalizeTaskPriority(value)
      normalizedPriority = .set(value)
    case .clear: normalizedPriority = .clear
    case .unset: normalizedPriority = .unset
    }
    guard let beforeStatusTyped = TaskStatus.parse(beforeStatus) else {
      throw StoreError.validation(
        "Invalid status '\(beforeStatus)'. "
          + "Expected one of: open, completed, cancelled, someday")
    }

    try validateCount(
      update.tagsSet?.count ?? 0, max: ValidationLimits.maxTaskTags, fieldName: "tags")
    try validateCount(
      update.tagsAdd?.count ?? 0, max: ValidationLimits.maxTaskTags, fieldName: "tags")
    try validateCount(
      update.tagsRemove?.count ?? 0, max: ValidationLimits.maxTaskTags, fieldName: "tags")
    try validateCount(
      update.dependsOn?.count ?? 0,
      max: ValidationLimits.maxTaskDependencies, fieldName: "depends_on")
    try validateCount(
      update.dependsOnAdd?.count ?? 0,
      max: ValidationLimits.maxTaskDependencies, fieldName: "depends_on_add")
    try validateCount(
      update.dependsOnRemove?.count ?? 0,
      max: ValidationLimits.maxTaskDependencies, fieldName: "depends_on_remove")
    if update.dependsOn != nil
      && (update.dependsOnAdd != nil || update.dependsOnRemove != nil)
    {
      throw StoreError.validation(
        "Use either depends_on or depends_on_add/depends_on_remove in one update, not both.")
    }
    try validateTags(update.tagsSet)
    try validateTags(update.tagsAdd)
    try validateTags(update.tagsRemove)
    if update.tagsSet != nil && (update.tagsAdd != nil || update.tagsRemove != nil) {
      throw StoreError.validation(
        "Use either tags_set or tags_add/tags_remove in one update, not both.")
    }

    let changedDeps =
      update.dependsOn != nil || update.dependsOnAdd != nil
      || update.dependsOnRemove != nil
    let newDependsOn: [String]?
    if changedDeps {
      let typedTaskId = TaskId(trusted: update.id)
      let merged: [String]
      if let replace = update.dependsOn {
        merged = TaskUpdateDependencies.normalizeDependencyIds(replace)
      } else {
        let current = try TaskUpdateDependencies.findTaskDependencies(db, taskId: typedTaskId)
        merged = TaskUpdateDependencies.applyDependencyPatch(
          current: current,
          dependsOnAdd: update.dependsOnAdd,
          dependsOnRemove: update.dependsOnRemove)
      }
      try validateCount(
        merged.count, max: ValidationLimits.maxTaskDependencies,
        fieldName: "depends_on")
      try TaskCreatePrepared.validateTaskIdsExist(
        db, taskIds: merged, field: "depends_on")
      newDependsOn = merged
    } else {
      newDependsOn = nil
    }

    let title: String?
    switch update.title {
    case .unset:
      title = nil
    case .clear:
      throw ValidationError.empty("title")
    case .set(let t):
      if t.trimmingCharacters(in: .whitespaces).isEmpty
        || ValidationText.isVisuallyEmpty(t)
      {
        throw ValidationError.empty("title")
      }
      try throwOnValidationFailure(
        ValidationText.validateStringLength(
          t, field: "title", max: ValidationLimits.maxTitleLength))
      title = t
    }
    try validateNullableStringLength(
      update.body.value, fieldName: "body",
      maxLen: ValidationLimits.maxBodyLength)
    try throwOnValidationFailure(
      PayloadByteBudget.validateOptionalEscapedBudget(
        update.body.value, field: "body",
        budget: PayloadByteBudget.longTextEscapedBytes))
    try validateNullableStringLength(
      update.aiNotes.value, fieldName: "ai_notes", maxLen: maxAiNotesLength)
    try throwOnValidationFailure(
      PayloadByteBudget.validateOptionalEscapedBudget(
        update.aiNotes.value, field: "ai_notes",
        budget: PayloadByteBudget.aiNotesEscapedBytes))
    try validateNullableStringLength(
      update.rawInput.value, fieldName: "raw_input",
      maxLen: ValidationLimits.maxShortTextLength)

    let pendingDueDatePatch =
      try update.dueDate.tryMap { v in
        try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: v)
      }

    let estimatedMinutes: Patch<Int64> =
      try update.estimatedMinutes.tryMap { m throws -> Int64 in
        let n = Int64(m)
        try throwOnValidationFailure(ValidationNumeric.validateEstimatedMinutes(n))
        return n
      }

    // `Patch.set(rule)` may collapse to `.clear` when the canonicalizer
    // returns nil (empty/whitespace rule).
    let newRecurrence: Patch<String>
    switch update.recurrence {
    case .set(let rule):
      // Serialize JSONValue to canonical JSON text: no whitespace,
      // sorted-by-source-key for arrays of recurrence rules.
      let raw = try serializeRecurrenceJSON(rule)
      switch ValidationRecurrence.normalizeTaskRecurrence(raw) {
      case .success(let canonical):
        if let c = canonical {
          newRecurrence = .set(c)
        } else {
          newRecurrence = .clear
        }
      case .failure(let err):
        throw StoreError.validation(err.description)
      }
    case .clear: newRecurrence = .clear
    case .unset: newRecurrence = .unset
    }

    let plannedDate =
      try update.plannedDate.tryMap { v in
        try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: v)
      }

    let availableFrom =
      try update.availableFrom.tryMap { v in
        try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: v)
      }

    let changedTags =
      update.tagsSet != nil || update.tagsAdd != nil || update.tagsRemove != nil
    let newTags: [String]?
    if changedTags {
      let typedTaskId = TaskId(trusted: update.id)
      let current = try TaskUpdateTags.findTaskTags(db, taskId: typedTaskId)
      let merged = TaskUpdateTags.applyTagPatch(
        currentTags: current,
        tagsSet: update.tagsSet,
        tagsAdd: update.tagsAdd,
        tagsRemove: update.tagsRemove)
      try validateCount(
        merged.count, max: ValidationLimits.maxTaskTags, fieldName: "tags")
      newTags = merged
    } else {
      newTags = nil
    }

    return PreparedTaskUpdate(
      newStatus: normalizedStatus,
      newDependsOn: newDependsOn,
      changedDeps: changedDeps,
      newTags: newTags,
      changedTags: changedTags,
      newRecurrence: newRecurrence,
      pendingDueDatePatch: pendingDueDatePatch,
      title: title,
      body: update.body,
      rawInput: update.rawInput,
      aiNotes: update.aiNotes,
      listId: listIdPatch,
      priority: normalizedPriority.map { Int64($0) },
      estimatedMinutes: estimatedMinutes,
      plannedDate: plannedDate,
      availableFrom: availableFrom,
      beforeStatus: beforeStatusTyped)
  }

  /// Validate that `id` parses through the canonical entity-id sentinel
  /// gate. Wrapping any `ValidationError` description in
  /// `StoreError.validation`.
  public static func validateTaskIdShape(_ id: String, fieldName: String) throws {
    switch EntityID.parseIDWithSentinel(id, field: fieldName, sentinel: nil) {
    case .success: return
    case .failure(let e): throw StoreError.validation(e.description)
    }
  }

  // MARK: - private helpers

  private static func rejectClearStringPatch(
    _ patch: Patch<String>, fieldName: String, message: String
  ) throws -> Patch<String> {
    if patch.isClear {
      _ = fieldName
      throw StoreError.validation(message)
    }
    return patch
  }

  private static func validateListExists(
    _ db: Database, listId: String?
  ) throws {
    guard let listId = listId else { return }
    if listId.trimmingCharacters(in: .whitespaces).isEmpty {
      throw StoreError.validation("list_id must not be empty")
    }
    try validateTaskIdShape(listId, fieldName: "list_id")
    let exists =
      (try Int64.fetchOne(
        db,
        sql: "SELECT EXISTS(SELECT 1 FROM lists WHERE id = ?)",
        arguments: [listId])) ?? 0
    if exists == 0 {
      throw StoreError.validation("list '\(listId)' does not exist")
    }
  }

  private static func normalizeStatus(_ status: String) throws -> String {
    switch status {
    case StatusName.open: return StatusName.open
    case StatusName.inProgress: return StatusName.inProgress
    case StatusName.completed: return StatusName.completed
    case StatusName.cancelled: return StatusName.cancelled
    case StatusName.someday: return StatusName.someday
    default:
      throw StoreError.validation(
        "Invalid status '\(status)'. "
          + "Expected one of: open, in_progress, completed, cancelled, someday")
    }
  }

  private static func validateCount(
    _ count: Int, max: Int, fieldName: String
  ) throws {
    if count > max {
      throw StoreError.validation(
        "\(fieldName) supports at most \(max) item(s), got \(count)")
    }
  }

  private static func validateNullableStringLength(
    _ value: String?, fieldName: String, maxLen: Int
  ) throws {
    if let v = value {
      try throwOnValidationFailure(
        ValidationText.validateStringLength(v, field: fieldName, max: maxLen))
    }
  }

  private static func validateTags(_ tags: [String]?) throws {
    guard let tags = tags else { return }
    for tag in tags {
      try throwOnValidationFailure(
        ValidationText.validateStringLength(
          tag, field: "tag", max: ValidationLimits.maxShortTextLength))
    }
  }

  private static func throwOnValidationFailure(
    _ result: Result<Void, ValidationError>
  ) throws {
    if case .failure(let error) = result {
      throw StoreError.validation(error.description)
    }
  }

  /// Render a recurrence-rule ``JSONValue`` to compact JSON text for the
  /// `ValidationRecurrence.normalizeTaskRecurrence` entry point.
  private static func serializeRecurrenceJSON(_ v: JSONValue) throws -> String {
    if case .string(let s) = v { return s }
    do {
      return try canonicalizeJSON(v)
    } catch {
      throw StoreError.validation("task recurrence must be valid JSON")
    }
  }
}
