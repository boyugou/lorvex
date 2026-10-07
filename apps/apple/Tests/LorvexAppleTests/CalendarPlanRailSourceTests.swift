import Foundation
import Testing

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test("The Calendar workspace stands the unplanned-tasks rail beside the grid")
func calendarWorkspaceHostsThePlanRail() throws {
  let workspace = try source("Sources/LorvexApple/Views/CalendarWorkspaceView.swift")
  let toolbar = try source("Sources/LorvexApple/Views/CalendarWorkspaceNavigationBar.swift")

  #expect(workspace.contains("@AppStorage(\"calendar.workspace.planRail\")"))
  #expect(workspace.contains("CalendarPlanRail(store: store"))
  // The rail loads when shown and the store stops following task changes when
  // it is hidden or the calendar leaves the screen.
  #expect(workspace.contains(".task(id: showsPlanRail)"))
  #expect(workspace.contains("store.showCalendarUnplannedTasks()"))
  #expect(workspace.contains("store.hideCalendarUnplannedTasks()"))
  #expect(workspace.contains(".onDisappear { store.hideCalendarUnplannedTasks() }"))
  #expect(toolbar.contains("Toggle(isOn: $showsPlanRail)"))
  #expect(toolbar.contains("calendar.planRail.toggle"))
  // A trailing-panel glyph, not a tray: a tray in a calendar toolbar reads as an
  // invitations inbox.
  #expect(toolbar.contains("systemImage: \"sidebar.trailing\""))
}

@Test("The rail's rows are the shared task row with its menu, and every task change reloads it")
func planRailReusesTheSharedTaskRowAndFollowsTaskChanges() throws {
  let rail = try source("Sources/LorvexApple/Views/CalendarPlanRail.swift")
  let workspaceActions = try source("Sources/LorvexApple/Stores/AppStoreTaskWorkspaceActions.swift")
  let unplanned = try source("Sources/LorvexApple/Stores/AppStoreCalendarUnplannedActions.swift")

  #expect(rail.contains("TaskRowItem(store: store, task: task)"))
  #expect(rail.contains("WorkspaceTaskContextMenu(store: store, task: task)"))
  #expect(rail.contains("ReviewCalmCopy.moreCount("))
  let reload = try #require(workspaceActions.range(of: "func reloadTaskWorkspaceIfLoaded() async {"))
  #expect(
    workspaceActions[reload.upperBound...].prefix(120)
      .contains("reloadCalendarUnplannedTasksIfShown()"))
  #expect(unplanned.contains("plannedPresence: \"absent\""))
  #expect(unplanned.contains("availability: \"visible\""))
}

@Test("A month cell drags its open tasks and takes dropped tasks for its day")
func monthGridCellsDragAndAcceptTasks() throws {
  let cell = try source("Sources/LorvexApple/Views/CalendarMonthGridDayCell.swift")
  let month = try source("Sources/LorvexApple/Views/CalendarMonthGridView.swift")

  #expect(cell.contains(".dropDestination(for: LorvexTaskRef.self)"))
  #expect(cell.contains("openingAndDraggable(task, open: onOpenTask)"))
  #expect(cell.contains("if task.status.isActionable"))
  // A task dropped on a month cell keeps its time of day: the cell cannot say
  // which time on the day it meant.
  #expect(month.contains("time: .unchanged"))
}

@Test("The shared task menu offers Plan Task with day choices, for pointers that cannot drag")
func taskContextMenuOffersPlanTaskDayChoices() throws {
  let menu = try source("Sources/LorvexApple/Views/WorkspaceTaskViews.swift")

  #expect(menu.contains("Label(AppStore.planTaskTitle, systemImage: \"calendar.badge.plus\")"))
  #expect(menu.contains("ForEach(TaskPlanDayChoice.allCases)"))
  #expect(menu.contains("ids: [task.id], daysFromToday: choice.daysFromToday, undoManager: undoManager"))
  // A finished or cancelled task cannot be planned.
  let plan = try #require(menu.range(of: "AppStore.planTaskTitle"))
  #expect(menu[plan.upperBound...].prefix(160).contains(".disabled(!task.status.isActionable)"))
}
