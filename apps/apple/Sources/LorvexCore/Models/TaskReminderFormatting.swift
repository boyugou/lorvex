import Foundation

public extension TaskReminder {
  /// Localized date-time in the supplied product timezone. Task reminders are
  /// absolute instants, but their wall-clock intent belongs to Lorvex's synced
  /// timezone rather than the timezone of whichever device renders the row.
  func displaySummary(timeZone: TimeZone, locale: Locale = LorvexClockFormat.displayLocale) -> String {
    TaskReminderDateTime.displayString(
      reminderAt: reminderAt,
      timeZone: timeZone,
      locale: locale)
  }

  /// Device-local compatibility display for callers without a loaded product
  /// session. Production app surfaces should call ``displaySummary(timeZone:locale:)``.
  var displaySummary: String {
    displaySummary(timeZone: .autoupdatingCurrent)
  }

  /// The reminder's day and clock time in `timeZone`, the product zone
  /// reminders are composed in, the way a task's rows name a day: the day as
  /// a sentence opens with it, relative to `logicalDay` (``LorvexDayPhrase``:
  /// "Tomorrow", "Thursday", "Oct 12", "Jan 4, 2027"), and the time ("9:30
  /// AM"). Each surface joins the two with its catalog's day-and-time format
  /// ("Tomorrow, 9:30 AM"). Nil when `reminderAt` is not a time.
  ///
  /// The phrase is relative to today, so text that outlives the screen (a
  /// spoken or shared reminder) uses ``displaySummary(timeZone:locale:)``.
  func dayAndTime(logicalDay: String, timeZone: TimeZone) -> (day: String, time: String)? {
    guard let instant = TaskReminderDateTime.instant(from: reminderAt) else { return nil }
    let day = LorvexDayPhrase.phrase(
      for: PlannedDayBridge.storageDate(forLocalInstant: instant, timeZone: timeZone),
      logicalDay: logicalDay, position: .leading)
    return (day, TaskReminderDateTime.displayTimeString(from: instant, timeZone: timeZone))
  }
}

/// Shared wall-clock and display policy for task-reminder UI on every Apple
/// surface. Day-based presets use a Gregorian calendar in the configured
/// product timezone; duration-based presets remain absolute elapsed time.
public enum TaskReminderDateTime {
  public enum Preset: Sendable {
    case inOneHour
    case thisEvening
    case tomorrowMorning
  }

  /// Tomorrow at 09:00 in `timeZone`, using calendar arithmetic so a DST
  /// transition produces the intended wall time rather than a fixed 24-hour
  /// offset. The one-hour fallback is only for an impossible calendar failure.
  public static func defaultDate(now: Date = Date(), timeZone: TimeZone) -> Date {
    presetDate(.tomorrowMorning, now: now, timeZone: timeZone)
      ?? now.addingTimeInterval(3600)
  }

  /// Resolves a quick preset. `inOneHour` is deliberately an absolute duration;
  /// the other presets are civil wall times owned by the product timezone.
  public static func presetDate(
    _ preset: Preset,
    now: Date = Date(),
    timeZone: TimeZone
  ) -> Date? {
    switch preset {
    case .inOneHour:
      return now.addingTimeInterval(3600)
    case .thisEvening:
      guard let evening = date(
        onDayContaining: now,
        addingDays: 0,
        hour: 18,
        timeZone: timeZone)
      else { return nil }
      return evening > now ? evening : nil
    case .tomorrowMorning:
      return date(
        onDayContaining: now,
        addingDays: 1,
        hour: 9,
        timeZone: timeZone)
    }
  }

  public static func displayString(
    reminderAt: String,
    timeZone: TimeZone,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    guard let date = instant(from: reminderAt) else { return reminderAt }
    return displayString(from: date, timeZone: timeZone, locale: locale)
  }

  public static func displayString(
    from date: Date,
    timeZone: TimeZone,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    LorvexDateFormatters.dayAndClockTime(date, timeZone: timeZone, locale: locale)
  }

  public static func displayTimeString(
    from date: Date,
    timeZone: TimeZone,
    locale: Locale = LorvexClockFormat.displayLocale
  ) -> String {
    LorvexDateFormatters.clockTime(date, timeZone: timeZone, locale: locale)
  }

  public static func calendar(timeZone: TimeZone) -> Calendar {
    LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
  }

  /// The instant a stored `reminder_at` names (ISO 8601, with or without
  /// fractional seconds), or nil when the string is not one.
  public static func instant(from reminderAt: String) -> Date? {
    if let date = LorvexDateFormatters.iso8601Fractional.date(from: reminderAt) {
      return date
    }
    return LorvexDateFormatters.iso8601.date(from: reminderAt)
  }

  private static func date(
    onDayContaining anchor: Date,
    addingDays dayOffset: Int,
    hour: Int,
    timeZone: TimeZone
  ) -> Date? {
    let calendar = calendar(timeZone: timeZone)
    guard let day = calendar.date(byAdding: .day, value: dayOffset, to: anchor) else {
      return nil
    }
    return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
  }
}
