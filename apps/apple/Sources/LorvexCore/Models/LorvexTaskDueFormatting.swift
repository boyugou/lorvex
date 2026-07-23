import Foundation

/// Day-granular due-date presentation shared by every task surface. Lives in
/// LorvexCore so macOS, iOS, widgets, and the accessibility helpers all format a
/// due date the same way. Foundation-localized (`RelativeDateTimeFormatter`), so
/// it needs no string-catalog keys.
extension LorvexTask {
  /// The stored planned date is a timezone-naive calendar day materialized at
  /// UTC midnight (`LorvexDateFormatters.ymdUTC`), so the day it names must be
  /// read back in UTC. Taking the user-calendar `startOfDay` of that instant
  /// instead would shift every date-only due one day early for any timezone
  /// west of UTC ("today" rendering as "yesterday" and instantly overdue).
  static let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }()

  /// The due date's calendar day, re-anchored to midnight in `calendar` so it
  /// compares against the user's local "today" on equal footing. Shared by the
  /// due-relative label and the overdue/hidden-until predicates.
  func dueDayStart(of dueDate: Date, in calendar: Calendar) -> Date {
    let day = Self.utcCalendar.dateComponents([.year, .month, .day], from: dueDate)
    return calendar.date(from: day) ?? dueDate
  }

  /// Whether the task is past due — its due day falls before today
  /// (day-granular). `false` when there is no due date.
  public func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard let dueDate else { return false }
    return dueDayStart(of: dueDate, in: calendar) < calendar.startOfDay(for: now)
  }

  /// Whether the task is hidden by a future defer-until date: `available_from`
  /// is set, its day falls strictly after today (day-granular), and the task is
  /// not overdue. Overdue-wins — a missed deadline always surfaces in the day
  /// surfaces, so an overdue-but-hidden task never reads as "hidden." Matches
  /// the day-surface filter's residual conjunct, so this bool answers exactly
  /// "is this row currently suppressed from the day surfaces by `available_from`."
  public func isHiddenUntilFuture(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard let availableFrom, !isOverdue(now: now, calendar: calendar) else { return false }
    return dueDayStart(of: availableFrom, in: calendar) > calendar.startOfDay(for: now)
  }

  /// A short, absolute day label for the `available_from` (defer-until) date —
  /// e.g. "Jun 14" — when the task is hidden by a future defer-until date, else
  /// `nil`. The stored date is a UTC-midnight day anchor, so it is re-anchored
  /// to the local day before formatting (mirroring `dueDayStart`).
  public func hiddenUntilShortLabel(now: Date = Date(), calendar: Calendar = .current) -> String? {
    guard isHiddenUntilFuture(now: now, calendar: calendar), let availableFrom else { return nil }
    return dueDayStart(of: availableFrom, in: calendar)
      .formatted(date: .abbreviated, time: .omitted)
  }
}
