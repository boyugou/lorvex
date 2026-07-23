import Foundation

/// Timezone parsing / normalization helpers and the timezone-aware
/// "today" / "today + N days" `YYYY-MM-DD` helpers used for day-boundary logic.
///
/// Generic event/reminder fields accept any identifier Foundation resolves.
/// The synced product-timezone preference is stricter: it uses Apple's canonical
/// region list (plus canonical `UTC`) so aliases and fixed-offset spellings do
/// not create distinct synced bytes for the same calendar-day authority.
/// A failure resolving the anchored timezone, carrying the human-readable
/// message used by the anchored-timezone resolver.
public struct TimezoneResolutionError: Error, Equatable, CustomStringConvertible {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var description: String { message }
}

public enum Timezone {
  /// Parse any non-empty timezone identifier Foundation recognizes.
  public static func parseTimezoneName(_ value: String) -> TimeZone? {
    let trimmed = ValidationFormat.trimWhitespace(value)
    guard !trimmed.isEmpty else { return nil }
    return TimeZone(identifier: trimmed)
  }

  /// Normalize a generic Foundation timezone identifier. Event and reminder
  /// payloads use this broader contract because fixed offsets are valid there.
  public static func normalizeTimezoneName(_ value: String?) -> String? {
    guard let value = value else { return nil }
    let trimmed = ValidationFormat.trimWhitespace(value)
    return parseTimezoneName(trimmed) != nil ? trimmed : nil
  }

  /// Normalize the synced product-day authority to one stable identifier.
  /// Abbreviations (`PST`), fixed offsets (`GMT+5`), and alias spellings absent
  /// from Apple's canonical identifier list are rejected. `GMT` and `UTC` both
  /// normalize to the single product spelling `UTC`.
  public static func normalizeProductTimezoneName(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = ValidationFormat.trimWhitespace(value)
    guard !trimmed.isEmpty else { return nil }
    if trimmed == "UTC" || trimmed == "GMT" { return "UTC" }
    guard TimeZone.knownTimeZoneIdentifiers.contains(trimmed) else { return nil }
    return trimmed
  }

  /// Parse a canonical JSON string preference containing a canonical product timezone.
  /// Raw unquoted strings and invalid identifiers are rejected.
  public static func parseJsonTimezonePreference(_ raw: String?) -> String? {
    guard let timezone = Parsing.parseJsonStringPreference(raw) else { return nil }
    return normalizeProductTimezoneName(timezone)
  }

  /// Parse a stored timezone preference that must contain a valid canonical IANA
  /// timezone string, surfacing a typed ``ValidationError`` for the missing /
  /// invalid cases.
  public static func parseRequiredTimezonePreference(
    _ raw: String, key: String
  ) -> Result<String, ValidationError> {
    guard let timezone = Parsing.parseJsonStringPreference(raw) else {
      return .failure(
        .message("invalid \(key) preference: expected canonical JSON timezone string"))
    }
    if let canonical = normalizeProductTimezoneName(timezone) {
      return .success(canonical)
    }
    return .failure(.message("invalid \(key) preference: unknown timezone '\(timezone)'"))
  }

  /// Resolve the anchored timezone used for calendar/day-boundary logic.
  ///
  /// Preference order: an explicit validated active timezone, then the current
  /// system IANA timezone (when resolvable and valid). When neither is available
  /// the caller fails rather than silently substituting UTC, which would shift
  /// calendar-day boundaries. The system lookup is passed in as a `Result` so
  /// the domain layer stays free of implicit host-clock reads.
  public static func resolveAnchoredTimezoneName(
    activeTimezone: String?,
    systemTimezoneLookup: Result<String, TimezoneResolutionError>
  ) -> Result<String, TimezoneResolutionError> {
    if let activeTimezone,
      let canonical = normalizeProductTimezoneName(activeTimezone)
    {
      return .success(canonical)
    }
    switch systemTimezoneLookup {
    case let .failure(error):
      return .failure(
        TimezoneResolutionError(
          "anchored timezone requires a resolvable system IANA timezone: \(error.message)"))
    case let .success(timezone):
      if let normalized = normalizeProductTimezoneName(timezone) {
        return .success(normalized)
      }
      return .failure(
        TimezoneResolutionError(
          "anchored timezone requires a valid IANA timezone, got '\(timezone)'"))
    }
  }

  /// Today's date as `YYYY-MM-DD` in the given IANA timezone, falling back to
  /// `systemFallback` when the timezone name is `nil` or unrecognized.
  ///
  /// `now` is the reference instant (the UTC wall clock). `systemFallback` is the
  /// time zone to use when no valid preference is supplied — the caller passes its
  /// system-local zone, keeping the domain layer free of implicit host reads.
  /// An invalid (`Some(invalid)`) preference name falls back gracefully to
  /// `systemFallback` rather than aborting.
  public static func todayYmdForTimezoneName(
    now: Date, timezoneName: String?, systemFallback: TimeZone
  ) -> String {
    baseDateComponents(now: now, timezoneName: timezoneName, systemFallback: systemFallback)
      .canonicalString
  }

  /// Today + `offsetDays` as `YYYY-MM-DD` in the given IANA timezone, falling back
  /// to `systemFallback` when the name is `nil` or unrecognized.
  public static func datePlusDaysYmdForTimezoneName(
    now: Date, timezoneName: String?, offsetDays: Int, systemFallback: TimeZone
  ) -> String {
    let base = baseDateComponents(now: now, timezoneName: timezoneName, systemFallback: systemFallback)
    // Day arithmetic on a pure date is timezone-agnostic; the shared UTC
    // calendar means adding days never crosses a DST boundary in the math.
    let cal = IsoDate.calendar
    var dc = DateComponents()
    dc.year = base.year
    dc.month = base.month
    dc.day = base.day
    guard let date = cal.date(from: dc),
      let shifted = cal.date(byAdding: .day, value: offsetDays, to: date)
    else { return base.canonicalString }
    let c = cal.dateComponents([.year, .month, .day], from: shifted)
    return IsoDate.YMD(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0).canonicalString
  }

  /// The first midnight strictly after `now` in the configured product zone.
  ///
  /// Long-lived app processes use this boundary to refresh their materialized
  /// logical day even when the device itself is in another time zone (where
  /// `NSCalendarDayChanged` fires at a different instant). Invalid names fail
  /// closed instead of silently scheduling against the device zone.
  public static func nextMidnight(after now: Date, timezoneName: String) -> Date? {
    guard let zone = parseTimezoneName(timezoneName) else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = zone
    return calendar.nextDate(
      after: now,
      matching: DateComponents(hour: 0, minute: 0, second: 0),
      matchingPolicy: .nextTime,
      direction: .forward
    )
  }

  /// Resolve the calendar date `now` falls on under `timezoneName`, falling back
  /// to `systemFallback` on either `nil` or an unparseable name.
  static func baseDateComponents(
    now: Date, timezoneName: String?, systemFallback: TimeZone
  ) -> IsoDate.YMD {
    let zone: TimeZone
    if let name = timezoneName, let parsed = parseTimezoneName(name) {
      zone = parsed
    } else {
      zone = systemFallback
    }
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = zone
    let c = cal.dateComponents([.year, .month, .day], from: now)
    return IsoDate.YMD(year: c.year ?? 0, month: c.month ?? 0, day: c.day ?? 0)
  }
}
