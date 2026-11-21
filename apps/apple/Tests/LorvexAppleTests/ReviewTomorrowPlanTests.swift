import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@MainActor
@Test("Tomorrow accounts for overlapping events, timed work, and the chosen unfinished tasks")
func forecastAndMoveReviewSelection() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let store = AppStore(core: core)
  await store.refresh()
  let today = store.logicalTodayDateString
  let tomorrow = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: 1))
  let from = try #require(PlannedDayBridge.storageDate(forLogicalDay: today))
  let to = try #require(PlannedDayBridge.storageDate(forLogicalDay: tomorrow))
  let carry = try await core.createTask(.init(title: "Carry", estimatedMinutes: 45, plannedDate: from))
  let leave = try await core.createTask(.init(title: "Leave", plannedDate: from))
  let existing = try await core.createTask(.init(title: "Scheduled", plannedDate: to, plannedTime: 720..<750))
  let unknown = try await core.createTask(.init(title: "Estimate later", plannedDate: to))
  for (start, end) in [("08:30", "10:00"), ("09:30", "10:30")] {
    _ = try await core.importCalendarEvent(id: UUID().uuidString.lowercased(), title: "Meeting",
      startDate: tomorrow, startTime: start, endDate: tomorrow, endTime: end,
      allDay: false, location: nil, notes: nil, url: nil, color: nil, eventType: "event", personName: nil,
      attendees: nil, timezone: nil, recurrence: nil, seriesId: nil, recurrenceInstanceDate: nil)
  }
  store.navigateToWorkspace(.reviews)
  await store.refresh()
  let agenda = try #require(await store.loadTomorrowAgenda())
  let summary = try await core.loadDaySummary(date: today)
  let chosen = summary.unfinishedTasks.filter { $0.id == carry.id }
  #expect(await store.saveWorkingHoursPreference(start: "09:00", end: "11:00"))
  let window = try #require(store.workdayWindow)
  #expect(window == 540..<660)
  let all = ReviewTomorrowLoad(agenda: agenda, window: window, selected: summary.unfinishedTasks)
  #expect(all.meetingMinutes == 90)
  #expect(all.existingMinutes == 30)
  #expect(all.selectedMinutes == 45)
  #expect(all.unknownCount == 2)
  #expect(all.plannedMinutes - window.count == 45)
  let partial = ReviewTomorrowLoad(agenda: agenda, window: window, selected: chosen)
  #expect(partial.unknownCount == 1)
  let quiet = ReviewTomorrowLoad(agenda: .init(key: tomorrow, events: [], tasks: []), window: window, selected: chosen)
  #expect(window.count - quiet.plannedMinutes == 75)

  let undo = UndoManager()
  undo.groupsByEvent = false
  undo.beginUndoGrouping()
  await store.arrangeReviewTasks(chosen, reviewedOn: today, destination: .day(tomorrow), undoManager: undo)
  undo.endUndoGrouping()
  let moved = try #require(await store.loadTomorrowAgenda())
  #expect(Set(moved.tasks.map(\.id)) == Set([existing.id, unknown.id, carry.id]))
  #expect(try await core.loadTask(id: leave.id).plannedDate == from)
  undo.undo()
  for _ in 0..<150 {
    if try await core.loadTask(id: carry.id).plannedDate == from { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  #expect(try await core.loadTask(id: carry.id).plannedDate == from)
  #expect(Set(try #require(await store.loadTomorrowAgenda()).tasks.map(\.id)) == Set([existing.id, unknown.id]))
}

@Test("A single-day forecast includes actionable work beyond the first fifty calendar rows")
func tomorrowReadsEveryPlannedTask() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let date = try #require(PlannedDayBridge.storageDate(forLogicalDay: "2026-10-13"))
  for index in 0..<54 {
    _ = try await core.createTask(.init(title: "Task \(index)", estimatedMinutes: 5, plannedDate: date))
  }
  let agenda = try await LorvexAgendaDay.loadDay(after: "2026-10-12", from: core)
  #expect(agenda.tasks.count == 54)
  #expect(agenda.tasks.compactMap(\.estimatedMinutes).reduce(0, +) == 270)
}
