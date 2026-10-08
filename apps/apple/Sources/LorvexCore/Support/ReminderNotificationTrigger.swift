import Foundation
import UserNotifications

extension UNCalendarNotificationTrigger {
  /// A one-shot trigger that fires at exactly `date`, in whatever time zone and
  /// calendar the device is using when that moment comes.
  ///
  /// The date is written as Gregorian components in UTC, and the components
  /// carry that calendar and zone. Components that name no zone are read again
  /// in the zone the device is in when the trigger fires: a reminder armed for
  /// 09:00 in Los Angeles would then fire at 09:00 in New York, three hours
  /// before its instant, when the device flew there and the app did not run in
  /// between to re-plan its reminders. Whole seconds are kept; a fraction of a
  /// second in `date` is dropped.
  static func oneShot(at date: Date) -> UNCalendarNotificationTrigger {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    var components = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: date)
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
  }
}
