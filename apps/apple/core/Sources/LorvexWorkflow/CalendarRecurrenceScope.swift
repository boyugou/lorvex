import Foundation
import LorvexDomain
import LorvexStore

/// Series-vs-occurrence scope decisions for recurring calendar events: shifting
/// a date range onto a chosen occurrence, and truncating an open-ended series
/// just before a split date. Pure date/JSON arithmetic with no database access.
public enum CalendarRecurrenceScope {
  /// Result of attempting to truncate a recurrence before a split date.
  ///
  /// `.truncated` carries the rewritten recurrence JSON. An unbounded rule
  /// gains `UNTIL = split - 1`; an existing `UNTIL` tightens; a COUNT-bounded
  /// rule keeps COUNT and reduces it to the actual number of pre-split slots.
  /// `.collapse` means the original event should become a single occurrence
  /// (no recurrence at all). `.noop` means the natural end already precedes the
  /// split so no rewrite is needed.
  public enum TruncateResult: Equatable {
    case truncated(String)
    case collapse
    case noop
  }

  // MARK: - Date helpers (UTC gregorian, proleptic)

  /// Add `days` to a canonical `YYYY-MM-DD` string. Returns `nil` if the input
  /// is malformed.
  public static func addYmdDays(_ value: String, _ days: Int) -> String? {
    guard let ymd = IsoDate.parse(value) else { return nil }
    return IsoDate.ymdFromDayNumber(IsoDate.dayNumber(ymd) + days).canonicalString
  }

  /// Shift a `(start, end?)` date range so its start lands on `occurrenceDate`,
  /// preserving the original span between start and end.
  public static func rebaseDateRangeToOccurrence(
    startDate: String, endDate: String?, occurrenceDate: String
  ) -> (String, String?)? {
    guard let previousStart = IsoDate.parse(startDate),
      let occurrence = IsoDate.parse(occurrenceDate)
    else { return nil }
    let nextEnd: String?
    if let end = endDate {
      guard let previousEnd = IsoDate.parse(end) else { return nil }
      let offset = IsoDate.dayNumber(previousEnd) - IsoDate.dayNumber(previousStart)
      nextEnd = IsoDate.ymdFromDayNumber(IsoDate.dayNumber(occurrence) + offset).canonicalString
    } else {
      nextEnd = nil
    }
    return (occurrenceDate, nextEnd)
  }

  private static func jsonString(_ v: JSONValue?) -> String? {
    if case .string(let s)? = v { return s }
    return nil
  }

  private static func jsonI64(_ v: JSONValue?) -> Int? {
    switch v {
    case .int(let i)?: return Int(i)
    case .uint(let u)? where u <= UInt64(Int64.max): return Int(u)
    default: return nil
    }
  }

  /// Count the recurrence slots whose original dates are strictly before the
  /// cutover. This deliberately delegates every cadence detail (BYDAY,
  /// BYMONTHDAY, BYSETPOS, leap days, month-end anchoring) to the same engine
  /// that expands calendar timelines, avoiding a second partial RRULE model.
  private static func countSlotsBeforeCutover(
    rawRecurrence: String, startYmd: String, splitDateYmd: String, count: Int
  ) -> Int? {
    guard count > 0 else { return nil }
    var current = startYmd
    for index in 0..<count {
      if current >= splitDateYmd { return index }
      if index == count - 1 { return count }
      do {
        guard
          let next = try CalendarRecurrence.calculateNextOccurrenceDate(
            recurrenceJson: rawRecurrence, baseDateYmd: current),
          next > current
        else {
          // A valid COUNT rule should always advance until its declared count.
          // If a defensive synced row terminates early, preserving it is safer
          // than fabricating a different finite series.
          return count
        }
        current = next
      } catch {
        return nil
      }
    }
    return count
  }

  /// Truncate a recurrence so it stops just before `splitDateYmd`.
  ///
  /// `nil` recurrence, a split at or before the series start, or non-object
  /// JSON all collapse the event to a single occurrence. An existing earlier
  /// `UNTIL` is preserved (never extended). A `COUNT`-bounded series whose
  /// natural end already precedes the split is a no-op; otherwise its COUNT is
  /// reduced to the actual number of original recurrence slots before the
  /// split. COUNT and UNTIL therefore remain mutually exclusive on the wire.
  public static func truncateRecurrenceBefore(
    rawRecurrence: String?, splitDateYmd: String, seriesStartYmd: String?
  ) -> TruncateResult {
    guard let rawRecurrence = rawRecurrence else { return .collapse }
    if let start = seriesStartYmd, splitDateYmd <= start { return .collapse }
    guard let parsed = JSONValue.parse(rawRecurrence),
      case .object(let parsedObj) = parsed
    else { return .collapse }
    guard let splitMinusOne = addYmdDays(splitDateYmd, -1) else { return .collapse }

    var next = parsedObj
    let existingUntil = jsonString(next["UNTIL"])
    let existingCount = jsonI64(next["COUNT"])

    if let existingUntil = existingUntil {
      next.removeValue(forKey: "COUNT")
      next["UNTIL"] = .string(existingUntil < splitMinusOne ? existingUntil : splitMinusOne)
      return .truncated(serialize(next))
    }

    if let existingCount = existingCount {
      guard let startYmd = seriesStartYmd,
        let retainedCount = countSlotsBeforeCutover(
          rawRecurrence: rawRecurrence, startYmd: startYmd,
          splitDateYmd: splitDateYmd, count: existingCount)
      else { return .collapse }
      if retainedCount == existingCount { return .noop }
      if retainedCount == 0 { return .collapse }
      next["COUNT"] = .int(Int64(retainedCount))
      return .truncated(serialize(next))
    }

    next["UNTIL"] = .string(splitMinusOne)
    return .truncated(serialize(next))
  }

  /// Serialize the rewritten recurrence object to JSON.
  ///
  /// Routes through ``canonicalizeJSON(_:)`` (sorted keys) because
  /// `JSONValue.object` is `Dictionary`-backed with no insertion order, so the
  /// stored string may differ in key order from another producer's output while
  /// parsing to the same value. Callers comparing the parsed object (the only
  /// contract the recurrence engine relies on) are unaffected.
  private static func serialize(_ obj: [String: JSONValue]) -> String {
    (try? canonicalizeJSON(.object(obj))) ?? "{}"
  }
}
