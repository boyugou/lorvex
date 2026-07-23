import Foundation

// MARK: - CanonicalCalendarEventType

/// The closed canonical set of `calendar_events.event_type` values. Every
/// trust boundary (IPC entry, sync apply, store repository, schema CHECK)
/// rejects any value outside this set; there is no tolerant `unknown`
/// catch-all.
///
/// Wire form is the snake_case tag string (`"event"`, `"birthday"`,
/// `"anniversary"`, `"memorial"`) — byte-identical to the persisted column
/// values.
public enum CanonicalCalendarEventType: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
  case event
  case birthday
  case anniversary
  case memorial

  /// Allowed wire values in declaration order.
  public static let allowedValues: [String] = ["event", "birthday", "anniversary", "memorial"]

  /// Human-readable list of the allowed values, used in validation messages.
  public static let allowedValuesDisplay: String = "event, birthday, anniversary, memorial"

  /// Canonical wire form (e.g. `"event"`).
  public var asString: String { rawValue }

  /// Parse a free-text candidate against the canonical set. Returns `nil`
  /// when the input is not one of the canonical tags.
  public static func parse(_ value: String) -> CanonicalCalendarEventType? {
    CanonicalCalendarEventType(rawValue: value)
  }

  /// Validate a free-text candidate against the canonical set. Returns the
  /// parsed enum on success, or a clean error string on failure suitable
  /// for direct embedding in user-facing validation messages.
  public static func validate(_ value: String) -> CanonicalCalendarEventTypeValidation {
    if let parsed = parse(value) {
      return .success(parsed)
    }
    return .failure("event_type must be one of: \(allowedValuesDisplay)")
  }

  // Codable: emit/accept only canonical tags. A non-canonical tag fails
  // decode (mirroring serde's rejection of unknown variants).
  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    guard let parsed = CanonicalCalendarEventType(rawValue: raw) else {
      throw DecodingError.dataCorrupted(
        .init(
          codingPath: decoder.codingPath,
          debugDescription: "event_type must be one of: \(Self.allowedValuesDisplay)"))
    }
    self = parsed
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// Result of `CanonicalCalendarEventType.validate(_:)`. `success` carries
/// the parsed enum; `failure` carries the canonical error message.
public enum CanonicalCalendarEventTypeValidation: Sendable, Equatable {
  case success(CanonicalCalendarEventType)
  case failure(String)
}

// MARK: - AllDayPatch

/// Tri-state intent for a calendar event update patch's `all_day` flag.
/// `setAllDay` and `setTimed` carry an explicit change; `noChange` leaves
/// the existing flag untouched.
public enum AllDayPatch: Sendable, Equatable, Hashable {
  /// Patch did not specify an `all_day` intent; leave the existing flag.
  case noChange
  /// Set `all_day = true` (all-day event; start_time / end_time must clear).
  case setAllDay
  /// Set `all_day = false` (timed event).
  case setTimed

  /// Build from the boundary `Bool?` shape used by IPC / CLI argument
  /// parsers. `nil → noChange`, `true → setAllDay`, `false → setTimed`.
  public static func fromOptionalBool(_ value: Bool?) -> AllDayPatch {
    switch value {
    case .none: return .noChange
    case .some(true): return .setAllDay
    case .some(false): return .setTimed
    }
  }

  /// The resulting `all_day` bool when the patch carries a change, or
  /// `nil` when the patch leaves the flag alone.
  public var targetValue: Bool? {
    switch self {
    case .noChange: return nil
    case .setAllDay: return true
    case .setTimed: return false
    }
  }

  /// True iff the patch carries an `all_day` change of any kind.
  public var isPresent: Bool {
    self != .noChange
  }
}

// MARK: - CalendarEventTiming

/// The three legal temporal shapes a calendar event row can take. Replaces
/// the implicit `(start_date, start_time, end_date, end_time, all_day)`
/// quintuple so every illegal combination is non-representable.
///
/// The five-field `(start_date, start_time, end_date, end_time, all_day)`
/// wire/column shape is validated into this enum via
/// ``fromFlatFields(startDate:startTime:endDate:endTime:allDay:)``.
public enum CalendarEventTiming: Sendable, Equatable, Hashable {
  /// `all_day = true`, no times. `end` is `nil` for a single-day all-day
  /// event; non-nil for a multi-day all-day span where `end >= start`.
  case allDay(start: LorvexDate, end: LorvexDate?)
  /// `all_day = false`, single-day timed event: `end_date == start_date`
  /// is implied (serialized as `end_date = nil`). `end` time is `nil` for
  /// a point-in-time event, non-nil for a duration where `end >= start`.
  case timedSingleDay(date: LorvexDate, start: TimeOfDay, end: TimeOfDay?)
  /// `all_day = false`, multi-day timed span. Both ends carry a time;
  /// `(end_date, end_time) >= (start_date, start_time)` lexicographically.
  case timedMultiDay(
    startDate: LorvexDate, startTime: TimeOfDay, endDate: LorvexDate, endTime: TimeOfDay)

