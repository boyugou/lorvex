import Foundation

/// RFC 5545 (ICS) calendar export.
///
/// The public entry points (`exportCalendarIcs`, `exportCalendarIcsWithWarnings`,
/// `validateExportRange`) produce a byte-stable ICS wire form for any common
/// input. Internal helpers (`formatIcsTimestamp`, `localToUtcIcsTimestamp`,
/// `foldLine`, `escapeIcsText`) are `internal` so the tests in the same module
/// can drive them directly.

// MARK: - Model

/// The immutable identity of one instance in an RFC 5545 recurrence set.
///
/// A replacement VEVENT keeps the series UID and carries the original
/// occurrence start in `RECURRENCE-ID`, even when its new `DTSTART` moves to a
/// different day or time. The enum makes the required DATE versus DATE-TIME
/// shape explicit and prevents a timed identifier without a time value.
public enum CalendarIcsRecurrenceID: Sendable, Equatable {
  case date(LorvexDate)
  case dateTime(date: LorvexDate, time: TimeOfDay, timezone: String?)
}

/// Field bundle accepted by `CalendarIcsEvent.make`. Keeps the validating
/// constructor's parameter list ergonomic so callers can route the flat
/// five-field `(start_date, start_time, end_date, end_time, all_day)` shape
/// through `CalendarEventTiming.fromFlatFields` at the boundary.
public struct CalendarIcsEventFields: Sendable, Equatable {
  public var id: String
  /// Stable recurrence-set identity. Defaults to `id` for standalone events
  /// and series masters; replacement instances set this to their master id.
  public var uid: String?
  /// Original occurrence identity for a replacement instance.
  public var recurrenceID: CalendarIcsRecurrenceID?
  public var title: String
  public var description: String?
  public var recurrence: String?
  public var recurrenceExceptions: String?
  public var startDate: LorvexDate
  public var startTime: TimeOfDay?
  public var endDate: LorvexDate?
  public var endTime: TimeOfDay?
  public var allDay: Bool
  public var location: String?
  public var timezone: String?
  public var createdAt: String
  public var updatedAt: String
  public var sequence: UInt32

  public init(
    id: String,
    uid: String? = nil,
    recurrenceID: CalendarIcsRecurrenceID? = nil,
    title: String,
    description: String? = nil,
    recurrence: String? = nil,
    recurrenceExceptions: String? = nil,
    startDate: LorvexDate,
    startTime: TimeOfDay? = nil,
    endDate: LorvexDate? = nil,
    endTime: TimeOfDay? = nil,
    allDay: Bool,
    location: String? = nil,
    timezone: String? = nil,
    createdAt: String,
    updatedAt: String,
    sequence: UInt32
  ) {
    self.id = id
    self.uid = uid
    self.recurrenceID = recurrenceID
    self.title = title
    self.description = description
    self.recurrence = recurrence
    self.recurrenceExceptions = recurrenceExceptions
    self.startDate = startDate
    self.startTime = startTime
    self.endDate = endDate
    self.endTime = endTime
    self.allDay = allDay
    self.location = location
    self.timezone = timezone
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.sequence = sequence
  }
}

/// Typed event passed to the ICS emission pipeline.
///
/// The `(startDate, startTime, endDate, endTime, allDay)` quintuple is bundled
/// into a `CalendarEventTiming` so every illegal combination is
/// non-representable. Construction routes through
/// `CalendarEventTiming.fromFlatFields`.
public struct CalendarIcsEvent: Sendable, Equatable {
  public var id: String
  public var uid: String?
  public var recurrenceID: CalendarIcsRecurrenceID?
  public var title: String
  public var description: String?
  public var recurrence: String?
  public var recurrenceExceptions: String?
  public var timing: CalendarEventTiming
  public var location: String?
  public var timezone: String?
  public var createdAt: String
  public var updatedAt: String
  public var sequence: UInt32

