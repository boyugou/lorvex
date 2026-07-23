import LorvexCore
import MCP

/// The single recurrence-rule wire contract shared by the task and calendar MCP
/// tools. Both surfaces advertise the same RFC-5545-aligned object (a required
/// `freq` axis plus named modifiers) and parse it the same way, so an AI client
/// introspecting either tool sees one recurrence shape instead of two.
///
/// The task variant carries `anchor` (schedule vs. completion); the calendar
/// variant omits it. Calendar events have no completion anchor — the calendar
/// normalizer rejects `ANCHOR` at runtime — so advertising it would promise a
/// value that always errors.
enum RecurrenceRuleSchema {
  private static let weekdayEnum: Value = .array([
    .string("MO"), .string("TU"), .string("WE"), .string("TH"),
    .string("FR"), .string("SA"), .string("SU"),
  ])

  /// Properties common to the task `rule` and calendar `recurrence` objects.
  private static var sharedProperties: [String: Value] {
    [
      "freq": .object([
        "type": .string("string"),
        "enum": .array([
          .string("DAILY"), .string("WEEKLY"), .string("MONTHLY"), .string("YEARLY"),
        ]),
      ]),
      "interval": .object(["type": .string("integer")]),
      "byday": .object([
        "type": .string("array"),
        "items": .object([
          "type": .string("string"),
          "pattern": .string(
            "^(?:[+-]?(?:[1-9]|[1-4][0-9]|5[0-3]))?(?:MO|TU|WE|TH|FR|SA|SU)$"),
          "description": .string(
            "Weekday code, optionally ordinal for MONTHLY/YEARLY (for example 1MO or -1FR). Runtime validation applies the frequency-specific ordinal limit."),
        ]),
      ]),
      "bymonth": .object([
        "type": .string("array"),
        "items": .object(["type": .string("integer")]),
      ]),
      "bymonthday": .object([
        "type": .string("array"),
        "items": .object(["type": .string("integer")]),
      ]),
      "bysetpos": .object([
        "type": .string("array"),
        "items": .object(["type": .string("integer")]),
      ]),
      "wkst": .object(["type": .string("string"), "enum": weekdayEnum]),
      "until": .object(["type": .string("string")]),
      "count": .object(["type": .string("integer")]),
    ]
  }

  /// The task `rule` object: the shared shape plus the completion/`schedule`
  /// anchor.
  static var taskRuleProperty: Value {
    var properties = sharedProperties
    properties["anchor"] = .object([
      "type": .string("string"),
      "enum": .array([.string("schedule"), .string("completion")]),
    ])
    return .object([
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array([.string("freq")]),
    ])
  }

  /// The calendar `recurrence` object: the shared shape, no `anchor`. The
  /// description records the calendar-only runtime limits JSON Schema can't
  /// express (see ``ValidationRecurrenceNormalize/normalizeCalendarRecurrence``):
  /// COUNT is capped at 365, and a MONTHLY/YEARLY `byday` needs an ordinal
  /// prefix or a `bysetpos`.
  static var calendarRecurrenceProperty: Value {
    .object([
      "type": .string("object"),
      "description": .string(calendarRecurrenceDetails),
      "properties": .object(sharedProperties),
      "required": .array([.string("freq")]),
    ])
  }

  /// Update-only form: omission preserves the stored rule, explicit null clears
  /// it, and an object replaces it. Create tools continue using the object-only
  /// property above.
  static var calendarRecurrencePatchProperty: Value {
    guard case .object(var schema) = calendarRecurrenceProperty else {
      return calendarRecurrenceProperty
    }
    schema["type"] = .array([.string("object"), .string("null")])
    schema["description"] = .string(
      "Recurrence patch. Omit to preserve the existing rule, send null to stop repeating, "
        + "or send a recurrence object to replace the rule. " + calendarRecurrenceDetails)
    return .object(schema)
  }

  private static let calendarRecurrenceDetails =
    "Recurrence rule — the same object set_task_recurrence takes, minus anchor. "
    + "freq is required (DAILY/WEEKLY/MONTHLY/YEARLY); optional "
    + "interval/byday/bymonth/bymonthday/bysetpos/wkst/until/count. Examples: "
    + "{\"freq\":\"WEEKLY\",\"byday\":[\"MO\",\"WE\",\"FR\"]}, "
    + "{\"freq\":\"MONTHLY\",\"bymonthday\":[1,15]}. Calendar-only limits the "
    + "schema can't express: count must be 1-365, and a MONTHLY/YEARLY byday "
    + "must carry an ordinal (e.g. \"1MO\", \"-1FR\") or be paired with bysetpos "
    + "(e.g. byday:[\"MO\"],bysetpos:[1] for the first Monday). Omit for a "
    + "non-recurring event. Calendar recurrence does not support a completion anchor."
}

