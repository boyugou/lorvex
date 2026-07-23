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
func taskIntentRunnerHandlesFocusAndReviewActions() async throws {
  let core = try await makeSeededInMemoryCore()
  let created = try await core.createTask(title: "Shortcut focus task", notes: "")
  let logicalDay = try await core.getSessionContext().date
  let focusedCount = try await LorvexTaskIntentRunner.addTaskToFocus(
    id: created.id,
    core: core
  )
  #expect(focusedCount == 1)
  let focus = try #require(try await core.loadCurrentFocus(date: logicalDay))
  #expect(focus.taskIDs == [created.id])

  let readFocus = try #require(try await LorvexTaskIntentRunner.readCurrentFocus(
    date: " \(logicalDay) ",
    core: core
  ))
  #expect(readFocus.taskIDs == [created.id])

  let removedFocus = try await LorvexTaskIntentRunner.removeTaskFromFocus(
    id: " \(created.id) ",
    date: " \(logicalDay) ",
    core: core
  )
  #expect(removedFocus == nil)
  #expect(try await core.loadCurrentFocus(date: logicalDay) == nil)

  let refocusedCount = try await LorvexTaskIntentRunner.addTaskToFocus(
    id: created.id,
    core: core
  )
  #expect(refocusedCount == 1)

  let proposedSchedule = try await LorvexTaskIntentRunner.proposeFocusSchedule(
    date: " \(logicalDay) ",
    core: core
  )
  #expect(proposedSchedule.date == logicalDay)
  // The real proposal engine adds structure blocks (buffers) around the work;
  // the contract is a non-empty schedule whose save/read round-trip is stable.
  #expect(!proposedSchedule.blocks.isEmpty)
  let savedSchedule = try await LorvexTaskIntentRunner.saveProposedFocusSchedule(
    date: " \(logicalDay) ",
    rationale: " Shortcut schedule ",
    core: core
  )
  #expect(savedSchedule.date == logicalDay)
  #expect(savedSchedule.blocks.count == proposedSchedule.blocks.count)
  #expect(savedSchedule.rationale == "Shortcut schedule")
  let readSchedule = try #require(try await LorvexTaskIntentRunner.readFocusSchedule(
    date: " \(logicalDay) ",
    core: core
  ))
  #expect(readSchedule.date == logicalDay)
  #expect(readSchedule.blocks.count == proposedSchedule.blocks.count)
  #expect(readSchedule.rationale == "Shortcut schedule")

  let clearedFocusDate = try await LorvexTaskIntentRunner.clearCurrentFocus(
    date: " \(logicalDay) ",
    core: core
  )
  #expect(clearedFocusDate == logicalDay)
  #expect(try await core.loadCurrentFocus(date: logicalDay) == nil)

  let deferredTitle = try await LorvexTaskIntentRunner.deferTaskUntilTomorrow(
    id: created.id,
    core: core
  )
  let today = try await core.loadToday()
  let deferred = try #require(today.tasks.first { $0.id == created.id })
  #expect(deferredTitle == "Shortcut focus task")
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
