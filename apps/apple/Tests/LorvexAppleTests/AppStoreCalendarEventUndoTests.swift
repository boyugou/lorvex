import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Dragging or resizing an event in the week grid goes through
// `AppStore.rescheduleCalendarEvent`, which registers its inverse with the
// window's undo manager.

/// Polls `condition` for up to three seconds. An undo or redo runs its writes in
/// a task of its own, so a test waits for the result rather than for a return.
@MainActor
private func waitUntil(_ condition: () async throws -> Bool) async throws -> Bool {
  for _ in 0..<60 {
    if try await condition() { return true }
    try await Task.sleep(for: .milliseconds(50))
  }
  return false
}

private let calendar = CalendarEventTiming.deviceCalendar

private func key(_ day: Date) -> String {
  LorvexDateFormatters.ymd.string(from: day)
}

private func instant(_ day: Date, hour: Int) throws -> Date {
  try #require(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day))
}

/// A store over an in-memory core holding one editable event that runs from
/// 21:00 today to midnight, the shape of an evening event the grid drags.
@MainActor
private func makeStore() async throws -> (
  store: AppStore, core: any LorvexCoreServicing, event: CalendarTimelineEvent, today: Date
) {
  let core = try await makeSeededInMemoryCore()
  let today = calendar.startOfDay(for: Date())
  let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
  let seeded = try await core.createCalendarEvent(
    title: "Late session", startDate: key(today), endDate: key(tomorrow), startTime: "21:00",
    endTime: "00:00", allDay: false, location: "Room 4", notes: nil)
  let store = AppStore(core: core)
  await store.refresh()
  let event = try #require(store.calendarTimeline?.events.first { $0.id == seeded.id })
  return (store, core, event, today)
}

@MainActor
@Test
func anEventMoveIsUndoneAndRedoneAndNamedInTheEditMenu() async throws {
  let (store, core, event, today) = try await makeStore()
  let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.rescheduleCalendarEvent(
    event, newStart: try instant(today, hour: 20), newEnd: try instant(today, hour: 23),
    undoManager: undoManager)
  undoManager.endUndoGrouping()

  let moved = try #require(await core.getCalendarEvent(id: event.id))
  #expect(moved.startTime == "20:00")
  #expect(moved.endTime == "23:00")
  #expect(moved.endDate == nil)
  #expect(undoManager.canUndo)
  #expect(undoManager.undoActionName == AppStore.moveEventTitle)

  undoManager.undo()
  #expect(
    try await waitUntil {
      let restored = try #require(await core.getCalendarEvent(id: event.id))
      return restored.startTime == "21:00" && restored.endTime == "00:00"
        && restored.endDate == key(tomorrow)
    })
  #expect(undoManager.canRedo)
  #expect(undoManager.redoActionName == AppStore.moveEventTitle)

  undoManager.redo()
  #expect(
    try await waitUntil {
      let again = try #require(await core.getCalendarEvent(id: event.id))
      return again.startTime == "20:00" && again.endTime == "23:00" && again.endDate == nil
    })
  #expect(undoManager.canUndo)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func undoingAMoveLeavesATitleEditedAfterwardsAlone() async throws {
  let (store, core, event, today) = try await makeStore()
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.rescheduleCalendarEvent(
    event, newStart: try instant(today, hour: 19), newEnd: try instant(today, hour: 20),
    undoManager: undoManager)
  undoManager.endUndoGrouping()
  _ = try await core.updateCalendarEvent(
    id: event.id, title: "Renamed session", startDate: nil, endDate: nil, startTime: nil,
    endTime: nil, allDay: nil, location: "Room 9", notes: nil)

  undoManager.undo()
  #expect(
    try await waitUntil {
      try #require(await core.getCalendarEvent(id: event.id)).startTime == "21:00"
    })
  let restored = try #require(await core.getCalendarEvent(id: event.id))
  #expect(restored.title == "Renamed session")
  #expect(restored.location == "Room 9")
}

@MainActor
@Test
func undoingAMoveOfADeletedEventDoesNothingAndReportsNoError() async throws {
  let (store, core, event, today) = try await makeStore()
  let undoManager = UndoManager()
  undoManager.groupsByEvent = false

  undoManager.beginUndoGrouping()
  await store.rescheduleCalendarEvent(
    event, newStart: try instant(today, hour: 19), newEnd: try instant(today, hour: 20),
    undoManager: undoManager)
  undoManager.endUndoGrouping()
  try await core.deleteCalendarEvent(id: event.id)

  undoManager.undo()
  #expect(undoManager.canRedo)
  try await Task.sleep(for: .milliseconds(300))
  #expect(try await core.getCalendarEvent(id: event.id) == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func aMoveWithoutAnUndoManagerRegistersNothing() async throws {
  let (store, core, event, today) = try await makeStore()
  await store.rescheduleCalendarEvent(
    event, newStart: try instant(today, hour: 19), newEnd: try instant(today, hour: 20))
  #expect(try #require(await core.getCalendarEvent(id: event.id)).startTime == "19:00")
  #expect(store.errorMessage == nil)
}
