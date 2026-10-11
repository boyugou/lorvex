import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

// Scratch probe (git-excluded): what does the Mac daily-review autosave do to
// text that is still being typed?

@MainActor
@Test
func zzReviewDraftProbe() async throws {
  guard ProcessInfo.processInfo.environment["REVIEW_PROBE"] != nil else { return }
  func fresh() async throws -> (AppStore, SwiftLorvexCoreService) {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    await store.refresh()
    await store.beginEditingDailyReview(date: store.logicalTodayDateString)
    return (store, core)
  }

  // 1. Trailing whitespace: what the editor shows after an autosave.
  do {
    let (store, _) = try await fresh()
    store.dailyReviewSummaryDraft = "Good day "
    store.dailyReviewWinsDraft = "Shipped the launch "
    store.dailyReviewBlockersDraft = "Waiting on legal "
    store.dailyReviewLearningsDraft = "Ask earlier "
    await store.saveDailyReviewDraft()
    print("TRAILING summary=\(store.dailyReviewSummaryDraft.debugDescription) wins=\(store.dailyReviewWinsDraft.debugDescription) blockers=\(store.dailyReviewBlockersDraft.debugDescription) learnings=\(store.dailyReviewLearningsDraft.debugDescription)")
    print("TRAILING clean=\(store.dailyReviewDraftMatchesLoaded)")
  }

  // 2. Keystrokes that arrive while the save is in flight.
  do {
    let (store, _) = try await fresh()
    store.dailyReviewSummaryDraft = "First"
    let save = Task { @MainActor in await store.saveDailyReviewDraft() }
    await Task.yield()
    store.dailyReviewSummaryDraft = "First and more"
    await save.value
    print("INFLIGHT draft=\(store.dailyReviewSummaryDraft.debugDescription) loaded=\(store.dailyReview?.summary.debugDescription ?? "nil") clean=\(store.dailyReviewDraftMatchesLoaded)")
  }

  // 3. Task detail: what the inspector shows after an autosave of text that ends in whitespace.
  do {
    let core = try await makeSeededInMemoryCore()
    let store = AppStore(core: core)
    await store.refresh()
    let task = try #require(store.today.tasks.first { $0.status == .open && $0.plannedDate == nil })
    store.selectOnlyTodayTask(task.id)
    store.syncSelectedTaskDraft()
    await store.loadSelectedTaskDetail()
    store.taskDetailTitle = "Call Bob and "
    store.taskDetailNotes = "First line\n"
    await store.saveSelectedTaskDraft()
    let stored = try await core.loadTask(id: task.id)
    print("TASKTRAIL title=\(store.taskDetailTitle.debugDescription) notes=\(store.taskDetailNotes.debugDescription) storedTitle=\(stored.title.debugDescription) storedNotes=\(stored.notes.debugDescription)")
  }

  // 4. A blank or whitespace-only summary on a day with no entry.
  do {
    let (store, core) = try await fresh()
    store.dailyReviewSummaryDraft = "  "
    print("BLANK matches=\(store.dailyReviewDraftMatchesLoaded)")
    await store.saveDailyReviewDraft()
    let stored = try await core.loadDailyReview(date: store.dailyReviewEditorDate)
    print("BLANK stored=\(stored.map { "summary=\($0.summary.debugDescription)" } ?? "nil") error=\(store.errorMessage ?? "none") matches=\(store.dailyReviewDraftMatchesLoaded)")
  }
}
