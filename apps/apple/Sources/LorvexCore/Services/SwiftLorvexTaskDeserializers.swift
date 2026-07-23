import Foundation
import LorvexDomain

/// Maps the core's enriched task JSON (`LorvexDomain.JSONValue`, produced by
/// `TaskResponse.loadEnrichedTaskJSON` and the workflow orchestrators) onto the
/// app's stable `LorvexCore` model types.
///
/// The core emits the enriched task wire shape: the 28 `TaskRow` columns plus
/// the five enrichment fields `tags`, `depends_on`, `checklist_items`,
/// `lateness_state`, `reminders`. This layer lowers a `JSONValue` to a
/// Foundation `[String: Any]` and feeds it through the `task(from:)` mapping
/// that the dependent views consume. The only behavioral seam is the
/// `JSONValue → Any?` lowering, which matches how `JSONSerialization` decodes
/// the equivalent JSON.
enum SwiftLorvexTaskDeserializers {

  // MARK: - JSONValue → Foundation lowering

  /// Lower a `JSONValue` to the Foundation `Any?` tree the `task(from:)` family
  /// consumes. `null` lowers to `NSNull` so the object/array shape matches what
  /// `JSONSerialization` would have produced from the bridge's JSON text.
  static func lower(_ value: JSONValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let b): return b
    case .int(let i): return Int(i)
    case .uint(let u): return u
    case .double(let d): return d
    case .string(let s): return s
    case .array(let arr): return arr.map(lower)
    case .object(let obj):
      var out: [String: Any] = [:]
      out.reserveCapacity(obj.count)
      for (key, element) in obj { out[key] = lower(element) }
      return out
    }
  }

  /// Lower a `JSONValue` known to be an object into a `[String: Any]` map,
  /// returning an empty map for any non-object value.
  static func lowerObject(_ value: JSONValue) -> [String: Any] {
    lower(value) as? [String: Any] ?? [:]
  }

  // MARK: - Task mapping

  static func task(_ value: JSONValue) throws -> LorvexTask {
    try task(from: lowerObject(value))
  }

  static func tasks(_ values: [JSONValue]) throws -> [LorvexTask] {
    try values.map(task)
  }

  /// Map one enriched task object (the core's `get_task`/`list_tasks` row shape)
  /// onto a `LorvexTask` for app-side rendering.
  ///
  /// Fails loud on a schema-contract violation instead of fabricating: a missing
  /// or mistyped required field (`id`, `title`, `status`) and an unknown
  /// closed-enum value (`priority` tier, `status`) each throw
  /// ``LorvexCoreError/malformedCoreData(path:reason:)`` with the offending
  /// field path. Nullable columns (`body`, `priority`, dates) keep their
  /// model-level empty representation.
  static func task(from object: [String: Any]) throws -> LorvexTask {
    let statusText = try requiredString(object, key: "status", path: "task.status")
    guard let status = LorvexTask.Status(rawValue: statusText) else {
      throw LorvexCoreError.malformedCoreData(
        path: "task.status", reason: "unknown status \"\(statusText)\"")
    }
    return LorvexTask(
      id: try requiredString(object, key: "id", path: "task.id"),
      title: try requiredString(object, key: "title", path: "task.title"),
      notes: object["body"] as? String ?? "",
      aiNotes: object["ai_notes"] as? String,
      rawInput: object["raw_input"] as? String,
      priority: try priority(from: object["priority"]),
      status: status,
      dueDate: date(from: object, column: "due_date"),
      plannedDate: date(from: object, column: "planned_date"),
      availableFrom: date(from: object, column: "available_from"),
      estimatedMinutes: object["estimated_minutes"] as? Int,
      tags: try stringArray(from: object["tags"], path: "task.tags"),
      dependsOn: try stringArray(from: object["depends_on"], path: "task.depends_on"),
      checklistItems: try checklistItems(from: object["checklist_items"]),
      reminders: try reminders(from: object["reminders"]),
      latenessState: latenessState(from: object["lateness_state"]),
      recurrence: TaskRecurrenceRule.bridgeRule(from: object["recurrence"]),
      recurrenceExceptions: TaskRecurrenceRule.bridgeExceptionDates(
        from: object["recurrence_exceptions"]),
      listID: object["list_id"] as? String,
      deferCount: object["defer_count"] as? Int ?? 0,
      lastDeferReason: object["last_defer_reason"] as? String,
      lastDeferredAt: object["last_deferred_at"] as? String,
      createdAt: object["created_at"] as? String,
      updatedAt: object["updated_at"] as? String,
      completedAt: object["completed_at"] as? String,
      archivedAt: object["archived_at"] as? String)
  }

  /// Decode the `tasks.priority` value. The column is nullable, and the app
  /// model's ``LorvexTask/Priority`` is a closed P1/P2/P3 enum with no "no
  /// priority" case, so an absent/null value maps to `.p2` (the neutral middle
  /// tier that `priority_effective` also treats as the default rank). A present
  /// value must be an integer tier of 1, 2, or 3 — any other integer or type is
  /// a closed-enum contract break and throws.
  static func priority(from value: Any?) throws -> LorvexTask.Priority {
    guard let value, !(value is NSNull) else { return .p2 }
    guard let tier = value as? Int else {
      throw LorvexCoreError.malformedCoreData(
        path: "task.priority", reason: "expected an integer tier, got \(typeName(value))")
    }
    guard let priority = LorvexTask.Priority(tier: tier) else {
      throw LorvexCoreError.malformedCoreData(
        path: "task.priority", reason: "unknown priority tier \(tier); expected 1, 2, or 3")
    }
    return priority
  }

  static func checklistItems(from value: Any?) throws -> [TaskChecklistItem] {
    guard let value, !(value is NSNull) else { return [] }
    guard let rows = value as? [Any] else {
      throw LorvexCoreError.malformedCoreData(
        path: "task.checklist_items", reason: "expected an array, got \(typeName(value))")
    }
    return try rows.enumerated().map { index, element in
      let path = "task.checklist_items[\(index)]"
      guard let row = element as? [String: Any] else {
        throw LorvexCoreError.malformedCoreData(
          path: path, reason: "expected an object, got \(typeName(element))")
      }
      return TaskChecklistItem(
        id: try requiredString(row, key: "id", path: "\(path).id"),
        taskID: try requiredString(row, key: "task_id", path: "\(path).task_id"),
        position: try requiredInt(row, key: "position", path: "\(path).position"),
        text: try requiredString(row, key: "text", path: "\(path).text"),
        completedAt: row["completed_at"] as? String,
        createdAt: row["created_at"] as? String,
        updatedAt: row["updated_at"] as? String)
    }
  }

  static func reminders(from value: Any?) throws -> [TaskReminder] {
    guard let value, !(value is NSNull) else { return [] }
    guard let rows = value as? [Any] else {
      throw LorvexCoreError.malformedCoreData(
        path: "task.reminders", reason: "expected an array, got \(typeName(value))")
    }
    return try rows.enumerated().map { index, element in
      let path = "task.reminders[\(index)]"
      guard let row = element as? [String: Any] else {
        throw LorvexCoreError.malformedCoreData(
          path: path, reason: "expected an object, got \(typeName(element))")
      }
      return TaskReminder(
        id: try requiredString(row, key: "id", path: "\(path).id"),
        reminderAt: try requiredString(row, key: "reminder_at", path: "\(path).reminder_at"),
        status: row["status"] as? String,
        dismissedAt: row["dismissed_at"] as? String,
        cancelledAt: row["cancelled_at"] as? String,
        createdAt: row["created_at"] as? String,
        originalLocalTime: row["original_local_time"] as? String,
        originalTz: row["original_tz"] as? String)
    }
  }

  static func latenessState(from value: Any?) -> String? {
    if let text = value as? String { return text }
    if let object = value as? [String: Any] {
      return object["state"] as? String ?? object["kind"] as? String
        ?? object["status"] as? String
    }
    return nil
  }

  /// Decode a JSON array of strings (`tags`, `depends_on`). A wrong-typed
  /// element is a contract break and throws rather than being silently dropped;
  /// an absent/null field is an empty array. `path` names the field for the
  /// error's element path (e.g. `task.tags[3]`).
  static func stringArray(from value: Any?, path: String) throws -> [String] {
    guard let value, !(value is NSNull) else { return [] }
    guard let values = value as? [Any] else {
      throw LorvexCoreError.malformedCoreData(
        path: path, reason: "expected an array, got \(typeName(value))")
    }
    return try values.enumerated().map { index, element in
      guard let string = element as? String else {
        throw LorvexCoreError.malformedCoreData(
          path: "\(path)[\(index)]", reason: "expected a string, got \(typeName(element))")
      }
      return string
    }
  }

  /// Read a schema-required string field, throwing when the key is absent, the
  /// value is JSON `null`, or the value is not a string.
  static func requiredString(
    _ object: [String: Any], key: String, path: String
  ) throws -> String {
    guard let value = object[key], !(value is NSNull) else {
      throw LorvexCoreError.malformedCoreData(path: path, reason: "required field is missing")
    }
    guard let string = value as? String else {
      throw LorvexCoreError.malformedCoreData(
        path: path, reason: "expected a string, got \(typeName(value))")
    }
    return string
  }

  /// Read a schema-required integer field, throwing when the key is absent, the
  /// value is JSON `null`, or the value is not an integer.
  static func requiredInt(_ object: [String: Any], key: String, path: String) throws -> Int {
    guard let value = object[key], !(value is NSNull) else {
      throw LorvexCoreError.malformedCoreData(path: path, reason: "required field is missing")
    }
    guard let number = value as? Int else {
      throw LorvexCoreError.malformedCoreData(
        path: path, reason: "expected an integer, got \(typeName(value))")
    }
    return number
  }

  /// Human-readable type name for a lowered Foundation value, used in decode
  /// error reasons. `NSNull` renders as `null` to match the JSON contract.
  static func typeName(_ value: Any) -> String {
    value is NSNull ? "null" : String(describing: type(of: value))
  }

  /// Parse a `YYYY-MM-DD` (UTC) date column (`due_date` or `planned_date`)
  /// into a `Date`. Returns nil when the column is absent or empty. The two
  /// columns are independent: `due_date` is the external deadline,
  /// `planned_date` the intended work day.
  static func date(from object: [String: Any], column: String) -> Date? {
    guard let raw = object[column] as? String, !raw.isEmpty else { return nil }
    return plannedDateFormatter.date(from: raw)
  }

  /// Formats/parses `due_date` and `planned_date` day keys. Both are stored as
  /// `YYYY-MM-DD` materialized at UTC midnight, so this is the **UTC** `ymd`
  /// formatter — using the current-time-zone `ymd` would shift the day across
  /// the date line for users east/west of GMT and round-trip a different date.
  static var plannedDateFormatter: DateFormatter { LorvexDateFormatters.ymdUTC }
}
