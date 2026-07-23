import Foundation
import LorvexDomain
import LorvexStore

// MARK: - Normalization entry points

/// Calendar-event normalization + validation.
public enum CalendarNormalization {

  /// Create-path driver: title + optional-field normalization,
  /// recurrence canonicalization (with BYMONTHDAY injection from the
  /// start_date anchor), all-day time-clearing, field-shape validation,
  /// DST guard.
  public static func normalizeCalendarCreate(
    _ input: CalendarCreateInput
  ) throws -> NormalizedCalendarCreate {
    let title = try normalizeCalendarTitle(input.title)
    let description = try normalizeOptionalText(
      input.description, field: "description", max: ValidationLimits.maxBodyLength,
      escapedBudget: PayloadByteBudget.longTextEscapedBytes)
    let location = try normalizeOptionalText(
      input.location, field: "location", max: ValidationLimits.maxShortTextLength)
    let personName = try normalizeOptionalText(
      input.personName, field: "person_name", max: ValidationLimits.maxShortTextLength)
    let url = try normalizeOptionalURL(input.url)
    try validateOptionalColor(input.color)
    let timezone = try normalizeOptionalTimezone(input.timezone)
    try validateDate(input.startDate, field: "start_date")
    if let v = input.startTime { try validateTime(v, field: "start_time") }
    if let v = input.endDate { try validateDate(v, field: "end_date") }
    if let v = input.endTime { try validateTime(v, field: "end_time") }
    let recurrence: String?
    switch input.recurrence {
    case .none: recurrence = nil
    case .some(let raw):
      switch try normalizeRecurrencePatch(.set(raw), startDate: input.startDate) {
      case .set(let v): recurrence = v
      case .clear, .unset: recurrence = nil
      }
    }
    try validateRecurrenceUntilAfterStart(recurrence, startDate: input.startDate)

    let allDay = input.allDay ?? false
    let startTime = allDay ? nil : input.startTime
    let endTime = allDay ? nil : input.endTime
    try validateFieldShape(
      startDate: input.startDate, startTime: startTime,
      endDate: input.endDate, endTime: endTime, allDay: allDay)
    let dst = try checkCalendarEventDST(
      startDate: input.startDate, startTime: startTime,
      timezone: timezone, allDay: allDay)

    return NormalizedCalendarCreate(
      title: title, recurrence: recurrence, timezone: timezone,
      startDate: input.startDate, startTime: startTime,
      endDate: input.endDate, endTime: endTime, allDay: allDay,
      description: description, location: location, url: url,
      color: input.color,
      eventType: input.eventType ?? .event,
      personName: personName, dstGuard: dst)
  }

