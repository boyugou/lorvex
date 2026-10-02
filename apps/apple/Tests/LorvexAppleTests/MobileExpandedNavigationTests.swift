import LorvexCore
import LorvexMobile
import SwiftUI
import Testing

@testable import LorvexMobile

// MARK: - MobileTab / MobileDestination set

@Suite("MobileTab destination set")
struct MobileTabDestinationSetTests {

  @Test("MobileTab includes review case")
  func mobileTabIncludesReviewCase() {
    #expect(MobileTab.allCases.contains(.review))
  }

  @Test("MobileTab holds exactly the four tabs the bar shows")
  func mobileTabHasFourCases() {
    // today, calendar, tasks, review. Habits and Memory are workspaces pushed
    // onto the Tasks stack, never tabs.
    #expect(MobileTab.allCases.count == 4)
  }

  @Test("MobileDestination includes all required domains")
  func mobileDestinationCoversAllDomains() {
    let cases = Set(MobileDestination.allCases.map(\.rawValue))
    for domain in ["tasks", "calendar", "habits", "lists", "memory", "settings"] {
      #expect(cases.contains(domain), "Missing domain: \(domain)")
    }
  }

  @Test("MobileDestination allCases has seven members")
  func mobileDestinationHasSevenCases() {
    // tasks, calendar, habits, lists, memory, review, settings.
    #expect(MobileDestination.allCases.count == 7)
  }

  @Test("MobileTab.review has correct metadata")
  func mobileTabReviewMetadata() {
    #expect(MobileTab.review.title == "Review")
    #expect(MobileTab.review.systemImage == "text.badge.checkmark")
    #expect(MobileTab.review.rawValue == "review")
  }
}

// MARK: - Workspace view instantiation

@Suite("Mobile workspace views")
@MainActor
struct MobileWorkspaceViewTests {

