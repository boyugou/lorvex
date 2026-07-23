import Foundation

/// Cross-scheduler budgeting for the OS pending-notification cap.
///
/// iOS/macOS keep at most 64 pending notification requests per app and silently
/// drop the rest. Task reminders and habit reminders are armed by two separate
/// schedulers, so without a shared budget their combined total can exceed the cap
/// and the OS drops an arbitrary excess — potentially near-term reminders in
/// favor of far-future ones, invisibly. This budgeter keeps the earliest-firing
/// requests across BOTH kinds, up to a single shared limit, and reports how many
/// were dropped so the truncation can be surfaced instead of lost.
public enum ReminderBudget {
  /// Shared ceiling on pending reminder notifications across the task + habit
  /// schedulers. Held below the OS hard cap of 64 to leave headroom for one-shot
  /// snooze notifications and other transient requests the app may add.
  public static let pendingNotificationLimit = 60

  /// Keep the earliest-`limit` items by fire date, returning the kept items
  /// (earliest first) and how many were dropped. Stable: items with equal fire
  /// dates retain their input order, so selection is deterministic.
  public static func selectEarliest<T>(
    _ items: [T], limit: Int = pendingNotificationLimit, fireDate: (T) -> Date
  ) -> (kept: [T], truncated: Int) {
    guard limit >= 0 else { return ([], items.count) }
    guard items.count > limit else { return (items, 0) }
    let ordered = items.enumerated().sorted { lhs, rhs in
      let l = fireDate(lhs.element)
      let r = fireDate(rhs.element)
      if l == r { return lhs.offset < rhs.offset }
      return l < r
    }
    let kept = ordered.prefix(limit).map(\.element)
    return (kept, items.count - limit)
  }

  /// Budget task-reminder candidates and habit occurrences together against the
  /// shared `limit`, keeping the earliest-firing requests across both kinds.
  /// Returns the kept task candidates, the kept habit occurrences (each in
  /// earliest-first order within its kind), and the total number dropped.
  public static func budget(
    taskCandidates: [ScheduledTaskReminder],
    habitOccurrences: [DueHabitReminderOccurrence],
    limit: Int = pendingNotificationLimit
  ) -> (tasks: [ScheduledTaskReminder], habits: [DueHabitReminderOccurrence], truncated: Int) {
    enum Item {
      case task(ScheduledTaskReminder)
      case habit(DueHabitReminderOccurrence)
      var fireDate: Date {
        switch self {
        case .task(let reminder): return reminder.fireDate
        case .habit(let occurrence): return occurrence.fireDate
        }
      }
    }
    let combined = taskCandidates.map(Item.task) + habitOccurrences.map(Item.habit)
    let (kept, truncated) = selectEarliest(combined, limit: limit, fireDate: \.fireDate)
    var tasks: [ScheduledTaskReminder] = []
    var habits: [DueHabitReminderOccurrence] = []
    for item in kept {
      switch item {
      case .task(let reminder): tasks.append(reminder)
      case .habit(let occurrence): habits.append(occurrence)
      }
    }
    return (tasks, habits, truncated)
  }
}
