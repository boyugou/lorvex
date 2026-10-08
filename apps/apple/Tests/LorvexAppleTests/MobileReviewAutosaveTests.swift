import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// Counts the daily-review writes that reach the stub core.
private actor ReviewWriteCounter {
  private(set) var count = 0

  func record() { count += 1 }
}

/// The review saves when a field loses focus, a rating changes, the page
/// disappears or the app goes to the background. A save stores each section
/// trimmed, and any of these can come right after a space or a line break the
/// user typed into a field that is still focused, so the fields must keep the
/// text the user typed.
@MainActor
@Test
func mobileStoreReviewAutosaveKeepsWhitespaceTypedAtTheEndOfASection() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  await store.loadDailyReviewDraft()

  store.dailyReviewDraft = MobileDailyReviewDraft(
    summary: "Good day ", wins: "Shipped the launch ", blockers: "Waiting on legal\n",
    learnings: "Ask earlier ")
  await store.flushDailyReviewDraftIfNeeded()

  #expect(store.dailyReview?.summary == "Good day")
  #expect(store.dailyReview?.wins == "Shipped the launch")
  #expect(store.dailyReview?.blockers == "Waiting on legal")
  #expect(store.dailyReview?.learnings == "Ask earlier")
  #expect(store.dailyReviewDraft.summary == "Good day ")
  #expect(store.dailyReviewDraft.wins == "Shipped the launch ")
  #expect(store.dailyReviewDraft.blockers == "Waiting on legal\n")
  #expect(store.dailyReviewDraft.learnings == "Ask earlier ")
  // The whitespace is not an unsaved edit: a refresh that adopts the loaded
  // review leaves the text alone.
  #expect(store.dailyReviewDraftMatchesLoaded)
  await store.refresh()
  #expect(store.dailyReviewDraft.wins == "Shipped the launch ")
  #expect(store.dailyReviewDraft.blockers == "Waiting on legal\n")
}

/// Whitespace alone is not an edit, so typing a space after a save, or a line
/// break, writes nothing: each write is a changelog row and a sync upload.
@MainActor
@Test
func mobileStoreReviewAutosaveWritesNothingWhenOnlyWhitespaceChanged() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let counter = ReviewWriteCounter()
  core.upsertDailyReviewGate = { await counter.record() }
  let store = MobileStore(core: core)
  await store.refresh()
  await store.loadDailyReviewDraft()

  store.dailyReviewDraft.summary = "Good day"
  await store.flushDailyReviewDraftIfNeeded()
  store.dailyReviewDraft.summary = "Good day "
  await store.flushDailyReviewDraftIfNeeded()
  store.dailyReviewDraft.summary = "Good day\n"
  await store.flushDailyReviewDraftIfNeeded()

  #expect(await counter.count == 1)
}

/// Space or a line break typed into the empty note of a day is not a review:
/// nothing is saved, so the day does not gain an entry with no words in it.
@MainActor
@Test
func mobileStoreReviewBlankNoteDoesNotCreateAnEntry() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core)
  await store.refresh()
  await store.loadDailyReviewDraft()

  store.dailyReviewDraft.summary = "  \n"
  #expect(store.dailyReviewDraftMatchesLoaded)
  await store.flushDailyReviewDraftIfNeeded()

  #expect(try await core.loadDailyReview(date: store.selectedReviewDate) == nil)
  #expect(store.dailyReview == nil)
}

/// Text typed while the write is in flight is not in the saved entry. It stays
/// in the editor as an unsaved edit that the next save picks up.
@MainActor
@Test
func mobileStoreReviewSaveKeepsTextTypedWhileItRuns() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let gate = ReviewGate()
  core.upsertDailyReviewGate = { await gate.hold() }
  let store = MobileStore(core: core)
  await store.refresh()
  await store.loadDailyReviewDraft()

  store.dailyReviewDraft.summary = "First"
  let save = Task { await store.flushDailyReviewDraftIfNeeded() }
  await gate.waitUntilHeld()
  store.dailyReviewDraft.summary = "First and more"
  await gate.release()
  await save.value

  #expect(try await core.loadDailyReview(date: store.selectedReviewDate)?.summary == "First")
  #expect(store.dailyReviewDraft.summary == "First and more")
  #expect(!store.dailyReviewDraftMatchesLoaded)

  await store.flushDailyReviewDraftIfNeeded()

  #expect(store.dailyReview?.summary == "First and more")
  #expect(store.dailyReviewDraftMatchesLoaded)
}

