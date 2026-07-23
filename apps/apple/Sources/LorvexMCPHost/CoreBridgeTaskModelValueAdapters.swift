import Foundation
import LorvexCore
import MCP

struct TaskValueOptions: Sendable, Equatable {
  enum Shape: String, Sendable {
    case compact
    case full
  }

  var shape: Shape
  var includeNulls: Bool
  var fields: Set<String>?
  var include: Set<String>

  static let full = TaskValueOptions(shape: .full, includeNulls: true)
  static let compact = TaskValueOptions(shape: .compact, includeNulls: false)

  init(
    shape: Shape = .compact,
    includeNulls: Bool = false,
    fields: Set<String>? = nil,
    include: Set<String> = []
  ) {
    self.shape = shape
    self.includeNulls = includeNulls
    self.fields = fields
    self.include = include
  }

  static func from(arguments: [String: Value], defaultShape: Shape = .compact) throws
    -> TaskValueOptions
  {
    let shape = Shape(
      rawValue: try StrictScalarArguments.string(
        arguments["shape"], field: "shape", default: defaultShape.rawValue))
      ?? defaultShape
    let requestedFields = try StrictArgumentArray.optionalStrings(
      arguments["fields"], field: "fields")
    let fields = requestedFields.map { Set($0.map(Self.normalizedKey)) }
    let include = Set(
      (try StrictArgumentArray.optionalStrings(arguments["include"], field: "include") ?? [])
        .map(Self.normalizedKey))
    return TaskValueOptions(
      shape: shape,
      includeNulls: try StrictScalarArguments.bool(
        arguments["include_nulls"], field: "include_nulls", default: shape == .full),
      fields: fields,
      include: include)
  }

  func filtered(_ fields: [String: Value]) -> [String: Value] {
    var out: [String: Value] = [:]
    for key in fields.keys.sorted() {
      guard wants(key) else { continue }
      guard let value = fields[key] else { continue }
      if shouldDrop(value, key: key) { continue }
      out[key] = value
    }
    return out
  }

  private func wants(_ key: String) -> Bool {
    if let requested = fields {
      return key == "id" || requested.contains(key)
    }
    if shape == .full { return true }
    return Self.compactDefaultFields.contains(key)
      || include.contains(Self.group(for: key))
      || include.contains(key)
  }

  private func shouldDrop(_ value: Value, key: String) -> Bool {
    switch value {
    case .null:
      if fields?.contains(key) == true { return false }
      return !includeNulls
    case .array(let values):
      if shape == .full {
        return false
      }
      if values.isEmpty {
        return !(fields?.contains(key) == true || include.contains(Self.group(for: key)))
      }
      return false
    default:
      return false
    }
  }

  private static let compactDefaultFields: Set<String> = [
    "id", "title", "priority", "priority_label", "status", "list_id", "estimated_minutes",
    "due_date", "planned_date", "available_from", "tags", "defer_count", "last_defer_reason",
    "last_deferred_at", "created_at", "updated_at", "completed_at",
  ]

  private static func group(for key: String) -> String {
    switch key {
    case "notes": return "notes"
    case "ai_notes": return "ai_notes"
    case "raw_input": return "raw_input"
    case "due_date", "planned_date", "available_from", "estimated_minutes": return "scheduling"
    case "created_at", "updated_at", "completed_at": return "lifecycle"
    case "tags": return "tags"
    case "depends_on": return "dependencies"
    case "checklist_items": return "checklist"
    case "reminders": return "reminders"
    case "recurrence", "recurrence_exceptions": return "recurrence"
    case "defer_count", "last_defer_reason", "last_deferred_at": return "defer"
    case "lateness_state": return "lateness"
    default: return key
    }
  }

