import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

@MainActor
@Test
func appStoreLoadsPreviewWeeklyReview() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()

  // The window title names the actual 7-day range (ending today) rather than
  // a relative label.
  let windowTitle = try #require(store.weeklyReview?.windowTitle)
  #expect(windowTitle.wholeMatch(of: /\d{4}-\d{2}-\d{2} - \d{4}-\d{2}-\d{2}/) != nil)
  // All six seeded tasks (someday, completed, and cancelled included) were
  // created this week; the Today pool carries only the three open ones, and
  // exactly one of the six is finished.
  #expect(store.weeklyReview?.createdThisWeek == 6)
  #expect(store.weeklyReview?.completedThisWeek == 1)
}

@MainActor
@Test
func appStoreLoadsAndSavesPreviewDailyReview() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()
  // The store loads today's review; the seed only carries the historical
  // 2026-05-22 entry, so today starts empty.
  #expect(store.dailyReview == nil)

  store.dailyReviewSummaryDraft = "Shipped a native daily review slice."
  store.dailyReviewMood = 5
  store.dailyReviewEnergy = 4
  store.dailyReviewWinsDraft = "Swift UI and MCP now share the same concept."
  await store.saveDailyReviewDraft()

  #expect(store.dailyReview?.summary == "Shipped a native daily review slice.")
  #expect(store.dailyReview?.mood == 5)
  #expect(store.dailyReview?.energyLevel == 4)
  #expect(store.dailyReview?.wins == "Swift UI and MCP now share the same concept.")
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func appStoreDailyReviewScalarEditPreservesLoadedLinks() async throws {
  let core = try await makeSeededInMemoryCore()
  let today = AppStore.todayDateString()
  _ = try await core.upsertDailyReview(
    date: today,
    summary: "Linked review",
    mood: 3,
    energyLevel: 4,
    wins: nil,
    blockers: nil,
    learnings: nil,
    linkedTaskIDs: [LorvexPreviewSeedID.agendaTask],
    linkedListIDs: [LorvexPreviewSeedID.appleNativeList])
  let store = AppStore(core: core)
  await store.refresh()

  // Simulate MCP/CloudKit updating links after the UI loaded its draft. The
  // human editor cannot edit links, so its later scalar save must not replay
  // the stale arrays it loaded above.
  _ = try await core.amendDailyReview(
    date: today,
    patch: DailyReviewPatch(
      linkedTaskIDs: [LorvexPreviewSeedID.statusUpdateTask],
      linkedListIDs: [LorvexPreviewSeedID.inboxList]))

  store.dailyReviewSummaryDraft = "Edited in the macOS review surface"
  await store.saveDailyReviewDraft()

  let saved = try #require(try await core.loadDailyReview(date: today))
  #expect(saved.linkedTaskIDs == [LorvexPreviewSeedID.statusUpdateTask])
  #expect(saved.linkedListIDs == [LorvexPreviewSeedID.inboxList])
}

