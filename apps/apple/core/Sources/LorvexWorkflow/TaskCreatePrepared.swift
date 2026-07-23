import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Input validation + INSERT-row materialization for task create.
///
/// ``PreparedTaskInsert`` is the validated, normalized row the orchestrator
/// hands to the store layer. ``prepareTaskInsert`` is the only constructor:
/// it walks the full validation chain (length limits, priority / date
/// normalization, recurrence transition planning, dependency-cycle check)
/// before producing it.
public struct PreparedTaskInsert: Sendable {
  public let id: String
  public let title: String
  public let dependsOn: [String]
  public let tags: [String]
  public let body: String?
  public let rawInput: String?
  public let aiNotes: String?
  public let status: String
  public let listId: String?
  public let priority: Int64?
  public let dueDate: String?
  public let estimatedMinutes: Int64?
  public let recurrence: String?
  public let recurrenceGroupId: String?
  public let canonicalOccurrenceDate: String?
  public let plannedDate: String?
  public let availableFrom: String?
  public let version: String
  public let now: String

  /// Run the row INSERT through ``TaskRepo/Write/createTask(_:params:)``.
  public func executeInsert(_ db: Database) throws {
    let params = TaskCreateParams(
      id: id,
      title: title,
      status: status,
      version: version,
      now: now,
      body: body,
      rawInput: rawInput,
      aiNotes: aiNotes,
      listId: listId,
      priority: priority,
      dueDate: dueDate,
      estimatedMinutes: estimatedMinutes,
      recurrence: recurrence,
      recurrenceGroupId: recurrenceGroupId,
      canonicalOccurrenceDate: canonicalOccurrenceDate,
      plannedDate: plannedDate,
      availableFrom: availableFrom)
    try TaskRepo.Write.createTask(db, params: params)
  }
}

public enum TaskCreatePrepared {
  /// Hard cap on AI-notes length, in Unicode codepoints
  /// (``ValidationLimits/maxAiNotesLength``).
  public static let maxAiNotesLength: Int = ValidationLimits.maxAiNotesLength

