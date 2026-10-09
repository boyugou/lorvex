import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// The phone's day grid draws each task with a time at that time. These tests
/// cover how the mobile store gathers those tasks: the loaded calendar window
/// reads the window's scheduled tasks, and completing a task from its block
/// updates the block in place.

@MainActor
@Test
func mobileCalendarWindowLoadsTheTimedTasksInsideIt() async throws {
  let core = try await makeSeededInMemoryCore()
  let inside = try await core.createTask(title: "Draft the launch note", notes: "")
  let outside = try await core.createTask(title: "Plan the offsite", notes: "")
  try await planTask(core, inside.id, on: "2026-05-25", time: 540..<630)
  try await planTask(core, outside.id, on: "2026-06-20", time: 840..<900)
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refreshCalendarTimeline(from: "2026-05-23", to: "2026-06-06")

  let loaded = try #require(store.calendarScheduledTasks.first { $0.id == inside.id })
  #expect(loaded.title == "Draft the launch note")
  #expect(loaded.plannedTime == 540..<630)
  // June 20 lies past the loaded window, so it is not read.
  #expect(!store.calendarScheduledTasks.contains { $0.id == outside.id })
}

@MainActor
@Test
func togglingATimedTaskFromTheGridMarksItsBlockDoneInPlace() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Send the weekly status update", notes: "")
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let today = store.logicalTodayString
  try await planTask(core, task.id, on: today, time: 585..<645)
  await store.refresh()
  await store.refreshCalendarTimeline(from: today, to: today)
  let block = try #require(store.calendarScheduledTasks.first { $0.id == task.id })
  #expect(block.status == .open)

  #expect(await store.toggleTaskCompletion(block))
  // The completed task leaves the day snapshot; the block keeps it, drawn
  // done at its time, through the copy the window loaded — updated without a
  // reload.
  #expect(store.snapshot.today.tasks.contains { $0.id == task.id } == false)
  let done = try #require(store.calendarScheduledTasks.first { $0.id == task.id })
  #expect(done.status == .completed)
  #expect(done.plannedTime == 585..<645)

  #expect(await store.toggleTaskCompletion(done))
  // Undoing the completion puts the task back where it was: on Today, at its
  // time on the grid.
  let reopened = try #require(store.calendarScheduledTasks.first { $0.id == task.id })
  #expect(reopened.status == .open)
  #expect(reopened.plannedTime == 585..<645)
  #expect(store.snapshot.today.tasks.contains { $0.id == task.id })
}

@Test
func mobileDayGridWiresTimedTasksThroughToTheGridModel() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let column = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayColumn.swift"),
    encoding: .utf8)
  let dayView = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarDayView.swift"),
    encoding: .utf8)
  let block = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileCalendarTaskBlock.swift"),
    encoding: .utf8)

  #expect(column.contains("tasks: tasks,"))
  #expect(column.contains("ForEach(day.taskBlocks)"))
  // The pager reads the window's tasks once and hands them to every page's
  // column.
  #expect(dayView.contains("let tasks = store.calendarScheduledTasks"))
  #expect(dayView.contains("tasks: tasks,"))
  #expect(block.contains(".accessibilityIdentifier(\"mobileCalendar.taskBlock\")"))
  // Task blocks open the task and complete it; they are never drag targets.
  #expect(!block.contains("rescheduleLift"))
  #expect(!block.contains("lorvexEventLift"))
}