@Test
func inMemoryLoadDaySummaryReturnsSeededDayEvidence() async throws {
  let core = try await makeSeededInMemoryCore()
  let day = "2026-04-05"
  let dueDate = LorvexDateFormatters.ymdUTC.date(from: day)

  // Two completed-that-day tasks (one earlier priority), one completed a
  // different day, one open task created and due that day — restored with
  // exact historical timestamps through the id-preserving import surface.
  func importHistoricalTask(
    title: String, priority: LorvexTask.Priority, status: LorvexTask.Status,
    dueDate: Date? = nil, completedAt: String? = nil, createdAt: String? = nil
  ) async throws -> LorvexTask {
    let task = try await core.importRemoteTask(
      id: UUID().uuidString.lowercased(), title: title, notes: "", aiNotes: nil,
      rawInput: nil, priority: priority, status: status, estimatedMinutes: nil,
      dueDate: dueDate, plannedDate: nil, availableFrom: nil, tags: [], dependsOn: [])
    try await core.restoreImportedTaskMetadata(
      id: task.id, archivedAt: nil, deferCount: nil, lastDeferReason: nil,
      lastDeferredAt: nil, completedAt: completedAt, createdAt: createdAt,
      updatedAt: nil)
    return task
  }
  let doneA = try await importHistoricalTask(
    title: "Done A", priority: .p2, status: .completed,
    completedAt: "2026-04-05T20:00:00Z")
  let doneB = try await importHistoricalTask(
    title: "Done B", priority: .p1, status: .completed,
    completedAt: "2026-04-05T08:00:00Z")
  _ = try await importHistoricalTask(
    title: "Done other day", priority: .p1, status: .completed,
    completedAt: "2026-04-04T20:00:00Z")
  _ = try await importHistoricalTask(
    title: "Due open", priority: .p2, status: .open,
    dueDate: dueDate, createdAt: "2026-04-05T09:00:00Z")

  // Seed habit fixtures: the Daily Review habit (target 1) met the day's
  // target; the Evening walk habit (target 1) logged nothing.
  _ = try await core.completeHabit(id: LorvexPreviewSeedID.dailyReviewHabit, date: day)

  // A same-day event plus a multi-day event spanning the day.
  _ = try await core.createCalendarEvent(
    title: "Same day", startDate: day, endDate: day, startTime: nil, endTime: nil,
    allDay: true, location: nil, notes: nil, recurrence: nil, timezone: nil, url: nil,
    color: nil, eventType: nil, personName: nil, attendees: nil)
  _ = try await core.createCalendarEvent(
    title: "Spanning", startDate: "2026-04-03", endDate: "2026-04-07", startTime: nil,
    endTime: nil, allDay: true, location: nil, notes: nil, recurrence: nil, timezone: nil,
    url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)

  let summary = try await core.loadDaySummary(date: day, completedLimit: 5)

  #expect(summary.date == day)
  #expect(summary.completedCount == 2)
  // Canonical sort puts P1 (Done B) before P2 (Done A).
  #expect(summary.topCompleted.map(\.id) == [doneB.id, doneA.id])
  #expect(summary.createdCount == 1)
  #expect(summary.dueOpenCount == 1)
  #expect(summary.habitsTotal == 2)
  #expect(summary.habitsCompleted == 1)
  #expect(summary.eventCount == 2)
}

@MainActor
@Test
func appStoreSelectReviewDayLoadsDayEvidence() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // Today's evidence is loaded on refresh.
  #expect(store.dayReviewEvidence != nil)
  #expect(store.selectedReviewDate == AppStore.todayDateString())
  #expect(store.selectedReviewDayIsEditable)

  // Selecting today's date keeps the editor editable and reloads evidence.
  let today = AppStore.todayDateString()
  await store.selectReviewDay(today)
  #expect(store.selectedReviewDate == today)
  #expect(store.selectedReviewDayIsEditable)
  #expect(store.dayReviewEvidence?.date == today)
}

@MainActor
@Test
func appStoreSelectingOldDayIsReadOnly() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // A day well outside the 7-day write window is read-only: the editing anchor
  // stays nil while the selected date points at the old day.
  let old = LorvexDateFormatters.ymdUTCAddingDays(AppStore.todayDateString(), days: -30)!
  await store.selectReviewDay(old)

  #expect(store.selectedReviewDate == old)
  #expect(!store.selectedReviewDayIsEditable)
  #expect(store.dailyReviewEditingDate == nil)
  #expect(store.dayReviewEvidence?.date == old)
}

@MainActor
@Test
func appStoreLoadWeekReviewDigestWindowsToTheWeek() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // The live week's digest is the trailing seven days ending today; the seeded
  // 2026-05-22 review is outside that window, so the live digest is empty.
  await store.loadWeekReviewDigest(weekOf: nil)
  #expect(
    store.weekReviewDigest.allSatisfy {
      $0.date >= LorvexDateFormatters.ymdUTCAddingDays(AppStore.todayDateString(), days: -6)!
    })

  // Anchoring the week on the seeded review's date includes it in the digest.
  await store.loadWeekReviewDigest(weekOf: "2026-05-22")
  #expect(store.weekReviewDigest.contains { $0.date == "2026-05-22" })
}