  /// Build a validated, normalized ``PreparedTaskInsert`` from the workflow
  /// input.
  public static func prepareTaskInsert(
    _ db: Database,
    hlc: HlcSession,
    id: String,
    now: String,
    input: TaskCreateInput
  ) throws -> PreparedTaskInsert {
    // For create, `Patch.unset` and `Patch.clear` collapse to the same
    // NULL-on-insert. Lower everything to `Optional` immediately.
    let listIdOpt = patchToOptional(input.listId)
    let priorityOpt = patchToOptional(input.priority)
    let dueDateRaw = patchToOptional(input.dueDate)
    let estimatedMinutesOpt = patchToOptional(input.estimatedMinutes)
    let bodyRaw = patchToOptional(input.body)
    let rawInputRaw = patchToOptional(input.rawInput)
    let aiNotesRaw = patchToOptional(input.aiNotes)
    let recurrenceJsonOpt = patchToOptional(input.recurrenceJson)
    let plannedDateRaw = patchToOptional(input.plannedDate)
    let availableFromRaw = patchToOptional(input.availableFrom)
    let statusOpt = patchToOptional(input.status)

    // Status seeding: only `open` (default) or `someday`.
    let initialStatus: String
    switch statusOpt {
    case nil, StatusName.open?:
      initialStatus = StatusName.open
    case StatusName.someday?:
      initialStatus = StatusName.someday
    case .some(let other):
      throw StoreError.validation(
        "invalid initial status for task create: '\(other)' "
          + "(only 'open' or 'someday' accepted)")
    }

    let title = UnicodeHygiene.sanitizeUserText(input.title)
    let body = bodyRaw.map(UnicodeHygiene.sanitizeUserText)
    let aiNotes = aiNotesRaw.map(UnicodeHygiene.sanitizeUserText)
    let rawInput = rawInputRaw.map(UnicodeHygiene.sanitizeUserText)
    let tags = input.tags?.map(UnicodeHygiene.sanitizeUserText)

    if title.trimmingCharacters(in: .whitespaces).isEmpty
      || ValidationText.isVisuallyEmpty(title)
    {
      throw ValidationError.empty("title")
    }
    try throwOnValidationFailure(
      ValidationText.validateStringLength(
        title, field: "title", max: ValidationLimits.maxTitleLength))
    try throwOnValidationFailure(
      ValidationText.validateOptionalStringLength(
        body, field: "body", max: ValidationLimits.maxBodyLength))
    try throwOnValidationFailure(
      PayloadByteBudget.validateOptionalEscapedBudget(
        body, field: "body", budget: PayloadByteBudget.longTextEscapedBytes))
    try throwOnValidationFailure(
      ValidationText.validateOptionalStringLength(
        aiNotes, field: "ai_notes", max: maxAiNotesLength))
    try throwOnValidationFailure(
      PayloadByteBudget.validateOptionalEscapedBudget(
        aiNotes, field: "ai_notes", budget: PayloadByteBudget.aiNotesEscapedBytes))
    try throwOnValidationFailure(
      ValidationText.validateOptionalStringLength(
        rawInput, field: "raw_input", max: ValidationLimits.maxShortTextLength))
    if let tags {
      for tag in tags {
        try throwOnValidationFailure(
          ValidationText.validateStringLength(
            tag, field: "tag", max: ValidationLimits.maxShortTextLength))
      }
    }
    try validateCount(tags?.count ?? 0, max: ValidationLimits.maxTaskTags, field: "tags")
    try validateCount(
      input.dependsOn?.count ?? 0, max: ValidationLimits.maxTaskDependencies,
      field: "depends_on")
    try validateCount(input.reminders?.count ?? 0, max: 50, field: "reminders")

    // Recurrence canonicalization.
    var recurrence: String? = nil
    if let raw = recurrenceJsonOpt {
      switch ValidationRecurrence.normalizeTaskRecurrence(raw) {
      case .success(let normalized):
        recurrence = normalized  // already Optional<String>
      case .failure(let error):
        throw StoreError.validation(error.description)
      }
    }

    // List resolution (explicit + validate, or default_list preference).
    let resolvedListId: String? = try TaskClassification.resolveRequiredTaskListId(
      db, explicitListId: listIdOpt)

    if let deps = input.dependsOn {
      try validateTaskIdsExist(db, taskIds: deps, field: "depends_on")
    }
    let idTyped = TaskId(trusted: id)
    try DependencyValidation.validateNoDependencyCycle(
      db, taskId: idTyped, newDependsOn: input.dependsOn ?? [])

    let priorityNormalized = try normalizeTaskPriority(priorityOpt)
    let dueDate: String? = try dueDateRaw.map {
      try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: $0)
    }
    let plannedDate: String? = try plannedDateRaw.map {
      try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: $0)
    }
    let availableFrom: String? = try availableFromRaw.map {
      try TaskCreateDateParse.normalizeDueDateInputForConn(db, value: $0)
    }

    let tagsNormalized = tags.map(normalizeTags) ?? []
    let version = hlc.nextVersionString()

    // Plan recurrence transition.
    var planDue = dueDate
    let oldState = RecurrenceConfig.State(
      recurrence: nil,
      recurrenceGroupId: nil,
      canonicalOccurrenceDate: nil,
      dueDate: dueDate)
    let today = try WorkflowTimezone.todayYmdForConn(db)
    let (_, recActions) = RecurrenceConfig.planRecurrenceTransition(
      old: oldState, newRecurrence: recurrence, today: today)
    let recurrenceGroupId = recActions.setRecurrenceGroupId
    let canonicalOccurrenceDate: String?
    switch recActions.setCanonicalOccurrenceDate {
    case .set(let v): canonicalOccurrenceDate = v
    case .unset, .clear: canonicalOccurrenceDate = nil
    }
    if let fallback = recActions.setDueDate {
      planDue = fallback
    }

    return PreparedTaskInsert(
      id: id,
      title: title,
      dependsOn: input.dependsOn ?? [],
      tags: tagsNormalized,
      body: body,
      rawInput: rawInput,
      aiNotes: aiNotes,
      status: initialStatus,
      listId: resolvedListId,
      priority: priorityNormalized.map(Int64.init),
      dueDate: planDue,
      estimatedMinutes: estimatedMinutesOpt.map(Int64.init),
      recurrence: recurrence,
      recurrenceGroupId: recurrenceGroupId,
      canonicalOccurrenceDate: canonicalOccurrenceDate,
      plannedDate: plannedDate,
      availableFrom: availableFrom,
      version: version,
      now: now)
  }

  /// Build the canonical create summary string.
  ///
  /// Builds the summary `"Created task '<title>'[ in
  /// <list-name>][, due <due>][ (completed)]"`.
  public static func buildCreateSummary(
    _ db: Database, prepared: PreparedTaskInsert, completed: Bool
  ) throws -> String {
    var listName: String? = nil
    if let listId = prepared.listId {
      listName = try String.fetchOne(
        db, sql: "SELECT name FROM lists WHERE id = ?1", arguments: [listId])
    }
    let listPart = listName.map { " in \($0)" } ?? ""
    let duePart = prepared.dueDate.map { ", due \($0)" } ?? ""
    let completedPart = completed ? " (completed)" : ""
    return "Created task '\(prepared.title)'\(listPart)\(duePart)\(completedPart)"
  }

  // MARK: - shared helpers

  /// Validate a 1..=3 task priority value. `nil` passes through.
  public static func normalizeTaskPriority(_ value: UInt8?) throws -> UInt8? {
    guard let v = value else { return nil }
    if v >= 1 && v <= 3 { return v }
    throw StoreError.validation(
      "Invalid priority '\(v)'. Expected one of: 1, 2, 3")
  }

  /// Validate that every task id in `taskIds` is non-empty, parseable, and
  /// references a row in `tasks`.
  public static func validateTaskIdsExist(
    _ db: Database, taskIds: [String], field: String
  ) throws {
    for id in taskIds {
      if id.trimmingCharacters(in: .whitespaces).isEmpty {
        throw StoreError.validation("\(field) contains an empty task ID")
      }
      switch EntityID.parseIDWithSentinel(id, field: field, sentinel: nil) {
      case .success: break
      case .failure(let e): throw StoreError.validation(e.description)
      }
    }
    if taskIds.isEmpty { return }
    let deduped = Array(Set(taskIds)).sorted()
    let placeholders = Sql.sqlCsvPlaceholders(deduped.count)
    let sql = "SELECT id FROM tasks WHERE id IN (\(placeholders))"
    let existing = Set(
      try String.fetchAll(db, sql: sql, arguments: StatementArguments(deduped)))
    if let missing = taskIds.first(where: { !existing.contains($0) }) {
      throw StoreError.validation(
        "\(field) references non-existent task '\(missing)'")
    }
  }

  // MARK: - internals

  private static func patchToOptional<T>(_ p: Patch<T>) -> T? {
    if case let .set(v) = p { return v }
    return nil
  }

  private static func validateCount(
    _ count: Int, max: Int, field: String
  ) throws {
    if count > max {
      throw StoreError.validation(
        "\(field) supports at most \(max) item(s), got \(count)")
    }
  }

  private static func normalizeTags<S: Sequence>(_ tags: S) -> [String]
  where S.Element == String {
    var seen = Set<String>()
    var out: [String] = []
    for tag in tags {
      let normalized = tag.trimmingCharacters(in: .whitespaces).lowercased()
      if !normalized.isEmpty && seen.insert(normalized).inserted {
        out.append(normalized)
      }
    }
    return out
  }

  private static func throwOnValidationFailure(
    _ result: Result<Void, ValidationError>
  ) throws {
    if case .failure(let error) = result {
      throw StoreError.validation(error.description)
    }
  }
}