  /// Update-path driver: applies `Patch<T>` per field, reconciles each
  /// patch against `existing` into ``EffectiveCalendarEventFields``,
  /// validates the prospective post-patch row + DST guard.
  public static func normalizeCalendarUpdate(
    _ input: CalendarUpdateInput, existing: CalendarUpdateExisting
  ) throws -> NormalizedCalendarUpdate {
    try validateExisting(existing)
    let title = try input.title.map(normalizeCalendarTitle)
    if let v = input.startDate { try validateDate(v, field: "start_date") }
    let startTime = try normalizeTimePatch(input.startTime, field: "start_time")
    let endDate = try normalizeDatePatch(input.endDate, field: "end_date")
    let endTime = try normalizeTimePatch(input.endTime, field: "end_time")
    let description = try normalizeTextPatch(
      input.description, field: "description", max: ValidationLimits.maxBodyLength,
      escapedBudget: PayloadByteBudget.longTextEscapedBytes)
    let location = try normalizeTextPatch(
      input.location, field: "location", max: ValidationLimits.maxShortTextLength)
    let personName = try normalizeTextPatch(
      input.personName, field: "person_name", max: ValidationLimits.maxShortTextLength)
    let url = try normalizeURLPatch(input.url)
    let color = try normalizeColorPatch(input.color)
    let timezone = try normalizeTimezonePatch(input.timezone)

    let effectiveStartDate = input.startDate ?? existing.startDate
    let recurrence: Patch<String>
    switch input.recurrence {
    case .set, .clear:
      recurrence = try normalizeRecurrencePatch(
        input.recurrence, startDate: effectiveStartDate)
    case .unset:
      // POLICY: moving a series' start re-normalizes its recurrence exactly as
      // creating the series at that start would. A start_date change with no
      // explicit recurrence edit re-runs create-time normalization against the
      // new anchor — re-deriving an auto-injected BYMONTHDAY and re-validating
      // WEEKLY BYDAY / UNTIL — so "move the start" and "create at that start"
      // yield identical rules. Leaving the stored rule untouched would strand the
      // OLD anchor's derived day-of-month (e.g. a monthly series moved from the
      // 28th to Jan-31 would keep recurring on the 28th). An explicitly-chosen
      // day-of-month is preserved (see ``CalendarRecurrence/reanchorBymonthday``).
      if let existingRec = existing.recurrence, let newStart = input.startDate,
        newStart != existing.startDate
      {
        let reanchored = try reanchoredRecurrence(
          existingRec, oldStart: existing.startDate, newStart: newStart)
        recurrence = try normalizeRecurrencePatch(.set(reanchored), startDate: newStart)
      } else {
        recurrence = .unset
      }
    }
    if case .set(let rec) = recurrence {
      try validateRecurrenceUntilAfterStart(rec, startDate: effectiveStartDate)
    }

    let (resolvedStartTime, resolvedEndTime): (Patch<String>, Patch<String>) =
      input.allDay == true ? (.clear, .clear) : (startTime, endTime)

    let effective = resolveEffectiveFields(
      existing: existing, startDate: input.startDate,
      startTime: resolvedStartTime, endDate: endDate, endTime: resolvedEndTime,
      allDay: input.allDay, timezone: timezone)
    try validateFieldShape(
      startDate: effective.startDate, startTime: effective.startTime,
      endDate: effective.endDate, endTime: effective.endTime,
      allDay: effective.allDay)
    let dst = try checkCalendarEventDST(
      startDate: effective.startDate, startTime: effective.startTime,
      timezone: effective.timezone, allDay: effective.allDay)

    return NormalizedCalendarUpdate(
      title: title, recurrence: recurrence, timezone: timezone,
      startDate: input.startDate, startTime: resolvedStartTime,
      endDate: endDate, endTime: resolvedEndTime, allDay: input.allDay,
      description: description, location: location, url: url, color: color,
      eventType: input.eventType, personName: personName,
      effective: effective, dstGuard: dst)
  }

  // MARK: - Title normalization (shared by create + update)

  static func normalizeCalendarTitle(_ title: String) throws -> String {
    let cleaned = UnicodeHygiene.sanitizeUserText(title)
    let trimmed = trimWhitespace(cleaned)
    if trimmed.isEmpty {
      throw CalendarEventOpError.validation(
        "calendar event title must not be empty")
    }
    try validateLength(trimmed, field: "title", max: ValidationLimits.maxTitleLength)
    return trimmed
  }

  // MARK: - Patch / Optional normalizers

  static func normalizeOptionalText(
    _ value: String?, field: String, max: Int, escapedBudget: Int? = nil
  ) throws -> String? {
    guard let value else { return nil }
    let normalized = UnicodeHygiene.sanitizeUserText(value)
    try validateLength(normalized, field: field, max: max)
    if let escapedBudget,
      case let .failure(e) = PayloadByteBudget.validateEscapedBudget(
        normalized, field: field, budget: escapedBudget)
    {
      throw CalendarEventOpError.validation(e.description)
    }
    return normalized
  }

  static func normalizeTextPatch(
    _ value: Patch<String>, field: String, max: Int, escapedBudget: Int? = nil
  ) throws -> Patch<String> {
    switch value {
    case .unset: return .unset
    case .clear: return .clear
    case .set(let raw):
      let normalized = UnicodeHygiene.sanitizeUserText(raw)
      try validateLength(normalized, field: field, max: max)
      if let escapedBudget,
        case let .failure(e) = PayloadByteBudget.validateEscapedBudget(
          normalized, field: field, budget: escapedBudget)
      {
        throw CalendarEventOpError.validation(e.description)
      }
      return .set(normalized)
    }
  }

  static func normalizeOptionalURL(_ value: String?) throws -> String? {
    guard let value else { return nil }
    let sanitized = UnicodeHygiene.sanitizeUserText(value)
    let trimmed = trimWhitespace(sanitized)
    if trimmed.isEmpty { return nil }
    try validateLength(trimmed, field: "url", max: ValidationLimits.maxShortTextLength)
    switch ValidationFormat.validateUserURL(trimmed) {
    case .success(let canonical): return canonical
    case .failure(let err):
      throw CalendarEventOpError.validation(err.description)
    }
  }

