import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing
import LorvexCloudSync

@testable import LorvexApple

@MainActor
@Test
func appStoreLoadsPreviewToday() async throws {
  let indexer = RecordingTaskSearchIndexer()
  let publisher = RecordingWidgetSnapshotPublisher()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    taskSearchIndexer: indexer,
    widgetSnapshotPublisher: publisher
  )

  await store.refresh()

  #expect(store.today.focusTitle == "Today")
  #expect(!store.today.tasks.isEmpty)
  #expect(store.weeklyReview != nil)
  #expect(store.lists?.lists.isEmpty == false)
  #expect(store.habits?.habits.isEmpty == false)
  #expect(store.runtimeDiagnostics?.setup.setupCompleted == true)
  // Spotlight indexes the full task corpus (4 seeded tasks, someday included);
  // the Today snapshot carries only the open top-by-priority pool (3).
  #expect(store.lastSpotlightIndexedTaskCount == 4)
  #expect(store.today.tasks.count == 3)
  #expect(store.lastSpotlightIndexedCalendarEventCount > 0)
  #expect(store.lastPublishedWidgetSnapshot?.version == WidgetSnapshot.supportedVersion)
  #expect(store.lastPublishedWidgetSnapshot?.focusTasks.isEmpty == false)
  #expect(store.lastPublishedWidgetSnapshot?.lists.map(\.id) == store.lists?.lists.map(\.id))
  // Sync runs invisibly through the engine coordinator; with the preview core
  // (no envelope-sync support) and no CK container, no cycle report is produced.
  #expect(store.lastCloudSyncCycleReport == nil)
  let indexedCalendarEvents = store.lastSpotlightIndexedCalendarEventCount
  let diagnostics = store.appleSurfaceDiagnostics
  #expect(
    diagnostics.spotlightStatus
    == "4 tasks, \(indexedCalendarEvents) calendar event\(indexedCalendarEvents == 1 ? "" : "s")"
  )
  #expect(diagnostics.reminderStatus == "Disabled")
  // No EventKit coordinator is wired in this preview store, so no ingest runs
  // and the import status stays at its initial "Not started".
  #expect(diagnostics.calendarImportStatus == "Not started")
  #expect(diagnostics.widgetStatus == "Published v\(WidgetSnapshot.supportedVersion)")
  #expect(diagnostics.widgetFocusTaskCount == 3)
  #expect(diagnostics.widgetGeneratedAt == "2026-05-22T16:00:00Z")
  #expect(await indexer.lastIndexedIDs().count == store.lastSpotlightIndexedTaskCount)
  #expect(publisher.publishedSnapshots().count == 1)
}

@MainActor
@Test
func appStoreCreateTaskInListLandsInListWithoutNavigating() async throws {
  let core = try await makeSeededInMemoryCore()
  // Isolated defaults: `selection` persists, and writing it through `.standard`
  // would leak into every parallel test that reads the restored navigation.
  let suiteName = "AppStoreCreateTaskInList.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()
  store.selection = .lists
  let targetList = try #require(store.lists?.lists.first)
  store.selectedListID = targetList.id
  try await store.loadSelectedListDetail()

  await store.createTaskInList(title: "  Inline quick add  ", listID: targetList.id)

  #expect(store.errorMessage == nil)
  #expect(store.selection == .lists, "inline add must not navigate away")
  let detail = try #require(store.selectedListDetail)
  #expect(detail.tasks.contains { $0.title == "Inline quick add" })

  // Whitespace-only input is a silent no-op.
  let countBefore = store.selectedListDetail?.tasks.count
  await store.createTaskInList(title: "   ", listID: targetList.id)
  #expect(store.selectedListDetail?.tasks.count == countBefore)
}

@MainActor
@Test
func appStoreClearsSelectedTaskAssistantContext() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Context task", notes: "")
  _ = try await core.setTaskAINotes(taskID: task.id, notes: "Temporary assistant context")
  let store = AppStore(core: core)

  await store.refresh()
  store.selectTaskFromList(task.id)
  await store.loadSelectedTaskDetail()
  #expect(store.selectedTask?.aiNotes == "Temporary assistant context")

  await store.clearSelectedTaskAINotes()

  #expect(store.selectedTask?.aiNotes == nil)
  let reloaded = try await core.loadTask(id: task.id)
  #expect(reloaded.aiNotes == nil)
}