@MainActor
@Test
func appStoreDailyReviewKeepsMoodUnsetWhenNotRated() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // An untouched rating must persist as nil — no fabricated middle value.
  store.dailyReviewMood = nil
  store.dailyReviewEnergy = nil
  store.dailyReviewSummaryDraft = "No ratings today."
  await store.saveDailyReviewDraft()

  #expect(store.dailyReview?.summary == "No ratings today.")
  #expect(store.dailyReview?.mood == nil)
  #expect(store.dailyReview?.energyLevel == nil)
  #expect(store.errorMessage == nil)
}

/// The autosave fires after a pause, which can come right after a space or a
/// line break. The save stores a body section trimmed, and the editor must not
/// take the whitespace out of what the user is typing in response.
@MainActor
@Test
func appStoreDailyReviewAutosaveKeepsWhitespaceTypedAtTheEndOfASection() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  store.dailyReviewSummaryDraft = "Good day "
  store.dailyReviewWinsDraft = "Shipped the launch "
  store.dailyReviewBlockersDraft = "Waiting on legal\n"
  store.dailyReviewLearningsDraft = "Ask earlier "
  await store.saveDailyReviewDraft()

  #expect(store.dailyReview?.summary == "Good day")
  #expect(store.dailyReview?.wins == "Shipped the launch")
  #expect(store.dailyReview?.blockers == "Waiting on legal")
  #expect(store.dailyReviewSummaryDraft == "Good day ")
  #expect(store.dailyReviewWinsDraft == "Shipped the launch ")
  #expect(store.dailyReviewBlockersDraft == "Waiting on legal\n")
  #expect(store.dailyReviewLearningsDraft == "Ask earlier ")
  // The whitespace is not an unsaved edit: Quit has nothing left to wait for,
  // and a refresh that adopts the loaded review leaves the text alone.
  #expect(store.dailyReviewDraftMatchesLoaded)
  #expect(!store.hasPendingAutosaveDraftForTermination)
  await store.refresh()
  #expect(store.dailyReviewWinsDraft == "Shipped the launch ")
  #expect(store.dailyReviewBlockersDraft == "Waiting on legal\n")
}

/// Space or a line break typed into the empty note of a day is not a review:
/// nothing is saved, so the day does not gain an entry with no words in it.
@MainActor
@Test
func appStoreDailyReviewBlankNoteDoesNotCreateAnEntry() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()

  store.dailyReviewSummaryDraft = "  \n"
  #expect(store.dailyReviewDraftMatchesLoaded)
  await store.flushDailyReviewDraftIfNeeded()

  #expect(try await core.loadDailyReview(date: store.dailyReviewEditorDate) == nil)
  #expect(store.dailyReview == nil)
}

/// Whitespace left in a section is kept only for the day it was typed on:
/// opening another day shows that day's entry exactly, a blank section blank.
@MainActor
@Test
func appStoreDailyReviewDaySwitchReplacesTheEditorTextExactly() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let yesterday = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(store.dailyReviewEditorDate, days: -1))

  store.dailyReviewWinsDraft = "   "
  #expect(store.dailyReviewDraftMatchesLoaded)
  await store.selectReviewDay(yesterday)

  #expect(store.selectedReviewDate == yesterday)
  #expect(store.dailyReviewWinsDraft.isEmpty)
}

/// Text typed while the write is in flight is not in the saved entry. It stays
/// in the editor as an unsaved edit that the next save picks up.
@MainActor
@Test
func appStoreDailyReviewSaveKeepsTextTypedWhileItRuns() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let gate = ReviewGate()
  core.upsertDailyReviewGate = { await gate.hold() }
  let store = AppStore(core: core)
  await store.refresh()

  store.dailyReviewSummaryDraft = "First"
  let save = Task { await store.saveDailyReviewDraft() }
  await gate.waitUntilHeld()
  store.dailyReviewSummaryDraft = "First and more"
  await gate.release()
  await save.value

  let stored = try await core.loadDailyReview(date: store.dailyReviewEditorDate)
  #expect(stored?.summary == "First")
  #expect(store.dailyReviewSummaryDraft == "First and more")
  #expect(!store.dailyReviewDraftMatchesLoaded)

  await store.saveDailyReviewDraft()

  #expect(store.dailyReview?.summary == "First and more")
  #expect(store.dailyReviewDraftMatchesLoaded)
}

