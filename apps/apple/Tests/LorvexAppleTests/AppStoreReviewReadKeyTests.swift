import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// The Review pages read tomorrow's agenda and the days ahead on their own. The
// day's evidence and the week's snapshot hold neither, so a task that the
// assistant plans for tomorrow leaves both equal; the pages' read keys must
// still move, or the pages keep showing the plan they loaded.

@MainActor
@Test
func appStoreReviewReadKeysMoveWhenAnAssistantPlansATaskForTomorrow() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Plan the offsite", notes: "")
  let store = AppStore(core: core)
  await store.refresh()
  store.selection = .reviews
  await store.loadWeeklyReview(weekOf: nil)
  let evidence = try #require(store.dayReviewEvidence)
  let dayKey = store.dayReviewReadKey
  let weekKey = store.weekReviewReadKey
  let tomorrowBefore = try #require(await store.loadTomorrowAgenda())
  #expect(tomorrowBefore.tasks.map(\.title).contains("Plan the offsite") == false)

  _ = try await core.updateTask(
    TaskUpdateDraft(
      id: task.id, plannedDate: .set(try store.storageDate(daysFromLogicalToday: 1))))
  await store.refresh()

  #expect(store.dayReviewEvidence == evidence)
  #expect(store.dayReviewReadKey != dayKey)
  #expect(store.weekReviewReadKey != weekKey)
  let tomorrowAfter = try #require(await store.loadTomorrowAgenda())
  #expect(tomorrowAfter.tasks.map(\.title).contains("Plan the offsite"))
}
