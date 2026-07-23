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
func mobileStoreSelectedTaskAutoSelectsNextTaskOnRefresh() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()

  // After refresh, selectedTaskID is auto-set to nextTask when one exists.
  if let nextTask = store.snapshot.nextTask {
    #expect(store.selectedTaskID == nextTask.id)
    #expect(store.selectedTask?.id == nextTask.id)
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
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })
  await store.refresh()
  let task = try #require(store.snapshot.openTasks.first)
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
  let task = try #require(store.snapshot.openTasks.first)
  _ = await publisher.publications

  await store.completeTask(task.id)

  let publications = await publisher.publications
  #expect(publications.count == 2)
  // The completed task leaves the open-only Today snapshot the widget mirrors.
  #expect(publications.last?.today.tasks.contains { $0.id == task.id } == false)
  #expect(try await core.loadTask(id: task.id).status == .completed)
}

// MARK: - Item 4: Tasks tab "All Tasks" section excludes nextTask

private func makeTask(id: String, status: LorvexTask.Status = .open) -> LorvexTask {
  LorvexTask(
    id: id, title: id, notes: "", priority: .p2, status: status, dueDate: nil,
    estimatedMinutes: nil, tags: [])
}

private func snapshotWith(tasks: [LorvexTask]) -> MobileHomeSnapshot {
  MobileHomeSnapshot(
    today: TodaySnapshot(focusTitle: "Today", summary: "", tasks: tasks, localChangeSequence: 0),
    currentFocus: nil,
    weeklyReview: nil
  )
}

@Test
func mobileHomeSnapshotNextTaskIsFirstFocusOrFirstOpenTask() {
  let task1 = makeTask(id: "t1")
  let task2 = makeTask(id: "t2")
  let snapshot = snapshotWith(tasks: [task1, task2])

  #expect(snapshot.nextTask?.id == "t1")
  #expect(snapshot.openTasks.count == 2)
}

@Test
func mobileHomeSnapshotOpenTasksAreFilteredByStatus() {
  let open = makeTask(id: "open")
  let done = makeTask(id: "done", status: .completed)
  let snapshot = snapshotWith(tasks: [open, done])

  #expect(snapshot.openTasks.count == 1)
  #expect(snapshot.openTasks.first?.id == "open")
  #expect(snapshot.nextTask?.id == "open")
}

@Test
func mobileHomeSnapshotNextTaskExcludedFromOpenTasksCountWhenUsedForDeduplication() {
  // The "All Tasks" section in MobileStoreTasksView filters out nextTask by ID.
  // Verify that openTasks (the source) includes nextTask so the view's manual filter is needed.
  let t1 = makeTask(id: "first")
  let t2 = makeTask(id: "second")
  let snapshot = snapshotWith(tasks: [t1, t2])
  let nextID = snapshot.nextTask?.id

  // Simulates what MobileStoreTasksView does: exclude nextTask from "All Tasks"
  let allTasksSection = snapshot.openTasks.filter { $0.id != nextID }
  #expect(allTasksSection.count == 1)
  #expect(allTasksSection.first?.id == "second")
}

@Test
func mobileTodaySectionExcludesNextTaskRow() {
  let first = makeTask(id: "first")
  let second = makeTask(id: "second")
  let snapshot = snapshotWith(tasks: [first, second])

  #expect(snapshot.nextTask?.id == "first")
  #expect(MobileTodayTaskSections.todayTasks(from: snapshot).map(\.id) == ["second"])
}

@Test
func mobileTodaySectionExcludesFocusedNextTaskEvenWhenItIsAlsoOpen() {
  let focus = makeTask(id: "focus")
  let open = makeTask(id: "open")
  let snapshot = MobileHomeSnapshot(
    today: TodaySnapshot(
      focusTitle: "Today", summary: "", tasks: [focus, open], localChangeSequence: 0),
    currentFocus: CurrentFocusPlan(
      date: "2026-06-02",
      taskIDs: [focus.id],
      briefing: nil,
      timezone: "UTC",
      localChangeSequence: 0
    ),
    weeklyReview: nil
  )

  #expect(snapshot.nextTask?.id == "focus")
  #expect(snapshot.openTasks.map(\.id) == ["focus", "open"])
  #expect(MobileTodayTaskSections.todayTasks(from: snapshot).map(\.id) == ["open"])
}

// MARK: - Item 6: Deep-link to .more with destination populates moreDestination