/// A save belongs to the day the editor was on when it started. Moving the
/// editor to another day while it runs must not show this entry as that day's.
@MainActor
@Test
func appStoreDailyReviewSaveDoesNotLandOnADayTheEditorMovedOffDuringIt() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let gate = ReviewGate()
  core.upsertDailyReviewGate = { await gate.hold() }
  let store = AppStore(core: core)
  await store.refresh()
  let today = store.dailyReviewEditorDate
  let yesterday = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: -1))

  store.dailyReviewSummaryDraft = "Written on the day that was open"
  let save = Task { await store.saveDailyReviewDraft() }
  await gate.waitUntilHeld()
  store.selectedReviewDate = yesterday
  await gate.release()
  await save.value

  #expect(try await core.loadDailyReview(date: today)?.summary == "Written on the day that was open")
  #expect(store.dailyReview == nil)
}

/// A refresh reads the loaded review before it adopts it. Text typed in between
/// is not in that read, so it stays in the editor as an unsaved edit.
@MainActor
@Test
func appStoreRefreshKeepsTextTypedWhileItReadsTheReview() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core)
  await store.refresh()
  store.dailyReviewSummaryDraft = "Saved text"
  await store.saveDailyReviewDraft()
  #expect(store.dailyReviewDraftMatchesLoaded)

  let gate = ReviewGate()
  core.loadDailyReviewGate = { await gate.hold() }
  let refresh = Task { await store.refresh() }
  await gate.waitUntilHeld()
  core.loadDailyReviewGate = nil
  store.dailyReviewSummaryDraft = "Saved text and more"
  await gate.release()
  await refresh.value

  #expect(store.dailyReviewSummaryDraft == "Saved text and more")
  #expect(!store.dailyReviewDraftMatchesLoaded)
}

/// A refresh that read one day must not put that day into an editor that has
/// since moved to another one.
@MainActor
@Test
func appStoreRefreshDoesNotAdoptADayTheEditorMovedOffDuringIt() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core)
  await store.refresh()
  let yesterday = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(store.dailyReviewEditorDate, days: -1))
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
  #expect(store.dailyReviewSummaryDraft == "Yesterday's note")
  #expect(store.dayReviewEvidence?.date == yesterday)
}

/// Two day selections overlap when the first one's read is slow. The editor
/// belongs to the day selected last, whichever read finishes last.
@MainActor
@Test
func appStoreDaySwitchDropsASlowerReadOfADayTheEditorLeft() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core)
  await store.refresh()
  let today = store.dailyReviewEditorDate
  let dayA = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: -1))
  let dayB = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: -2))
  for (date, text) in [(dayA, "Note of A"), (dayB, "Note of B")] {
    _ = try await core.upsertDailyReview(
      date: date, summary: text, mood: nil, energyLevel: nil, wins: nil, blockers: nil,
      learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
  }

  let gate = ReviewGate()
  core.loadDailyReviewGate = { await gate.hold() }
  let first = Task { await store.selectReviewDay(dayA) }
  await gate.waitUntilHeld()
  core.loadDailyReviewGate = nil
  await store.selectReviewDay(dayB)
  await gate.release()
  await first.value

  #expect(store.selectedReviewDate == dayB)
  #expect(store.dailyReview?.summary == "Note of B")
  #expect(store.dailyReviewSummaryDraft == "Note of B")
  #expect(store.dayReviewEvidence?.date == dayB)
}

/// "Back to Today" selects today like any other day, so the day's evidence moves
/// with the entry instead of staying on the day that was open.
@MainActor
@Test
func appStoreBackToTodayLoadsTodaysEvidence() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let today = store.dailyReviewEditorDate
  let yesterday = try #require(LorvexDateFormatters.ymdUTCAddingDays(today, days: -1))
  await store.selectReviewDay(yesterday)
  #expect(store.dailyReviewEditingDate == yesterday)
  #expect(store.dayReviewEvidence?.date == yesterday)

  await store.endEditingDailyReview()

  #expect(store.selectedReviewDate == today)
  #expect(store.dailyReviewEditingDate == nil)
  #expect(store.dayReviewEvidence?.date == today)
}