  private static func normalizedKey(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  /// Every task field key `CoreBridgeClient.taskValue(from:)` can emit. The
  /// `fields` argument selects from this closed set; published as the `fields`
  /// schema enum so clients see the valid values instead of an open string array.
  static let fieldNames: [String] = [
    "id", "title", "notes", "ai_notes", "raw_input", "priority", "priority_label",
    "status", "list_id", "estimated_minutes", "due_date", "planned_date",
    "available_from", "recurrence", "recurrence_exceptions", "tags", "depends_on",
    "checklist_items", "reminders", "lateness_state", "defer_count",
    "last_defer_reason", "last_deferred_at", "created_at", "updated_at",
    "completed_at",
  ]

  /// Every valid `include` value: the field-group names plus the individual field
  /// names, both of which `wants(_:)` honors. Derived from `fieldNames` and
  /// `group(for:)` so it can't drift from the projection logic. Published as the
  /// `include` schema enum.
  static let includeValues: [String] = {
    var values = Set(fieldNames)
    for name in fieldNames { values.insert(group(for: name)) }
    return values.sorted()
  }()
}

/// Maps the `LorvexCore` task model types onto the MCP `Value` JSON shapes the
/// task tool handlers return. Field names and shapes mirror the contract
/// expected by existing MCP clients, so external integrations see stable task
/// objects while the implementation stays pure Swift.
extension CoreBridgeClient {
  static var plannedDateFormatter: DateFormatter { LorvexDateFormatters.ymdUTC }

  /// Parses an optional `planned_date` argument with explicit clear semantics.
  ///
  /// `nil`/empty means "clear the due date" (the client deliberately passed no
  /// date). A non-empty string must be a valid `YYYY-MM-DD` date; a malformed
  /// value throws rather than silently coercing to nil, which would erase the
  /// task's existing due date without telling the caller.
  static func resolveOptionalPlannedDate(_ raw: String?) throws -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return try requirePlannedDate(raw)
  }

  /// Parses a required `planned_date` argument, throwing on a malformed value
  /// instead of falling back to the current date.
  static func requirePlannedDate(_ raw: String) throws -> Date {
    guard let date = plannedDateFormatter.date(from: raw) else {
      throw TaskMutationToolStoreError(
        message: "planned_date must be a valid YYYY-MM-DD date.")
    }
    return date
  }

  static func taskValue(from task: LorvexTask, options: TaskValueOptions = .full) -> Value {
    let dueDate = task.dueDate.map { plannedDateFormatter.string(from: $0) }
    let plannedDate = task.plannedDate.map { plannedDateFormatter.string(from: $0) }
    let availableFrom = task.availableFrom.map { plannedDateFormatter.string(from: $0) }
    // Built as a mutable dictionary rather than one literal: the full set of
    // fields exceeds the Swift type-checker's single-expression budget.
    var fields: [String: Value] = [
      "id": .string(task.id),
      "title": .string(task.title),
      "notes": .string(task.notes),
      "ai_notes": task.aiNotes.map(Value.string) ?? .null,
      "raw_input": task.rawInput.map(Value.string) ?? .null,
      "priority": .int(task.priority.tier),
      "priority_label": .string(task.priority.rawValue),
      "status": .string(task.status.rawValue),
      "list_id": task.listID.map(Value.string) ?? .null,
      "estimated_minutes": task.estimatedMinutes.map(Value.int) ?? .null,
      "due_date": dueDate.map(Value.string) ?? .null,
      "planned_date": plannedDate.map(Value.string) ?? .null,
      "available_from": availableFrom.map(Value.string) ?? .null,
      "recurrence": recurrencePayloadValue(task.recurrence),
      "recurrence_exceptions": recurrenceExceptionsValue(task.recurrenceExceptions),
      "tags": .array(task.tags.map(Value.string)),
      "depends_on": .array(task.dependsOn.map(Value.string)),
      "checklist_items": .array(task.checklistItems.map(checklistItemValue(from:))),
      "reminders": .array(task.reminders.map(reminderValue(from:))),
    ]
    fields["lateness_state"] = task.latenessState.map(Value.string) ?? .null
    fields["defer_count"] = .int(task.deferCount)
    fields["last_defer_reason"] = task.lastDeferReason.map(Value.string) ?? .null
    fields["last_deferred_at"] = task.lastDeferredAt.map(Value.string) ?? .null
    fields["created_at"] = task.createdAt.map(Value.string) ?? .null
    fields["updated_at"] = task.updatedAt.map(Value.string) ?? .null
    fields["completed_at"] = task.completedAt.map(Value.string) ?? .null
    return .object(options.filtered(fields))
  }

