import Foundation

/// Structured recurrence rule for a Lorvex task. An RFC 5545-aligned shape:
/// a `freq` axis plus a handful of named modifiers. `byDay` carries 2-letter
/// weekday codes (`MO`, `TU`, ...); `until` is an ISO date / datetime string;
/// `count` and `until` are mutually exclusive on the canonical normalization
/// side, but the type itself does not enforce that — the validation
/// happens server-side.
public struct TaskRecurrenceRule: Equatable, Sendable {
  public enum Frequency: String, Sendable, CaseIterable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"
  }

  /// What the next occurrence is measured from.
  ///
  /// - `schedule` (default): fixed calendar cadence anchored on the task's
  ///   canonical occurrence date — every Monday, the 1st of each month, etc.
  /// - `completion`: the next occurrence lands `interval` `freq`-units after the
  ///   task is *completed*, so a task finished late slips forward rather than
  ///   piling up missed occurrences. Positional modifiers (`byDay`/`byMonth`/…)
  ///   are meaningless in this mode and must be absent.
  public enum Anchor: String, Sendable, CaseIterable {
    case schedule = "schedule"
    case completion = "completion"
  }

  public var freq: Frequency
  public var interval: Int?
  public var byDay: [String]?
  public var byMonth: [Int]?
  public var byMonthDay: [Int]?
  public var bySetPos: [Int]?
  public var wkst: String?
  public var until: String?
  public var count: Int?
  public var anchor: Anchor

  public init(
    freq: Frequency,
    interval: Int? = nil,
    byDay: [String]? = nil,
    byMonth: [Int]? = nil,
    byMonthDay: [Int]? = nil,
    bySetPos: [Int]? = nil,
    wkst: String? = nil,
    until: String? = nil,
    count: Int? = nil,
    anchor: Anchor = .schedule
  ) {
    self.freq = freq
    self.interval = interval
    self.byDay = byDay
    self.byMonth = byMonth
    self.byMonthDay = byMonthDay
    self.bySetPos = bySetPos
    self.wkst = wkst
    self.until = until
    self.count = count
    self.anchor = anchor
  }
}

extension TaskRecurrenceRule {
  /// The snake_case wire shape (lower-case `freq` token) the MCP recurrence
  /// value adapter serializes when emitting the rule to clients.
  public func bridgePayload() -> [String: Any] {
    var payload: [String: Any] = ["freq": freq.rawValue.lowercased()]
    if let interval { payload["interval"] = interval }
    if let byDay, !byDay.isEmpty { payload["byday"] = byDay }
    if let byMonth, !byMonth.isEmpty { payload["bymonth"] = byMonth }
    if let byMonthDay, !byMonthDay.isEmpty { payload["bymonthday"] = byMonthDay }
    if let bySetPos, !bySetPos.isEmpty { payload["bysetpos"] = bySetPos }
    if let wkst { payload["wkst"] = wkst }
    if let until { payload["until"] = until }
    if let count { payload["count"] = count }
    // Omit the default schedule anchor so a fixed-cadence rule's wire shape is
    // unchanged.
    if anchor == .completion { payload["anchor"] = anchor.rawValue }
    return payload
  }