@MainActor
@Test
func appStoreCreateTaskPlannedTodayLandsInTodayWithoutNavigating() async throws {
  let core = try await makeSeededInMemoryCore()
  let suiteName = "AppStoreCreateTaskPlannedToday.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()
  store.selection = .today

  await store.createTaskPlannedToday(title: "  Plan me for today  ")

  #expect(store.errorMessage == nil)
  #expect(store.selection == .today, "inline add must not navigate away")
  let created = try #require(store.today.tasks.first { $0.title == "Plan me for today" })
  #expect(created.plannedDate != nil, "the quick-added task is planned for today")
}

@MainActor
@Test
func appStoreReschedulesScheduledTaskToAnotherDay() async throws {
  let core = try await makeSeededInMemoryCore()
  let suiteName = "AppStoreRescheduleScheduledTask.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()
  await store.createTaskPlannedToday(title: "Drag me to tomorrow")
  let task = try #require(store.calendarScheduledTasks?.first { $0.title == "Drag me to tomorrow" })

  let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
  await store.rescheduleScheduledTask(id: task.id, to: tomorrow)

  #expect(store.errorMessage == nil)
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.timeZone = TimeZone.current
  let tomorrowYmd = formatter.string(from: tomorrow)
  let onTomorrow = try await core.getScheduledTasks(from: tomorrowYmd, to: tomorrowYmd, limit: 50)
  #expect(onTomorrow.contains { $0.id == task.id })
}

@MainActor
@Test
func appStoreWeeklyReviewNavigationAnchorsAndClamps() async throws {
  let suiteName = "AppStoreWeeklyReviewNavigation.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  #expect(store.isViewingCurrentWeek)
  let currentTitle = store.weeklyReview?.windowTitle

  await store.stepWeeklyReview(byWeeks: -1)
  #expect(!store.isViewingCurrentWeek)
  let anchor = try #require(store.weeklyReviewAnchor)
  #expect(store.weeklyReview?.windowTitle.contains(anchor) == true)
  #expect(store.weeklyReview?.windowTitle != currentTitle)

  // A full refresh keeps the viewed week.
  await store.refresh()
  #expect(store.weeklyReviewAnchor == anchor)

  // Stepping forward from one week back clamps to the live week.
  await store.stepWeeklyReview(byWeeks: 1)
  #expect(store.isViewingCurrentWeek)
}

@MainActor
@Test
func appStoreEditsRecentDailyReviewWithinWindow() async throws {
  let suiteName = "AppStoreEditsRecentDailyReview.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  let yesterday = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(AppStore.todayDateString(), days: -1))
  _ = try await core.importDailyReview(
    date: yesterday, summary: "Yesterday's reflection", mood: 2, energyLevel: 2,
    wins: nil, blockers: nil, learnings: nil)
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()

  await store.beginEditingDailyReview(date: yesterday)
  #expect(store.dailyReviewEditingDate == yesterday)
  #expect(store.dailyReviewSummaryDraft == "Yesterday's reflection")

  // Edits save onto the anchored day, not today.
  store.dailyReviewSummaryDraft = "Amended later"
  await store.saveDailyReviewDraft()
  #expect(store.errorMessage == nil)
  let saved = try await core.loadDailyReview(date: yesterday)
  #expect(saved?.summary == "Amended later")

  // A full refresh keeps the anchor; returning home clears it.
  await store.refresh()
  #expect(store.dailyReviewEditingDate == yesterday)
  await store.endEditingDailyReview()
  #expect(store.dailyReviewEditingDate == nil)

  // Days outside the write window never anchor.
  await store.beginEditingDailyReview(date: "2020-01-01")
  #expect(store.dailyReviewEditingDate == nil)
}

@MainActor
@Test
func appStoreWorkingHoursPreferenceRoundTripsAndValidates() async throws {
  let suiteName = "AppStoreWorkingHoursPreference.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, defaults: defaults)

  #expect(await store.saveWorkingHoursPreference(start: "08:30", end: "16:15"))
  let loaded = await store.loadWorkingHoursPreference()
  #expect(loaded.start == "08:30")
  #expect(loaded.end == "16:15")

  // The schedule proposal sees the saved window.
  let task = try await core.createTask(title: "Working hours probe", notes: "")
  _ = try await core.setCurrentFocus(
    date: "2026-03-06", taskIDs: [task.id], briefing: nil,
    timezone: TimeZone.current.identifier)
  let proposal = try await core.proposeFocusSchedule(date: "2026-03-06")
  #expect(proposal.workingHours?.start == "08:30")

  // An inverted window is rejected and never persisted.
  #expect(await store.saveWorkingHoursPreference(start: "18:00", end: "09:00") == false)
  #expect(store.errorMessage != nil)
  let unchanged = await store.loadWorkingHoursPreference()
  #expect(unchanged.start == "08:30")
}

