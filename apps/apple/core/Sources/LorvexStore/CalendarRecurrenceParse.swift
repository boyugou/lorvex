import Foundation
import LorvexDomain

/// RRULE recurrence-expansion engine for the calendar timeline.
///
/// Pure date math (date in → date(s) out); no DB access. All calendar
/// arithmetic flows through ``CalendarRecurrence/calendar`` — an explicit
/// proleptic-Gregorian calendar pinned to UTC with the POSIX locale — so
/// add-days / add-months / weekday-of-date / month-length results are
/// deterministic on any machine.
public enum CalendarRecurrence {
  /// Maximum `COUNT` a recurrence rule may carry for expansion.
  public static let maxRecurrenceCount: Int64 = 1000

  /// The proleptic-Gregorian calendar used for every recurrence date
  /// computation — the shared ``IsoDate/calendar`` (explicit gregorian
  /// identifier, UTC time zone, POSIX locale), exposed here as the recurrence
  /// engine's canonical handle so date math is deterministic on any machine.
  static let calendar: Calendar = IsoDate.calendar
}

/// A calendar date with no time-of-day.
///
/// Backed by a `Foundation.Date` anchored at UTC midnight of the day. All
/// arithmetic and field access route through ``CalendarRecurrence/calendar``
/// (gregorian / UTC / POSIX). Comparison and equality are by calendar day.
struct RDate: Comparable, Hashable {
  let date: Date

  /// Days from Sunday: Sunday = 0 … Saturday = 6.
  ///
  /// Foundation's `.weekday` is Sunday = 1 … Saturday = 7, so this value
  /// is `foundationWeekday - 1`. BYDAY codes (`SU=0`, `MO=1`, …, `SA=6`) and
  /// `WKST` use this same Sunday-based numbering.
  var numDaysFromSunday: UInt32 {
    let wd = CalendarRecurrence.calendar.component(.weekday, from: date)
    return UInt32(wd - 1)
  }

  var year: Int { CalendarRecurrence.calendar.component(.year, from: date) }
  var month: UInt32 { UInt32(CalendarRecurrence.calendar.component(.month, from: date)) }
  /// 0-based month index.
  var month0: UInt32 { month - 1 }
  var day: UInt32 { UInt32(CalendarRecurrence.calendar.component(.day, from: date)) }
  /// Day-of-year (1-based).
  var ordinal: UInt32 {
    UInt32(CalendarRecurrence.calendar.ordinality(of: .day, in: .year, for: date)!)
  }

  /// Construct from `(year, month, day)`, validating the date round-trips
  /// (rejects month/day out of range, non-existent days).
  static func fromYMD(_ year: Int, _ month: UInt32, _ day: UInt32) -> RDate? {
    guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
    var dc = DateComponents()
    dc.year = year
    dc.month = Int(month)
    dc.day = Int(day)
    guard let d = CalendarRecurrence.calendar.date(from: dc) else { return nil }
    let back = CalendarRecurrence.calendar.dateComponents([.year, .month, .day], from: d)
    guard back.year == year, back.month == Int(month), back.day == Int(day) else { return nil }
    return RDate(date: d)
  }

  /// Construct from `(year, day-of-year)`.
  static func fromYearOrdinal(_ year: Int, _ dayOfYear: UInt32) -> RDate? {
    guard dayOfYear >= 1 else { return nil }
    guard let jan1 = fromYMD(year, 1, 1) else { return nil }
    guard let d = jan1.addingDays(Int64(dayOfYear) - 1) else { return nil }
    // Reject overflow into the next year: the ordinal must not exceed the
    // year's day count.
    guard d.year == year else { return nil }
    return d
  }