  /// Serialize to the RFC-5545-keyed JSON string (`{"FREQ":…,"BYMONTHDAY":[…]}`)
  /// the recurrence normalizer reads.
  ///
  /// Distinct from ``bridgePayload()``, which emits the lowercase, client-facing
  /// wire shape: this uses the uppercase canonical key spellings the calendar /
  /// task recurrence normalizer expects on input. The normalizer re-canonicalizes
  /// (sorted keys) and re-validates, so key order here is not significant. The
  /// default `schedule` anchor is omitted; `completion` is emitted verbatim (the
  /// calendar normalizer rejects it, matching the string path). Returns `nil`
  /// only if the rule somehow fails JSON serialization.
  public func canonicalRecurrenceJSON() -> String? {
    var object: [String: Any] = ["FREQ": freq.rawValue]
    if let interval { object["INTERVAL"] = interval }
    if let byDay, !byDay.isEmpty { object["BYDAY"] = byDay }
    if let byMonth, !byMonth.isEmpty { object["BYMONTH"] = byMonth }
    if let byMonthDay, !byMonthDay.isEmpty { object["BYMONTHDAY"] = byMonthDay }
    if let bySetPos, !bySetPos.isEmpty { object["BYSETPOS"] = bySetPos }
    if let wkst { object["WKST"] = wkst }
    if let until { object["UNTIL"] = until }
    if let count { object["COUNT"] = count }
    if anchor == .completion { object["ANCHOR"] = anchor.rawValue }
    guard JSONSerialization.isValidJSONObject(object),
      let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
      let string = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return string
  }

  public static func bridgeRule(from value: Any?) -> TaskRecurrenceRule? {
    if let object = value as? [String: Any] {
      return bridgeRule(fromObject: object)
    }
    guard
      let text = value as? String,
      let data = text.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return bridgeRule(fromObject: object)
  }

  public static func bridgeExceptionDates(from value: Any?) -> [String] {
    if let strings = value as? [String] {
      return strings
    }
    guard
      let text = value as? String,
      let data = text.data(using: .utf8),
      let strings = try? JSONSerialization.jsonObject(with: data) as? [String]
    else {
      return []
    }
    return strings
  }

  private static func bridgeRule(fromObject object: [String: Any]) -> TaskRecurrenceRule? {
    guard
      let rawFreq = stringValue(object, keys: ["freq", "FREQ"]),
      let frequency = Frequency(rawValue: rawFreq.uppercased())
    else {
      return nil
    }

    return TaskRecurrenceRule(
      freq: frequency,
      interval: intValue(object, keys: ["interval", "INTERVAL"]),
      byDay: stringArray(object, keys: ["byday", "BYDAY", "byDay"]),
      byMonth: intArray(object, keys: ["bymonth", "BYMONTH", "byMonth"]),
      byMonthDay: intArray(object, keys: ["bymonthday", "BYMONTHDAY", "byMonthDay"]),
      bySetPos: intArray(object, keys: ["bysetpos", "BYSETPOS", "bySetPos"]),
      wkst: stringValue(object, keys: ["wkst", "WKST"]),
      until: stringValue(object, keys: ["until", "UNTIL"]),
      count: intValue(object, keys: ["count", "COUNT"]),
      anchor: stringValue(object, keys: ["anchor", "ANCHOR"])
        .flatMap(Anchor.init(rawValue:)) ?? .schedule
    )
  }

  private static func stringValue(_ object: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = object[key] as? String, !value.isEmpty {
        return value
      }
    }
    return nil
  }

  private static func intValue(_ object: [String: Any], keys: [String]) -> Int? {
    for key in keys {
      if let value = object[key] as? Int {
        return value
      }
      if let value = object[key] as? String, let int = Int(value) {
        return int
      }
    }
    return nil
  }

  private static func stringArray(_ object: [String: Any], keys: [String]) -> [String]? {
    for key in keys {
      if let value = object[key] as? [String], !value.isEmpty {
        return value
      }
      if let value = object[key] as? String, !value.isEmpty {
        return value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
      }
    }
    return nil
  }

  private static func intArray(_ object: [String: Any], keys: [String]) -> [Int]? {
    for key in keys {
      if let value = object[key] as? [Int], !value.isEmpty {
        return value
      }
      if let value = object[key] as? [String] {
        let ints = value.compactMap(Int.init)
        if !ints.isEmpty {
          return ints
        }
      }
      // Accept scalar wire values (`15`) for array fields by wrapping to `[15]`.
      if let value = object[key] as? Int {
        return [value]
      }
      if let value = object[key] as? String, let int = Int(value) {
        return [int]
      }
    }
    return nil
  }
}
