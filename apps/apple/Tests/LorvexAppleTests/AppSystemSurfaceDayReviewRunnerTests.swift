import Foundation
import LorvexCore
import LorvexSystemIntents
import Testing

@testable import LorvexApple
@testable import LorvexSystemIntents

private func contractYmd(daysFromToday offset: Int) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = .current
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: Date(timeIntervalSinceNow: TimeInterval(offset) * 86_400))
}

@Test
func taskIntentRunnerHandlesDayPlanningAndReviewActions() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(
    TaskCreateDraft(title: "Shortcut planned task", estimatedMinutes: 30))
  let logicalDay = try await core.getSessionContext().date

  let planned = try await LorvexTaskIntentRunner.planTaskForToday(
    id: " \(created.id) ",
    core: core
  )
  #expect(planned.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == logicalDay)
  #expect(try await core.loadToday().tasks.contains { $0.id == created.id })

  // Suggesting stores nothing; saving the suggestion stores exactly its times.
  let proposal = try await LorvexTaskIntentRunner.proposeDayTimes(
    date: " \(logicalDay) ",
    core: core
  )
  #expect(proposal.date == logicalDay)
  #expect(proposal.placements.contains { $0.task.id == created.id })
  #expect(try await LorvexTaskIntentRunner.readDayTimes(date: logicalDay, core: core).tasks.isEmpty)

  let saved = try await LorvexTaskIntentRunner.saveProposedDayTimes(
    date: " \(logicalDay) ",
    core: core
  )
  #expect(saved.times == proposal.times)
  let read = try await LorvexTaskIntentRunner.readDayTimes(date: " \(logicalDay) ", core: core)
  #expect(read.date == logicalDay)
  #expect(read.tasks.map(\.id) == saved.placements.map(\.task.id))
  let savedTime = try #require(saved.placements.first { $0.task.id == created.id }?.time)
  #expect(try await core.loadTask(id: created.id).plannedTime == savedTime)

  let deferredTitle = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(
    id: created.id,
    core: core
  )
  // Deferral moves the task to tomorrow, so it is no longer in today's pool.
  let deferred = try await core.loadTask(id: created.id)
  #expect(deferredTitle == "Shortcut planned task")
  #expect(deferred.status == .open)
  #expect(deferred.plannedDate != nil)

  // Daily-review writes are validated against the configured logical-day
  // window (today-7 … today+1).
  let reviewDate = contractYmd(daysFromToday: 0)
  let review = try await LorvexTaskIntentRunner.saveDailyReview(
    summary: "  Reviewed shortcut surfaces  ",
    date: reviewDate,
    mood: 4,
    energyLevel: 5,
    wins: "  Shortcut review logging  ",
    blockers: "   ",
    learnings: "  Keep Apple entrypoints on shared core semantics  ",
    core: core
  )
  #expect(review.date == reviewDate)
  #expect(review.summary == "Reviewed shortcut surfaces")
  #expect(review.mood == 4)
  #expect(review.energyLevel == 5)
  #expect(review.wins == "Shortcut review logging")
  #expect(review.blockers == nil)
  #expect(review.learnings == "Keep Apple entrypoints on shared core semantics")
  let amendedReview = try await LorvexTaskIntentRunner.amendDailyReview(
    date: " \(reviewDate) ",
    summary: "  Refined shortcut review  ",
    mood: 3,
    core: core
  )
  #expect(amendedReview.date == reviewDate)
  #expect(amendedReview.summary == "Refined shortcut review")
  #expect(amendedReview.mood == 3)
  #expect(amendedReview.energyLevel == 5)
  let reviewHistory = try await LorvexTaskIntentRunner.readReviewHistory(
    from: " \(contractYmd(daysFromToday: -2)) ",
    to: " \(contractYmd(daysFromToday: 1)) ",
    limit: 10,
    core: core
  )
  #expect(reviewHistory.map(\.date).contains(reviewDate))
  let weeklyReview = try await LorvexTaskIntentRunner.readWeeklyReview(
    weekOf: " \(reviewDate) ",
    core: core
  )
  #expect(!weeklyReview.windowTitle.isEmpty)
}
