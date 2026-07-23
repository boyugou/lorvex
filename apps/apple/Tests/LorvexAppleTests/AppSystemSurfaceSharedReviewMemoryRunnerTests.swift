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
func sharedSystemIntentRunnerMutatesReviewsAndMemory() async throws {
  let core = try await makeSeededInMemoryCore()
  let expectedDate = try await core.getSessionContext().date
  let review = try await LorvexSystemIntentRunner.saveDailyReview(
    summary: "  Shared review intent  ", date: nil, mood: nil, energyLevel: nil, wins: nil,
    blockers: nil, learnings: nil, core: core)
  #expect(review.date == expectedDate)
  #expect(review.summary == "Shared review intent")
  let amendedReview = try await LorvexSystemIntentRunner.amendDailyReview(
    date: " \(expectedDate) ", summary: "  Shared amended review  ", mood: 5, energyLevel: nil,
    wins: nil, blockers: nil, learnings: nil, core: core)
  #expect(amendedReview.summary == "Shared amended review")
  #expect(amendedReview.mood == 5)
  let reviewHistory = try await LorvexSystemIntentRunner.readReviewHistory(
    from: " \(contractYmd(daysFromToday: -2)) ", to: nil, limit: 10, core: core)
  #expect(reviewHistory.map(\.date).contains(expectedDate))
  let weeklyReview = try await LorvexSystemIntentRunner.readWeeklyReview(
    weekOf: " \(expectedDate) ", core: core)
  #expect(!weeklyReview.windowTitle.isEmpty)
  let memory = try await LorvexSystemIntentRunner.saveMemory(
    key: " system_context ", content: "  Shared system memory  ", core: core)
  #expect(memory.key == "system_context")
  #expect(memory.content == "Shared system memory")
  let readMemory = try await LorvexSystemIntentRunner.readMemory(
    key: " system_context ", core: core)
  #expect(readMemory == memory)
  let deletedKey = try await LorvexSystemIntentRunner.deleteMemory(
    key: " system_context ", core: core)
  #expect(deletedKey == "system_context")
  let postDeleteMemory = try await core.loadMemory()
  #expect(!postDeleteMemory.entries.contains { $0.key == "system_context" })
}

@Test
func systemIntentDailyReviewScalarEditPreservesExistingLinks() async throws {
  let core = try await makeSeededInMemoryCore()
  let date = contractYmd(daysFromToday: 0)
  _ = try await core.upsertDailyReview(
    date: date,
    summary: "Linked intent review",
    mood: 3,
    energyLevel: 4,
    wins: nil,
    blockers: nil,
    learnings: nil,
    linkedTaskIDs: [LorvexPreviewSeedID.agendaTask],
    linkedListIDs: [LorvexPreviewSeedID.appleNativeList])

  let saved = try await LorvexSystemIntentRunner.saveDailyReview(
    summary: "Edited through App Intent",
    date: date,
    mood: 5,
    energyLevel: 4,
    wins: nil,
    blockers: nil,
    learnings: nil,
    core: core)

  #expect(saved.linkedTaskIDs == [LorvexPreviewSeedID.agendaTask])
  #expect(saved.linkedListIDs == [LorvexPreviewSeedID.appleNativeList])
}