  /// The calendar date `days` whole days from `self` (negative shifts earlier),
  /// or `nil` when the shift can't be represented — it overflows the platform
  /// `Int`, or Foundation returns no date. Dropping the historical force-unwrap
  /// means an out-of-range shift can never trap (Foundation clamps rather than
  /// failing on an extreme shift, so the result is merely unspecified, never a
  /// crash). The recurrence engine additionally overflow-checks all interval
  /// arithmetic upstream, so an absurd `INTERVAL` yields "no occurrence" before
  /// an extreme offset ever reaches here. Callers treat `nil` as "no such
  /// occurrence / stop expansion."
  func addingDays(_ days: Int64) -> RDate? {
    guard let intDays = Int(exactly: days),
      let d = CalendarRecurrence.calendar.date(byAdding: .day, value: intDays, to: date)
    else { return nil }
    return RDate(date: d)
  }

  /// Add `months` calendar months, clamping the day-of-month to the target
  /// month's length (Jan 31 + 1 month → Feb 28/29). `nil` only on an
  /// out-of-range result.
  func addingMonths(_ months: Int64) -> RDate? {
    let total = Int64(year) * 12 + Int64(month0) + months
    var y = Int(total / 12)
    var m0 = total % 12
    if m0 < 0 {
      m0 += 12
      y -= 1
    }
    let newMonth = UInt32(m0) + 1
    // Fail loud on an out-of-range month length rather than silently clamping to
    // 28 (matches `ByMonthDayAnchor.resolve`'s contract); callers handle `nil`.
    guard let maxDay = CalendarRecurrence.daysInMonth(y, newMonth) else { return nil }
    return RDate.fromYMD(y, newMonth, min(day, maxDay))
  }

  /// Whole calendar days from `self` to `other`.
  func daysUntil(_ other: RDate) -> Int64 {
    Int64(CalendarRecurrence.calendar.dateComponents([.day], from: date, to: other.date).day!)
  }

  static func < (lhs: RDate, rhs: RDate) -> Bool { lhs.date < rhs.date }
  static func == (lhs: RDate, rhs: RDate) -> Bool { lhs.date == rhs.date }

  /// Canonical `YYYY-MM-DD` rendering.
  var ymdString: String {
    String(format: "%04d-%02d-%02d", year, month, day)
  }
}

// ---------------------------------------------------------------------------
// Rule parsing — consumes a JSONValue object.
// ---------------------------------------------------------------------------

extension CalendarRecurrence {
  /// Parse a `"YYYY-MM-DD"` string into an ``RDate``.
  static func parseYmd(_ value: String) throws -> RDate {
    guard let ymd = IsoDate.parse(value) else {
      throw StoreError.validation("invalid YYYY-MM-DD date string `\(value)`: invalid date")
    }
    guard let d = RDate.fromYMD(ymd.year, UInt32(ymd.month), UInt32(ymd.day)) else {
      throw StoreError.validation("invalid YYYY-MM-DD date string `\(value)`: invalid date")
    }
    return d
  }

  static func parseRequiredYmd(_ value: String, _ field: String) throws -> RDate {
    do {
      return try parseYmd(value)
    } catch {
      throw StoreError.validation("invalid \(field): \(value)")
    }
  }

  /// Parse a recurrence-rule JSON string into a JSON object: malformed JSON or
  /// a non-object top level both surface as `StoreError.serialization`.
  ///
  /// Keys are uppercased on parse so the calendar recurrence reader is
  /// case-insensitive over its rule keys (`freq`/`byday`/… as well as
  /// `FREQ`/`BYDAY`/…). This accepts the lowercase structured form that
  /// `set_task_recurrence` uses, even though the canonical stored form remains
  /// uppercase. On a case-only key collision the later entry wins, matching the
  /// last-write semantics of merging the two spellings of one key.
  static func parseRuleObject(_ recurrenceJson: String) throws -> [String: JSONValue] {
    guard let parsed = JSONValue.parse(recurrenceJson) else {
      throw StoreError.serialization("invalid recurrence rule: malformed JSON")
    }
    guard case let .object(rule) = parsed else {
      throw StoreError.serialization(
        "invalid recurrence rule: recurrence must be a JSON object")
    }
    var upper: [String: JSONValue] = [:]
    upper.reserveCapacity(rule.count)
    for (key, value) in rule {
      upper[key.uppercased()] = value
    }
    return upper
  }