  /// Validating constructor.
  public static func make(_ fields: CalendarIcsEventFields) -> Result<CalendarIcsEvent, ValidationError> {
    switch CalendarEventTiming.fromFlatFields(
      startDate: fields.startDate,
      startTime: fields.startTime,
      endDate: fields.endDate,
      endTime: fields.endTime,
      allDay: fields.allDay
    ) {
    case .success(let timing):
      return .success(
        CalendarIcsEvent(
          id: fields.id, uid: fields.uid, recurrenceID: fields.recurrenceID,
          title: fields.title, description: fields.description,
          recurrence: fields.recurrence, recurrenceExceptions: fields.recurrenceExceptions,
          timing: timing, location: fields.location, timezone: fields.timezone,
          createdAt: fields.createdAt, updatedAt: fields.updatedAt, sequence: fields.sequence))
    case .failure(let err):
      return .failure(err)
    }
  }

  public var startDate: LorvexDate { timing.startDate }
  public var startTime: TimeOfDay? { timing.startTime }
  public var endDate: LorvexDate? { timing.endDate }
  public var endTime: TimeOfDay? { timing.endTime }
  public var allDay: Bool { timing.allDay }
}

// MARK: - Errors / Warnings

/// Typed errors surfaced by the ICS export pipeline. The `description` wording
/// is stable; keep it consistent across surfaces.
public enum CalendarIcsError: Error, Equatable, CustomStringConvertible {
  case invalidDate(field: String, value: String)
  case invalidTime(field: String, value: String)
  case invalidTimestamp(field: String, value: String)
  case invalidRange(from: String, to: String)
  case invalidRecurrenceJson(String)
  case invalidRecurrenceRule(String)
  case invalidRecurrenceExceptionJson(String)
  case invalidRecurrenceExceptionDate(String)
  case dateOverflow(field: String, value: String)
  case recurrenceExdateLimitExceeded(count: Int, limit: Int)
  case preGregorianTimestampYear(field: String, year: Int)
  case internalContractViolation(field: String, detail: String)

  public var description: String {
    switch self {
    case .invalidDate(let field, let value):
      return "invalid \(field) date '\(value)', expected YYYY-MM-DD"
    case .invalidTime(let field, let value):
      return "invalid \(field) time '\(value)', expected HH:MM"
    case .invalidTimestamp(let field, let value):
      return "invalid \(field) timestamp '\(value)'"
    case .invalidRange(let from, let to):
      return "to (\(to)) cannot be before from (\(from))"
    case .invalidRecurrenceJson(let raw):
      return "invalid recurrence JSON: \(raw)"
    case .invalidRecurrenceRule(let message):
      return "invalid recurrence rule: \(message)"
    case .invalidRecurrenceExceptionJson(let raw):
      return "invalid recurrence exceptions JSON: \(raw)"
    case .invalidRecurrenceExceptionDate(let value):
      return "invalid recurrence exception date '\(value)', expected YYYY-MM-DD"
    case .dateOverflow(let field, let value):
      return "date overflow computing next day for \(field)='\(value)' (chrono representable range exceeded)"
    case .recurrenceExdateLimitExceeded(let count, let limit):
      return "recurrence_exceptions produced \(count) EXDATE lines, exceeding the cap of \(limit) per VEVENT"
    case .preGregorianTimestampYear(let field, let year):
      return "\(field) year \(year) is before 1900 (RFC 5545 §3.3.5 requires 4-digit Gregorian timestamps; many clients drop VEVENTs that violate this)"
    case .internalContractViolation(let field, let detail):
      return "internal export contract violation on '\(field)': \(detail)"
    }
  }
}

/// Non-fatal observations produced while building an ICS export. Returned
/// alongside the rendered string by `exportCalendarIcsWithWarnings`.
public enum CalendarIcsWarning: Sendable, Equatable {
  case recurrence(RecurrenceWarning)
  case legacyNaiveTimestamp(field: String, value: String)
  case textTruncated(field: String, originalChars: Int, truncatedTo: Int)
}

// MARK: - Validation helpers (date-shape, range)

/// `YYYY-MM-DD` range validator used at the export public-API boundary.
public func validateExportRange(from: String, to: String) -> Result<Void, CalendarIcsError> {
  if case .failure(let e) = parseRequiredIcsDate(field: "from", raw: from) { return .failure(e) }
  if case .failure(let e) = parseRequiredIcsDate(field: "to", raw: to) { return .failure(e) }
  // For canonical `YYYY-MM-DD`, lexical `to < from` is the same as calendar
  // ordering.
  if to < from { return .failure(.invalidRange(from: from, to: to)) }
  return .success(())
}

