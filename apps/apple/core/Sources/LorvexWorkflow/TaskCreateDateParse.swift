import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Flexible date-string normalization for task-create due / planned dates.
///
/// Accepts `YYYY-MM-DD`, `today`/`tomorrow`/`yesterday`, RFC 3339 datetimes,
/// and a handful of common locale-friendly formats.
///
/// Relative tokens and timezone-bearing datetimes resolve through the active
/// preference timezone, falling back to the process-local zone when no
/// preference is configured.
public enum TaskCreateDateParse {
  /// Normalize a user-supplied date string into canonical `YYYY-MM-DD`.
  /// Throws ``StoreError/validation(_:)`` on an invalid or unparsable date
  /// string.
  public static func normalizeDueDateInputForConn(
    _ db: Database, value: String, now: Date = Date()
  ) throws -> String {
    let timezoneName = try WorkflowTimezone.activeTimezoneName(db)
    let timezone = timezoneName.flatMap(Timezone.parseTimezoneName)
    let today: String = Timezone.todayYmdForTimezoneName(
      now: now, timezoneName: timezoneName, systemFallback: TimeZone.current)
    let tomorrow: String = Timezone.datePlusDaysYmdForTimezoneName(
      now: now, timezoneName: timezoneName, offsetDays: 1,
      systemFallback: TimeZone.current)
    let yesterday: String = Timezone.datePlusDaysYmdForTimezoneName(
      now: now, timezoneName: timezoneName, offsetDays: -1,
      systemFallback: TimeZone.current)

    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      throw StoreError.validation("due_date must be a non-empty date string")
    }
    switch trimmed.lowercased() {
    case "today": return today
    case "tomorrow": return tomorrow
    case "yesterday": return yesterday
    default: break
    }

    // Strict `YYYY-MM-DD`: validate via the domain ISO parser to reject
    // shape lookalikes (`2025-13-01`, `2025-02-30`, …).
    if isCanonicalYmdShape(trimmed) {
      switch IsoDate.parseIsoDate(trimmed) {
      case .success: return trimmed
      case .failure:
        throw StoreError.validation("'\(trimmed)' is not a valid calendar date")
      }
    }

    if let parsed =
      parseFlexibleDate(value: trimmed, zone: timezone) ?? parseFlexibleDate(
        value: trimmed, zone: TimeZone.current)
    {
      return parsed
    }
    throw StoreError.validation(
      "Invalid due_date '\(value)'. Expected YYYY-MM-DD, today, tomorrow, "
        + "yesterday, an RFC3339 datetime, or a common date format")
  }

  private static func isCanonicalYmdShape(_ s: String) -> Bool {
    let bytes = Array(s.utf8)
    guard bytes.count == 10, bytes[4] == 0x2D, bytes[7] == 0x2D else { return false }
    for (i, b) in bytes.enumerated() {
      if i == 4 || i == 7 { continue }
      if b < 0x30 || b > 0x39 { return false }
    }
    return true
  }

  private static func parseFlexibleDate(value: String, zone: TimeZone?) -> String? {
    if let zone {
      if let s = parseRfc3339AsYmd(value, zone: zone) { return s }
      if let s = parseNaiveDatetimeAsYmd(value, zone: zone) { return s }
    }
    return parseAlternateDateFormat(value)
  }

  private static func parseRfc3339AsYmd(_ value: String, zone: TimeZone) -> String? {
    guard let d = ReminderAnchor.parseRfc3339ToDate(value) else { return nil }
    // `ISO8601DateFormatter` silently normalizes an out-of-range calendar day
    // (`2026-02-30T…` parses as 2026-03-02). Reject that so the RFC 3339 due-date
    // path is held to the same strict calendar-day validity as the bare
    // `YYYY-MM-DD` path — the written date is in the string's own offset, so
    // validate it directly rather than re-deriving it through `zone`.
    guard rfc3339WrittenDateIsValid(value) else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = zone
    let c = cal.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  /// Whether the leading `YYYY-MM-DD` of an RFC 3339 datetime is a real calendar
  /// day, using the same strict validator the bare-date path applies. Rejects
  /// rolled-over days (`2026-02-30`, `2023-02-29`) and out-of-range months.
  private static func rfc3339WrittenDateIsValid(_ value: String) -> Bool {
    let datePart = String(value.prefix { $0 != "T" && $0 != "t" })
    if case .success = IsoDate.parseIsoDate(datePart) { return true }
    return false
  }

  private static func parseNaiveDatetimeAsYmd(_ value: String, zone: TimeZone) -> String? {
    for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
      let df = DateFormatter()
      df.locale = Locale(identifier: "en_US_POSIX")
      df.timeZone = zone
      df.dateFormat = fmt
      if let d = df.date(from: value) {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
      }
    }
    return nil
  }

  private static func parseAlternateDateFormat(_ value: String) -> String? {
    for fmt in [
      "yyyy/MM/dd", "yyyy.MM.dd",
      "MM/dd/yyyy", "MM-dd-yyyy", "MM.dd.yyyy",
      "MMM d, yyyy", "MMMM d, yyyy",
    ] {
      let df = DateFormatter()
      df.locale = Locale(identifier: "en_US_POSIX")
      df.timeZone = TimeZone(identifier: "UTC")!
      df.dateFormat = fmt
      if let d = df.date(from: value) {
        let c = IsoDate.calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
      }
    }
    return nil
  }
}