  @Test("MobileStoreTasksView instantiates against SwiftLorvexCoreService")
  func mobileTasksViewInstantiates() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    let data = renderSnapshot(
      MobileStoreTasksView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("MobileStoreCalendarView instantiates against SwiftLorvexCoreService")
  func mobileCalendarViewInstantiates() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    let data = renderSnapshot(
      MobileStoreCalendarView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("MobileStoreCalendarView renders iPad agenda workspace")
  func mobileCalendarViewRendersIPadAgendaWorkspace() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()

    let data = renderSnapshot(
      NavigationStack {
        MobileStoreCalendarView(store: store)
          .environment(\.horizontalSizeClass, .regular)
      },
      size: CGSize(width: 1024, height: 768)
    )

    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("MobileStoreHabitsView instantiates against SwiftLorvexCoreService")
  func mobileHabitsViewInstantiates() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    let data = renderSnapshot(
      MobileStoreHabitsView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("MobileStoreHabitsView renders iPad split workspace")
  func mobileHabitsViewRendersIPadSplitWorkspace() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()

    let data = renderSnapshot(
      NavigationStack {
        MobileStoreHabitsView(store: store)
          .environment(\.horizontalSizeClass, .regular)
      },
      size: CGSize(width: 1024, height: 768)
    )

    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("A list's screen renders on iPhone and in the iPad split")
  func mobileListScreenRenders() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.refresh()
    let scope = MobileTasksScope.list(LorvexPreviewSeedID.appleNativeList)

    let phone = renderSnapshot(
      NavigationStack {
        MobileStoreTasksView(store: store, scope: scope, scopeTitle: scope.displayTitle(store: store))
      },
      size: CGSize(width: 390, height: 844)
    )
    let pad = renderSnapshot(
      NavigationStack {
        MobileStoreTasksView(store: store, scope: scope, scopeTitle: scope.displayTitle(store: store))
          .environment(\.horizontalSizeClass, .regular)
      },
      size: CGSize(width: 1024, height: 768)
    )

    #expect((phone?.count ?? 0) > 1024)
    #expect((pad?.count ?? 0) > 1024)
  }

  @Test("MobileStoreMemoryView instantiates against SwiftLorvexCoreService")
  func mobileMemoryViewInstantiates() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    let data = renderSnapshot(
      MobileStoreMemoryView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("MobileStoreMemoryView renders iPad split workspace")
  func mobileMemoryViewRendersIPadSplitWorkspace() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    await store.loadMemorySnapshot()

    let data = renderSnapshot(
      NavigationStack {
        MobileStoreMemoryView(store: store)
          .environment(\.horizontalSizeClass, .regular)
      },
      size: CGSize(width: 1024, height: 768)
    )

    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("Today summary sections expose full workspace links")
  func todaySummarySectionsExposeFullWorkspaceLinks() throws {
    let todaySource = try appleSourceFile("Sources/LorvexMobile/MobileTodayPage.swift")

    // Lists live in their own destination, not on Today, so Today only links out
    // to the habits workspace.
    #expect(todaySource.contains("store.routePath.append(.workspace(.habits))"))
  }

  @Test("Compact habit rows push detail visualization route")
  func compactHabitRowsPushDetailVisualizationRoute() throws {
    let navigationSource = try appleSourceFile("Sources/LorvexMobile/MobileNavigation.swift")
    let habitsSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreHabitsView.swift")
    let sectionSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreHabitSection.swift")
    let routeSource = try appleSourceFile("Sources/LorvexMobile/MobileRouteViews.swift")

    #expect(navigationSource.contains("case habit(LorvexHabit.ID)"))
    #expect(habitsSource.contains("detailRoute: { .habit($0.id) }"))
    #expect(sectionSource.contains("NavigationLink(value: detailRoute)"))
    #expect(routeSource.contains("case .habit(let id):"))
    #expect(routeSource.contains("MobileHabitDetailPanel("))
    #expect(routeSource.contains("await store.loadHabitDetail(id: id)"))
  }

}

// MARK: - Settings view

@Suite("MobileStoreSettingsView")
@MainActor
struct MobileStoreSettingsViewTests {

  @Test("MobileStoreSettingsView renders against SwiftLorvexCoreService")
  func mobileSettingsViewRenders() async throws {
    let store = MobileStore(core: try await makeSeededInMemoryCore())
    let data = renderSnapshot(
      MobileStoreSettingsView(store: store),
      size: CGSize(width: 390, height: 844)
    )
    #expect(data != nil)
    #expect((data?.count ?? 0) > 1024)
  }

  @Test("Mobile setup and settings do not expose desktop MCP helper copy")
  func mobileSetupAndSettingsAvoidDesktopMCPTransport() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let settingsSource = try String(
      contentsOf: packageRoot.appending(path: "Sources/LorvexMobile/MobileSettingsSections.swift"),
      encoding: .utf8
    )
    let setupSource = try String(
      contentsOf: packageRoot.appending(path: "Sources/LorvexMobile/MobileSetupWizard.swift"),
      encoding: .utf8
    )

    #expect(!settingsSource.contains(#""settings.mcp.host_value""#))
    #expect(!settingsSource.contains(#""settings.mcp.transport_value""#))
    #expect(!setupSource.contains(#""setup.mcp.apple_helper""#))
    #expect(!settingsSource.contains("Model Context Protocol"))
    #expect(!settingsSource.contains("stdio (localhost)"))
    #expect(!setupSource.contains("lorvex-apple-mcp-client.json"))
  }
}

// MARK: - Workspace views

@Suite("MobileStoreWorkspaceViews")
@MainActor
struct MobileStoreWorkspaceViewsTests {

  @Test("A list has one screen: the scoped Tasks workspace with the list's own chrome")
  func mobileListScreenIsTheScopedTasksWorkspace() throws {
    let navigationSource = try appleSourceFile("Sources/LorvexMobile/MobileNavigation.swift")
    let tasksSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreTasksView.swift")
    let chromeSource = try appleSourceFile("Sources/LorvexMobile/MobileListScopeChrome.swift")

    // No second list route: every entry point pushes `.tasksScope(.list(id))`.
    #expect(!navigationSource.contains("case list("))
    #expect(
      tasksSource.contains(
        "MobileListScopeChrome(store: store, listID: scope.listID, isBatchSelecting: isBatchSelecting)"))
    #expect(chromeSource.contains(".navigationSubtitle(list?.description ?? \"\")"))
    // The core never deletes the Inbox, so its menu has no Delete List.
    #expect(chromeSource.contains("if !list.isInbox {"))
  }

  @Test("Mobile Calendar all-day strip accepts dropped task refs")
  func mobileCalendarAllDayStripAcceptsDroppedTaskRefs() throws {
    let chromeSource = try appleSourceFile("Sources/LorvexMobile/MobileCalendarDayChrome.swift")
    let columnSource = try appleSourceFile("Sources/LorvexMobile/MobileCalendarDayColumn.swift")
    let dayViewSource = try appleSourceFile("Sources/LorvexMobile/MobileCalendarDayView.swift")
    let actionsSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreTaskActions.swift")

    #expect(chromeSource.contains(".dropDestination(for: LorvexTaskRef.self)"))
    #expect(chromeSource.contains("onDropTask(ref, day.date)"))
    #expect(columnSource.contains("let onDropTask: (LorvexTaskRef, Date) -> Void"))
    #expect(dayViewSource.contains("await store.planTask(ref.id, on: day)"))
    #expect(actionsSource.contains("func planTask(_ id: LorvexTask.ID, on day: Date)"))
  }

  @Test("Mobile Habits workspace uses adaptive list detail with store-backed selection")
  func mobileHabitsWorkspaceUsesAdaptiveListDetail() throws {
    let habitsSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreHabitsView.swift")
    let storeSource = try appleSourceFile("Sources/LorvexMobile/MobileStore.swift")
    let routingSource = try appleSourceFile(
      "Sources/LorvexMobile/MobileStoreNavigationRouting.swift")

    #expect(habitsSource.contains("MobileAdaptiveListDetail(selection: habitSelection)"))
    #expect(!habitsSource.contains("HStack(spacing: 0)"))
    #expect(!habitsSource.contains("@State private var selectedHabitID"))
    #expect(storeSource.contains("var selectedHabitID: LorvexHabit.ID?"))
    #expect(routingSource.contains("func selectHabit(_ id: LorvexHabit.ID?)"))
  }

  @Test("Mobile Memory workspace uses adaptive list detail with store-backed selection")
  func mobileMemoryWorkspaceUsesAdaptiveListDetail() throws {
    let memorySource = try appleSourceFile("Sources/LorvexMobile/MobileStoreMemoryView.swift")
    let storeSource = try appleSourceFile("Sources/LorvexMobile/MobileStore.swift")
    let routingSource = try appleSourceFile(
      "Sources/LorvexMobile/MobileStoreNavigationRouting.swift")

    #expect(memorySource.contains("MobileAdaptiveListDetail(selection: memorySelection)"))
    #expect(!memorySource.contains("HStack(spacing: 0)"))
    #expect(!memorySource.contains("@State private var selectedMemoryKey"))
    #expect(storeSource.contains("var selectedMemoryKey: MemoryEntry.ID?"))
    #expect(routingSource.contains("func selectMemoryEntry(_ id: MemoryEntry.ID?)"))
    #expect(memorySource.contains("MobileStoreMemoryEditorSheet("))
  }

  @Test("Compact memory rows push the entry's route, rendered by the route view")
  func compactMemoryRowsPushEntryRoute() throws {
    let navigationSource = try appleSourceFile("Sources/LorvexMobile/MobileNavigation.swift")
    let memorySource = try appleSourceFile("Sources/LorvexMobile/MobileStoreMemoryView.swift")
    let routeSource = try appleSourceFile("Sources/LorvexMobile/MobileRouteViews.swift")

    #expect(navigationSource.contains("case memoryEntry(MemoryEntry.ID)"))
    #expect(memorySource.contains("NavigationLink(value: MobileRoute.memoryEntry(entry.id))"))
    #expect(!memorySource.contains("MobileStoreMemoryDetailDestination("))
    #expect(routeSource.contains("case .memoryEntry(let id):"))
    #expect(routeSource.contains("MobileStoreMemoryDetailDestination("))
    #expect(routeSource.contains("MobileStoreMemoryEditorSheet("))
  }

  @Test("A split's detail pane leaves the bar's title and toolbar to the list")
  func splitDetailPanesLeaveTheBarToTheList() throws {
    let splitSource = try appleSourceFile("Sources/LorvexMobile/MobileAdaptiveListDetail.swift")
    let taskContentSource = try appleSourceFile("Sources/LorvexMobile/MobileTaskDetailContent.swift")
    let taskDetailSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreTaskDetailView.swift")

    #expect(splitSource.contains(".environment(\\.mobileDetailPresentation, .pane)"))
    #expect(taskContentSource.contains(".mobileDetailScreenChrome("))
    #expect(!taskContentSource.contains(".navigationTitle("))
    #expect(taskContentSource.contains("if presentation == .pane {"))
    #expect(taskDetailSource.contains("if presentation == .screen {"))
    #expect(taskDetailSource.contains("} paneActions: {"))
  }

  @Test("Mobile Tasks workspace queries completed deferred and cancelled tasks from core")
  func mobileTasksWorkspaceQueriesFullCorpus() async throws {
    let core = try await makeSeededInMemoryCore()
    let completed = try await core.createTask(title: "Closed from corpus", notes: "")
    _ = try await core.completeTask(id: completed.id)
    let deferred = try await core.createTask(title: "Deferred from corpus", notes: "")
    _ = try await core.deferTask(id: deferred.id, until: Date(timeIntervalSince1970: 1_779_494_400))
    let cancelled = try await core.createTask(title: "Cancelled from corpus", notes: "")
    _ = try await core.cancelTask(id: cancelled.id)

    let store = MobileStore(core: core)
    let completedPage = await store.taskWorkspacePage(scope: .completed, query: "Closed")
    // A deferred task keeps status open (defer pushes planned_date), so it
    // surfaces under the open filter, not a separate deferred tab.
    let deferredPage = await store.taskWorkspacePage(scope: .all, query: "Deferred")
    let cancelledPage = await store.taskWorkspacePage(scope: .cancelled, query: "Cancelled")

    #expect(completedPage.tasks.map(\.id).contains(completed.id))
    #expect(deferredPage.tasks.map(\.id).contains(deferred.id))
    #expect(cancelledPage.tasks.map(\.id).contains(cancelled.id))
    #expect(store.resolveTask(completed.id)?.title == "Closed from corpus")
    #expect(store.resolveTask(deferred.id)?.title == "Deferred from corpus")
    #expect(store.resolveTask(cancelled.id)?.title == "Cancelled from corpus")
  }

  @Test("Mobile Tasks workspace pages through core-backed results")
  func mobileTasksWorkspacePagesThroughCoreResults() async throws {
    let core = try await makeSeededInMemoryCore()
    var ids: [LorvexTask.ID] = []
    for index in 0..<3 {
      let task = try await core.createTask(title: "Paged mobile task \(index)", notes: "")
      ids.append(task.id)
    }

    let store = MobileStore(core: core)
    let firstPage = await store.taskWorkspacePage(
      scope: .all,
      query: "Paged mobile task",
      limit: 2,
      offset: 0
    )
    let secondPage = await store.taskWorkspacePage(
      scope: .all,
      query: "Paged mobile task",
      limit: 2,
      offset: firstPage.nextOffset ?? 0
    )
    let combined = firstPage.appending(secondPage)

    #expect(firstPage.tasks.count == 2)
    #expect(firstPage.nextOffset != nil)
    #expect(combined.tasks.map(\.id).filter { ids.contains($0) }.count == 3)
    #expect(combined.nextOffset == nil)
  }

  /// The pause itself is ``LorvexSearchDebounce`` (`LorvexSearchDebounceTests`);
  /// this pins that the Tasks list loads through it and drops a superseded load.
  @Test("Mobile Tasks workspace debounces non-empty search input")
  func mobileTasksWorkspaceDebouncesNonEmptySearchInput() throws {
    let source = try appleSourceFile("Sources/LorvexMobile/MobileStoreTasksView.swift")
    let loadingSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreTasksView+Loading.swift")

    #expect(source.contains("guard await LorvexSearchDebounce.shouldSearch(query) else { return }"))
    #expect(loadingSource.contains("guard !Task.isCancelled else {"))
  }

  @Test("Mobile root view init does not reset store-selected tab")
  func mobileRootViewInitDoesNotResetStoreSelectedTab() throws {
    let source = try appleSourceFile("Sources/LorvexMobile/LorvexMobileStoreRootView.swift")

    #expect(!source.contains("self.store.selectedTab = selectedTab"))
    #expect(!source.contains("selectedTab: MobileTab = .today"))
  }

  @Test("Mobile result-backed task rows reload after status mutations")
  func mobileResultBackedTaskRowsReloadAfterStatusMutations() throws {
    let tasksSource = try appleSourceFile("Sources/LorvexMobile/MobileStoreTasksView.swift")

    #expect(tasksSource.contains("actions: store.rowActions(for: task.id) { await load() }"))
  }

  @Test("Mobile deferred task search preserves core pagination")
  func mobileDeferredTaskSearchPreservesCorePagination() async throws {
    let core = try await makeSeededInMemoryCore()
    var ids: [LorvexTask.ID] = []
    for index in 0..<3 {
      let task = try await core.createTask(title: "Deferred paged mobile task \(index)", notes: "")
      _ = try await core.deferTask(
        id: task.id,
        until: Date(timeIntervalSince1970: 1_779_494_400 + TimeInterval(index))
      )
      ids.append(task.id)
    }

    let store = MobileStore(core: core)
    // Deferred tasks keep status open (defer pushes planned_date); they page
    // through the open filter.
    let firstPage = await store.taskWorkspacePage(
      scope: .all,
      query: "Deferred paged mobile task",
      limit: 2,
      offset: 0
    )
    let secondPage = await store.taskWorkspacePage(
      scope: .all,
      query: "Deferred paged mobile task",
      limit: 2,
      offset: firstPage.nextOffset ?? 0
    )
    let combined = firstPage.appending(secondPage)

    #expect(firstPage.tasks.count == 2)
    #expect(firstPage.nextOffset != nil)
    #expect(combined.tasks.map(\.id).filter { ids.contains($0) }.count == 3)
    #expect(combined.nextOffset == nil)
  }

  @Test("Mobile task routes lazy-load offscreen deep-linked tasks")
  func mobileTaskRoutesLazyLoadOffscreenDeepLinkedTasks() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = MobileStore(core: core)
    await store.refresh()

    let task = try await core.createTask(title: "Mobile offscreen deep link", notes: "")
    #expect(store.resolveTask(task.id) == nil)

    store.openNavigationTarget(MobileNavigationTarget(route: .task(task.id)))
    let loaded = await store.refreshTaskForRoute(task.id)

    #expect(loaded)
    #expect(store.selectedTaskID == task.id)
    #expect(store.resolveTask(task.id)?.title == "Mobile offscreen deep link")
  }

