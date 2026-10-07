import Foundation
import LorvexCore

extension AppStore {
  /// The most tasks the Calendar's "Unplanned Tasks" rail lists; the rest are counted in
  /// ``calendarUnplannedTotal`` and found in the Tasks workspace.
  static let calendarUnplannedLimit = 40

  /// The rail appears: loads its tasks, and keeps them current with every task
  /// change until ``hideCalendarUnplannedTasks()``.
  func showCalendarUnplannedTasks() async {
    calendarStorage.calendarUnplannedRailIsShown = true
    await loadCalendarUnplannedTasks()
  }

  /// The rail goes away: forgets its tasks, so task changes stop reloading them.
  func hideCalendarUnplannedTasks() {
    calendarStorage.calendarUnplannedRailIsShown = false
    calendarStorage.calendarUnplannedTasks = nil
    calendarStorage.calendarUnplannedTotal = 0
  }

  /// Refreshes the rail's tasks while the rail is shown.
  func reloadCalendarUnplannedTasksIfShown() async {
    guard calendarStorage.calendarUnplannedRailIsShown else { return }
    await loadCalendarUnplannedTasks()
  }

  /// Loads the rail's tasks: open tasks with no planned day that are available
  /// now (a task deferred to a later day is not yet something to plan), in the
  /// canonical order (priority, then due date). A failed read keeps what is
  /// shown, as the other quiet reloads do, and a rail hidden while the read ran
  /// stays empty.
  private func loadCalendarUnplannedTasks() async {
    let query = TaskListQueryRequest(
      status: "open", availability: "visible", plannedPresence: "absent",
      limit: Self.calendarUnplannedLimit)
    guard let page = try? await core.listTasks(query: query),
      calendarStorage.calendarUnplannedRailIsShown
    else { return }
    calendarStorage.calendarUnplannedTasks = page.tasks
    calendarStorage.calendarUnplannedTotal = page.totalMatching
  }
}