/// A refresh reads the loaded review before it adopts it. Text typed in between
/// is not in that read, so it stays in the editor as an unsaved edit.
@MainActor
@Test
func mobileStoreRefreshKeepsTextTypedWhileItReadsTheReview() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core)
  await store.refresh()
  await store.loadDailyReviewDraft()
  store.dailyReviewDraft.summary = "Saved text"
  await store.flushDailyReviewDraftIfNeeded()
  #expect(store.dailyReviewDraftMatchesLoaded)

  let gate = ReviewGate()
  core.loadDailyReviewGate = { await gate.hold() }
  let refresh = Task { await store.refresh() }
  await gate.waitUntilHeld()
  core.loadDailyReviewGate = nil
  store.dailyReviewDraft.summary = "Saved text and more"
  await gate.release()
  await refresh.value

  #expect(store.dailyReviewDraft.summary == "Saved text and more")
  #expect(!store.dailyReviewDraftMatchesLoaded)
}

/// A refresh that read one day must not put that day into a review that has
/// since moved to another one.
@MainActor
@Test
func mobileStoreRefreshDoesNotAdoptADayTheReviewMovedOffDuringIt() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core)
  await store.refresh()
  let yesterday = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(store.selectedReviewDate, days: -1))
  _ = try await core.upsertDailyReview(
    date: yesterday, summary: "Yesterday's note", mood: nil, energyLevel: nil, wins: nil,
    blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])

  let gate = ReviewGate()
  core.loadDailyReviewGate = { await gate.hold() }
  let refresh = Task { await store.refresh() }
  await gate.waitUntilHeld()
  core.loadDailyReviewGate = nil
  await store.selectReviewDay(yesterday)
  await gate.release()
  await refresh.value

  #expect(store.selectedReviewDate == yesterday)
  #expect(store.dailyReview?.summary == "Yesterday's note")
  #expect(store.dailyReviewDraft.summary == "Yesterday's note")
  #expect(store.dayReviewEvidence?.date == yesterday)
}

/// Whitespace typed after the last save is not an unsaved edit, so a review
/// written on another device still reaches the editor, through the full refresh
/// and through the selective reload that an inbound sync runs.
@MainActor
@Test
func mobileStoreReviewReloadAdoptsARemoteEditOverTrailingWhitespace() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core)
  await store.refresh()
  await store.loadDailyReviewDraft()
  store.dailyReviewDraft.summary = "Good day"
  await store.flushDailyReviewDraftIfNeeded()
  let today = store.selectedReviewDate

  store.dailyReviewDraft.summary = "Good day "
  _ = try await core.upsertDailyReview(
    date: today, summary: "Edited on the Mac", mood: nil, energyLevel: nil, wins: nil,
    blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
  await store.refresh()
  #expect(store.dailyReviewDraft.summary == "Edited on the Mac")

  store.dailyReviewDraft.summary = "Edited on the Mac\n"
  _ = try await core.upsertDailyReview(
    date: today, summary: "Edited again", mood: nil, energyLevel: nil, wins: nil, blockers: nil,
    learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
  await store.reloadInboundDomains([.reviews])
  #expect(store.dailyReviewDraft.summary == "Edited again")
}

/// Re-entering the Review tab reloads the day the page already shows. The
/// fields stay on screen through the read, so the page does not flash its
/// loading skeleton, the scroll position survives, and text typed meanwhile is
/// kept.
@MainActor
@Test
func mobileStoreReviewReloadOfTheShownDayKeepsThePageOnScreen() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core)
  await store.refresh()
  await store.loadDailyReviewDraft()
  #expect(!store.isLoadingDailyReviewDraft)

  let gate = ReviewGate()
  core.loadDailyReviewGate = { await gate.hold() }
  let reload = Task { await store.loadDailyReviewDraft() }
  await gate.waitUntilHeld()
  core.loadDailyReviewGate = nil
  #expect(!store.isLoadingDailyReviewDraft)
  store.dailyReviewDraft.summary = "Typed while the page reloaded "
  await gate.release()
  await reload.value

  #expect(!store.isLoadingDailyReviewDraft)
  #expect(store.dailyReviewDraft.summary == "Typed while the page reloaded ")
}

/// A different day has nothing on the page yet, so it shows the loading state
/// until its review is read.
@MainActor
@Test
func mobileStoreReviewShowsTheLoadingStateWhileAnotherDayLoads() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core)
  await store.refresh()
  await store.loadDailyReviewDraft()
  let yesterday = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(store.selectedReviewDate, days: -1))

  let gate = ReviewGate()
  core.loadDailyReviewGate = { await gate.hold() }
  let select = Task { await store.selectReviewDay(yesterday) }
  await gate.waitUntilHeld()
  core.loadDailyReviewGate = nil
  #expect(store.isLoadingDailyReviewDraft)
  await gate.release()
  await select.value

  #expect(!store.isLoadingDailyReviewDraft)
  #expect(store.selectedReviewDate == yesterday)
}