  /// Read the required FREQ value, normalized to uppercase so a lowercase
  /// `"weekly"` matches the uppercase `switch freq` arms downstream.
  static func parseFreq(_ rule: [String: JSONValue]) throws -> String {
    guard let freq = rule["FREQ"]?.rcStr else {
      throw StoreError.validation("invalid recurrence rule: missing FREQ")
    }
    return freq.uppercased()
  }

  static func parseInterval(_ rule: [String: JSONValue]) throws -> Int64 {
    switch rule["INTERVAL"] {
    case nil, .some(.null):
      return 1
    case let .some(value):
      guard let interval = value.rcI64, interval >= 1 else {
        throw StoreError.validation(
          "invalid recurrence rule: INTERVAL must be a positive integer")
      }
      // Defense in depth behind the write-path normalizer: a synced peer can
      // deliver a rule whose INTERVAL bypassed our validation. Reject the absurd
      // value so a poison row is skipped by `extendWithTolerantExpansion` rather
      // than driving expansion arithmetic to the edge of the representable range.
      guard interval <= ValidationLimits.maxRecurrenceInterval else {
        throw StoreError.validation(
          "invalid recurrence rule: INTERVAL \(interval) exceeds maximum "
            + "\(ValidationLimits.maxRecurrenceInterval)")
      }
      return interval
    }
  }

  static func parseUntil(_ rule: [String: JSONValue]) throws -> RDate? {
    switch rule["UNTIL"] {
    case nil, .some(.null):
      return nil
    case let .some(value):
      guard let until = value.rcStr else {
        throw StoreError.validation(
          "invalid recurrence rule: UNTIL must be a YYYY-MM-DD string")
      }
      return try parseRequiredYmd(until, "UNTIL")
    }
  }

  static func parsePositiveCount(_ rule: [String: JSONValue]) throws -> Int64? {
    switch rule["COUNT"] {
    case nil, .some(.null):
      return nil
    case let .some(value):
      if let count = value.rcI64, count >= 1 {
        return count
      }
      throw StoreError.validation(
        "invalid recurrence rule: COUNT must be a positive integer")
    }
  }

  static func parseBoundedCountForExpansion(_ rule: [String: JSONValue]) throws -> Int64? {
    guard let count = try parsePositiveCount(rule) else {
      return nil
    }
    if count > maxRecurrenceCount {
      throw StoreError.validation(
        "invalid recurrence rule: COUNT \(count) exceeds maximum \(maxRecurrenceCount)")
    }
    return count
  }

  /// RFC 5545 BYMONTHDAY anchor. `fromStart` counts from month start (1-31);
  /// `fromEnd` counts from month end (`-1` = last day, `-2` = penultimate, …).
  enum ByMonthDayAnchor: Equatable {
    case fromStart(UInt32)
    case fromEnd(UInt32)

    /// Resolve to a concrete day in `(year, month)`, clamping `fromStart`
    /// against the month length (so `fromStart(31)` in February → 28/29).
    func resolve(_ year: Int, _ month: UInt32) -> UInt32? {
      guard let maxDay = CalendarRecurrence.daysInMonth(year, month) else { return nil }
      switch self {
      case let .fromStart(day):
        return min(day, maxDay)
      case let .fromEnd(offset):
        let clamped = min(offset, maxDay)
        return maxDay - clamped + 1
      }
    }
  }