@MainActor
@Test
func appStoreMirrorsWizardCompletionIntoCoreSetupState() async throws {
  let suiteName = "AppStoreSetupCompletion.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, defaults: defaults)

  await store.markCoreSetupComplete()
  #expect(store.errorMessage == nil)
  #expect(try await core.getPreference(key: "setup_completed") == "true")
  // The seeded preview core already carries working hours; completion must
  // not overwrite an existing window.
  #expect(
    try await core.getPreference(key: "working_hours")
      == #"{"end":"17:00","start":"09:00"}"#)

  // With no stored window, completion seeds the engine default.
  _ = try await core.deletePreference(key: "working_hours")
  await store.markCoreSetupComplete()
  #expect(
    try await core.getPreference(key: "working_hours")
      == #"{"end":"18:00","start":"09:00"}"#)
}

actor RecordingHabitReminderScheduler: HabitReminderScheduling {
  private var occurrences: [[DueHabitReminderOccurrence]] = []
  func replacements() -> [[DueHabitReminderOccurrence]] { occurrences }
  func replaceScheduledHabitReminders(
    for occurrences: [DueHabitReminderOccurrence]
  ) async -> TaskReminderScheduleReport {
    self.occurrences.append(occurrences)
    return .scheduled(occurrences.count)
  }
}

@MainActor
@Test
func appStoreRefreshReplansHabitReminders() async throws {
  let suiteName = "AppStoreHabitReminders.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  let habit = try await core.createHabit(name: "Hydrate", cue: nil, targetCount: 1)
  _ = try await core.upsertHabitReminderPolicy(
    id: habit.id,
    // An empty policy id is the create form; a non-empty id must already exist.
    policy: HabitReminderPolicy(
      id: "", habitID: habit.id, habitName: habit.name,
      reminderTime: "08:00", enabled: true, createdAt: "", updatedAt: ""))
  let scheduler = RecordingHabitReminderScheduler()
  let store = AppStore(core: core, habitReminderScheduler: scheduler, defaults: defaults)

  await store.refresh()

  let last = try #require(await scheduler.replacements().last)
  #expect(last.contains { $0.policy.habitID == habit.id && $0.policy.reminderTime == "08:00" })
  #expect(store.lastHabitReminderScheduleReport.scheduledCount == last.count)
}

@MainActor
@Test
func appStoreRefreshFailureClearsStaleLoadedState() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let publisher = RecordingWidgetSnapshotPublisher()
  let suiteName = "AppStoreRefreshFailureClearsStaleLoadedState.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(
    core: core,
    widgetSnapshotPublisher: publisher,
    defaults: defaults
  )

  await store.refresh()
  let staleTaskID = try #require(store.today.tasks.first?.id)
  store.selectedTaskID = staleTaskID

  #expect(!store.today.tasks.isEmpty)
  #expect(store.selectedTask?.id == staleTaskID)
  #expect(store.lists != nil)
  #expect(store.selectedListID != nil)
  #expect(store.selectedListDetail != nil)
  #expect(store.habits != nil)
  #expect(store.calendarTimeline != nil)
  #expect(store.calendarScheduledTasks != nil)
  #expect(store.lastPublishedWidgetSnapshot != nil)

  core.loadTodayError = .unsupportedOperation("macOS refresh unavailable.")
  await store.refresh()

  #expect(store.today == .empty)
  #expect(store.currentFocus == nil)
  #expect(store.focusSchedule == nil)
  #expect(store.dailyReview == nil)
  #expect(store.weeklyReview == nil)
  #expect(store.lists == nil)
  #expect(store.selectedListID == nil)
  #expect(store.selectedListDetail == nil)
  #expect(store.habits == nil)
  #expect(store.calendarTimeline == nil)
  #expect(store.calendarScheduledTasks == nil)
  #expect(store.selectedTaskID == nil)
  #expect(store.lastPublishedWidgetSnapshot == nil)
  #expect(store.errorMessage == "macOS refresh unavailable.")
}