/// Parse a `YYYY-MM-DD` string into `IsoDate.YMD`, returning the typed
/// `CalendarIcsError.invalidDate` variant on any deviation.
func parseRequiredIcsDate(field: String, raw: String) -> Result<IsoDate.YMD, CalendarIcsError> {
  if let ymd = IsoDate.parse(raw) { return .success(ymd) }
  return .failure(.invalidDate(field: field, value: raw))
}

/// Render a typed `LorvexDate` as the RFC 5545 `YYYYMMDD` form.
func dateToIcs(_ date: LorvexDate) -> String {
  let y = date.ymd.year
  let m = date.ymd.month
  let d = date.ymd.day
  // Emit compact `YYYYMMDD` for the common 4-digit-year case. The upper-bound
  // case wants `+10000-01-01` produced when the input is at the boundary —
  // handled by formatYearMonthDay below.
  return formatYearMonthDay(year: y, month: m, day: d)
}

/// String-input variant of `dateToIcs` used by the recurrence JSON parse
/// path (UNTIL field).
func dateStrToIcs(field: String, raw: String) -> Result<String, CalendarIcsError> {
  switch parseRequiredIcsDate(field: field, raw: raw) {
  case .success(let ymd):
    return .success(formatYearMonthDay(year: ymd.year, month: ymd.month, day: ymd.day))
  case .failure(let e):
    return .failure(e)
  }
}

/// Compute the calendar day after `date`. Returns `dateOverflow` only on the
/// extreme upper bound. Within the parser-accepted range (years 0001..9999) the
/// result is well-defined; for `9999-12-31` the result is a `LorvexDate`-shaped
/// value whose `.asString` renders `+10000-01-01`.
func nextIcsDate(field: String, _ date: LorvexDate) -> Result<LorvexDate, CalendarIcsError> {
  // We model "next day" as raw (year, month, day) arithmetic on a proleptic
  // Gregorian calendar, then re-wrap. For year 9999-12-31 the result is
  // year=10000, month=1, day=1; we surface that through a synthetic YMD so
  // the canonical render is `+10000-01-01`. Overflow is surfaced only when
  // year exceeds `Int.max` — which the YYYY-MM-DD parser makes unreachable.
  let y = date.ymd.year
  let m = date.ymd.month
  let d = date.ymd.day
  let dim = daysInMonth(year: y, month: m)
  if d < dim {
    return .success(LorvexDate(ymd: IsoDate.YMD(year: y, month: m, day: d + 1)))
  }
  if m < 12 {
    return .success(LorvexDate(ymd: IsoDate.YMD(year: y, month: m + 1, day: 1)))
  }
  // year rollover
  if y == Int.max { return .failure(.dateOverflow(field: field, value: date.asString)) }
  return .success(LorvexDate(ymd: IsoDate.YMD(year: y + 1, month: 1, day: 1)))
}

private func daysInMonth(year: Int, month: Int) -> Int {
  switch month {
  case 1, 3, 5, 7, 8, 10, 12: return 31
  case 4, 6, 9, 11: return 30
  case 2:
    let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    return leap ? 29 : 28
  default: return 30
  }
}

/// Format `(year, month, day)` as compact `YYYYMMDD` for the standard case;
/// for 5+ digit years emit `+10000` style (a leading `+` and the full year).
/// The wide case is exercised only by `nextIcsDate(year=10000)`; the matching
/// `LorvexDate.asString` produces `+10000-01-01` via the IsoDate canonical
/// form. For the canonical 4-digit case, output is zero-padded.
private func formatYearMonthDay(year: Int, month: Int, day: Int) -> String {
  if year >= 0 && year <= 9999 {
    return String(format: "%04d%02d%02d", year, month, day)
  }
  // 5+ digit year — emit the leading-`+` `+YYYYYY` form.
  let sign = year >= 0 ? "+" : "-"
  return "\(sign)\(abs(year))" + String(format: "%02d%02d", month, day)
}