  @Test("Mobile task route retries loading from every visible state")
  func mobileTaskRouteReloadModifierWrapsNotFoundState() throws {
    let source = try appleSourceFile("Sources/LorvexMobile/MobileRouteViews.swift")
    let taskCase = try #require(
      source.split(separator: "case .habit(let id):", maxSplits: 1).first?
        .split(separator: "case .task(let id):", maxSplits: 1).last)

    #expect(taskCase.contains("Group {"))
    #expect(
      taskCase.contains(
        ".task(id: \"\\(id)|\\(store.taskWorkspaceRevision)\")"),
      "the revision-keyed reload must wrap loading, content, and not-found branches")
    #expect(
      String(taskCase).components(separatedBy: "taskWorkspaceRevision").count == 2,
      "one shared modifier prevents a not-found branch from dropping future retries")
  }

  @Test("Mobile edit helpers use all loaded task pools")
  func mobileEditHelpersUseAllLoadedTaskPools() async throws {
    let core = try await makeSeededInMemoryCore()
    let store = MobileStore(core: core)
    await store.refresh()

    let cached = try await core.createTask(title: "Cached dependency", notes: "")
    let tagged = try await core.updateTask(
      id: cached.id,
      title: cached.title,
      notes: cached.notes,
      priority: cached.priority,
      estimatedMinutes: cached.estimatedMinutes,
      plannedDate: cached.dueDate,
      tags: ["offscreen-tag"],
      dependsOn: cached.dependsOn
    )
    store.cacheTasks([tagged])

    let dependencyTasks = await store.dependencyTasks(for: [tagged.id])

    #expect(store.knownTagSuggestions.contains("offscreen-tag"))
    #expect(dependencyTasks.map(\.id) == [tagged.id])
  }
}