@MainActor
@Test
func appStoreRefreshClearsStaleTodayInspectorSelection() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let suiteName = "AppStoreRefreshClearsStaleTodayInspectorSelection.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: core, defaults: defaults)

  await store.refresh()
  let staleTask = try #require(store.today.tasks.first)
  store.taskDetailStorage.loadedTasksByID[staleTask.id] = staleTask
  store.selectedTaskID = staleTask.id

  core.todayOverride = TodaySnapshot(
    focusTitle: "Today",
    summary: "All clear for today",
    tasks: [],
    localChangeSequence: 42
  )

  await store.refresh()

  #expect(store.selection == .today)
  #expect(!store.hasVisibleTodayTasks)
  #expect(store.selectedTaskID == nil)
}

@MainActor
@Test
func reviewsNavigationClearsTaskInspectorSelection() async throws {
  let suiteName = "ReviewsNavigationClearsTaskInspectorSelection.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  store.selectedTaskID = try #require(store.today.tasks.first?.id)

  store.selection = .reviews

  #expect(store.selectedTaskID == nil)
}

@Test
func lorvexCoreRuntimeFactorySelectsSharedAppleRuntimeFromEnvironment() {
  // Production default (no/unknown override) is the on-disk Swift core.
  #expect(LorvexCoreRuntimeFactory.make(environment: [:]) is SwiftLorvexCoreService)
  #expect(
    LorvexCoreRuntimeFactory.make(environment: [
      "LORVEX_APPLE_CORE": "swift",
      "LORVEX_APPLE_DB_PATH": "/tmp/lorvex-mobile.db",
    ]) is SwiftLorvexCoreService)
  // `LORVEX_APPLE_CORE` never selects a fixture; tests construct fixtures directly.
  #expect(
    LorvexCoreRuntimeFactory.make(environment: ["LORVEX_APPLE_CORE": "inmemory"])
      is SwiftLorvexCoreService)
  #expect(
    LorvexCoreRuntimeFactory.make(environment: ["LORVEX_APPLE_CORE": "preview"])
      is SwiftLorvexCoreService)
}

@MainActor
@Test
func appStoreLoadsRuntimeDiagnostics() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())

  await store.refresh()

  #expect(store.runtimeDiagnostics?.sync.backend == "unknown")
}

@MainActor
@Test
func appStoreDiagnosticsReloadFailureSurfacesError() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = AppStore(core: core)

  core.loadRuntimeDiagnosticsError = .unsupportedOperation("Diagnostics unavailable.")

  await store.loadRuntimeDiagnostics()

  #expect(store.errorMessage == "Diagnostics unavailable.")
}

@MainActor
@Test
func replaceCorePropagatesNewCoreToDetachedWindowStores() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()
  let first = try #require(store.today.tasks.first)

  let detached = store.makeDetachedWindowStore()
  await detached.loadDetachedTaskWindow(taskID: first.id)

  let newCore = try await makeSeededInMemoryCore()
  await store.replaceCore(newCore)

  // The detached window store adopted the new database instead of continuing to
  // write to the old one. (Identity computed outside `#expect` to avoid a
  // swift-frontend crash expanding an `as AnyObject` cast inside the macro.)
  let adoptedNewCore =
    ObjectIdentifier(detached.core as AnyObject) == ObjectIdentifier(newCore as AnyObject)
  #expect(adoptedNewCore)
}

@MainActor
@Test
func startLifetimeObserversStartsObserversOnceAndIsIdempotent() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  #expect(store.lifetimeObserverTasks.isEmpty)

  store.startLifetimeObserversIfNeeded()
  // Remote-change, EventKit, notification-action-error, app-activation, unified
  // database-change, CloudKit-account-change, and calendar-day-change observers;
  // plus the one-shot interrupted CloudKit deletion-cleanup retry.
  #expect(store.lifetimeObserverTasks.count == 8)

  // A second call (e.g. the main window reopening) must not double-start.
  store.startLifetimeObserversIfNeeded()
  #expect(store.lifetimeObserverTasks.count == 8)

  for task in store.lifetimeObserverTasks { task.cancel() }
}