  static func taskValues(from tasks: [LorvexTask], options: TaskValueOptions = .full) -> Value {
    .array(tasks.map { taskValue(from: $0, options: options) })
  }

  /// The shared slim task-summary projection. Overview `top_tasks`,
  /// dependency-graph nodes, weekly-brief items, and the task context embedded in
  /// reminder rows all emit this identical base shape, so a client parses one task
  /// summary everywhere rather than a different one per surface. Every base key is
  /// always present with uniform nullability — in particular `list_id`, which is
  /// nullable across every task projection (the full task and this summary alike);
  /// an empty list id collapses to null.
  ///
  /// Surface-specific fields (e.g. `completed_at` / `defer_count` on
  /// weekly-brief items) are layered on via `extra`, which is merged on top of
  /// the base keys.
  static func slimTaskSummaryValue(
    id: String,
    title: String,
    status: String,
    listID: String?,
    priority: Int?,
    dueDate: String?,
    plannedDate: String?,
    extra: [String: Value] = [:]
  ) -> Value {
    let listValue: Value = (listID?.isEmpty == false) ? .string(listID ?? "") : .null
    var object: [String: Value] = [
      "id": .string(id),
      "title": .string(title),
      "status": .string(status),
      "list_id": listValue,
      "priority": priority.map(Value.int) ?? .null,
      "due_date": dueDate.map(Value.string) ?? .null,
      "planned_date": plannedDate.map(Value.string) ?? .null,
    ]
    for (key, value) in extra { object[key] = value }
    return .object(object)
  }

  /// Serialize a recurrence rule to the lowercase-keyed MCP object clients read
  /// (``TaskRecurrenceRule/bridgePayload()``). Shared by task and calendar
  /// responses so both surfaces emit the identical `recurrence` shape; `nil`
  /// yields `.null`.
  static func recurrencePayloadValue(_ rule: TaskRecurrenceRule?) -> Value {
    guard let rule else { return .null }
    return value(fromJSONCompatible: rule.bridgePayload()) ?? .null
  }

  private static func recurrenceExceptionsValue(_ exceptions: [String]) -> Value {
    guard !exceptions.isEmpty else { return .null }
    return .array(exceptions.map(Value.string))
  }

  private static func checklistItemValue(from item: TaskChecklistItem) -> Value {
    .object([
      "id": .string(item.id),
      "task_id": .string(item.taskID),
      "position": .int(item.position),
      "text": .string(item.text),
      "completed_at": item.completedAt.map(Value.string) ?? .null,
    ])
  }

  private static func reminderValue(from reminder: TaskReminder) -> Value {
    .object([
      "id": .string(reminder.id),
      "reminder_at": .string(reminder.reminderAt),
      // Named to match the DB column and the standalone reminder-query tools;
      // `status` on a reminder would collide with a task's `status`.
      "delivery_state": reminder.status.map(Value.string) ?? .null,
    ])
  }

  private static func value(fromJSONCompatible raw: Any) -> Value? {
    switch raw {
    case let value as String:
      return .string(value)
    case let value as Bool:
      return .bool(value)
    case let value as Int:
      return .int(value)
    case let value as Int64:
      return .int(Int(value))
    case let value as [Any]:
      return .array(value.compactMap(value(fromJSONCompatible:)))
    case let dictionary as [String: Any]:
      var object: [String: Value] = [:]
      for key in dictionary.keys.sorted() {
        object[key] = value(fromJSONCompatible: dictionary[key] as Any)
      }
      return .object(object)
    case is NSNull:
      return .null
    default:
      return nil
    }
  }
}
