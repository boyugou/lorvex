import Foundation

/// Day-granular due-date presentation shared by every task surface. Lives in
/// LorvexCore so macOS, iOS, widgets, and the accessibility helpers all format a
/// due date the same way. Foundation-localized (`RelativeDateTimeFormatter`), so
/// it needs no string-catalog keys.
///
/// Stored due, planned, and available-from dates are timezone-naive days
/// materialized at UTC midnight (`LorvexDateFormatters.ymdUTC`). Each predicate
/// reads the stored day back through ``PlannedDayBridge`` and compares it with
/// the day `now` falls on in `timeZone`, counting whole Gregorian days. Taking
/// the local `startOfDay` of the stored instant instead would shift every
/// date-only due one day early west of UTC ("today" rendering as "yesterday"
/// and instantly overdue).
extension LorvexTask {
  /// Whether the task is overdue: it is unresolved (open, started, or parked
  /// for someday) and its due day falls before today (day-granular). A
  /// completed or cancelled task is never overdue, whatever its due date, so a
  /// finished row never carries the missed-deadline warning. `false` when
  /// there is no due date.
  public func isOverdue(now: Date = Date(), timeZone: TimeZone = .current) -> Bool {
    status.isActive && isPastDue(now: now, timeZone: timeZone)
  }

  /// Whether the task is due soon: it is unresolved and its due day is today
  /// or tomorrow (day-granular). Surfaces tint such a due date orange, the
  /// same rule the task inspector's Due row follows; an overdue task is not
  /// due soon. `false` when there is no due date.
  public func isDueSoon(now: Date = Date(), timeZone: TimeZone = .current) -> Bool {
    guard status.isActive, let dueDate else { return false }
    let days = PlannedDayBridge.dayOffset(from: now, toStorageDate: dueDate, timeZone: timeZone)
    return days == 0 || days == 1
  }

  /// Whether the due day falls before today (day-granular), whatever the
  /// task's status. `false` when there is no due date.
  func isPastDue(now: Date, timeZone: TimeZone) -> Bool {
    guard let dueDate else { return false }
    return PlannedDayBridge.dayOffset(from: now, toStorageDate: dueDate, timeZone: timeZone) < 0
  }

  /// Whether the task is hidden by a future defer-until date: `available_from`
  /// is set, its day falls strictly after today (day-granular), and the task is
  /// not overdue. Overdue-wins — a missed deadline always surfaces in the day
  /// surfaces, so an overdue-but-hidden task never reads as "hidden." Matches
  /// the day-surface filter's residual conjunct, so this bool answers exactly
  /// "is this row currently suppressed from the day surfaces by `available_from`."
  public func isHiddenUntilFuture(now: Date = Date(), timeZone: TimeZone = .current) -> Bool {
    guard let availableFrom, !isPastDue(now: now, timeZone: timeZone) else { return false }
    return PlannedDayBridge.dayOffset(from: now, toStorageDate: availableFrom, timeZone: timeZone) > 0
  }

  /// A short, absolute day label for the `available_from` (defer-until) date —
  /// e.g. "Jun 14" — when the task is hidden by a future defer-until date, else
  /// `nil`. The label names the stored day itself, so it is formatted in UTC,
  /// the zone the day is anchored in.
  public func hiddenUntilShortLabel(now: Date = Date(), timeZone: TimeZone = .current) -> String? {
    guard isHiddenUntilFuture(now: now, timeZone: timeZone), let availableFrom else { return nil }
    var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
    style.timeZone = .gmt
    return availableFrom.formatted(style)
  }
}