// MARK: - Emit entry points

/// VEVENT text cap (SUMMARY/DESCRIPTION/LOCATION), in Unicode scalars, equal to
/// ``ValidationLimits/maxTitleLength``.
let maxVeventTextLength = ValidationLimits.maxTitleLength

public func exportCalendarIcs(_ events: [CalendarIcsEvent]) -> Result<String, CalendarIcsError> {
  switch exportCalendarIcsWithWarnings(events) {
  case .success(let (ics, _)): return .success(ics)
  case .failure(let e): return .failure(e)
  }
}

public func exportCalendarIcsWithWarnings(
  _ events: [CalendarIcsEvent]
) -> Result<(String, [CalendarIcsWarning]), CalendarIcsError> {
  var lines: [String] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Lorvex//Calendar \(LorvexVersion.appVersion)//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
  ]
  var warnings: [CalendarIcsWarning] = []
  for event in events {
    switch appendVevent(into: &lines, event: event, warnings: &warnings) {
    case .success: continue
    case .failure(let e): return .failure(e)
    }
  }
  lines.append("END:VCALENDAR")

  var ics = ""
  ics.reserveCapacity(lines.reduce(0) { $0 + $1.utf8.count } + lines.count * 2)
  for (i, line) in lines.enumerated() {
    if i > 0 { ics += "\r\n" }
    appendFoldedLine(into: &ics, line: line)
  }
  return .success((ics, warnings))
}

private func appendVevent(
  into lines: inout [String], event: CalendarIcsEvent, warnings: inout [CalendarIcsWarning]
) -> Result<Void, CalendarIcsError> {
  let startDateIcs = dateToIcs(event.startDate)
  let createdStamp: String
  switch formatIcsTimestamp(field: "created_at", raw: event.createdAt, warnings: &warnings) {
  case .success(let s): createdStamp = s
  case .failure(let e): return .failure(e)
  }
  let updatedStamp: String
  switch formatIcsTimestamp(field: "updated_at", raw: event.updatedAt, warnings: &warnings) {
  case .success(let s): updatedStamp = s
  case .failure(let e): return .failure(e)
  }

  lines.append("BEGIN:VEVENT")
  lines.append("UID:\(event.uid ?? event.id)@lorvex")
  lines.append("DTSTAMP:\(updatedStamp)")
  lines.append("CREATED:\(createdStamp)")
  lines.append("SEQUENCE:\(event.sequence)")

  if let recurrenceID = event.recurrenceID {
    switch recurrenceID {
    case .date(let date):
      lines.append("RECURRENCE-ID;VALUE=DATE:\(dateToIcs(date))")
    case .dateTime(let date, let time, let timezone):
      lines.append(
        "RECURRENCE-ID:\(localToUtcIcsTimestamp(date: date, time: time, timezone: timezone))")
    }
  }

  let isDateValue = isDateValueEvent(event)
  if isDateValue {
    lines.append("DTSTART;VALUE=DATE:\(startDateIcs)")
    let endDate = event.endDate ?? event.startDate
    switch nextIcsDate(field: "end_date", endDate) {
    case .success(let next):
      lines.append("DTEND;VALUE=DATE:\(dateToIcs(next))")
    case .failure(let e): return .failure(e)
    }
  } else {
    guard let startTime = event.startTime else {
      return .failure(.internalContractViolation(
        field: "start_time",
        detail: "is_date_value_event=false requires start_time to be Some on the timed VEVENT branch"))
    }
    let startUtc = localToUtcIcsTimestamp(
      date: event.startDate, time: startTime, timezone: event.timezone)
    lines.append("DTSTART:\(startUtc)")
    if let endTime = event.endTime {
      let endDate = event.endDate ?? event.startDate
      let endUtc = localToUtcIcsTimestamp(date: endDate, time: endTime, timezone: event.timezone)
      lines.append("DTEND:\(endUtc)")
    } else {
      lines.append("DTEND:\(addOneHourIcs(date: event.startDate, time: startTime, timezone: event.timezone))")
    }
  }

  lines.append("SUMMARY:\(escapeAndCapIcsText(field: "SUMMARY", text: event.title, warnings: &warnings))")

  if let description = event.description, !description.isEmpty {
    lines.append("DESCRIPTION:\(escapeAndCapIcsText(field: "DESCRIPTION", text: description, warnings: &warnings))")
  }
  if let location = event.location, !location.isEmpty {
    lines.append("LOCATION:\(escapeAndCapIcsText(field: "LOCATION", text: location, warnings: &warnings))")
  }

  switch recurrenceToRrule(
    event.recurrence, isDateValue: isDateValue, timezone: event.timezone, warnings: &warnings) {
  case .success(let rrule):
    if let rrule { lines.append(rrule) }
  case .failure(let e): return .failure(e)
  }

  switch recurrenceExdates(event) {
  case .success(let exdates):
    for ex in exdates { lines.append(ex) }
  case .failure(let e): return .failure(e)
  }

  lines.append("END:VEVENT")
  return .success(())
}

