import Foundation
import LorvexCore
import LorvexWidgetKitSupport
import Testing

@testable import LorvexApple

// MARK: - Item 6: deferSelectedTask throws instead of silently deferring to today

// We cannot easily intercept the Calendar.date(byAdding:) return value from outside,
// but we can verify the happy path works and that the function surface throws errors.
@MainActor
@Test
func deferSelectedTaskSucceedsWithInMemoryCore() async throws {
  let suiteName = "DeferSelectedTaskSucceedsWithInMemoryCore.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    now: { Date(timeIntervalSince1970: 1_779_649_200) },
    defaults: defaults
  )

  await store.refresh()
  let tomorrow = try #require(
    LorvexDateFormatters.ymdUTCAddingDays(store.logicalTodayDateString, days: 1))
  let taskID = try #require(store.today.tasks.first?.id)
  store.selectedTaskID = taskID

  await store.deferSelectedTask()
  let deferred = store.today.tasks.first { $0.id == taskID }

  // No error should be set on happy path.
  #expect(store.errorMessage == nil)
  // Planned dates are storage-frame (a naive day at UTC midnight), so the
  // deferred day must read back through the UTC formatter: tomorrow in the
  // synced product calendar, regardless of the machine timezone. Deferral
  // writes planned_date and keeps the task open.
  #expect(deferred?.status == .open)
  #expect(deferred?.plannedDate.map(LorvexDateFormatters.ymdUTC.string(from:)) == tomorrow)
}

@MainActor
@Test
func refreshDoesNotAutoSelectFirstTaskAfterInspectorDismissal() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  #expect(store.dismissOpenInspector() == true)
  #expect(store.selectedTaskID == nil)
  #expect(store.selectedTask == nil)

  await store.refresh()

  #expect(store.selectedTaskID == nil)
  #expect(store.selectedTask == nil)
}

@MainActor
@Test
func taskWorkspaceRangeSelectionUsesVisibleOrderedIDs() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  store.selection = .today
  store.selectedTaskID = "open-a"
  store.setTaskWorkspaceSelection(["open-a", "hidden-backlog"])

  store.setTaskWorkspaceVisibleOrderedTaskIDs(["open-a", "deferred-a", "completed-a"])
  store.extendTaskSelection(on: .taskWorkspace, to: "completed-a")

  #expect(store.taskWorkspaceSelectedTaskIDs == ["open-a", "deferred-a", "completed-a"])
  #expect(!store.taskWorkspaceSelectedTaskIDs.contains("hidden-backlog"))
}

// MARK: - Item 3: EventKit observer records errors into lastCalendarImportReport

// Direct test of the error surface: when refreshCalendarTimeline throws, the
// observer must record a failed report rather than silently ignoring the error.
// We can verify this indirectly by checking that lastCalendarImportReport is
// populated after a failing import.
@MainActor
@Test
func calendarTimelineRefreshWithFailingImporterRecordsDiagnostic() async throws {
  let access = FakeEventKitAccess()
  await access.setReadAccessGranted(false)
  let coordinator = EventKitCoordinator(
    access: access, provider: FakeEventKitProvider(),
    loadAccessMode: { .busyOnly }, isEnabled: { true })
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    eventKitCoordinator: coordinator
  )

  // After refresh the ingest should fail (read denied) but be recorded.
  await store.refresh()

  #expect(store.lastCalendarImportReport.status == .failed)
}

// MARK: - Item 9: exportCalendarICS routes through AppStore (not store.core directly)

@MainActor
@Test
func exportCalendarICSVigorouslyRoutedThroughStore() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  guard let from = store.calendarTimeline?.from,
    let to = store.calendarTimeline?.to
  else {
    Issue.record("calendarTimeline not loaded")
    return
  }

  // The store.exportCalendarICS method now routes through store.core; ensure it
  // returns a non-empty ICS string without throwing.
  let ics = try await store.exportCalendarICS(from: from, to: to)
  #expect(!ics.isEmpty)
}

@MainActor
@Test
func dismissOpenInspectorClosesTaskAndHabitPanels() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  await store.refresh()

  // Nothing open → Escape falls through (the helper reports no dismissal).
  store.selectedTaskID = nil
  #expect(store.dismissOpenInspector() == false)

  // Task inspector open → dismissed.
  let task = try #require(store.today.tasks.first)
  store.selectedTaskID = task.id
  #expect(store.dismissOpenInspector() == true)
  #expect(store.selectedTaskID == nil)

  // Habit inspector open → dismissed.
  store.selectedHabitID = "habit-under-test"
  #expect(store.dismissOpenInspector() == true)
  #expect(store.selectedHabitID == nil)
  #expect(store.errorMessage == nil)
}
