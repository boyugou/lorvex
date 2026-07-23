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
  // All four seeded tasks (someday included) were created this week; the
  // Today pool carries only the three open ones.
  #expect(store.weeklyReview?.createdThisWeek == 4)
  #expect(store.weeklyReview?.completedThisWeek == 0)
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