  static func normalizeURLPatch(_ value: Patch<String>) throws -> Patch<String> {
    switch value {
    case .unset: return .unset
    case .clear: return .clear
    case .set(let raw):
      let sanitized = UnicodeHygiene.sanitizeUserText(raw)
      let trimmed = trimWhitespace(sanitized)
      if trimmed.isEmpty {
        throw CalendarEventOpError.validation(
          "url must not be empty; clear the field instead")
      }
      try validateLength(trimmed, field: "url", max: ValidationLimits.maxShortTextLength)
      switch ValidationFormat.validateUserURL(trimmed) {
      case .success(let canonical): return .set(canonical)
      case .failure(let err):
        throw CalendarEventOpError.validation(err.description)
      }
    }
  }

  static func normalizeOptionalTimezone(_ value: String?) throws -> String? {
    guard let raw = value else { return nil }
    let trimmed = trimWhitespace(raw)
    guard let normalized = Timezone.normalizeTimezoneName(trimmed) else {
      throw CalendarEventOpError.validation("invalid IANA timezone: '\(raw)'")
    }
    return normalized
  }

  static func normalizeTimezonePatch(_ value: Patch<String>) throws -> Patch<String> {
    switch value {
    case .unset: return .unset
    case .clear: return .clear
    case .set(let raw):
      let normalized = try normalizeOptionalTimezone(raw)
      if let v = normalized { return .set(v) }
      return .clear
    }
  }

  static func normalizeRecurrencePatch(
    _ value: Patch<String>, startDate: String
  ) throws -> Patch<String> {
    switch value {
    case .unset: return .unset
    case .clear: return .clear
    case .set(let raw):
      let normalized: String?
      switch ValidationRecurrence.normalizeCalendarRecurrence(Optional(raw)) {
      case .success(let v): normalized = v
      case .failure(let err):
        throw CalendarEventOpError.validation(err.description)
      }
      guard let canonical = normalized else { return .clear }
      // BYMONTHDAY injection for monthly anchors.
      let injected: String
      do {
        if let withByMonthDay = try CalendarRecurrence.injectBymonthday(
          recurrenceJson: canonical, dueDateYmd: startDate)
        {
          injected = withByMonthDay
        } else {
          injected = canonical
        }
      } catch let error as StoreError {
        if case .validation(let m) = error {
          throw CalendarEventOpError.validation(m)
        }
        throw CalendarEventOpError.store(error)
      } catch {
        throw CalendarEventOpError.validation(String(describing: error))
      }
      try validateWeeklyBydayIncludesStartDate(injected, startDate: startDate)
      return .set(injected)
    }
  }

  /// Re-derive an auto-injected BYMONTHDAY when the anchor (start_date) moves
  /// from `oldStart` to `newStart`, mapping store-layer errors onto
  /// ``CalendarEventOpError`` like the rest of recurrence normalization. The
  /// returned rule (unchanged when nothing is re-anchored) is fed back through
  /// ``normalizeRecurrencePatch(_:startDate:)`` so the full create-time pipeline
  /// runs against the new anchor.
  static func reanchoredRecurrence(
    _ recurrenceJson: String, oldStart: String, newStart: String
  ) throws -> String {
    do {
      return try CalendarRecurrence.reanchorBymonthday(
        recurrenceJson: recurrenceJson, oldAnchorYmd: oldStart, newAnchorYmd: newStart)
    } catch let error as StoreError {
      if case .validation(let m) = error {
        throw CalendarEventOpError.validation(m)
      }
      throw CalendarEventOpError.store(error)
    } catch {
      throw CalendarEventOpError.validation(String(describing: error))
    }
  }

  static func validateWeeklyBydayIncludesStartDate(_ recurrence: String, startDate: String) throws {
    guard let parsed = JSONValue.parse(recurrence),
      case .object(let obj) = parsed,
      case .string("WEEKLY") = obj["FREQ"],
      case .array(let byday) = obj["BYDAY"],
      !byday.isEmpty
    else {
      return
    }

    let codes = Set(
      byday.compactMap { value -> String? in
        guard case .string(let code) = value, code.utf8.count == 2 else { return nil }
        return code
      })
    guard !codes.isEmpty else { return }
    guard let startCode = weekdayCode(for: startDate) else {
      throw CalendarEventOpError.validation("start_date is not a valid YYYY-MM-DD calendar date")
    }
    guard codes.contains(startCode) else {
      throw CalendarEventOpError.validation(
        "recurrence.BYDAY must include start_date's weekday (\(startCode)); got \(codes.sorted().joined(separator: ","))")
    }
  }

