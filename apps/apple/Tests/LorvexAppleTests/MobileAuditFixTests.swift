import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

// MARK: - Item 3: selectedTask returns nil when no task is selected

@MainActor
@Test
func mobileStoreSelectedTaskIsNilWhenNoTaskIDIsSet() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  #expect(store.selectedTaskID == nil)
  #expect(store.selectedTask == nil)
}

@MainActor
@Test
func mobileStoreSelectedTaskAutoSelectsTheFirstTaskOnRefresh() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()

  // After refresh, selectedTaskID is auto-set to Today's first task when one
  // exists.
  if let first = store.snapshot.today.tasks.first {
    #expect(store.selectedTaskID == first.id)
    #expect(store.selectedTask?.id == first.id)
  }
}

@MainActor
@Test
func mobileStoreSelectedTaskResolvesCorrectTaskWhenIDIsSet() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()

  let task = try #require(store.snapshot.today.tasks.first)
  store.selectTask(task.id)
  #expect(store.selectedTask?.id == task.id)
}

@MainActor
@Test
func mobileTaskStatusMutationDoesNotReloadPlanningCorpus() async throws {
  let core = StubCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let task = try #require(store.snapshot.today.tasks.first)
  core.loadListsCallCount = 0
  core.loadHabitsCallCount = 0
  core.loadCalendarTimelineCallCount = 0
  core.listTasksCallCount = 0

  await store.completeTask(task.id)

  // Completed tasks leave the open-only Today snapshot.
  #expect(!store.snapshot.today.tasks.contains { $0.id == task.id })
  #expect(try await core.preview.loadTask(id: task.id).status == .completed)
  #expect(core.loadListsCallCount == 0)
  #expect(core.loadHabitsCallCount == 0)
  #expect(core.loadCalendarTimelineCallCount == 0)
  #expect(core.listTasksCallCount == 0)
  #expect(store.errorMessage == nil)
}

@MainActor
@Test
func mobileTaskStatusMutationPublishesWidgetSnapshot() async throws {
  let core = try await makeSeededInMemoryCore()
  let publisher = RecordingMobileWidgetSnapshotPublisher()
  let store = MobileStore(
    core: core,
    widgetSnapshotPublisher: publisher,
    todayString: { "2026-05-23" }
  )

  await store.refresh()
  let task = try #require(store.snapshot.today.tasks.first)
  _ = await publisher.publications

  await store.completeTask(task.id)

  let publications = await publisher.publications
  #expect(publications.count == 2)
  // The completed task leaves the open-only Today snapshot the widget mirrors.
  #expect(publications.last?.today.tasks.contains { $0.id == task.id } == false)
  #expect(try await core.loadTask(id: task.id).status == .completed)
}

// MARK: - Item 6: Deep-link to a shared destination resolves to its primary tab

@Test
func mobileDeepLinkToCalendarDestinationSetsMobileNavigationTarget() {
  let url = URL(string: "lorvex://calendar")!
  let route = MobileDeepLinkRoute(url: url)
  let target = route?.navigationTarget(resolvedFrom: url)

  #expect(target?.selectedTab == .calendar)
  #expect(target?.route == nil)
}

@Test
func mobileDeepLinkToListsDestinationSetsMobileNavigationTarget() {
  let url = URL(string: "lorvex://lists")!
  let route = MobileDeepLinkRoute(url: url)
  let target = route?.navigationTarget(resolvedFrom: url)

  // Lists is merged into the Tasks tab, so it selects that tab.
  #expect(target?.selectedTab == .tasks)
}

@Test
func mobileDeepLinkToTasksDestinationSetsMobileNavigationTarget() {
  let url = URL(string: "lorvex://tasks")!
  let route = MobileDeepLinkRoute(url: url)
  let target = route?.navigationTarget(resolvedFrom: url)

  #expect(target?.selectedTab == .tasks)
}

// MARK: - Item 7: openListActivity routes to the Tasks tab with the list pushed

@MainActor
@Test
func mobileStoreOpenNavigationTargetWithTasksRoutePushesTasksRoutePath() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  let target = MobileNavigationTarget(
    selectedTab: .tasks,
    route: nil,
    tasksRoute: .tasksScope(.list("list-42"))
  )
  store.openNavigationTarget(target)

  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.tasksScope(.list("list-42"))])
}

