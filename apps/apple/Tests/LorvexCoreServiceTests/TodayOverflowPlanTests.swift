import Foundation
import LorvexCore
import Testing

@Test("Moving Today overflow preserves carry-over plans and rechecks stale selections")
func moveTodayOverflowAndRestore() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let day = try #require(try await core.loadToday().logicalDay)
  let today = try #require(PlannedDayBridge.storageDate(forLogicalDay: day))
  let yesterday = try #require(PlannedDayBridge.storageDate(forLogicalDay: day, addingDays: -1))
  let tomorrow = try #require(PlannedDayBridge.storageDate(forLogicalDay: day, addingDays: 1))
  let historical = try await core.createTask(.init(title: "Carried from yesterday", estimatedMinutes: 45,
    plannedDate: yesterday, plannedTime: 660..<700))
  let stays = try await core.createTask(.init(title: "Keep today", estimatedMinutes: 20, plannedDate: today))
  let started = try await core.createTask(.init(title: "Started in another window", estimatedMinutes: 30, plannedDate: today))
  let deadline = try await core.createTask(.init(title: "Due date added", estimatedMinutes: 30, plannedDate: today))
  let timed = try await core.createTask(.init(title: "Time now booked", estimatedMinutes: 30, plannedDate: today))
  let revised = try await core.createTask(.init(title: "Estimate revised", estimatedMinutes: 30, plannedDate: today))
  let rows = LorvexCalmToday.Overbooked(workMinutes: 185, freeMinutes: 30,
    candidates: [historical, stays, started, deadline, timed, revised]).planningRows
  _ = try await core.startTask(id: started.id)
  _ = try await core.updateTask(.init(id: deadline.id, dueDate: .set(today)))
  _ = try await core.saveDayTimes(date: day, times: [.init(taskID: timed.id, time: 660..<690)])
  _ = try await core.updateTask(.init(id: revised.id, estimatedMinutes: .set(90)))
  let chosen = rows.filter { $0.id != stays.id }
  let changes = try await core.moveTodayOverflow(chosen + chosen, on: day)
  #expect(changes.map(\.id) == [historical.id])
  let moved = try await core.loadTask(id: historical.id)
  #expect(moved.plannedDate == tomorrow)
  #expect(moved.plannedTime == nil)
  #expect(try await core.loadTask(id: stays.id).plannedDate == today)
  #expect(try await core.moveTodayOverflow(chosen, on: day).isEmpty)
  try await core.restoreReviewTasks(changes, undo: true)
  let restored = try await core.loadTask(id: historical.id)
  #expect(restored.plannedDate == yesterday)
  #expect(restored.plannedTime == historical.plannedTime)
  #expect(restored.deferCount == historical.deferCount)
  #expect(try await core.moveTodayOverflow(chosen, on: LorvexDateFormatters.ymdUTC.string(from: yesterday)).isEmpty)
}