// MARK: - Timestamp / timezone helpers

func addOneHourIcs(date: LorvexDate, time: TimeOfDay, timezone: String?) -> String {
  // Add one hour to the naive (date, time) in UTC arithmetic, then convert.
  let local = NaiveDateTime(
    year: date.ymd.year, month: date.ymd.month, day: date.ymd.day,
    hour: time.hour, minute: time.minute, second: time.second)
  let plus = addHoursNaive(local, 1)
  return localNaiveToUtcIcsString(plus, timezone: timezone)
}

/// Convert a stored (local date, local time, timezone) tuple to a UTC ICS
/// timestamp string `YYYYMMDDTHHMMSSZ`. When `timezone` is nil or
/// unparseable, the local time is treated as already-UTC.
func localToUtcIcsTimestamp(date: LorvexDate, time: TimeOfDay, timezone: String?) -> String {
  let local = NaiveDateTime(
    year: date.ymd.year, month: date.ymd.month, day: date.ymd.day,
    hour: time.hour, minute: time.minute, second: time.second)
  return localNaiveToUtcIcsString(local, timezone: timezone)
}

private func localNaiveToUtcIcsString(_ local: NaiveDateTime, timezone: String?) -> String {
  if let tzName = timezone, !tzName.isEmpty, let tz = TimeZone(identifier: tzName) {
    let utc = resolveLocalToUtcIcs(local: local, timezone: tz)
    return formatUtcDateAsIcs(utc)
  }
  return formatNaiveAsIcsZ(local)
}

private func resolveLocalToUtcIcs(local: NaiveDateTime, timezone: TimeZone) -> Date {
  switch DstResolution.resolveLocalDatetime(timezone: timezone, local: local) {
  case .valid(let d): return d
  case .ambiguous(let earlier, _): return earlier
  case .skipped(_, let snappedTo): return snappedTo
  }
}

private let icsUtcCalendar: Calendar = IsoDate.calendar

