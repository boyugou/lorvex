import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

@Test
func sharedSystemIntentRunnerPlansTheDayAndMovesTasks() async throws {
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try await core.getSessionContext().date
  let task = try await core.createTask(
    TaskCreateDraft(title: "Shared system task", estimatedMinutes: 25))

  let planned = try await LorvexSystemIntentRunner.planTaskForToday(
    id: " \(task.id) ", core: core)
  #expect(planned.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == logicalDay)

  // A nil date means the product's today on every day-planning action.
  let proposal = try await LorvexSystemIntentRunner.proposeDayTimes(date: nil, core: core)
  #expect(proposal.date == logicalDay)
  #expect(proposal.placements.contains { $0.task.id == task.id })
  let saved = try await LorvexSystemIntentRunner.saveProposedDayTimes(date: nil, core: core)
  #expect(saved.times == proposal.times)
  let read = try await LorvexSystemIntentRunner.readDayTimes(date: nil, core: core)
  #expect(read.date == logicalDay)
  #expect(read.tasks.contains { $0.id == task.id })

  let deferredTitle = try await LorvexSystemIntentRunner.deferTaskUntilTomorrow(
    id: task.id, core: core)
  // Deferral moves the task to tomorrow, off today's pool, and a time belongs
  // to its day, so the saved time goes with it.
  let deferred = try await core.loadTask(id: task.id)
  #expect(deferredTitle == "Shared system task")
  #expect(deferred.status == .open)
  #expect(deferred.plannedDate != nil)
  #expect(deferred.plannedTime == nil)
  #expect(!(try await core.loadToday()).tasks.contains { $0.id == task.id })

  let completedTitle = try await LorvexSystemIntentRunner.completeTask(id: task.id, core: core)
  #expect(completedTitle == "Shared system task")
  #expect(try await core.loadTask(id: task.id).status == .completed)
}
