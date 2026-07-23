import Foundation
import LorvexCore

extension AppStore {
  /// Product calendar day materialized by the core. Every synced day-scoped
  /// write uses this value; the device-local formatter is only a cold-preview
  /// fallback before the first database snapshot lands.
  var logicalTodayDateString: String {
    today.logicalDay ?? Self.todayDateString()
  }

  /// IANA zone that owns ``logicalTodayDateString``. Focus rows record this
  /// product zone rather than whichever zone this Mac happens to be in.
  var logicalTimezoneName: String {
    today.timezone ?? TimeZone.current.identifier
  }

  /// Resolved timezone for wall-clock UI such as task-reminder composition.
  /// A loaded Today snapshot has already validated its IANA identifier; the
  /// fallback exists only during the cold state before that snapshot lands.
  var logicalTimeZone: TimeZone {
    guard let name = today.timezone, let timeZone = TimeZone(identifier: name) else {
      return .autoupdatingCurrent
    }
    return timeZone
  }

  /// The product's logical tomorrow as a storage-frame date. The configured
  /// synced timezone owns the semantic day even when this Mac is in another
  /// zone; deriving from `Calendar.current` would fork the planned-date value.
  func tomorrowDate() throws -> Date {
    try storageDate(daysFromLogicalToday: 1)
  }

  /// A storage-frame day `days` from the product logical day, for the defer
  /// presets (tomorrow, in N days, next week).
  func deferStorageDate(daysFromNow days: Int) -> Date? {
    try? storageDate(daysFromLogicalToday: days)
  }

  func storageDate(daysFromLogicalToday days: Int) throws -> Date {
    guard
      let date = PlannedDayBridge.storageDate(
        forLogicalDay: logicalTodayDateString,
        addingDays: days)
    else {
      throw LorvexCoreError.unsupportedOperation(
        "Couldn't compute a date from the configured logical day.")
    }
    return date
  }

  nonisolated static func todayDateString() -> String {
    dateString(daysFromToday: 0)
  }

  nonisolated static func dateString(daysFromToday days: Int) -> String {
    // Calendar day arithmetic, not fixed 86400-second steps, so a DST-shift day
    // doesn't land the result on the wrong wall-clock date.
    dateString(days: days, from: Date())
  }

  nonisolated static func dateString(days: Int, from anchor: Date) -> String {
    let date = Calendar.current.date(byAdding: .day, value: days, to: anchor) ?? anchor
    return ymdFormatter.string(from: date)
  }

  nonisolated static var ymdFormatter: DateFormatter { LorvexDateFormatters.ymd }

  nonisolated static var hmFormatter: DateFormatter { LorvexDateFormatters.hourMinute }

  nonisolated static var isoDateTimeFormatter: ISO8601DateFormatter { LorvexDateFormatters.iso8601 }
}