@MainActor
@Test
func appStoreRefreshReloadsMemoryWithoutClobberingComposerDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  await store.loadMemory()
  let editing = try #require(store.memoryEntries.first)
  store.beginEditingMemory(editing)
  store.memoryContentDraft = "unsaved composer text"

  _ = try await core.upsertMemory(key: "peer_added", content: "Written by another surface")
  await store.refresh()

  #expect(store.memoryEntries.contains { $0.key == "peer_added" })
  #expect(store.memoryEditingKey == editing.key)
  #expect(store.memoryKeyDraft == editing.key)
  #expect(store.memoryContentDraft == "unsaved composer text")
}

@MainActor
@Test
func appStoreDeletingTheEntryBeingEditedResetsTheComposer() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  await store.loadMemory()
  let editing = try #require(store.memoryEntries.first)
  store.beginEditingMemory(editing)
  store.memoryContentDraft = "unsaved composer text"

  let deleted = await store.deleteMemoryEntry(editing)

  #expect(deleted)
  #expect(store.memoryEntries.contains { $0.key == editing.key } == false)
  #expect(store.memoryEditingKey == nil)
  #expect(store.memoryKeyDraft.isEmpty)
  #expect(store.memoryContentDraft.isEmpty)
}

@MainActor
@Test
func appStoreDeletingAnotherEntryKeepsTheComposerDraft() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core)
  await store.refresh()
  await store.loadMemory()
  let editing = try #require(store.memoryEntries.first)
  let other = try #require(store.memoryEntries.first { $0.key != editing.key })
  store.beginEditingMemory(editing)
  store.memoryContentDraft = "unsaved composer text"

  let deleted = await store.deleteMemoryEntry(other)

  #expect(deleted)
  #expect(store.memoryEditingKey == editing.key)
  #expect(store.memoryContentDraft == "unsaved composer text")
}

/// The daily review's still-open rows complete their task in place: on the
/// Review page the task moves from Still open to What moved forward, and ⌘Z
/// moves it back.
@MainActor
@Test
func appStoreCompletingAStillOpenTaskOnReviewMovesItBetweenTheDaysLists() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let today = AppStore.todayDateString()
  let created = try await core.createTask(title: "Due today", notes: "")
  _ = try await core.updateTask(
    id: created.id, title: created.title, notes: "", priority: created.priority,
    estimatedMinutes: nil, dueDate: LorvexDateFormatters.ymdUTC.date(from: today),
    plannedDate: nil, availableFrom: nil, tags: [], dependsOn: [])
  let store = AppStore(core: core)
  await store.refresh()
  store.selection = .reviews
  await store.selectReviewDay(today)
  #expect(store.dayReviewEvidence?.dueOpenTasks.map(\.id) == [created.id])

  let undoManager = UndoManager()
  await store.completeTask(id: created.id, undoManager: undoManager)

  #expect(store.dayReviewEvidence?.dueOpenTasks.isEmpty == true)
  #expect(store.dayReviewEvidence?.topCompleted.map(\.id) == [created.id])
  #expect(store.selectedTaskID == nil)

  await store.reopenTaskForUndo(created.id)
  #expect(store.dayReviewEvidence?.dueOpenTasks.map(\.id) == [created.id])
}

/// The week review's overdue rows complete their task in place too: the task
/// leaves the overdue list without the page reloading by hand.
@MainActor
@Test
func appStoreCompletingAnOverdueTaskOnReviewDropsItFromTheWeek() async throws {
  let core = try SwiftLorvexCoreService.inMemory()
  let yesterday = LorvexDateFormatters.ymdUTCAddingDays(AppStore.todayDateString(), days: -1)!
  let created = try await core.createTask(title: "Overdue", notes: "")
  _ = try await core.updateTask(
    id: created.id, title: created.title, notes: "", priority: created.priority,
    estimatedMinutes: nil, dueDate: LorvexDateFormatters.ymdUTC.date(from: yesterday),
    plannedDate: nil, availableFrom: nil, tags: [], dependsOn: [])
  let store = AppStore(core: core)
  await store.refresh()
  store.selection = .reviews
  await store.loadWeeklyReview(weekOf: nil)
  #expect(store.weeklyReview?.overdueTasks.map(\.id) == [created.id])

  await store.completeTask(id: created.id)

  #expect(store.weeklyReview?.overdueTasks.isEmpty == true)
}
