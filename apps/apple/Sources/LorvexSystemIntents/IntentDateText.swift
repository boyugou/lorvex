import Foundation
import LorvexCore

/// The `yyyy-MM-dd` day, `HH:mm` time, and ISO-8601 timestamp texts the intent
/// runners take, read from the values of an intent's date and time parameters.
///
/// Siri and Shortcuts hand a date parameter an instant on the day the person
/// picked or said, and a time parameter an instant at the clock time they
/// chose, both meant in the device's time zone. Reading the day and the time
/// in that zone keeps what the person chose: the date the picker showed is the
/// day Lorvex stores, and 9:00 stays 9:00. A date-and-time parameter names one
/// moment, such as when a reminder fires, so it travels as a UTC timestamp.
enum IntentDateText {
  /// The calendar day `date` falls on in the device's time zone.
  static func day(_ date: Date) -> String {
    LorvexDateFormatters.ymd.string(from: date)
  }

  /// The hour and minute of `date` in the device's time zone.
  static func time(_ date: Date) -> String {
    LorvexDateFormatters.hourMinute.string(from: date)
  }

  /// The moment `date` names, as the canonical UTC timestamp.
  static func timestamp(_ date: Date) -> String {
    LorvexDateFormatters.iso8601.string(from: date)
  }

  /// The days of `from` and `to` in calendar order, so a range picked
  /// backwards still covers the days between its two dates.
  static func dayRange(from: Date, to: Date) -> (from: String, to: String) {
    to < from ? (day(to), day(from)) : (day(from), day(to))
  }

  /// The days of an open-ended range: an absent bound stays absent, and two
  /// bounds come back in calendar order.
  static func dayRange(from: Date?, to: Date?) -> (from: String?, to: String?) {
    guard let from, let to else { return (from.map(day), to.map(day)) }
    let range = dayRange(from: from, to: to)
    return (range.from, range.to)
  }
}
