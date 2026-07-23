import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// Shared task-reminder local wall-clock anchor resolution.
///
/// Reminder rows store `reminder_at` as a UTC instant, but timezone
/// preference changes must preserve the user's local wall-clock intent
/// ("9 AM") rather than keep the old UTC instant fixed. The anchor columns
/// (`original_local_time`, `original_tz`) capture that intent at write time
/// for every task reminder writer.
public enum ReminderAnchor {
  /// Resolve `(originalLocalTime, originalTz)` from an RFC 3339 reminder
  /// instant. Returns `(nil, nil)` if the string is unparseable or no
  /// timezone preference is set.
  public static func resolveTaskReminderLocalAnchor(
    _ db: Database, reminderAtRfc3339: String
  ) throws -> (String?, String?) {
    guard let reminderUtc = parseRfc3339ToDate(reminderAtRfc3339) else {
      return (nil, nil)
    }
    return try resolveTaskReminderLocalAnchorForUtc(db, reminderUtc: reminderUtc)
  }

  /// Resolve `(originalLocalTime, originalTz)` from a parsed UTC instant.
  public static func resolveTaskReminderLocalAnchorForUtc(
    _ db: Database, reminderUtc: Date
  ) throws -> (String?, String?) {
    guard let tzName = try WorkflowTimezone.activeTimezoneName(db) else {
      return (nil, nil)
    }
    guard let tz = Timezone.parseTimezoneName(tzName) else {
      return (nil, nil)
    }
    var cal = Calendar(identifier: .gregorian)
    cal.locale = Locale(identifier: "en_US_POSIX")
    cal.timeZone = tz
    let c = cal.dateComponents([.hour, .minute], from: reminderUtc)
    let local = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    return (local, tzName)
  }

  /// Re-materialize a reminder's UTC instant when the timezone preference
  /// changes, preserving the wall-clock intent captured by the anchor columns.
  ///
  /// The anchor date is derived here (never persisted): interpret the current
  /// `reminder_at` in `originalTzName` to recover the calendar date the reminder
  /// falls on, then return the instant of that same date at `originalLocalTime`
  /// (`HH:MM`) in `newTz`. So a reminder stored as "09:00 America/New_York" on a
  /// given day becomes 09:00 on that same day in `newTz` — "9 AM local" survives
  /// the zone change. When the target wall time does not exist in `newTz` (it
  /// lands in a spring-forward gap that calendar day), the reminder resolves to
  /// the day's first valid instant rather than the missing time, so it stays on
  /// its intended day and the caller can still advance `original_tz` — never
  /// leaving the stale old-zone instant paired with a mismatched anchor. Returns
  /// `nil` only when an input is unparseable.
  public static func rematerializedInstant(
    currentReminderAtRfc3339: String, originalLocalTime: String,
    originalTz originalTzName: String, newTz: TimeZone
  ) -> Date? {
    guard let reminderUtc = parseRfc3339ToDate(currentReminderAtRfc3339),
      let originalTz = Timezone.parseTimezoneName(originalTzName),
      let (hour, minute) = parseLocalHourMinute(originalLocalTime)
    else { return nil }

    var originalCal = Calendar(identifier: .gregorian)
    originalCal.locale = Locale(identifier: "en_US_POSIX")
    originalCal.timeZone = originalTz
    let anchorDate = originalCal.dateComponents([.year, .month, .day], from: reminderUtc)

    var newCal = Calendar(identifier: .gregorian)
    newCal.locale = Locale(identifier: "en_US_POSIX")
    newCal.timeZone = newTz
    var dc = DateComponents()
    dc.year = anchorDate.year
    dc.month = anchorDate.month
    dc.day = anchorDate.day
    dc.hour = hour
    dc.minute = minute
    dc.second = 0
    guard let candidate = newCal.date(from: dc) else { return nil }
    // `Calendar.date(from:)` slides a nonexistent spring-forward wall time to
    // the next real instant; when the result round-trips, the wall time exists
    // in `newTz` and is used directly.
    let roundTrip = newCal.dateComponents([.hour, .minute], from: candidate)
    if roundTrip.hour == hour, roundTrip.minute == minute {
      return candidate
    }
    // The wall time falls in a spring-forward gap in `newTz` (it does not exist
    // that calendar day). Resolve to the day's first valid instant so the
    // reminder stays on its intended day and the caller still advances the anchor
    // zone, rather than leaving the stale old-zone instant with a mismatched
    // `original_tz`.
    guard let year = anchorDate.year, let month = anchorDate.month, let day = anchorDate.day
    else { return nil }
    return WorkflowTimezone.firstValidUtcOn(
      day: IsoDate.YMD(year: year, month: month, day: day), zone: newTz)
  }

  /// Parse a stored `HH:MM` local time (the `original_local_time` shape) into
  /// `(hour, minute)`, rejecting anything out of range or malformed.
  private static func parseLocalHourMinute(_ raw: String) -> (Int, Int)? {
    let parts = raw.split(separator: ":")
    guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
      (0...23).contains(hour), (0...59).contains(minute)
    else { return nil }
    return (hour, minute)
  }

  /// Parse an RFC 3339 date-time (with offset or `Z`) to a `Date`, trying the
  /// fractional-seconds form first and falling back to whole-second
  /// `withInternetDateTime`. Returns `nil` on any deviation.
  ///
  /// The single shared RFC 3339 → `Date` parser for the workflow reminder/date
  /// paths (reminder-anchor resolution, successor spawning, reminder-shift
  /// deferral, task-create date normalization). Distinct from the domain
  /// `SyncTimestampFormat.parseRfc3339` char-by-char parser, which deliberately
  /// accepts a wider set (space separator, arbitrary fractional width).
  static func parseRfc3339ToDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
  }
}