  /// Parse `BYMONTHDAY` into the set of day-of-month anchors a period expands to.
  ///
  /// Absent / null / empty falls back to `[.fromStart(fallbackDay)]` (the base
  /// day-of-month). A scalar (`15`, stored before the array form) yields one
  /// anchor; an array (`[1, 15]` — "1st and 15th") yields one anchor per entry.
  /// Each entry must be in [-31, -1] ∪ [1, 31]. The returned anchors are not
  /// pre-sorted; callers resolve each to a date and sort/dedup the results.
  static func parseBymonthday(
    _ rule: [String: JSONValue], _ fallbackDay: UInt32
  ) throws -> [ByMonthDayAnchor] {
    let raws: [Int64]
    switch rule["BYMONTHDAY"] {
    case nil, .some(.null):
      return [.fromStart(fallbackDay)]
    case let .some(value):
      if let scalar = value.rcI64 {
        raws = [scalar]
      } else if let arr = value.rcArray {
        var xs: [Int64] = []
        xs.reserveCapacity(arr.count)
        for item in arr {
          guard let n = item.rcI64 else {
            throw StoreError.validation(
              "invalid recurrence rule: BYMONTHDAY entries must be integers in [-31, -1] or [1, 31]")
          }
          xs.append(n)
        }
        raws = xs
      } else {
        throw StoreError.validation(
          "invalid recurrence rule: BYMONTHDAY must be an integer or array of integers in [-31, -1] or [1, 31]")
      }
    }
    if raws.isEmpty { return [.fromStart(fallbackDay)] }
    var anchors: [ByMonthDayAnchor] = []
    anchors.reserveCapacity(raws.count)
    for day in raws {
      if (1...31).contains(day) {
        anchors.append(.fromStart(UInt32(day)))
      } else if (-31 ... -1).contains(day) {
        anchors.append(.fromEnd(UInt32(day.magnitude)))
      } else {
        throw StoreError.validation(
          "invalid recurrence rule: BYMONTHDAY must be an integer in [-31, -1] or [1, 31]")
      }
    }
    return anchors
  }

  /// Map an iCalendar BYDAY two-letter code to a Sunday-based day number
  /// (Sunday = 0 … Saturday = 6), delegating to the shared domain map.
  /// Case-insensitive: a lowercase `"mo"` resolves the same as `"MO"`.
  static func bydayCodeToNum(_ value: String) -> UInt32? {
    ValidationRecurrence.bydayCodeToSundayNumber(value)
  }

  /// Number of days in the given calendar month.
  static func daysInMonth(_ year: Int, _ month: UInt32) -> UInt32? {
    let nextMonthFirst: RDate?
    if month == 12 {
      nextMonthFirst = RDate.fromYMD(year + 1, 1, 1)
    } else {
      nextMonthFirst = RDate.fromYMD(year, month + 1, 1)
    }
    guard let nmf = nextMonthFirst, let lastOfMonth = nmf.addingDays(-1) else { return nil }
    return lastOfMonth.day
  }

  struct ByDayToken: Equatable {
    let ordinal: Int32?
    let dow: UInt32
  }

  static func parseBydayToken(_ value: String) throws -> ByDayToken {
    let bytes = Array(value.utf8)
    // RFC 5545 BYDAY tokens are ASCII-only. Reject non-ASCII up front so a
    // multi-byte char straddling the 2-from-end boundary becomes a typed
    // Validation error rather than a slice panic.
    let isAscii = bytes.allSatisfy { $0 < 0x80 }
    guard bytes.count >= 2, isAscii else {
      throw StoreError.validation(
        "invalid recurrence rule: unsupported BYDAY code \(value)")
    }
    let splitIdx = value.index(value.endIndex, offsetBy: -2)
    let prefix = String(value[value.startIndex..<splitIdx])
    let code = String(value[splitIdx...])
    guard let dow = bydayCodeToNum(code) else {
      throw StoreError.validation(
        "invalid recurrence rule: unsupported BYDAY code \(value)")
    }
    var ordinal: Int32? = nil
    if !prefix.isEmpty {
      guard let parsed = Int32(prefix) else {
        throw StoreError.validation(
          "invalid recurrence rule: unsupported BYDAY ordinal \(value)")
      }
      if parsed == 0 || !(-53...53).contains(parsed) {
        throw StoreError.validation(
          "invalid recurrence rule: unsupported BYDAY ordinal \(value)")
      }
      ordinal = parsed
    }
    return ByDayToken(ordinal: ordinal, dow: dow)
  }

