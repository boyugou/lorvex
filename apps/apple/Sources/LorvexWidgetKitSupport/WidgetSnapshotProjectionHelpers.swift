import Foundation
import LorvexCore

extension WidgetSnapshotProjector {
  /// Returns the subset of `tasks` that should be projected given the current focus filter.
  ///
  /// When the filter is active and `showNonFocusTasks` is false, only tasks whose IDs
  /// appear in `currentFocus.taskIDs` are kept. If there is no current focus plan the
  /// task list is returned unchanged regardless of the filter state.
  func focusFilteredTasks(
    from tasks: [LorvexTask],
    currentFocus: CurrentFocusPlan?,
    focusFilter: FocusFilterConfiguration
  ) -> [LorvexTask] {
    guard focusFilter.isActive, !focusFilter.showNonFocusTasks,
          let focusTaskIDs = currentFocus?.taskIDs, !focusTaskIDs.isEmpty
    else {
      return tasks
    }
    let allowedIDs = Set(focusTaskIDs)
    return tasks.filter { allowedIDs.contains($0.id) }
  }

  func focusOrderedTasks(
    from tasks: [LorvexTask],
    currentFocus: CurrentFocusPlan?,
    expandBeyondFocus: Bool = false
  ) -> [LorvexTask] {
    guard let currentFocus, !currentFocus.taskIDs.isEmpty else {
      return tasks
    }
    let tasksByID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let focused = currentFocus.taskIDs.compactMap { tasksByID[$0] }
    if expandBeyondFocus {
      let focusedIDs = Set(currentFocus.taskIDs)
      let others = tasks.filter { !focusedIDs.contains($0.id) }
      return focused + others
    }
    return focused.isEmpty ? tasks : focused
  }

  static func dateOnlyString(from date: Date) -> String {
    LorvexDateFormatters.ymdUTC.string(from: date)
  }

  /// `YYYY-MM-DD` for `date` in `calendar`'s time zone — the user's perceived
  /// wall-calendar day. Used to derive "today" for the due-today/overdue stats,
  /// versus `dateOnlyString` which reads a stored due date's canonical day in
  /// UTC.
  static func localDateOnlyString(from date: Date, calendar: Calendar) -> String {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let components = gregorian.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  static func timestampString(from date: Date) -> String {
    LorvexDateFormatters.iso8601.string(from: date)
  }
}