@Test
func mobileTodayScheduleListsEveryHoldOfTheDay() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let scheduleSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileTodayScheduleSheet.swift"),
    encoding: .utf8
  )
  let calmStateSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreTodayCalmState.swift"),
    encoding: .utf8
  )

  // Today's schedule draws the day's events and timed tasks as one timeline:
  // every event of the logical day, with no display cap and no link out to the
  // Calendar workspace standing in for the rest.
  #expect(scheduleSource.contains("let rows = store.todaySchedule"))
  #expect(scheduleSource.contains("MobileTodayScheduleTimelineSection(\n              store: store, items: rows"))
  #expect(!scheduleSource.contains("displayLimit"))
  #expect(!scheduleSource.contains("hiddenEventCount"))
  #expect(!scheduleSource.contains("openMoreDestination(.calendar)"))
  #expect(calmStateSource.contains("calendarTimeline?.eventsOccurring(on: logicalTodayString)"))
}

@Test
func mobileMemoryWorkspaceDoesNotClampFullCompactCatalogToFourEntries() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let memoryViewSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreMemoryView.swift"),
    encoding: .utf8
  )

  #expect(!memoryViewSource.contains("MobileStoreMemorySection(store: store)"))
  #expect(memoryViewSource.contains("private var compactBody: some View"))
  #expect(memoryViewSource.contains("regularList"))
  #expect(memoryViewSource.contains("if !isBatchSelecting"))
  #expect(!memoryViewSource.contains(".entries ?? []).prefix(4)"))
}

@Test
func mobileHabitsWorkspaceDoesNotClampFullCompactCatalogToFourHabits() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let habitSectionSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreHabitSection.swift"),
    encoding: .utf8
  )
  let habitsViewSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreHabitsView.swift"),
    encoding: .utf8
  )
  let todaySource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileTodayPage.swift"),
    encoding: .utf8
  )

  #expect(habitsViewSource.contains("MobileStoreHabitsSection("))
  #expect(!habitSectionSource.contains("displayLimit"))
  #expect(!habitSectionSource.contains(".prefix("))
  // Today shows every habit as a ring in one horizontal row.
  #expect(todaySource.contains("MobileHabitCompletionRing("))
}

// MARK: - Item 10: Single isMutatingCalendarEvent flag covers create, update, and delete

@MainActor
@Test
func mobileStoreCalendarMutatingFlagIsFalseInitially() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  #expect(store.isMutatingCalendarEvent == false)
}

@MainActor
@Test
func mobileStoreCalendarCreateSetsAndClearsMutatingFlag() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()

  store.calendarDraft.title = "Audit Flag Test"
  store.calendarDraft.date = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z") ?? Date()
  let created = await store.createDraftCalendarEvent()

  #expect(created)
  #expect(store.isMutatingCalendarEvent == false)
}

@MainActor
@Test
func mobileStoreCalendarUpdateSetsAndClearsMutatingFlag() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  let event = try await core.createCalendarEvent(
    title: "Flag update test",
    startDate: "2026-06-01",
    endDate: nil,
    startTime: nil,
    endTime: nil,
    allDay: true,
    location: nil,
    notes: nil
  )
  await store.refresh()
  store.prepareCalendarDraft(for: event)
  store.calendarDraft.title = "Updated flag test"

  let updated = await store.updateCalendarEvent(event)

  #expect(updated)
  #expect(store.isMutatingCalendarEvent == false)
}

// Moving an event's day through the single-day edit form must shift the stored
// end date with the start, preserving the span. Passing the core `nil` (preserve)
// would strand the original multi-day end, which then fails "end before start"
// moving the day forward (regression guard).
@MainActor
@Test
func mobileStoreCalendarDateEditShiftsStoredEndDate() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  let event = try await core.createCalendarEvent(
    title: "Multi-day move",
    startDate: "2026-06-01",
    endDate: "2026-06-03",
    startTime: nil,
    endTime: nil,
    allDay: true,
    location: nil,
    notes: nil
  )
  #expect(event.endDate == "2026-06-03")
  await store.refresh()
  store.prepareCalendarDraft(for: event)
  store.calendarDraft.date = try #require(LorvexDateFormatters.ymd.date(from: "2026-06-05"))

  let updated = await store.updateCalendarEvent(event)
  #expect(store.errorMessage == nil)
  #expect(updated)

  let timeline = try await core.loadCalendarTimeline(from: "2026-06-01", to: "2026-06-15")
  let moved = try #require(timeline.events.first { $0.eventID == event.eventID })
  #expect(moved.startDate == "2026-06-05")
  // The 2-day span rides along instead of stranding the end on 2026-06-03.
  #expect(moved.endDate == "2026-06-07")
}
