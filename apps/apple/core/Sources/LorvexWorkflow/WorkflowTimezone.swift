import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// UTC bounds of a trailing day-count window, expressed as both the local
/// day strings the window covers and the UTC instants that bound the SQL
/// query.
public struct TrailingDayWindowUtcBounds: Sendable, Equatable {
  public let fromDay: String
  public let toDay: String
  public let startUtc: String
  public let endUtc: String
}

/// DB-backed timezone helpers used across workflow surfaces, layered over
/// the pure-domain helpers in ``Timezone``.
public enum WorkflowTimezone {
  /// Maximum number of skipped local days probed before giving up when
  /// resolving the first valid UTC instant for a local day.
  static let maxSkippedDayFallback: Int = 3

  /// Read the `timezone` preference from the database and validate it.
  public static func activeTimezoneName(_ db: Database) throws -> String? {
    guard
      let raw = try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?1",
        arguments: [PreferenceKeys.prefTimezone])
    else { return nil }
    switch Timezone.parseRequiredTimezonePreference(raw, key: PreferenceKeys.prefTimezone) {
    case .success(let name):
      return name
    case .failure(let error):
      throw StoreError.validation(error.description)
    }
  }

  /// Resolve the anchored timezone: prefer the DB preference, fall back to
  /// the system IANA timezone, error otherwise.
  public static func anchoredTimezoneName(_ db: Database) throws -> String {
    let active = try activeTimezoneName(db)
    let systemLookup: Result<String, TimezoneResolutionError>
    if let id = TimeZone.current.identifier as String? {
      systemLookup = .success(id)
    } else {
      systemLookup = .failure(TimezoneResolutionError("system timezone unavailable"))
    }
    switch Timezone.resolveAnchoredTimezoneName(
      activeTimezone: active, systemTimezoneLookup: systemLookup)
    {
    case .success(let name): return name
    case .failure(let error): throw StoreError.validation(error.message)
    }
  }

  /// Today's date as `YYYY-MM-DD` in the user's configured timezone.
  public static func todayYmdForConn(_ db: Database, now: Date = Date()) throws -> String {
    let tz = try anchoredTimezoneName(db)
    return Timezone.todayYmdForTimezoneName(
      now: now, timezoneName: tz, systemFallback: TimeZone.current)
  }

  /// Date offset by `days` from `now` as `YYYY-MM-DD` in the user's
  /// configured timezone.
  public static func datePlusDaysYmdForConn(
    _ db: Database, now: Date = Date(), days: Int
  ) throws -> String {
    let tz = try anchoredTimezoneName(db)
    return Timezone.datePlusDaysYmdForTimezoneName(
      now: now, timezoneName: tz, offsetDays: days, systemFallback: TimeZone.current)
  }

  /// The calendar day `instant` falls on as `YYYY-MM-DD` in the user's
  /// configured timezone. ``todayYmdForConn(_:now:)`` is this with `instant`
  /// pinned to now; callers that need the local day of a stored UTC timestamp
  /// (e.g. a habit's `created_at`) pass that instant here.
  public static func ymdForConn(_ db: Database, instant: Date) throws -> String {
    let tz = try anchoredTimezoneName(db)
    return Timezone.todayYmdForTimezoneName(
      now: instant, timezoneName: tz, systemFallback: TimeZone.current)
  }

  /// UTC bounds for a trailing day-count window ending today, computed in
  /// the user's configured timezone.
  public static func trailingDayWindowUtcBoundsForConn(
    _ db: Database, now: Date = Date(), spanDays: Int
  ) throws -> TrailingDayWindowUtcBounds {
    if spanDays < 1 {
      throw StoreError.validation("trailing day window must cover at least one day")
    }
    let tzName = try anchoredTimezoneName(db)
    let toDay = Timezone.todayYmdForTimezoneName(
      now: now, timezoneName: tzName, systemFallback: TimeZone.current)
    let fromDay = try datePlusDaysYmdForConn(db, now: now, days: -(spanDays - 1))
    let nextDay = try datePlusDaysYmdForConn(db, now: now, days: 1)
    let zone = Timezone.parseTimezoneName(tzName) ?? TimeZone.current
    return TrailingDayWindowUtcBounds(
      fromDay: fromDay, toDay: toDay,
      startUtc: try utcStartOfDay(day: fromDay, zone: zone),
      endUtc: try utcStartOfDay(day: nextDay, zone: zone))
  }

  /// Pure-calendar day offset on a canonical `YYYY-MM-DD`; timezone-free
  /// (day arithmetic does not depend on the wall clock).
  static func ymdPlusDays(_ day: String, days: Int) throws -> String {
    guard case .success(let ymd) = IsoDate.parseIsoDate(day) else {
      throw StoreError.validation("'\(day)' is not a valid YYYY-MM-DD calendar date")
    }
    return IsoDate.addingDays(ymd, days).canonicalString
  }

  /// UTC bounds for a `spanDays` window ending on `anchorDay` (inclusive),
  /// computed in the user's configured timezone. Produces the same window as
  /// ``trailingDayWindowUtcBoundsForConn(_:now:spanDays:)`` when `anchorDay`
  /// is today — the anchored form exists so callers can ask for past weeks.
  public static func dayWindowUtcBoundsForConn(
    _ db: Database, endingOn anchorDay: String, spanDays: Int
  ) throws -> TrailingDayWindowUtcBounds {
    if spanDays < 1 {
      throw StoreError.validation("trailing day window must cover at least one day")
    }
    guard case .success(let anchor) = IsoDate.parseIsoDate(anchorDay) else {
      throw StoreError.validation("'\(anchorDay)' is not a valid YYYY-MM-DD calendar date")
    }
    let tzName = try anchoredTimezoneName(db)
    let zone = Timezone.parseTimezoneName(tzName) ?? TimeZone.current
    let toDay = anchor.canonicalString
    let fromDay = try ymdPlusDays(toDay, days: -(spanDays - 1))
    let nextDay = try ymdPlusDays(toDay, days: 1)
    return TrailingDayWindowUtcBounds(
      fromDay: fromDay, toDay: toDay,
      startUtc: try utcStartOfDay(day: fromDay, zone: zone),
      endUtc: try utcStartOfDay(day: nextDay, zone: zone))
  }

  /// First valid UTC instant for a local day, falling back across up to
  /// ``maxSkippedDayFallback`` adjacent days when the supplied day is
  /// entirely skipped under the zone. Internal.
  static func firstValidUtcForLocalDay(
    day: IsoDate.YMD, zone: TimeZone
  ) -> Date? {
    for offset in 0...maxSkippedDayFallback {
      let probeDay = IsoDate.addingDays(day, offset)
      if let value = firstValidUtcOn(day: probeDay, zone: zone) {
        return value
      }
    }
    return nil
  }

  /// Scan the 24 * 60 minutes of `day` in `zone` and return the UTC instant
  /// of the first one resolvable as a local wall-clock time. Skipped DST
  /// gaps are stepped past; ambiguous repeats pick the earlier UTC instant.
  /// Returns `nil` if every minute of `day` is in a skipped range.
  static func firstValidUtcOn(day: IsoDate.YMD, zone: TimeZone) -> Date? {
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = zone
    for minute in 0..<(24 * 60) {
      var dc = DateComponents()
      dc.year = day.year
      dc.month = day.month
      dc.day = day.day
      dc.hour = minute / 60
      dc.minute = minute % 60
      dc.second = 0
      guard let local = cal.date(from: dc) else { continue }
      // `Calendar.date(from:)` rounds forward through gaps and picks
      // the *first* of two ambiguous repeats.
      let roundtripComponents = cal.dateComponents(
        [.year, .month, .day, .hour, .minute], from: local)
      if roundtripComponents.year == day.year, roundtripComponents.month == day.month,
        roundtripComponents.day == day.day, roundtripComponents.hour == minute / 60,
        roundtripComponents.minute == minute % 60
      {
        return local
      }
    }
    return nil
  }

  static func utcStartOfDay(day: String, zone: TimeZone) throws -> String {
    let parsedDay: IsoDate.YMD
    switch IsoDate.parseIsoDate(day) {
    case .success(let ymd): parsedDay = ymd
    case .failure:
      throw StoreError.validation("invalid local day boundary '\(day)'")
    }
    guard let utc = firstValidUtcForLocalDay(day: parsedDay, zone: zone) else {
      throw StoreError.validation(
        "could not resolve UTC boundary for local day '\(day)': "
          + "every probed day was skipped by the timezone")
    }
    return SyncTimestampFormat.formatSyncTimestamp(utc)
  }
}