  static func weekdayCode(for ymd: String) -> String? {
    let parts = ymd.split(separator: "-")
    guard parts.count == 3,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2])
    else { return nil }
    let calendar = IsoDate.calendar
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
      return nil
    }
    switch calendar.component(.weekday, from: date) {
    case 1: return "SU"
    case 2: return "MO"
    case 3: return "TU"
    case 4: return "WE"
    case 5: return "TH"
    case 6: return "FR"
    case 7: return "SA"
    default: return nil
    }
  }

  static func normalizeDatePatch(
    _ value: Patch<String>, field: String
  ) throws -> Patch<String> {
    switch value {
    case .unset: return .unset
    case .clear: return .clear
    case .set(let raw):
      try validateDate(raw, field: field)
      return .set(raw)
    }
  }

  static func normalizeTimePatch(
    _ value: Patch<String>, field: String
  ) throws -> Patch<String> {
    switch value {
    case .unset: return .unset
    case .clear: return .clear
    case .set(let raw):
      try validateTime(raw, field: field)
      return .set(raw)
    }
  }

  static func normalizeColorPatch(_ value: Patch<String>) throws -> Patch<String> {
    if case .set(let v) = value {
      try validateOptionalColor(v)
    }
    return value
  }

  // MARK: - Pure validation helpers

  static func validateLength(_ value: String, field: String, max: Int) throws {
    let actual = value.unicodeScalars.count  // codepoint count
    if actual > max {
      throw CalendarEventOpError.validation(
        "\(field) exceeds maximum length of \(max)")
    }
  }

  static func validateDate(_ value: String, field: String) throws {
    if parseYMD(value) == nil {
      throw CalendarEventOpError.validation("\(field) must be YYYY-MM-DD")
    }
  }

  static func validateTime(_ value: String, field: String) throws {
    if parseHHMM(value) == nil {
      throw CalendarEventOpError.validation("\(field) must be HH:MM (24h)")
    }
  }

  static func validateOptionalColor(_ value: String?) throws {
    guard let value else { return }
    if case .failure(let err) = ValidationFormat.validateHexColor(value) {
      throw CalendarEventOpError.validation(err.description)
    }
  }

  static func validateFieldShape(
    startDate: String, startTime: String?, endDate: String?,
    endTime: String?, allDay: Bool
  ) throws {
    guard let startDay = parseYMD(startDate) else {
      throw CalendarEventOpError.validation("start_date must be YYYY-MM-DD")
    }
    var endDay: (year: Int, month: Int, day: Int)? = nil
    if let v = endDate {
      guard let parsed = parseYMD(v) else {
        throw CalendarEventOpError.validation("end_date must be YYYY-MM-DD")
      }
      if compareYMD(parsed, startDay) < 0 {
        throw CalendarEventOpError.validation(
          "end_date (\(v)) cannot be before start_date (\(startDate))")
      }
      endDay = parsed
    }
    let parsedStart = startTime.flatMap(parseHHMM)
    let parsedEnd = endTime.flatMap(parseHHMM)
    if startTime != nil && parsedStart == nil {
      throw CalendarEventOpError.validation("start_time must be HH:MM (24h)")
    }
    if endTime != nil && parsedEnd == nil {
      throw CalendarEventOpError.validation("end_time must be HH:MM (24h)")
    }
    if allDay { return }
    if parsedStart == nil {
      throw CalendarEventOpError.validation(
        "Pick a start time, or mark this event as all-day.")
    }
    if parsedEnd != nil && parsedStart == nil {
      throw CalendarEventOpError.validation(
        "start_time is required when end_time is provided")
    }
    if let s = parsedStart, let e = parsedEnd {
      let sameDay = (endDay.map { compareYMD($0, startDay) == 0 } ?? true)
      if sameDay && e < s {
        throw CalendarEventOpError.validation(
          "end_time cannot be before start_time for same-day events")
      }
    }
  }

  static func validateRecurrenceUntilAfterStart(
    _ recurrence: String?, startDate: String
  ) throws {
    guard case let .success(typedStartDate) = LorvexDate.parse(startDate) else {
      throw CalendarEventOpError.validation("start_date must be YYYY-MM-DD")
    }
    switch ValidationRecurrence.validateCalendarRecurrenceBound(
      recurrence, startDate: typedStartDate)
    {
    case .success:
      return
    case let .failure(error):
      throw CalendarEventOpError.validation(error.description)
    }
  }

  static func checkCalendarEventDST(
    startDate: String, startTime: String?, timezone: String?, allDay: Bool
  ) throws -> CalendarDstGuard {
    if allDay { return .ok }
    guard let startTime else { return .ok }
    guard let tzName = timezone, !tzName.isEmpty else { return .ok }
    guard let tz = Timezone.parseTimezoneName(tzName) else { return .ok }
    guard let ymd = parseYMD(startDate), let hm = parseHHMM(startTime) else {
      // Shape errors caught earlier; defensive fallback.
      return .ok
    }
    let local = NaiveDateTime(
      year: ymd.year, month: ymd.month, day: ymd.day,
      hour: hm.h, minute: hm.m, second: 0)
    switch DstResolution.resolveLocalDatetime(timezone: tz, local: local) {
    case .valid: return .ok
    case .ambiguous:
      return .ambiguous(
        wallClock: "\(startDate) \(startTime)", timezone: tzName)
    case .skipped:
      throw CalendarEventOpError.validation(
        "The selected time \(startTime) on \(startDate) does not exist in "
          + "\(tzName) - a daylight-saving spring-forward transition skipped "
          + "over it. Please pick a wall-clock time before or after the gap "
          + "(typically one hour earlier or later).")
    }
  }

  static func validateExisting(_ existing: CalendarUpdateExisting) throws {
    if trimWhitespace(existing.startDate).isEmpty {
      throw CalendarEventOpError.validation(
        "existing calendar event row missing required field 'start_date'")
    }
    try validateDate(existing.startDate, field: "start_date")
    if let v = existing.startTime { try validateTime(v, field: "start_time") }
    if let v = existing.endDate { try validateDate(v, field: "end_date") }
    if let v = existing.endTime { try validateTime(v, field: "end_time") }
    if let v = existing.timezone {
      _ = try normalizeOptionalTimezone(v)
    }
  }

  static func resolveEffectiveFields(
    existing: CalendarUpdateExisting, startDate: String?,
    startTime: Patch<String>, endDate: Patch<String>, endTime: Patch<String>,
    allDay: Bool?, timezone: Patch<String>
  ) -> EffectiveCalendarEventFields {
    var eff = EffectiveCalendarEventFields(
      startDate: startDate ?? existing.startDate,
      startTime: resolvePatchString(startTime, existing: existing.startTime),
      endDate: resolvePatchString(endDate, existing: existing.endDate),
      endTime: resolvePatchString(endTime, existing: existing.endTime),
      allDay: allDay ?? existing.allDay,
      timezone: resolvePatchString(timezone, existing: existing.timezone))
    if eff.allDay {
      eff.startTime = nil
      eff.endTime = nil
    }
    return eff
  }

  static func resolvePatchString(
    _ patch: Patch<String>, existing: String?
  ) -> String? {
    switch patch {
    case .unset: return existing
    case .clear: return nil
    case .set(let v): return v
    }
  }
}