  /// Construct a `CalendarEventTiming` from the flat five-field shape
  /// that flows through SQL row reads, JSON deserialize, and IPC / CLI
  /// argument boundaries.
  ///
  /// Validation rules:
  /// - `allDay = true` → both times must be nil; `endDate` optional, must
  ///   be `>= startDate` when present.
  /// - `allDay = false` → `startTime` required. Single-day (endDate nil or
  ///   equal to startDate): `endTime` optional, must be `>= startTime`
  ///   when present. Multi-day (`endDate > startDate`): both `startTime`
  ///   and `endTime` required; `(endDate, endTime) >= (startDate, startTime)`.
  public static func fromFlatFields(
    startDate: LorvexDate,
    startTime: TimeOfDay?,
    endDate: LorvexDate?,
    endTime: TimeOfDay?,
    allDay: Bool
  ) -> Result<CalendarEventTiming, ValidationError> {
    if allDay {
      if startTime != nil || endTime != nil {
        return .failure(
          .message("all_day events must not carry start_time or end_time"))
      }
      if let end = endDate, end < startDate {
        return .failure(
          .message(
            "calendar event end_date (\(end.asString)) is before start_date (\(startDate.asString))"
          ))
      }
      return .success(.allDay(start: startDate, end: endDate))
    }

    guard let start = startTime else {
      return .failure(
        .message("timed (non-all-day) calendar event must carry start_time"))
    }

    // Single-day if endDate is nil or equal to startDate.
    let singleDay: Bool
    if let end = endDate {
      if end == startDate {
        singleDay = true
      } else if end < startDate {
        return .failure(
          .message(
            "calendar event end_date (\(end.asString)) is before start_date (\(startDate.asString))"
          ))
      } else {
        singleDay = false
      }
    } else {
      singleDay = true
    }

    if singleDay {
      if let end = endTime, end < start {
        return .failure(
          .message(
            "calendar event end_time (\(end.asString)) is before start_time (\(start.asString))"
          ))
      }
      return .success(.timedSingleDay(date: startDate, start: start, end: endTime))
    } else {
      // Multi-day branch: endDate is non-nil and > startDate by construction.
      guard let endD = endDate else {
        return .failure(.message("multi-day branch requires end_date"))
      }
      guard let endT = endTime else {
        return .failure(
          .message("multi-day timed calendar event must carry end_time"))
      }
      // Lexicographic (date, time) check — automatically satisfied by
      // endD > startDate above, but verify for completeness.
      if endD < startDate || (endD == startDate && endT < start) {
        return .failure(
          .message(
            "calendar event end (\(endD.asString) \(endT.asString)) is before start (\(startDate.asString) \(start.asString))"
          ))
      }
      return .success(
        .timedMultiDay(startDate: startDate, startTime: start, endDate: endD, endTime: endT))
    }
  }

  /// `start_date` accessor — present on every variant.
  public var startDate: LorvexDate {
    switch self {
    case let .allDay(start, _): return start
    case let .timedSingleDay(date, _, _): return date
    case let .timedMultiDay(startDate, _, _, _): return startDate
    }
  }

  /// `start_time` accessor in the flat optional shape. `allDay` returns
  /// nil; timed variants return the start time.
  public var startTime: TimeOfDay? {
    switch self {
    case .allDay: return nil
    case let .timedSingleDay(_, start, _): return start
    case let .timedMultiDay(_, startTime, _, _): return startTime
    }
  }

  /// `end_date` accessor in the flat optional shape. Single-day variants
  /// return nil (the flat storage convention).
  public var endDate: LorvexDate? {
    switch self {
    case let .allDay(_, end): return end
    case .timedSingleDay: return nil
    case let .timedMultiDay(_, _, endDate, _): return endDate
    }
  }

  /// `end_time` accessor in the flat optional shape.
  public var endTime: TimeOfDay? {
    switch self {
    case .allDay: return nil
    case let .timedSingleDay(_, _, end): return end
    case let .timedMultiDay(_, _, _, endTime): return endTime
    }
  }

  /// `all_day` accessor — `true` only for the `allDay` variant.
  public var allDay: Bool {
    if case .allDay = self { return true }
    return false
  }

}
