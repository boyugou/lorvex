import Foundation

/// The task every glance leads with, when one deserves to lead.
///
/// A glance (a widget, the menu bar, the watch, CarPlay, Control Center) puts
/// one task above the rest only when the day itself says it is the one that
/// matters right now:
///
/// 1. **Running:** a task whose saved time today contains the clock. When
///    several do, the earliest-starting one leads, and list order breaks a tie.
/// 2. **Started:** otherwise, the first task in Today's order that the user
///    marked started.
/// 3. **Next:** otherwise, the task whose saved time starts soonest after the
///    clock.
///
/// Otherwise nothing leads, and a glance shows Today's list as it is: the top
/// of the list is where the plan starts, not a task to do now. A day that is
/// not today (no clock) leads only with a started task. Widgets, the menu bar,
/// the watch, and CarPlay all apply this rule to the same list, so they name
/// the same task.
public enum TodayLead {
  /// Why a task leads.
  public enum Kind: Equatable, Sendable {
    /// Its saved time contains the clock.
    case running
    /// The user marked it started.
    case started
    /// Its saved time is the next to start today.
    case next
  }

  /// The lead's index in `tasks` (Today's order) and why it leads, or nil when
  /// no task leads. `time` gives a task's saved time today as minutes since
  /// midnight; `isStarted` says whether the user marked it started.
  public static func lead<Item>(
    in tasks: [Item], nowMinutes: Int?, time: (Item) -> Range<Int>?,
    isStarted: (Item) -> Bool
  ) -> (index: Int, kind: Kind)? {
    if let nowMinutes {
      var running: (index: Int, start: Int)?
      for (index, task) in tasks.enumerated() {
        guard let range = time(task), range.contains(nowMinutes) else { continue }
        if running.map({ range.lowerBound < $0.start }) ?? true {
          running = (index, range.lowerBound)
        }
      }
      if let running { return (running.index, .running) }
    }
    if let started = tasks.firstIndex(where: isStarted) {
      return (started, .started)
    }
    guard let nowMinutes else { return nil }
    var next: (index: Int, start: Int)?
    for (index, task) in tasks.enumerated() {
      guard let range = time(task), range.lowerBound > nowMinutes else { continue }
      if next.map({ range.lowerBound < $0.start }) ?? true {
        next = (index, range.lowerBound)
      }
    }
    return next.map { ($0.index, .next) }
  }

  /// `tasks` with the lead first, when one leads; the others keep Today's
  /// order.
  public static func ordered<Item>(
    _ tasks: [Item], nowMinutes: Int?, time: (Item) -> Range<Int>?,
    isStarted: (Item) -> Bool
  ) -> [Item] {
    guard
      let index = lead(in: tasks, nowMinutes: nowMinutes, time: time, isStarted: isStarted)?
        .index,
      index > 0
    else { return tasks }
    var result = tasks
    result.insert(result.remove(at: index), at: 0)
    return result
  }
}
