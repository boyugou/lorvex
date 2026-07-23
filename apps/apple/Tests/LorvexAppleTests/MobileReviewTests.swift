import Foundation
import LorvexCore
import LorvexMobile
import Testing

/// The store's injected clock must agree with the live write window the
/// daily-review guard validates against, so the tests pin "today" to the
/// real today rather than a fixed demo date.
private let mobileReviewToday: String = {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = .current
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: Date())
}()

private func mobileReviewYmdAddingDays(_ day: String, _ days: Int) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = TimeZone(secondsFromGMT: 0)
  formatter.dateFormat = "yyyy-MM-dd"
  let base = formatter.date(from: day)!
  let shifted = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: base)!
  return formatter.string(from: shifted)
}

@Test
func mobileDailyReviewDraftTrimsOptionalFields() {
  let draft = MobileDailyReviewDraft(
    summary: "  Today moved forward  ",
    wins: "  shipped review  ",
    blockers: "   ",
    learnings: "  native forms fit well  ",
    mood: 4,
    energy: 5
  )

  #expect(draft.canSave)
  #expect(draft.trimmedSummary == "Today moved forward")
  #expect(draft.trimmedWins == "shipped review")
  #expect(draft.trimmedBlockers == nil)
  #expect(draft.trimmedLearnings == "native forms fit well")
}

@Test
func mobileDailyReviewDraftDefaultsRatingsToUnset() {
  let draft = MobileDailyReviewDraft(summary: "Summary only")

  #expect(draft.mood == nil)
  #expect(draft.energy == nil)
  #expect(draft.canSave)
}

@MainActor
@Test
func mobileStoreDailyReviewDraftStartsInLoadingStateUntilLoaded() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { mobileReviewToday })

  #expect(store.isLoadingDailyReviewDraft)

  await store.loadDailyReviewDraft()

  #expect(!store.isLoadingDailyReviewDraft)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreRefreshLoadsReviewEvidenceAndWeekDigest() async throws {
  let core = try await makeSeededInMemoryCore()
  let yesterday = mobileReviewYmdAddingDays(mobileReviewToday, -1)
  _ = try await core.importDailyReview(
    date: mobileReviewToday,
    summary: "Today had enough signal",
    mood: 4,
    energyLevel: 3,
    wins: nil,
    blockers: nil,
    learnings: nil
  )
  _ = try await core.importDailyReview(
    date: yesterday,
    summary: "Yesterday shipped the review flow",
    mood: 5,
    energyLevel: 4,
    wins: nil,
    blockers: nil,
    learnings: nil
  )
  let store = MobileStore(core: core, todayString: { mobileReviewToday })

  await store.refresh()

  #expect(store.dailyReview?.date == mobileReviewToday)
  #expect(store.dayReviewEvidence?.date == mobileReviewToday)
  #expect(store.weekReviewDigest.map(\.date).contains(mobileReviewToday))
  #expect(store.weekReviewDigest.map(\.date).contains(yesterday))
  #expect(store.snapshot.weeklyReview != nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreSelectReviewDayLoadsReadOnlyReviewAndEvidence() async throws {
  let core = try await makeSeededInMemoryCore()
  let olderDay = mobileReviewYmdAddingDays(mobileReviewToday, -2)
  _ = try await core.importDailyReview(
    date: olderDay,
    summary: "Past day review",
    mood: 2,
    energyLevel: 3,
    wins: "Closed loop",
    blockers: nil,
    learnings: nil
  )
  let store = MobileStore(core: core, todayString: { mobileReviewToday })

  await store.selectReviewDay(olderDay)
  store.dailyReviewDraft.summary = "Attempted mobile edit"
  let saved = await store.saveDailyReviewDraft()

  #expect(store.selectedReviewDate == olderDay)
  #expect(!store.selectedReviewDayIsEditable)
  #expect(store.dailyReview?.summary == "Past day review")
  #expect(store.dayReviewEvidence?.date == olderDay)
  #expect(!saved)
}

