import Foundation
import LorvexCore
import LorvexDomain
import Testing

@testable import LorvexApple

/// The Plan week draws each timed task at its time. These tests cover how the
/// store keeps those tasks: the loaded timeline window reads its tasks beside
/// its events, a change to today's times reaches the grid without a
/// navigation, and completing a block acts on the task by id.

@MainActor
@Test
func refreshCalendarTimelineLoadsTheWindowsTimedTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let inWindow = try await core.createTask(title: "Draft the launch note", notes: "")
  let pastWindow = try await core.createTask(title: "Review the launch note", notes: "")
  try await planTask(core, inWindow.id, on: "2026-02-03", time: 9 * 60..<10 * 60 + 30)
  try await planTask(core, pastWindow.id, on: "2026-02-20", time: 14 * 60..<15 * 60)
  let store = AppStore(core: core)
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian)
  comps.timeZone = .current
  comps.year = 2026
  comps.month = 2
  comps.day = 1
  let anchor = try #require(comps.date)

  try await store.refreshCalendarTimeline(anchorDate: anchor)

  let tasks = try #require(store.calendarScheduledTasks)
  let loaded = try #require(tasks.first { $0.id == inWindow.id })
  #expect(loaded.title == "Draft the launch note")
  #expect(loaded.time(on: "2026-02-03") == 9 * 60..<10 * 60 + 30)
  // Feb 20 lies past the fourteen-day window, so it is not loaded.
  #expect(!tasks.contains { $0.id == pastWindow.id })
}

@MainActor
@Test
func clearingTodaysTimesReachesTheGridWithoutANavigation() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Review the sync design", notes: "")
  let store = AppStore(core: core)
  await store.refresh()
  let today = store.logicalTodayDateString
  try await planTask(core, task.id, on: today, time: 9 * 60 + 45..<10 * 60 + 45)
  await store.refresh()
  await store.loadTodaySchedule()
  #expect(
    store.calendarScheduledTasks?.first { $0.id == task.id }?.time(on: today)
      == 9 * 60 + 45..<10 * 60 + 45)

  await store.clearDayTimes(undoManager: nil)

  let cleared = try #require(store.calendarScheduledTasks?.first { $0.id == task.id })
  #expect(cleared.time(on: today) == nil, "the block leaves the grid")
  #expect(
    cleared.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == today,
    "the task stays on today")
  #expect(store.today.tasks.contains { $0.id == task.id })
}

@MainActor
@Test
func taskDetailDoOnSummaryReadsTheDayThenTheTime() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Write the brief", notes: "")
  let store = AppStore(core: core)
  await store.refresh()
  let today = store.logicalTodayDateString
  try await planTask(core, task.id, on: today, time: 9 * 60 + 45..<10 * 60 + 45)
  await store.refresh()

  store.selectTaskFromList(task.id)

  let day = LorvexDayPhrase.phrase(
    for: store.taskDetailPlannedDatePickerDate, logicalDay: today, position: .leading)
  let range = lorvexClockRangeLabel(startMinutes: 9 * 60 + 45, endMinutes: 10 * 60 + 45)
  // The time stays whole, so a value too wide for the inspector wraps after the day.
  #expect(store.taskDetailDoOnSummary == "\(day), \(lorvexWholeSpan(range))")

  // Without a time the summary is the day alone.
  _ = try await core.updateTask(TaskUpdateDraft(id: task.id, plannedTime: .clear))
  await store.refresh()
  store.selectedTaskID = nil
  store.selectTaskFromList(task.id)
  #expect(store.taskDetailDoOnSummary == day)
}

@MainActor
@Test
func toggleCalendarTaskCompletionCompletesByIDAndMarksTheBlockDone() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Send the weekly status update", notes: "")
  let store = AppStore(core: core)
  await store.refresh()
  let today = store.logicalTodayDateString
  try await planTask(core, task.id, on: today, time: 10 * 60 + 55..<11 * 60 + 55)
  await store.refresh()
  await store.loadTodaySchedule()
  #expect(store.calendarScheduledTasks?.first { $0.id == task.id }?.status == .open)

  await store.toggleCalendarTaskCompletion(id: task.id)

  #expect(try await core.loadTask(id: task.id).status == .completed)
  #expect(store.calendarScheduledTasks?.first { $0.id == task.id }?.status == .completed)
  #expect(store.selectedTaskID != task.id)

  await store.toggleCalendarTaskCompletion(id: task.id)
  #expect(try await core.loadTask(id: task.id).status == .open)
}