/// Convert the typed recurrence object an MCP client sends (lowercase keys, the
/// ``RecurrenceRuleSchema`` shape) into the `[String: Any]` payload
/// ``TaskRecurrenceRule/bridgeRule(from:)`` decodes. A bare integer `bymonthday`
/// is accepted and wrapped to a single-element array. `anchor` is carried
/// through when present so the task path can read it; the calendar path never
/// advertises it and the calendar normalizer rejects it downstream.
struct RecurrenceRuleWireError: Error { let message: String }

/// Decode a homogeneous string array, REJECTING a non-array value or any
/// non-string element rather than silently dropping it. A dropped recurrence
/// token (e.g. a weekday in `byday`) would make the server accept a DIFFERENT
/// schedule than the caller sent — the exact silent-partial-apply hazard this
/// guards against. Returns nil only when the field is absent.
private func strictRecurrenceStringArray(_ value: Value?, field: String) throws -> [String]? {
  guard let value else { return nil }
  guard case .array(let elements) = value else {
    throw RecurrenceRuleWireError(message: "\(field) must be an array of strings.")
  }
  return try elements.map { element in
    guard let string = element.stringValue else {
      throw RecurrenceRuleWireError(
        message: "\(field) must contain only strings; got \(element).")
    }
    return string
  }
}

/// Decode a homogeneous integer array, rejecting a non-array value or any
/// non-integer element (see ``strictRecurrenceStringArray``). Returns nil when
/// the field is absent.
private func strictRecurrenceIntArray(_ value: Value?, field: String) throws -> [Int]? {
  guard let value else { return nil }
  guard case .array(let elements) = value else {
    throw RecurrenceRuleWireError(message: "\(field) must be an array of integers.")
  }
  return try elements.map { element in
    guard let int = element.intValue else {
      throw RecurrenceRuleWireError(
        message: "\(field) must contain only integers; got \(element).")
    }
    return int
  }
}

/// Decode one optional string scalar without treating a present wrong-typed
/// value as omission. JSON Schema is advisory at the MCP boundary; runtime
/// parsing must reject a request whose meaning would otherwise change.
private func strictRecurrenceString(_ value: Value?, field: String) throws -> String? {
  guard let value else { return nil }
  guard let string = value.stringValue else {
    throw RecurrenceRuleWireError(message: "\(field) must be a string.")
  }
  return string
}

/// Integer counterpart to ``strictRecurrenceString(_:field:)``.
private func strictRecurrenceInt(_ value: Value?, field: String) throws -> Int? {
  guard let value else { return nil }
  guard let int = value.intValue else {
    throw RecurrenceRuleWireError(message: "\(field) must be an integer.")
  }
  return int
}

func recurrenceRulePayload(from rule: [String: Value]) throws -> [String: Any] {
  var out: [String: Any] = [:]
  if let freq = try strictRecurrenceString(rule["freq"], field: "freq") {
    out["freq"] = freq
  }
  if let interval = try strictRecurrenceInt(rule["interval"], field: "interval") {
    out["interval"] = interval
  }
  if let byday = try strictRecurrenceStringArray(rule["byday"], field: "byday") {
    out["byday"] = byday
  }
  if let bymonth = try strictRecurrenceIntArray(rule["bymonth"], field: "bymonth") {
    out["bymonth"] = bymonth
  }
  // `bymonthday` accepts a bare integer (wrapped to a single-element array) as
  // well as an array; an array is decoded strictly, and a value that is neither
  // an integer nor an array is rejected rather than dropped.
  if let bymonthdayValue = rule["bymonthday"] {
    if case .array = bymonthdayValue {
      out["bymonthday"] = try strictRecurrenceIntArray(bymonthdayValue, field: "bymonthday")
    } else if let scalar = bymonthdayValue.intValue {
      out["bymonthday"] = [scalar]
    } else {
      throw RecurrenceRuleWireError(
        message: "bymonthday must be an integer or an array of integers.")
    }
  }
  if let bysetpos = try strictRecurrenceIntArray(rule["bysetpos"], field: "bysetpos") {
    out["bysetpos"] = bysetpos
  }
  if let wkst = try strictRecurrenceString(rule["wkst"], field: "wkst") {
    out["wkst"] = wkst
  }
  if let until = try strictRecurrenceString(rule["until"], field: "until") {
    out["until"] = until
  }
  if let count = try strictRecurrenceInt(rule["count"], field: "count") {
    out["count"] = count
  }
  if let anchor = try strictRecurrenceString(rule["anchor"], field: "anchor") {
    out["anchor"] = anchor
  }
  return out
}