@MainActor
@Test
func mobileStoreSavesDailyReviewThroughCore() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { mobileReviewToday })

  await store.refresh()
  await store.loadDailyReviewDraft()
  store.dailyReviewDraft = MobileDailyReviewDraft(
    summary: "  Shipped mobile review editing  ",
    wins: "  Native daily form  ",
    blockers: "   ",
    learnings: "  Keep mobile state sliced  ",
    mood: 4,
    energy: 5
  )

  let saved = await store.saveDailyReviewDraft()
  let review = try #require(store.dailyReview)

  #expect(saved)
  #expect(review.date == mobileReviewToday)
  #expect(review.summary == "Shipped mobile review editing")
  #expect(review.wins == "Native daily form")
  #expect(review.blockers == nil)
  #expect(review.learnings == "Keep mobile state sliced")
  #expect(review.mood == 4)
  #expect(review.energyLevel == 5)
  #expect(store.snapshot.weeklyReview != nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreDailyReviewScalarEditPreservesLoadedLinks() async throws {
  let core = try await makeSeededInMemoryCore()
  _ = try await core.upsertDailyReview(
    date: mobileReviewToday,
    summary: "Linked mobile review",
    mood: 3,
    energyLevel: 4,
    wins: nil,
    blockers: nil,
    learnings: nil,
    linkedTaskIDs: [LorvexPreviewSeedID.agendaTask],
    linkedListIDs: [LorvexPreviewSeedID.appleNativeList])
  let store = MobileStore(core: core, todayString: { mobileReviewToday })
  await store.loadDailyReviewDraft()

  // A non-UI writer may change links while this scalar-only draft is open.
  // Saving the stale draft must preserve the transaction-current link sets.
  _ = try await core.amendDailyReview(
    date: mobileReviewToday,
    patch: DailyReviewPatch(
      linkedTaskIDs: [LorvexPreviewSeedID.statusUpdateTask],
      linkedListIDs: [LorvexPreviewSeedID.inboxList]))

  store.dailyReviewDraft.summary = "Edited in the iPhone review surface"
  let didSave = await store.saveDailyReviewDraft()

  let saved = try #require(try await core.loadDailyReview(date: mobileReviewToday))
  #expect(didSave)
  #expect(saved.linkedTaskIDs == [LorvexPreviewSeedID.statusUpdateTask])
  #expect(saved.linkedListIDs == [LorvexPreviewSeedID.inboxList])
}

@MainActor
@Test
func mobileStoreSavesSummaryOnlyDailyReviewWithNilRatings() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { mobileReviewToday })

  await store.loadDailyReviewDraft()
  store.dailyReviewDraft = MobileDailyReviewDraft(summary: "Summary only review")

  let saved = await store.saveDailyReviewDraft()
  let review = try #require(try await core.loadDailyReview(date: mobileReviewToday))

  #expect(saved)
  #expect(review.summary == "Summary only review")
  #expect(review.mood == nil)
  #expect(review.energyLevel == nil)
  #expect(store.dailyReview?.mood == nil)
  #expect(store.dailyReview?.energyLevel == nil)
}

@MainActor
@Test
func mobileStoreSelectReviewDayFlushesUnsavedDailyReviewDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let olderDay = mobileReviewYmdAddingDays(mobileReviewToday, -2)
  _ = try await core.importDailyReview(
    date: olderDay,
    summary: "Older day",
    mood: nil,
    energyLevel: nil,
    wins: nil,
    blockers: nil,
    learnings: nil
  )
  let store = MobileStore(core: core, todayString: { mobileReviewToday })

  await store.loadDailyReviewDraft()
  store.dailyReviewDraft = MobileDailyReviewDraft(
    summary: "Unsaved today",
    wins: "Preserved before switching",
    mood: nil,
    energy: nil
  )
  await store.selectReviewDay(olderDay)
  let todayReview = try #require(try await core.loadDailyReview(date: mobileReviewToday))

  #expect(todayReview.summary == "Unsaved today")
  #expect(todayReview.wins == "Preserved before switching")
  #expect(todayReview.mood == nil)
  #expect(todayReview.energyLevel == nil)
  #expect(store.selectedReviewDate == olderDay)
  #expect(store.dailyReview?.summary == "Older day")
}

@MainActor
@Test
func mobileStoreDoesNotSaveDailyReviewBeforeDraftLoadFinishes() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { mobileReviewToday })
  store.dailyReviewDraft = MobileDailyReviewDraft(summary: "Should wait for the loaded draft")

  let saved = await store.saveDailyReviewDraft()

  #expect(!saved)
  #expect(store.dailyReview == nil)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileStoreDailyReviewSaveSurfacesWeeklyReviewReloadFailure() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { mobileReviewToday })

  await store.refresh()
  await store.loadDailyReviewDraft()
  store.dailyReviewDraft = MobileDailyReviewDraft(summary: "Saved but weekly reload fails")
  core.loadWeeklyReviewError = .unsupportedOperation("Weekly review reload unavailable.")

  let saved = await store.saveDailyReviewDraft()

  #expect(!saved)
  #expect(store.dailyReview?.summary == "Saved but weekly reload fails")
  #expect(store.errorMessage == "Weekly review reload unavailable.")
}

@MainActor
@Test
func mobileStoreRejectsBlankDailyReviewSummary() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { mobileReviewToday })

  store.dailyReviewDraft = MobileDailyReviewDraft(summary: "   ")

  let saved = await store.saveDailyReviewDraft()

  #expect(!saved)
  #expect(store.dailyReview == nil)
  #expect(store.errorMessage == nil)
}
