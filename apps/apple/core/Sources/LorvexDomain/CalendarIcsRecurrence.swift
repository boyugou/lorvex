import Foundation

// MARK: - RRULE serializer

/// Convert a stored recurrence JSON payload into the RFC 5545 `RRULE:` line.
/// Delegates acceptance to `ValidationRecurrence.normalizeTaskRecurrenceWithWarnings`
/// so every surface shares the same canonical recurrence contract.
///
/// `isDateValue` must match the emitted `DTSTART` value type
/// (`isDateValueEvent(_:)`): RFC 5545 §3.3.10 requires `UNTIL` to share
/// `DTSTART`'s type, so a date-only event emits a bare `UNTIL=YYYYMMDD` while a
/// timed event emits a UTC `DATE-TIME` `UNTIL=YYYYMMDDTHHMMSSZ`.
///
/// For a timed event the `UNTIL` value must be ≥ the last intended occurrence's
/// UTC instant. Occurrences fall at `DTSTART`'s wall-clock time on each local
/// day, so the last one lands somewhere on the local `UNTIL` day; `UNTIL` is
/// therefore the *end of that day in `timezone`* converted to UTC. For a zone
/// west of UTC that instant rolls onto the next UTC calendar day (keeping the
/// final local occurrence, which a bare `YYYYMMDDT235959Z` cap would drop); for
/// a zone east of UTC it stays on the same or a prior UTC day (so no phantom
/// occurrence is added). `timezone` nil/unparseable treats the local wall time
/// as already-UTC, matching `DTSTART` emission.
func recurrenceToRrule(
  _ recurrence: String?, isDateValue: Bool, timezone: String? = nil,
  warnings: inout [CalendarIcsWarning]
) -> Result<String?, CalendarIcsError> {
  let trimmed = recurrence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  if trimmed.isEmpty { return .success(nil) }

  let normalizedResult = ValidationRecurrence.normalizeTaskRecurrenceWithWarnings(trimmed)
  let normalized: ValidationRecurrence.NormalizedRecurrence?
  switch normalizedResult {
  case .success(let v): normalized = v
  case .failure(let err):
    return .failure(.invalidRecurrenceRule(err.description))
  }
  guard let normalized else { return .success(nil) }

  for w in normalized.warnings {
    warnings.append(.recurrence(w))
  }

  guard let parsed = JSONValue.parse(normalized.canonical), let obj = parsed.asObject else {
    return .failure(.invalidRecurrenceJson(normalized.canonical))
  }
  guard let freq = obj["FREQ"]?.asStr else {
    return .failure(.internalContractViolation(
      field: "FREQ",
      detail: "normalize_recurrence_rule must populate FREQ before format_rrule runs"))
  }

  var rrule = "RRULE:FREQ=\(freq)"

  guard let interval = obj["INTERVAL"]?.asI64 else {
    return .failure(.internalContractViolation(
      field: "INTERVAL",
      detail: "normalize_recurrence_rule must populate INTERVAL before format_rrule runs"))
  }
  if interval > 1 {
    rrule += ";INTERVAL=\(interval)"
  }

  if let byday = obj["BYDAY"]?.asArray {
    let strs = byday.compactMap { $0.asStr }
    if !strs.isEmpty {
      rrule += ";BYDAY=" + strs.joined(separator: ",")
    }
  }

  if let bymonth = obj["BYMONTH"]?.asArray {
    let ints = bymonth.compactMap { $0.asI64 }
    if !ints.isEmpty {
      rrule += ";BYMONTH=" + ints.map(String.init).joined(separator: ",")
    }
  }
  if let bymonthday = obj["BYMONTHDAY"]?.asArray {
    let ints = bymonthday.compactMap { $0.asI64 }
    if !ints.isEmpty {
      rrule += ";BYMONTHDAY=" + ints.map(String.init).joined(separator: ",")
    }
  }

  if let bysetpos = obj["BYSETPOS"]?.asArray {
    let ints = bysetpos.compactMap { $0.asI64 }
    if !ints.isEmpty {
      rrule += ";BYSETPOS=" + ints.map(String.init).joined(separator: ",")
    }
  }

  if let count = obj["COUNT"]?.asI64 {
    rrule += ";COUNT=\(count)"
  }

  if let until = obj["UNTIL"]?.asStr {
    if isDateValue {
      // All-day (VALUE=DATE) DTSTART: UNTIL stays a bare `YYYYMMDD`.
      switch dateStrToIcs(field: "UNTIL", raw: until) {
      case .success(let s): rrule += ";UNTIL=\(s)"
      case .failure(let e): return .failure(e)
      }
    } else {
      // Timed (UTC DATE-TIME) DTSTART: UNTIL is the end of the local UNTIL day
      // in `timezone`, converted to UTC, so it is ≥ the last local occurrence's
      // UTC instant (see the function docstring for the west/east reasoning).
      switch parseRequiredIcsDate(field: "UNTIL", raw: until) {
      case .success(let ymd):
        let untilUtc = localToUtcIcsTimestamp(
          date: LorvexDate(ymd: ymd),
          time: TimeOfDay(hour: 23, minute: 59, second: 59),
          timezone: timezone)
        rrule += ";UNTIL=\(untilUtc)"
      case .failure(let e): return .failure(e)
      }
    }
  }

  if let wkst = obj["WKST"]?.asStr {
    rrule += ";WKST=\(wkst)"
  }

  return .success(rrule)
}