@Test
func mobileDeepLinkToCalendarDestinationSetsMobileNavigationTarget() {
  let url = URL(string: "lorvex://calendar")!
  let route = MobileDeepLinkRoute(url: url)
  let target = route?.navigationTarget(resolvedFrom: url)

  // Calendar is a primary tab after the IA restructure, so it selects its own tab
  // rather than opening as a workspace inside More.
  #expect(target?.selectedTab == .calendar)
  #expect(target?.moreDestination == nil)
  #expect(target?.route == nil)
}

@Test
func mobileDeepLinkToListsDestinationSetsMobileNavigationTarget() {
  let url = URL(string: "lorvex://lists")!
  let route = MobileDeepLinkRoute(url: url)
  let target = route?.navigationTarget(resolvedFrom: url)

  #expect(target?.selectedTab == .more)
  #expect(target?.moreDestination == .lists)
}

@Test
func mobileDeepLinkToTasksDestinationSetsMobileNavigationTarget() {
  let url = URL(string: "lorvex://tasks")!
  let route = MobileDeepLinkRoute(url: url)
  let target = route?.navigationTarget(resolvedFrom: url)

  // Tasks is a primary tab after the IA restructure, so it selects its own tab
  // rather than opening as a workspace inside More.
  #expect(target?.selectedTab == .tasks)
  #expect(target?.moreDestination == nil)
}

@Test
func mobileDeepLinkLegacyNavigationTargetHasNilMoreDestination() {
  // The legacy .navigationTarget property (no URL) must not set moreDestination
  let route = MobileDeepLinkRoute.tab(.more)
  #expect(route.navigationTarget.moreDestination == nil)
}

// MARK: - Item 7: openListActivity routes to .more tab with lists destination

@MainActor
@Test
func mobileStoreOpenNavigationTargetWithMoreDestinationPushesMoreNavigationPath() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  let target = MobileNavigationTarget(
    selectedTab: .more,
    route: nil,
    moreDestination: .lists
  )
  store.openNavigationTarget(target)

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.lists])
  #expect(store.iPadDestination == .lists)
  #expect(store.pendingListRoute == nil)
}

@MainActor
@Test
func mobileStoreOpenNavigationTargetWithMoreListRouteSetsListRoute() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  let target = MobileNavigationTarget(
    selectedTab: .more,
    route: nil,
    moreDestination: .lists,
    moreListRoute: .list("list-42")
  )
  store.openNavigationTarget(target)

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.lists])
  #expect(store.iPadDestination == .lists)
  #expect(store.pendingListRoute == .list("list-42"))
}

@MainActor
@Test
func mobileStoreOpenNavigationTargetToNonMoreTabClearsMorePath() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })
  store.moreNavigationPath = [.lists]
  store.iPadDestination = .lists
  store.pendingListRoute = .list("x")

  store.openNavigationTarget(MobileNavigationTarget(selectedTab: .calendar, route: nil))

  #expect(store.selectedTab == .calendar)
  #expect(store.moreNavigationPath.isEmpty)
  #expect(store.iPadDestination == nil)
  #expect(store.pendingListRoute == nil)
}

@Test
func mobileTodayCalendarSummaryCanOpenFullCalendarWorkspace() throws {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let todaySource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreTodayView.swift"),
    encoding: .utf8
  )
  let calendarSectionSource = try String(
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreCalendarSection.swift"),
    encoding: .utf8
  )

  #expect(todaySource.contains("displayLimit: 5"))
  #expect(todaySource.contains("viewAll: { store.openPrimaryShortcutTab(.calendar) }"))
  #expect(!todaySource.contains("openMoreDestination(.calendar)"))
  #expect(calendarSectionSource.contains("private var hiddenEventCount: Int"))
  #expect(calendarSectionSource.contains("if let viewAll, hiddenEventCount > 0"))
  #expect(calendarSectionSource.contains("mobileCalendar.viewAll"))
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
    contentsOf: root.appending(path: "Sources/LorvexMobile/MobileStoreTodayView.swift"),
    encoding: .utf8
  )

  #expect(habitsViewSource.contains("MobileStoreHabitsSection("))
  #expect(habitSectionSource.contains("displayLimit: Int? = nil"))
  #expect(habitSectionSource.contains("let visibleHabitCount = displayLimit.map"))
  #expect(!habitSectionSource.contains("allActiveHabits.prefix(4)"))
  #expect(todaySource.contains("displayLimit: 4"))
  #expect(habitSectionSource.contains("mobileHabits.viewAll"))
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