private func appleSourceFile(_ relativePath: String) throws -> String {
  let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let url = root.appendingPathComponent(relativePath)
  return try String(contentsOf: url, encoding: .utf8)
}

/// Every way to open Habits (the keyboard menu, a workspace link, Handoff, a
/// habit link) selects the Tasks tab and pushes the Habits workspace there.
@MainActor
@Test
func everyHabitsEntryPointOpensTheWorkspaceOnTheTasksStack() async throws {
  let store = MobileStore(core: try await makeSeededInMemoryCore(), todayString: { "2026-05-23" })

  store.openShortcutDestination(.habits)
  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.workspace(.habits)])

  store.selectedTab = .review
  store.tasksRoutePath = []
  store.openDeepLink(URL(string: "lorvex://open/habits")!)
  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.workspace(.habits)])

  store.selectedTab = .today
  store.continueOpenDestinationActivity(makeOpenDestinationActivity(selection: .habits))
  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.workspace(.habits)])

  store.selectedTab = .calendar
  store.openDeepLink(URL(string: "lorvex://habit/habit-1")!)
  #expect(store.selectedTab == .tasks)
  #expect(store.tasksRoutePath == [.workspace(.habits), .habit("habit-1")])
  #expect(store.selectedHabitID == "habit-1")
}

/// iOS 27's UIKit asserts (`_UITabModel _setSelectedItem`) and aborts the app
/// when a SwiftUI `TabView` selects a tab marked `.hidden(true)`, so the shell
/// declares only the tabs the bar draws and reaches every other workspace by
/// pushing it onto a tab's stack.
@Test
func mobileTabShellDeclaresNoHiddenTab() throws {
  let source = try appleSourceFile("Sources/LorvexMobile/LorvexMobileStoreRootView.swift")
  #expect(!source.contains(".hidden("))
}