// MARK: - Tiny shared parsers (codepoint-counted YYYY-MM-DD / HH:MM)

@inline(__always)
private func trimWhitespace(_ s: String) -> String {
  let scalars = Array(s.unicodeScalars)
  var lo = 0
  var hi = scalars.count
  while lo < hi && scalars[lo].properties.isWhitespace { lo += 1 }
  while hi > lo && scalars[hi - 1].properties.isWhitespace { hi -= 1 }
  return String(String.UnicodeScalarView(scalars[lo..<hi]))
}

@inline(__always)
func parseYMD(_ s: String) -> (year: Int, month: Int, day: Int)? {
  // Parses a calendar date in the exact digit
  // shape the workflow accepts: `YYYY-MM-DD`.
  let parts = s.split(separator: "-", omittingEmptySubsequences: false)
  guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2
  else { return nil }
  guard let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
    return nil
  }
  if m < 1 || m > 12 || d < 1 || d > 31 { return nil }
  // Day-of-month bounds check against month length (Gregorian leap-year rule).
  let isLeap = (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0)
  let monthLen: [Int] = [31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
  if d > monthLen[m - 1] { return nil }
  return (y, m, d)
}

@inline(__always)
func parseHHMM(_ s: String) -> (h: Int, m: Int)? {
  let parts = s.split(separator: ":", omittingEmptySubsequences: false)
  guard parts.count == 2, parts[0].count == 2, parts[1].count == 2 else { return nil }
  guard let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
  if h < 0 || h > 23 || m < 0 || m > 59 { return nil }
  return (h, m)
}

@inline(__always)
private func compareYMD(
  _ a: (year: Int, month: Int, day: Int), _ b: (year: Int, month: Int, day: Int)
) -> Int {
  if a.year != b.year { return a.year < b.year ? -1 : 1 }
  if a.month != b.month { return a.month < b.month ? -1 : 1 }
  if a.day != b.day { return a.day < b.day ? -1 : 1 }
  return 0
}
