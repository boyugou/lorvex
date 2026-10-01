import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

@MainActor
@Test
func mobileStoreRefreshShowsSavedTimesInTheSchedule() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  _ = try await core.saveDayTimes(
    date: date, times: [LorvexTaskTime(taskID: task.id, time: 540..<570)])
  let store = MobileStore(core: core, todayString: { date })

  await store.refresh()

  let row = try #require(store.todaySchedule.first { $0.id == "task:\(task.id)" })
  #expect(row.startMinutes == 540)
  #expect(row.endMinutes == 570)
  #expect(store.proposedDayTimes == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreSuggestsTimesAndSavesThemOnlyWhenUsed() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  let store = MobileStore(core: core, todayString: { date })
  await store.refresh()
  let timedBefore = try await core.loadTimedTasks(from: date, through: date)

  await store.suggestDayTimes()

  let proposal = try #require(store.proposedDayTimes)
  #expect(proposal.date == date)
  #expect(proposal.placements.contains { $0.task.id == task.id })
  // A suggestion is a draft: nothing is stored until it is used.
  #expect(try await core.loadTimedTasks(from: date, through: date) == timedBefore)

  await store.useSuggestedDayTimes()

  #expect(store.proposedDayTimes == nil)
  for placement in proposal.placements {
    #expect(try await core.loadTask(id: placement.task.id).plannedTime == placement.time)
  }
  let row = try #require(store.todaySchedule.first { $0.id == "task:\(task.id)" })
  #expect(row.startMinutes == proposal.placements.first { $0.task.id == task.id }?.time.lowerBound)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreDismissingASuggestionKeepsTheSavedTimes() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  _ = try await core.saveDayTimes(
    date: date, times: [LorvexTaskTime(taskID: task.id, time: 540..<570)])
  let store = MobileStore(core: core, todayString: { date })
  await store.refresh()
  store.proposedDayTimes = DayTimesProposal(
    date: date, workingHours: 540..<1080, availableMinutes: 540,
    placements: [DayTimesProposal.Placement(task: task, time: 600..<630)])

  store.dismissSuggestedDayTimes()

  #expect(store.proposedDayTimes == nil)
  #expect(try await core.loadTask(id: task.id).plannedTime == 540..<570)
}

@MainActor
@Test
func mobileStoreClearDayTimesKeepsTheTasksOnToday() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  _ = try await core.saveDayTimes(
    date: date, times: [LorvexTaskTime(taskID: task.id, time: 600..<630)])
  let store = MobileStore(core: core, todayString: { date })
  await store.refresh()
  await store.suggestDayTimes()
  #expect(store.proposedDayTimes != nil)

  await store.clearDayTimes()

  #expect(store.proposedDayTimes == nil)
  #expect(try await core.loadTask(id: task.id).plannedTime == nil)
  #expect(store.snapshot.today.tasks.contains { $0.id == task.id })
  #expect(!store.todaySchedule.contains { $0.id == "task:\(task.id)" })
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreClearingTimesRefreshesTheCalendarsCopyOfTheTask() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = try await core.loadToday()
  let date = try #require(today.logicalDay)
  let task = try #require(today.tasks.first)
  _ = try await core.saveDayTimes(
    date: date, times: [LorvexTaskTime(taskID: task.id, time: 600..<630)])
  let store = MobileStore(core: core, todayString: { date })
  await store.refresh()
  await store.refreshCalendarTimeline(from: date, to: date)
  #expect(store.calendarScheduledTasks.first { $0.id == task.id }?.plannedTime == 600..<630)

  await store.clearDayTimes()

  // The calendar loaded its copy before the save; the copy is replaced, so the
  // grid draws the task untimed on its day instead of at its old time.
  let copy = try #require(store.calendarScheduledTasks.first { $0.id == task.id })
  #expect(copy.plannedTime == nil)
  #expect(copy.plannedDate != nil)
}
