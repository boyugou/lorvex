import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// A store over the seeded core with its own preferences suite, plus the suite
/// name to remove afterwards.
@MainActor
private func makeReviewStore() async throws -> (store: AppStore, core: SwiftLorvexCoreService, suite: String) {
  let suite = "AppStoreWeeklyReviewAnchor.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defaults.removePersistentDomain(forName: suite)
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()
  return (store, core, suite)
}

/// Writes today's review the way an assistant does, straight through the core.
private func assistantWritesTodaysReview(
  _ core: SwiftLorvexCoreService, summary: String
) async throws {
  _ = try await core.upsertDailyReview(
    date: nil, summary: summary, mood: nil, energyLevel: nil, wins: nil, blockers: nil,
    learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
}

/// The weekly pane shows the week `weeklyReviewAnchor` names, and its digest and
/// date strip follow the same anchor. Saving the day review refreshes the weekly
/// snapshot, so the refresh must read the anchored week, not the live one.
@MainActor
@Test
func appStoreSavingTheDayReviewKeepsTheViewedWeek() async throws {
  let (store, _, suite) = try await makeReviewStore()
  defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
  await store.stepWeeklyReview(byWeeks: -2)
  let anchor = try #require(store.weeklyReviewAnchor)
  let viewedWindow = try #require(store.weeklyReview?.windowTitle)
  #expect(viewedWindow.contains(anchor))

  store.dailyReviewSummaryDraft = "A quiet day."
  await store.saveDailyReviewDraft()

  #expect(store.dailyReview?.summary == "A quiet day.")
  #expect(store.weeklyReviewAnchor == anchor)
  #expect(store.weeklyReview?.windowTitle == viewedWindow)
}

/// The Week scope's digest lists the daily reviews of the viewed week. Switching
/// from the Day scope saves the draft and loads the digest at the same moment,
/// so the save itself brings the digest up to date.
@MainActor
@Test
func appStoreSavingTheDayReviewAddsItToTheWeekDigest() async throws {
  let (store, _, suite) = try await makeReviewStore()
  defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
  await store.loadWeekReviewDigest(weekOf: nil)
  #expect(!store.weekReviewDigest.contains { $0.summary == "A quiet day." })

  store.dailyReviewSummaryDraft = "A quiet day."
  await store.saveDailyReviewDraft()

  #expect(store.weekReviewDigest.contains { $0.summary == "A quiet day." })
}

/// An assistant's write reaches the Mac through the database change signal,
/// which runs a full refresh; the Week scope may be on screen when it does.
@MainActor
@Test
func appStoreRefreshBringsAnAssistantsReviewIntoTheWeekDigest() async throws {
  let (store, core, suite) = try await makeReviewStore()
  defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
  await store.loadWeekReviewDigest(weekOf: nil)

  try await assistantWritesTodaysReview(core, summary: "Written by the assistant.")
  await store.refresh()

  #expect(store.weekReviewDigest.contains { $0.summary == "Written by the assistant." })
}

/// A review synced from another device reloads the review domain only.
@MainActor
@Test
func appStoreInboundReviewReloadBringsAPeersReviewIntoTheWeekDigest() async throws {
  let (store, core, suite) = try await makeReviewStore()
  defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
  await store.loadWeekReviewDigest(weekOf: nil)

  try await assistantWritesTodaysReview(core, summary: "Written on the iPhone.")
  await store.performSelectiveInboundReload([.reviews])

  #expect(store.weekReviewDigest.contains { $0.summary == "Written on the iPhone." })
}
