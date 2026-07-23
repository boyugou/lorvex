import Foundation

/// The canonical hyphenated-date parser shared by every domain caller that
/// reads a calendar date column (`canonical_occurrence_date`, `start_date`,
/// `due_date`, `planned_date`, …).
///
/// Accepts only the canonical hyphenated `YYYY-MM-DD` form. Parsing is byte-exact
/// rather than delegated to a lenient `DateFormatter`: the input must be exactly
/// ten ASCII characters laid out as four digits, hyphen, two digits, hyphen, two
/// digits, and the resulting `(year, month, day)` must round-trip through a
/// proleptic-Gregorian `Calendar` unchanged. That round-trip rejects out-of-range
/// months (`2026-13-01`), non-existent days (`2026-02-30`), and respects
/// leap-year rules (`2024-02-29` valid, `2026-02-29` rejected).
public enum IsoDate {
  /// The shared proleptic-Gregorian calendar used for all domain date math:
  /// explicit identifier, UTC time zone, POSIX locale — never the device's
  /// implicit calendar/locale, so results are deterministic across machines.
  ///
  /// This is the single audited UTC-proleptic calendar every Lorvex date
  /// computation must funnel through. Callers outside `LorvexDomain` reference
  /// it here rather than reconstructing an equivalent calendar, so a stray
  /// local-time-zone calendar can never leak into date math.
  public static let calendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    cal.locale = Locale(identifier: "en_US_POSIX")
    return cal
  }()

  /// Parsed `(year, month, day)` triple for a canonical ISO date. Used by the
  /// ``LorvexDate`` newtype and any caller that wants the validated components
  /// without a `Foundation.Date`.
  public struct YMD: Sendable, Equatable, Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
      self.year = year
      self.month = month
      self.day = day
    }

    public static func < (lhs: YMD, rhs: YMD) -> Bool {
      (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Canonical hyphenated rendering (`YYYY-MM-DD`), zero-padded.
    public var canonicalString: String {
      String(format: "%04d-%02d-%02d", year, month, day)
    }
  }

  /// Parse a canonical hyphenated ISO date (`YYYY-MM-DD`).
  ///
  /// Returns ``ValidationError/invalidFormat(field:expected:actual:)`` with field
  /// label `"date"` and expected `"YYYY-MM-DD"` for any malformed input — the same
  /// shape every other domain format validator returns.
  public static func parseIsoDate(_ s: String) -> Result<YMD, ValidationError> {
    if let ymd = parse(s) {
      return .success(ymd)
    }
    return .failure(.invalidFormat(field: "date", expected: "YYYY-MM-DD", actual: s))
  }

  /// Byte-exact `YYYY-MM-DD` parse, returning `nil` on any deviation.
  public static func parse(_ s: String) -> YMD? {
    let bytes = Array(s.utf8)
    guard bytes.count == 10 else { return nil }
    guard bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
    for i in [0, 1, 2, 3, 5, 6, 8, 9] where !isAsciiDigit(bytes[i]) {
      return nil
    }
    let year = digit(bytes[0]) * 1000 + digit(bytes[1]) * 100 + digit(bytes[2]) * 10 + digit(bytes[3])
    let month = digit(bytes[5]) * 10 + digit(bytes[6])
    let day = digit(bytes[8]) * 10 + digit(bytes[9])

    // Reject impossible components before the calendar round-trip; a proleptic
    // calendar would otherwise normalize month 0 / day 0 into an adjacent date.
    guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }

    var dc = DateComponents()
    dc.year = year
    dc.month = month
    dc.day = day
    guard let date = calendar.date(from: dc) else { return nil }
    let back = calendar.dateComponents([.year, .month, .day], from: date)
    guard back.year == year, back.month == month, back.day == day else { return nil }
    return YMD(year: year, month: month, day: day)
  }

  static func isAsciiDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
  static func digit(_ b: UInt8) -> Int { Int(b) - 0x30 }

  // MARK: - Epoch-day arithmetic

  /// The UTC midnight `Date` for a `(year, month, day)` triple, using the shared
  /// ``calendar``. Force-unwraps because a proleptic-Gregorian calendar always
  /// yields a `Date` for a component set (out-of-range components normalize
  /// rather than fail); pass a ``YMD`` that came from ``parse(_:)`` /
  /// ``parseIsoDate(_:)`` to guarantee a real calendar date.
  public static func ymdToDate(_ ymd: YMD) -> Date {
    var dc = DateComponents()
    dc.year = ymd.year
    dc.month = ymd.month
    dc.day = ymd.day
    return calendar.date(from: dc)!
  }

  /// The integer count of whole days from the Unix epoch (1970-01-01) to `ymd`,
  /// negative for dates before the epoch. Two dates' day numbers subtract to the
  /// exact day span between them, and adding an integer to a day number and
  /// feeding it back through ``ymdFromDayNumber(_:)`` shifts the date by that
  /// many days — the basis for all whole-day workflow arithmetic.
  public static func dayNumber(_ ymd: YMD) -> Int {
    Int((ymdToDate(ymd).timeIntervalSince1970 / 86_400).rounded())
  }

  /// The calendar date `days` whole days after the Unix epoch, the inverse of
  /// ``dayNumber(_:)``.
  public static func ymdFromDayNumber(_ days: Int) -> YMD {
    let date = Date(timeIntervalSince1970: Double(days) * 86_400)
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return YMD(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
  }

  /// The calendar date `days` whole days after `ymd` (negative `days` shifts
  /// earlier), computed on the shared UTC-proleptic ``calendar`` via epoch-day
  /// arithmetic. This is the single whole-day shift every UTC-pinned date-math
  /// caller uses instead of reconstructing a Gregorian/UTC calendar locally.
  public static func addingDays(_ ymd: YMD, _ days: Int) -> YMD {
    ymdFromDayNumber(dayNumber(ymd) + days)
  }

  /// Parse an RFC 5545 §3.3.10 `UNTIL` value into the canonical `YYYY-MM-DD`
  /// storage form, returning `nil` if the input matches none of the three
  /// accepted shapes.
  ///
  /// Accepts, in priority order:
  /// - the canonical hyphenated `YYYY-MM-DD` (via ``parse(_:)``),
  /// - the RFC 5545 DATE form `YYYYMMDD` (8 digits),
  /// - the RFC 5545 DATE-TIME form `YYYYMMDDTHHMMSSZ` (the trailing `Z` is
  ///   required for the UNTIL-DATE-TIME variant).
  ///
  /// The time-of-day is discarded: only the date portion is stored, matching how
  /// the projection engine treats UNTIL ("valid through this day").
  public static func parseUntilToYmd(_ s: String) -> String? {
    if let ymd = parse(s) {
      return ymd.canonicalString
    }
    if let ymd = parseCompactDate(s) {
      return ymd.canonicalString
    }
    if let ymd = parseCompactDateTimeZ(s) {
      return ymd.canonicalString
    }
    return nil
  }

  /// Parse the RFC 5545 compact DATE form `YYYYMMDD` (exactly eight ASCII
  /// digits) into a validated calendar date, or `nil` on any deviation.
  /// Calendar-range validation (month, day, leap year) matches ``parse(_:)``.
  static func parseCompactDate(_ s: String) -> YMD? {
    let bytes = Array(s.utf8)
    guard bytes.count == 8 else { return nil }
    for b in bytes where !isAsciiDigit(b) { return nil }
    let year = digit(bytes[0]) * 1000 + digit(bytes[1]) * 100 + digit(bytes[2]) * 10 + digit(bytes[3])
    let month = digit(bytes[4]) * 10 + digit(bytes[5])
    let day = digit(bytes[6]) * 10 + digit(bytes[7])
    return validatedYMD(year: year, month: month, day: day)
  }

  /// Parse the RFC 5545 compact DATE-TIME form `YYYYMMDDTHHMMSSZ` (16 chars:
  /// 8 date digits, literal `T`, 6 time digits, literal `Z`) and return its date
  /// portion, or `nil` on any deviation.
  ///
  /// Time-field ranges are hour `00...23`, minute `00...59`, second `00...60`
  /// (the leap-second value is admitted). The time-of-day itself is discarded;
  /// only the validated date is returned.
  static func parseCompactDateTimeZ(_ s: String) -> YMD? {
    let bytes = Array(s.utf8)
    guard bytes.count == 16 else { return nil }
    guard bytes[8] == UInt8(ascii: "T"), bytes[15] == UInt8(ascii: "Z") else { return nil }
    for i in [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14] where !isAsciiDigit(bytes[i]) {
      return nil
    }
    let year = digit(bytes[0]) * 1000 + digit(bytes[1]) * 100 + digit(bytes[2]) * 10 + digit(bytes[3])
    let month = digit(bytes[4]) * 10 + digit(bytes[5])
    let day = digit(bytes[6]) * 10 + digit(bytes[7])
    let hour = digit(bytes[9]) * 10 + digit(bytes[10])
    let minute = digit(bytes[11]) * 10 + digit(bytes[12])
    let second = digit(bytes[13]) * 10 + digit(bytes[14])
    guard hour <= 23, minute <= 59, second <= 60 else { return nil }
    return validatedYMD(year: year, month: month, day: day)
  }

  /// Validate `(year, month, day)` against the proleptic-Gregorian calendar via
  /// the same round-trip ``parse(_:)`` uses, returning `nil` for impossible
  /// components, out-of-range months/days, or non-existent dates.
  static func validatedYMD(year: Int, month: Int, day: Int) -> YMD? {
    guard month >= 1, month <= 12, day >= 1, day <= 31 else { return nil }
    var dc = DateComponents()
    dc.year = year
    dc.month = month
    dc.day = day
    guard let date = calendar.date(from: dc) else { return nil }
    let back = calendar.dateComponents([.year, .month, .day], from: date)
    guard back.year == year, back.month == month, back.day == day else { return nil }
    return YMD(year: year, month: month, day: day)
  }
}
