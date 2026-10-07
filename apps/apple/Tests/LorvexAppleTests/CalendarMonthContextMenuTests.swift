import Foundation
import Testing

// The month grid's chips and day cells carry the same right-click menus as the
// week grid's blocks: an event's Open Details, Edit and Delete, a task's shared
// task menu, and, on a day cell, Create Event for that day.

private func source(_ path: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  return try String(contentsOf: root.appending(path: path), encoding: .utf8)
}

@Test
func monthChipsCarryTheSharedEventAndTaskMenus() throws {
  let cell = try source("Sources/LorvexApple/Views/CalendarMonthGridDayCell.swift")
  #expect(cell.contains("CalendarEventContextMenu("))
  #expect(cell.contains("event: event, select: onSelectEvent, edit: onEditEvent"))
  #expect(cell.contains("requestDelete: onDeleteEvent"))
  // Both an untimed and a timed task chip open the shared task menu.
  #expect(cell.components(separatedBy: ".contextMenu { WorkspaceTaskContextMenu(store: store, task: task) }").count == 3)
}

@Test
func aMonthDayCellCreatesAnEventFromItsMenuAndItsVoiceOverActions() throws {
  let cell = try source("Sources/LorvexApple/Views/CalendarMonthGridDayCell.swift")
  #expect(cell.contains("Button(Self.createEventTitle, systemImage: \"plus\", action: onCreateEvent)"))
  #expect(cell.contains(".accessibilityAction(named: Text(Self.createEventTitle), onCreateEvent)"))
  #expect(cell.contains("\"calendar.create_event\""))

  let grid = try source("Sources/LorvexApple/Views/CalendarMonthGridView.swift")
  #expect(grid.contains("onCreateEvent: { createEvent(day.date) }"))
  #expect(grid.contains("onEditEvent: editEvent"))
  #expect(grid.contains("onDeleteEvent: requestDeleteEvent"))
}

@Test
func theWorkspaceStartsAMonthDayEventTodayAtTheNextHourAndElsewhereAtNineAM() throws {
  let workspace = try source("Sources/LorvexApple/Views/CalendarWorkspaceView.swift")
  let month = try #require(workspace.range(of: "CalendarMonthGridView("))
  let call = workspace[month.upperBound...].prefix(520)
  #expect(call.contains("editEvent: { eventActions.beginEditing($0, store: store) }"))
  #expect(call.contains("requestDeleteEvent: { eventActions.requestDelete($0) }"))
  #expect(call.contains("createEvent: { createEvent(on: $0) }"))

  let create = try #require(workspace.range(of: "private func createEvent(on day: Date)"))
  let body = workspace[create.upperBound...].prefix(380)
  #expect(body.contains("calendar.isDate(day, inSameDayAs: logicalTodayAnchor)"))
  #expect(body.contains("eventActions.beginCreating(store: store)"))
  #expect(body.contains("prepareCreateDraft(date: day, minutes: 9 * 60)"))
  #expect(body.contains("eventActions.activeSheet = .create"))
}

@Test
func theWeekGridEventBlocksShareTheEventMenuWithTheMonthGrid() throws {
  let block = try source("Sources/LorvexApple/Views/CalendarWeekGridEventBlock.swift")
  #expect(block.contains("CalendarEventContextMenu("))
  #expect(block.contains("event: block.event, select: selectEvent, edit: editEvent"))
  #expect(!block.contains("func eventBlockContextMenu"))

  let menu = try source("Sources/LorvexApple/Views/CalendarEventContextMenu.swift")
  #expect(menu.contains("if event.editable {"))
  #expect(menu.contains("\"calendar.event.open_details\""))
}
