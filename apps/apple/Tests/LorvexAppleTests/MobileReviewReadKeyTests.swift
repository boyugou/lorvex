import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// The Review pages read tomorrow's agenda and the days ahead on their own. The
// day's evidence and the week's snapshot hold neither, so a task that the
// assistant plans for tomorrow leaves both equal; the pages' read keys must
// still move, or the pages keep showing the plan they loaded.

@MainActor
@Test
func mobileStoreReviewReadKeysMoveWhenAnAssistantPlansATaskForTomorrow() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Plan the offsite", notes: "")
  let store = MobileStore(core: core)
  await store.refresh()
  let evidence = try #require(store.dayReviewEvidence)
  let dayKey = store.dayReviewReadKey
  let weekKey = store.weekReviewReadKey
  let tomorrowBefore = try #require(await store.loadTomorrowAgenda())
  #expect(tomorrowBefore.tasks.map(\.title).contains("Plan the offsite") == false)

  let tomorrowKey = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(store.logicalTodayString, days: 1))
  let tomorrow = try #require(LorvexDateFormatters.ymdUTC.date(from: tomorrowKey))
  _ = try await core.updateTask(TaskUpdateDraft(id: task.id, plannedDate: .set(tomorrow)))
  await store.refresh()

  #expect(store.dayReviewEvidence == evidence)
  #expect(store.dayReviewReadKey != dayKey)
  #expect(store.weekReviewReadKey != weekKey)
  let tomorrowAfter = try #require(await store.loadTomorrowAgenda())
  #expect(tomorrowAfter.tasks.map(\.title).contains("Plan the offsite"))
}