  static func parseBydayTokens(_ rule: [String: JSONValue]) throws -> [ByDayToken]? {
    guard let byday = rule["BYDAY"]?.rcArray else {
      return nil
    }
    if byday.isEmpty {
      return nil
    }
    var tokens: [ByDayToken] = []
    tokens.reserveCapacity(byday.count)
    for raw in byday {
      guard let code = raw.rcStr else {
        throw StoreError.validation(
          "invalid recurrence rule: BYDAY entries must be weekday codes")
      }
      tokens.append(try parseBydayToken(code))
    }
    return tokens
  }

  static func parseBymonth(_ rule: [String: JSONValue]) throws -> [UInt32]? {
    guard let bymonth = rule["BYMONTH"]?.rcArray else {
      if rule["BYMONTH"] != nil {
        throw StoreError.validation(
          "invalid recurrence rule: BYMONTH must be an array of months in 1..=12")
      }
      return nil
    }
    if bymonth.isEmpty {
      return nil
    }
    var months: [UInt32] = []
    months.reserveCapacity(bymonth.count)
    for raw in bymonth {
      if let month = raw.rcI64, (1...12).contains(month) {
        months.append(UInt32(month))
      } else {
        throw StoreError.validation(
          "invalid recurrence rule: BYMONTH entries must be integers in 1..=12")
      }
    }
    months.sort()
    months = dedupSorted(months)
    return months
  }

  static func parseBysetpos(_ rule: [String: JSONValue]) throws -> [Int64]? {
    guard let bysetpos = rule["BYSETPOS"]?.rcArray else {
      if rule["BYSETPOS"] != nil {
        throw StoreError.validation(
          "invalid recurrence rule: BYSETPOS must be an array of integers")
      }
      return nil
    }
    if bysetpos.isEmpty {
      return nil
    }
    var positions: [Int64] = []
    positions.reserveCapacity(bysetpos.count)
    for raw in bysetpos {
      if let position = raw.rcI64, position != 0, (-366...366).contains(position) {
        positions.append(position)
      } else {
        throw StoreError.validation(
          "invalid recurrence rule: BYSETPOS entries must be in -366..=-1 or 1..=366")
      }
    }
    positions.sort()
    positions = dedupSorted(positions)
    return positions
  }

  static func parseWkst(_ rule: [String: JSONValue]) throws -> UInt32 {
    switch rule["WKST"] {
    case nil, .some(.null):
      return 1
    case let .some(value):
      guard let code = value.rcStr else {
        throw StoreError.validation(
          "invalid recurrence rule: WKST must be a weekday code")
      }
      guard let num = bydayCodeToNum(code) else {
        throw StoreError.validation(
          "invalid recurrence rule: unsupported WKST code \(code)")
      }
      return num
    }
  }

  /// Drop consecutive duplicates from a sorted array.
  static func dedupSorted<T: Equatable>(_ values: [T]) -> [T] {
    var out: [T] = []
    for v in values where out.last != v {
      out.append(v)
    }
    return out
  }
}

/// JSON accessors local to the recurrence engine so it does not depend on the
/// `internal` accessors in LorvexDomain.
extension JSONValue {
  var rcStr: String? {
    if case let .string(s) = self { return s }
    return nil
  }
  var rcArray: [JSONValue]? {
    if case let .array(a) = self { return a }
    return nil
  }
  /// Integer value in signed 64-bit range only. Floats and oversize unsigned
  /// values return `nil`.
  var rcI64: Int64? {
    switch self {
    case let .int(i): return i
    case let .uint(u): return u <= UInt64(Int64.max) ? Int64(u) : nil
    default: return nil
    }
  }
}
