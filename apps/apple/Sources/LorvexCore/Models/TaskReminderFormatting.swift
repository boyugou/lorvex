import Foundation

public extension TaskReminder {
  /// Localized date-time in the supplied product timezone. Task reminders are
  /// absolute instants, but their wall-clock intent belongs to Lorvex's synced
  /// timezone rather than the timezone of whichever device renders the row.
  func displaySummary(timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
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
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    guard let date = date(from: reminderAt) else { return reminderAt }
    return displayString(from: date, timeZone: timeZone, locale: locale)
  }

  public static func displayString(
    from date: Date,
    timeZone: TimeZone,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    var style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale)
    style.calendar = Calendar(identifier: .gregorian)
    style.timeZone = timeZone
    return style.format(date)
  }

  public static func displayTimeString(
    from date: Date,
    timeZone: TimeZone,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
    style.calendar = Calendar(identifier: .gregorian)
    style.timeZone = timeZone
    return style.format(date)
  }

  public static func calendar(timeZone: TimeZone) -> Calendar {
    LorvexDateFormatters.gregorianCalendar(timeZone: timeZone)
  }

  private static func date(from string: String) -> Date? {
    if let date = LorvexDateFormatters.iso8601Fractional.date(from: string) {
      return date
    }
    return LorvexDateFormatters.iso8601.date(from: string)
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