// MARK: - EXDATE emission

/// Cap on emitted EXDATE lines per VEVENT: ``ValidationRecurrence/maxCalendarRecurrenceCount``
/// (365) + 1, covering a full leap year.
let maxRecurrenceExdates: Int = Int(ValidationRecurrence.maxCalendarRecurrenceCount) + 1

func recurrenceExdates(_ event: CalendarIcsEvent) -> Result<[String], CalendarIcsError> {
  let trimmed = event.recurrenceExceptions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  if trimmed.isEmpty { return .success([]) }

  guard let parsed = JSONValue.parse(trimmed), let arr = parsed.asArray else {
    return .failure(.invalidRecurrenceExceptionJson(trimmed))
  }
  var dates: [String] = []
  dates.reserveCapacity(arr.count)
  for v in arr {
    guard let s = v.asStr else {
      return .failure(.invalidRecurrenceExceptionJson(trimmed))
    }
    dates.append(s)
  }

  // Canonicalize and dedupe by canonical `YYYY-MM-DD` before checking the cap.
  var seen = Set<String>()
  var canonical: [String] = []
  canonical.reserveCapacity(min(dates.count, maxRecurrenceExdates))
  for date in dates {
    guard let ymd = IsoDate.parse(date) else {
      return .failure(.invalidRecurrenceExceptionDate(date))
    }
    let canon = ymd.canonicalString
    if seen.insert(canon).inserted {
      canonical.append(canon)
    }
  }
  if canonical.count > maxRecurrenceExdates {
    return .failure(.recurrenceExdateLimitExceeded(count: canonical.count, limit: maxRecurrenceExdates))
  }

  let isDateValue = isDateValueEvent(event)
  var out: [String] = []
  out.reserveCapacity(canonical.count)
  for date in canonical {
    guard let ymd = IsoDate.parse(date) else {
      return .failure(.invalidRecurrenceExceptionDate(date))
    }
    let typedDate = LorvexDate(ymd: ymd)
    let dateIcs = dateToIcs(typedDate)
    if isDateValue {
      out.append("EXDATE;VALUE=DATE:\(dateIcs)")
    } else {
      guard let startTime = event.startTime else {
        return .failure(.internalContractViolation(
          field: "start_time",
          detail: "is_date_value_event=false requires start_time to be Some when emitting EXDATE"))
      }
      let utcTs = localToUtcIcsTimestamp(date: typedDate, time: startTime, timezone: event.timezone)
      out.append("EXDATE:\(utcTs)")
    }
  }
  return .success(out)
}