private func formatUtcDateAsIcs(_ date: Date) -> String {
  let c = icsUtcCalendar.dateComponents(
    [.year, .month, .day, .hour, .minute, .second], from: date)
  return String(
    format: "%04d%02d%02dT%02d%02d%02dZ",
    c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
}

private func formatNaiveAsIcsZ(_ local: NaiveDateTime) -> String {
  return String(
    format: "%04d%02d%02dT%02d%02d%02dZ",
    local.year, local.month, local.day, local.hour, local.minute, local.second)
}

/// Add `hours` to a naive wall clock as plain calendar arithmetic on a UTC
/// gregorian calendar (no timezone), so the step never silently re-snaps
/// across a DST boundary.
private func addHoursNaive(_ local: NaiveDateTime, _ hours: Int) -> NaiveDateTime {
  guard let base = icsUtcCalendar.date(from: local.components),
    let shifted = icsUtcCalendar.date(byAdding: .hour, value: hours, to: base)
  else { return local }
  let c = icsUtcCalendar.dateComponents(
    [.year, .month, .day, .hour, .minute, .second], from: shifted)
  return NaiveDateTime(
    year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0,
    hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0)
}

/// Tries RFC 3339 first, then the two naive fallbacks (T separator and space
/// separator), each of which emits a `legacyNaiveTimestamp` warning. Year < 1900
/// in either naive path is rejected.
func formatIcsTimestamp(
  field: String, raw: String, warnings: inout [CalendarIcsWarning]
) -> Result<String, CalendarIcsError> {
  if let parsed = SyncTimestampFormat.parseRfc3339(raw) {
    // Render the UTC instant.
    let utcSeconds = Int(SyncTimestampFormat.floorDiv(parsed.epochMilliseconds, 1000))
    let date = Date(timeIntervalSince1970: TimeInterval(utcSeconds))
    return .success(formatUtcDateAsIcs(date))
  }
  // Naive `YYYY-MM-DDTHH:MM:SS[.frac]?`
  if let naive = parseNaiveLocalDateTime(raw, separator: "T") {
    if naive.year < 1900 {
      return .failure(.preGregorianTimestampYear(field: field, year: naive.year))
    }
    warnings.append(.legacyNaiveTimestamp(field: field, value: raw))
    return .success(formatNaiveAsIcsZ(naive))
  }
  if let naive = parseNaiveLocalDateTime(raw, separator: " ") {
    if naive.year < 1900 {
      return .failure(.preGregorianTimestampYear(field: field, year: naive.year))
    }
    warnings.append(.legacyNaiveTimestamp(field: field, value: raw))
    return .success(formatNaiveAsIcsZ(naive))
  }
  return .failure(.invalidTimestamp(field: field, value: raw))
}

/// Strict naive datetime parser used by the naive fallback path. Accepts
/// `YYYY-MM-DDTHH:MM:SS` or `YYYY-MM-DD HH:MM:SS` (separator selected by the
/// caller) with an optional fractional-seconds suffix (any digit count). No
/// timezone marker is accepted; the offset is implicit.
private func parseNaiveLocalDateTime(_ raw: String, separator: Character) -> NaiveDateTime? {
  let chars = Array(raw)
  guard chars.count >= 19 else { return nil }
  func d(_ i: Int) -> Int? {
    let c = chars[i]
    guard c.isASCII, c.isNumber, let v = c.wholeNumberValue else { return nil }
    return v
  }
  guard chars[4] == "-", chars[7] == "-" else { return nil }
  guard let y0 = d(0), let y1 = d(1), let y2 = d(2), let y3 = d(3),
    let mo0 = d(5), let mo1 = d(6), let da0 = d(8), let da1 = d(9)
  else { return nil }
  guard chars[10] == separator else { return nil }
  guard chars[13] == ":", chars[16] == ":" else { return nil }
  guard let h0 = d(11), let h1 = d(12), let mi0 = d(14), let mi1 = d(15),
    let s0 = d(17), let s1 = d(18)
  else { return nil }
  // Optional fraction
  var idx = 19
  if idx < chars.count, chars[idx] == "." {
    idx += 1
    guard idx < chars.count, let _ = chars[idx].wholeNumberValue, chars[idx].isNumber else { return nil }
    while idx < chars.count, let _ = chars[idx].wholeNumberValue, chars[idx].isNumber, chars[idx].isASCII {
      idx += 1
    }
  }
  guard idx == chars.count else { return nil }
  let year = y0 * 1000 + y1 * 100 + y2 * 10 + y3
  let month = mo0 * 10 + mo1
  let day = da0 * 10 + da1
  let hour = h0 * 10 + h1
  let minute = mi0 * 10 + mi1
  let second = s0 * 10 + s1
  guard (1...12).contains(month), (1...31).contains(day),
    (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second)
  else { return nil }
  // Validate calendar date (rejects 2026-02-30 etc.) via IsoDate.
  guard IsoDate.validatedYMD(year: year, month: month, day: day) != nil else { return nil }
  return NaiveDateTime(
    year: year, month: month, day: day, hour: hour, minute: minute, second: second)
}

/// Single source of truth for "is the VEVENT a date-only value
/// (`DTSTART;VALUE=DATE`) or a timed datetime?".
func isDateValueEvent(_ event: CalendarIcsEvent) -> Bool {
  return event.allDay || event.startTime == nil
}

// MARK: - Text escape / cap

/// Truncate `text` to `maxVeventTextLength` Unicode scalars, append a
/// single-scalar ellipsis truncation marker, and emit a `textTruncated`
/// warning when the input exceeds the cap. Returns the escaped, capped value.
func escapeAndCapIcsText(
  field: String, text: String, warnings: inout [CalendarIcsWarning]
) -> String {
  // Count Unicode scalars via `unicodeScalars.count`.
  let scalars = Array(text.unicodeScalars)
  let originalChars = scalars.count
  if originalChars > maxVeventTextLength {
    let head = String(String.UnicodeScalarView(scalars.prefix(maxVeventTextLength - 1)))
    let truncated = head + "\u{2026}"
    warnings.append(.textTruncated(
      field: field, originalChars: originalChars, truncatedTo: maxVeventTextLength))
    return escapeIcsText(truncated)
  }
  return escapeIcsText(text)
}

/// Escape an ICS TEXT value per RFC 5545 §3.3.11 and strip the bidi /
/// zero-width / line-separator codepoints `UnicodeHygiene.sanitizeUserText`
/// strips at write boundaries.
func escapeIcsText(_ text: String) -> String {
  let scrubbed = UnicodeHygiene.sanitizeUserText(text)
  var out = ""
  out.reserveCapacity(scrubbed.utf8.count)
  for ch in scrubbed {
    switch ch {
    case "\\": out += "\\\\"
    case ";": out += "\\;"
    case ",": out += "\\,"
    case "\n": out += "\\n"
    case "\r": continue
    default: out.append(ch)
    }
  }
  return out
}

// MARK: - Line folding (75 octets, UTF-8 codepoint safe)

/// Standalone fold helper preserved for tests; in production the exporter
/// streams through `appendFoldedLine`. Splits `line` into 75-octet runs (74
/// after the first line, to leave room for the leading continuation space),
/// inserts `CRLF SP` between runs, and never splits a multi-byte UTF-8
/// codepoint.
public func foldLine(_ line: String) -> String {
  var out = ""
  appendFoldedLine(into: &out, line: line)
  return out
}

/// Streaming variant of `foldLine` that writes into an existing `String`.
/// Walks the input as UTF-8 bytes. The fold point is the last UTF-8 leading
/// byte at or before the octet limit, so multi-byte scalars are never split.
public func appendFoldedLine(into out: inout String, line: String) {
  let bytes = Array(line.utf8)
  if bytes.count <= 75 {
    out += line
    return
  }
  var pos = 0
  var first = true
  while pos < bytes.count {
    let maxChunk = first ? 75 : 74
    var end = min(pos + maxChunk, bytes.count)
    // Walk back to the last UTF-8 codepoint boundary. A boundary is either
    // end-of-string or a non-continuation byte at position `end`.
    while end > pos && !isStartOfCodepoint(bytes, end) {
      end -= 1
    }
    if end == pos {
      // Single multi-byte codepoint exceeded the chunk; advance by its
      // full UTF-8 length so we make progress.
      end = pos + utf8CodepointLength(bytes, at: pos)
    }
    if !first { out += "\r\n " }
    if let chunk = String(bytes: bytes[pos..<end], encoding: .utf8) {
      out += chunk
    }
    pos = end
    first = false
  }
}

/// True iff `bytes[i]` is a UTF-8 continuation byte (`10xxxxxx`).
private func isUtf8ContinuationByte(_ b: UInt8) -> Bool {
  return (b & 0xC0) == 0x80
}

/// True iff position `i` (0-based) sits on a UTF-8 codepoint boundary —
/// either at the end of the buffer or on a non-continuation byte.
private func isStartOfCodepoint(_ bytes: [UInt8], _ i: Int) -> Bool {
  if i == bytes.count { return true }
  return !isUtf8ContinuationByte(bytes[i])
}

/// UTF-8 codepoint length starting at byte `i`. Matches `char::len_utf8`.
private func utf8CodepointLength(_ bytes: [UInt8], at i: Int) -> Int {
  guard i < bytes.count else { return 1 }
  let b = bytes[i]
  if b < 0x80 { return 1 }
  if b < 0xC0 { return 1 }  // stray continuation; defensive
  if b < 0xE0 { return 2 }
  if b < 0xF0 { return 3 }
  return 4
}
