import Foundation
import GRDB
import LorvexDomain
import LorvexStore

/// A reminder time as a caller writes it, resolved to the stored UTC instant.
///
/// Two forms are accepted:
/// - An RFC 3339 date-time with `Z` or an offset (`2026-05-23T17:00:00Z`,
///   `2026-05-23T10:00:00-07:00`) names the instant itself.
/// - A date-time without an offset (`2026-05-23T10:00`, seconds optional) is a
///   time on the user's clock: the wall time in the product time zone, which
///   is the `timezone` preference, or the device's zone when none is set.
///
/// A wall time the zone skips on that day (the hour lost when clocks move
/// forward) is rejected, because no instant has that reading. A wall time
/// that occurs twice (the hour repeated when clocks move back) resolves to
/// the earlier instant.
public enum ReminderTimeInput {
  /// The canonical sync-timestamp form of the instant `raw` names. Reads the
  /// product time zone from `db` only when `raw` has no offset. Throws
  /// `StoreError.validation` for a value in neither form, and for a wall time
  /// that does not exist.
  public static func canonicalInstant(_ db: Database, raw: String) throws -> String {
    if let instant = SyncTimestampFormat.canonicalizeRfc3339Instant(raw) {
      return instant
    }
    guard let wallTime = WallTime(raw) else {
      throw StoreError.validation(
        "Invalid reminder time '\(raw)'. Use the local date and time as YYYY-MM-DDTHH:MM "
          + "(e.g. 2025-12-01T09:00), or an RFC 3339 date-time with Z or an offset "
          + "(e.g. 2025-12-01T17:00:00Z).")
    }
    let zoneName = try WorkflowTimezone.anchoredTimezoneName(db)
    guard let zone = Timezone.parseTimezoneName(zoneName) else {
      throw StoreError.validation("The time zone '\(zoneName)' is not a known zone.")
    }
    guard let instant = wallTime.instant(in: zone) else {
      throw StoreError.validation(
        "The reminder time '\(raw)' does not exist in \(zoneName): the clocks skip it on that "
          + "day. Choose a time outside the skipped hour.")
    }
    return SyncTimestampFormat.formatSyncTimestamp(instant)
  }

  /// A calendar date and a time of day with no zone attached.
  struct WallTime: Equatable {
    let day: IsoDate.YMD
    let hour: Int
    let minute: Int
    let second: Int

    /// Parses `YYYY-MM-DDTHH:MM` or `YYYY-MM-DDTHH:MM:SS`; `nil` for anything
    /// else, including a value that carries an offset or a fraction.
    init?(_ raw: String) {
      let parts = raw.split(separator: "T", omittingEmptySubsequences: false)
      guard parts.count == 2, let day = IsoDate.parse(String(parts[0])) else { return nil }
      let fields = parts[1].split(separator: ":", omittingEmptySubsequences: false)
      guard fields.count == 2 || fields.count == 3 else { return nil }
      var numbers: [Int] = []
      for field in fields {
        guard field.utf8.count == 2, field.utf8.allSatisfy({ (48...57).contains($0) }),
          let number = Int(field)
        else { return nil }
        numbers.append(number)
      }
      let second = numbers.count == 3 ? numbers[2] : 0
      guard (0...23).contains(numbers[0]), (0...59).contains(numbers[1]),
        (0...59).contains(second)
      else { return nil }
      self.day = day
      self.hour = numbers[0]
      self.minute = numbers[1]
      self.second = second
    }

    /// The instant at which a clock in `zone` reads this wall time: the
    /// earlier one when the reading occurs twice, `nil` when it never occurs.
    func instant(in zone: TimeZone) -> Date? {
      var calendar = Calendar(identifier: .gregorian)
      calendar.locale = Locale(identifier: "en_US_POSIX")
      calendar.timeZone = zone
      var components = DateComponents()
      components.year = day.year
      components.month = day.month
      components.day = day.day
      components.hour = hour
      components.minute = minute
      components.second = second
      // `Calendar.date(from:)` returns the first of two repeated readings and
      // slides a skipped reading forward; only a result that reads back as the
      // requested wall time is that wall time.
      guard let candidate = calendar.date(from: components) else { return nil }
      let readBack = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: candidate)
      guard readBack.year == day.year, readBack.month == day.month, readBack.day == day.day,
        readBack.hour == hour, readBack.minute == minute, readBack.second == second
      else { return nil }
      return candidate
    }
  }
}
