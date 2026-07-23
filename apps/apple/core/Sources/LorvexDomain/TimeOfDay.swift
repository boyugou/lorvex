/// Canonical typed wrapper around a clock time rendered in the canonical
/// 24-hour `HH:MM` form used across calendar / focus / reminder columns.
///
/// Backed by hour/minute/second so two values compare by clock order, not by
/// lexicographic byte order. The wire encoding is the canonical zero-padded
/// `HH:MM` string (seconds are dropped on render), byte-identical to the
/// `String` columns it replaces.
///
/// ``parse(_:)`` accepts a one-or-two-digit hour and minute separated by a
/// single `:`,
/// tolerates leading whitespace, rejects any trailing characters, and
/// range-checks hour `0...23` / minute `0...59` (so `24:00` and `09:60` are
/// rejected). Inputs that are not in this shape surface a
/// ``ValidationError/invalidFormat(field:expected:actual:)`` with field `"time"`.
public struct TimeOfDay: Sendable, Equatable, Hashable, Comparable, Codable {
  public let hour: Int
  public let minute: Int
  public let second: Int

  init(hour: Int, minute: Int, second: Int) {
    self.hour = hour
    self.minute = minute
    self.second = second
  }

  /// Minute offset from midnight (`hour * 60 + minute`); seconds are dropped.
  public var minutesOfDay: Int { hour * 60 + minute }

  /// Construct from a minute-of-day offset, saturating at 23:59. A value past
  /// 1439 minutes is a programming bug; saturation is a rendering fallback so
  /// the boundary never traps.
  public static func fromMinutesSaturating(_ value: Int) -> TimeOfDay {
    let clamped = min(max(value, 0), 1439)
    return TimeOfDay(hour: clamped / 60, minute: clamped % 60, second: 0)
  }

  /// Parse a canonical 24-hour `HH:MM` time-of-day string.
  public static func parse(_ raw: String) -> Result<TimeOfDay, ValidationError> {
    if let t = parseHHMM(raw) {
      return .success(t)
    }
    return .failure(.invalidFormat(field: "time", expected: "HH:MM", actual: raw))
  }

  /// Render as the canonical 24-hour `HH:MM` string (seconds dropped).
  public var asString: String { String(format: "%02d:%02d", hour, minute) }

  public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
    (lhs.hour, lhs.minute, lhs.second) < (rhs.hour, rhs.minute, rhs.second)
  }

  /// Parse `HH:MM`: optional leading whitespace, 1–2 digit hour, `:`,
  /// 1–2 digit minute, no trailing characters, range-checked.
  static func parseHHMM(_ raw: String) -> TimeOfDay? {
    var scalars = Array(raw.unicodeScalars)[...]
    // Leading whitespace is consumed before the hour digits.
    while let first = scalars.first, isAsciiWhitespace(first) {
      scalars = scalars.dropFirst()
    }
    guard let (hour, afterHour) = takeNumber(scalars, maxDigits: 2) else { return nil }
    guard let colon = afterHour.first, colon == ":" else { return nil }
    let afterColon = afterHour.dropFirst()
    guard let (minute, rest) = takeNumber(afterColon, maxDigits: 2) else { return nil }
    guard rest.isEmpty else { return nil }
    guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    return TimeOfDay(hour: hour, minute: minute, second: 0)
  }

  /// Consume 1…`maxDigits` leading ASCII digits, returning the value and the
  /// remaining slice. `nil` when no digit is present.
  private static func takeNumber(
    _ scalars: ArraySlice<Unicode.Scalar>, maxDigits: Int
  ) -> (Int, ArraySlice<Unicode.Scalar>)? {
    var value = 0
    var consumed = 0
    var rest = scalars
    while consumed < maxDigits, let s = rest.first, s.value >= 0x30, s.value <= 0x39 {
      value = value * 10 + Int(s.value - 0x30)
      consumed += 1
      rest = rest.dropFirst()
    }
    return consumed == 0 ? nil : (value, rest)
  }

  private static func isAsciiWhitespace(_ s: Unicode.Scalar) -> Bool {
    s == " " || s == "\t" || s == "\n" || s == "\r"
  }

  public init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    switch TimeOfDay.parse(raw) {
    case let .success(time):
      self = time
    case let .failure(error):
      throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: error.description))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(asString)
  }
}
