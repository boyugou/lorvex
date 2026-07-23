import Foundation
import LorvexCore
import LorvexMobile
import Testing

@MainActor
@Test
func mobileStoreConsumesPendingIntentHandoff() async throws {
  let suiteName = "MobileIntentHandoffTests.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  let seededCore = try await makeSeededInMemoryCore()
  LorvexIntentHandoffStore.withScopedSuiteName(suiteName) {
    MobileIntentHandoff.clear()
    defer { MobileIntentHandoff.clear() }
    let store = MobileStore(
      core: seededCore,
      selectedTab: .tasks,
      todayString: { "2026-05-23" }
    )

    // A recognized destination handoff navigates to its tab and is then consumed.
    MobileIntentHandoff.storeDestination("today")
    store.applyPendingIntentHandoff()

    #expect(store.selectedTab == .today)
    #expect(store.routePath.isEmpty)
    #expect(MobileIntentHandoff.consumeNavigationTarget() == nil)

    MobileIntentHandoff.storeTask("task-from-shortcuts")
    store.applyPendingIntentHandoff()

    #expect(store.selectedTab == .today)
    #expect(store.routePath == [.task("task-from-shortcuts")])
    #expect(store.selectedTaskID == "task-from-shortcuts")
    #expect(MobileIntentHandoff.consumeNavigationTarget() == nil)
  }
}

@MainActor
@Test
func mobileIntentHandoffIgnoresInvalidDestinationsWithoutChangingNavigation() async throws {
  let suiteName = "MobileInvalidIntentHandoffTests.\(UUID().uuidString)"
  defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
  let seededCore = try await makeSeededInMemoryCore()
  LorvexIntentHandoffStore.withScopedSuiteName(suiteName) {
    MobileIntentHandoff.clear()
    defer { MobileIntentHandoff.clear() }
    let store = MobileStore(
      core: seededCore,
      selectedTab: .tasks,
      todayString: { "2026-05-23" }
    )

    MobileIntentHandoff.storeDestination("unsupported")
    store.applyPendingIntentHandoff()

    #expect(store.selectedTab == .tasks)
    #expect(store.routePath.isEmpty)
    #expect(MobileIntentHandoff.consumeNavigationTarget() == nil)
  }
}

@MainActor
@Test
func mobileStoreRefreshLoadsCoreSnapshots() async throws {
  let core = try await makeSeededInMemoryCore()
  let logicalDay = try #require(try await core.loadToday().logicalDay)
  // The mobile calendar window starts on the product logical day, so give it
  // an event inside that authoritative window. The fixed preview event may be
  // outside the live window as wall time advances.
  _ = try await core.createCalendarEvent(
    title: "Window review", startDate: logicalDay, endDate: nil,
    startTime: "15:00", endTime: "15:45", allDay: false, location: nil, notes: nil)
  let store = MobileStore(core: core, todayString: { logicalDay })

  await store.refresh()

  #expect(store.snapshot.today.focusTitle == "Today")
  #expect(!store.snapshot.today.tasks.isEmpty)
  #expect(store.snapshot.weeklyReview != nil)
  #expect(store.lists?.lists.map(\.name).contains("Apple Native") == true)
  #expect(store.habits?.habits.map(\.name).contains("Daily Review") == true)
  #expect(store.calendarTimeline?.events.map(\.title).contains("Window review") == true)
  #expect(store.selectedTaskID == store.snapshot.nextTask?.id)
  #expect(store.errorMessage == nil)
  #expect(!store.isLoading)
}

@MainActor
@Test
func mobileStoreRefreshFailureClearsStaleDashboardState() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  let staleTaskID = try #require(store.snapshot.nextTask?.id)
  store.openNavigationTarget(MobileNavigationTarget(selectedTab: .today, route: .task(staleTaskID)))

  #expect(store.selectedTaskID == staleTaskID)
  #expect(!store.snapshot.today.tasks.isEmpty)
  #expect(store.lists != nil)
  #expect(store.habits != nil)
  #expect(store.calendarTimeline != nil)

  core.loadTodayError = .unsupportedOperation("Mobile refresh unavailable.")
  await store.refresh()

  #expect(store.snapshot.today == .empty)
  #expect(store.snapshot.currentFocus == nil)
  #expect(store.snapshot.weeklyReview == nil)
  #expect(store.lists == nil)
  #expect(store.selectedListDetail == nil)
  #expect(store.habits == nil)
  #expect(store.calendarTimeline == nil)
  #expect(store.selectedTaskID == nil)
  #expect(store.errorMessage == "Mobile refresh unavailable.")
  #expect(!store.isLoading)
}

@MainActor
@Test
func mobileStorePlanningSnapshotFailureIsNotSilentlyIgnored() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  #expect(!store.snapshot.today.tasks.isEmpty)
  let loadedLists = try #require(store.lists)
  #expect(store.habits != nil)
  #expect(store.calendarTimeline != nil)

  core.loadListsError = .unsupportedOperation("Mobile lists unavailable.")
  await store.refresh()

  #expect(!store.snapshot.today.tasks.isEmpty)
  #expect(store.snapshot.weeklyReview != nil)
  #expect(store.lists == loadedLists)
  #expect(store.habits != nil)
  #expect(store.calendarTimeline != nil)
  #expect(store.errorMessage == "Mobile lists unavailable.")
}

@MainActor
@Test
func mobileStoreWeeklyReviewFailureIsNotSilentlyIgnored() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  await store.refresh()
  #expect(store.snapshot.weeklyReview != nil)

  core.loadWeeklyReviewError = .unsupportedOperation("Mobile weekly review unavailable.")
  await store.refresh()

  #expect(store.snapshot.today == .empty)
  #expect(store.snapshot.weeklyReview == nil)
  #expect(store.errorMessage == "Mobile weekly review unavailable.")
}

@MainActor
@Test
func mobileStoreRoutesDeepLinksIntoTabAndPathState() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .tasks,
    todayString: { "2026-05-23" }
  )

  store.openDeepLink(URL(string: "lorvex://open/today")!)

  #expect(store.selectedTab == .today)
  #expect(store.routePath.isEmpty)

  store.openDeepLink(URL(string: "lorvex://task/task%20with%2Fslash")!)

  #expect(store.selectedTab == .today)
  #expect(store.routePath == [.task("task with/slash")])
  #expect(store.selectedTaskID == "task with/slash")

  store.openDeepLink(URL(string: "https://lorvex/task/task-ignored")!)

  #expect(store.selectedTab == .today)
  #expect(store.routePath == [.task("task with/slash")])
  #expect(store.selectedTaskID == "task with/slash")
}

@MainActor
@Test
func mobileStoreRoutesDestinationHandoffToTheExactMoreWorkspace() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .today,
    todayString: { "2026-05-23" }
  )

  store.continueOpenDestinationActivity(makeOpenDestinationActivity(selection: .memory))

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.memory])
  #expect(store.iPadDestination == .memory)
}

@MainActor
@Test
func mobileStoreRoutesRepeatedDestinationHandoffsWithoutLosingTheirMoreWorkspace() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .today,
    todayString: { "2026-05-23" }
  )

  store.continueOpenDestinationActivity(makeOpenDestinationActivity(selection: .reviews))

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.review])
  #expect(store.iPadDestination == .review)

  store.continueOpenDestinationActivity(makeOpenDestinationActivity(selection: .lists))

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.lists])
  #expect(store.iPadDestination == .lists)
}

// MARK: - Deep link routing to a specific habit / list / review entity
//
// The mobile URL parser used to recognize only `task`/`open` hosts, so
// `lorvex://habit/<id>`, `lorvex://list/<id>`, and `lorvex://review/<date>`
// either failed to parse or, once parsed via the shared resolver, only opened
// the destination's index page. `openDeepLink` now parses every URL through
// the same `LorvexDeepLinkRoute` the macOS shell and Handoff/Spotlight use, and
// threads the payload all the way to the specific entity.

@MainActor
@Test
func mobileStoreDeepLinkOpensSpecificHabitEntity() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .today,
    todayString: { "2026-05-23" }
  )

  store.openDeepLink(URL(string: "lorvex://habit/\(LorvexPreviewSeedID.dailyReviewHabit)")!)

  #expect(store.selectedTab == .habits)
  #expect(store.selectedHabitID == LorvexPreviewSeedID.dailyReviewHabit)
  #expect(store.habitsRoutePath == [.habit(LorvexPreviewSeedID.dailyReviewHabit)])
}

@MainActor
@Test
func mobileStoreDeepLinkOpensSpecificListEntity() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .today,
    todayString: { "2026-05-23" }
  )

  store.openDeepLink(URL(string: "lorvex://list/\(LorvexPreviewSeedID.appleNativeList)")!)

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.lists])
  #expect(store.pendingListRoute == .list(LorvexPreviewSeedID.appleNativeList))
}

@MainActor
@Test
func mobileStoreDeepLinkOpensSpecificReviewDay() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .today,
    todayString: { "2026-05-23" }
  )

  store.openDeepLink(URL(string: "lorvex://review/2026-05-20")!)

  #expect(store.selectedTab == .more)
  #expect(store.moreNavigationPath == [.review])
  // The tab switch is synchronous; the day switch awaits a daily-review read
  // on a detached Task, so poll instead of assuming it lands within one tick.
  for _ in 0..<50 where store.selectedReviewDate != "2026-05-20" {
    try await Task.sleep(nanoseconds: 10_000_000)
  }
  #expect(store.selectedReviewDate == "2026-05-20")
}

@MainActor
@Test
func mobileStoreIgnoresMalformedDeepLinkURLs() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .tasks,
    todayString: { "2026-05-23" }
  )

  // An impossible calendar date, an empty habit id, and a foreign scheme must
  // all be safely ignored rather than trusted into navigation state.
  store.openDeepLink(URL(string: "lorvex://review/2026-02-30")!)
  store.openDeepLink(URL(string: "lorvex://habit/")!)
  store.openDeepLink(URL(string: "https://lorvex/habit/\(LorvexPreviewSeedID.dailyReviewHabit)")!)

  #expect(store.selectedTab == .tasks)
  #expect(store.selectedHabitID == nil)
  #expect(store.habitsRoutePath.isEmpty)
}

@MainActor
@Test
func mobileStoreOpensSpecificHabitFromScheduledReminderNotificationPayload() async throws {
  // The real habit-notification pipeline, end to end: a due occurrence maps to
  // a UNNotificationRequest whose userInfo carries the habit deep link;
  // LorvexNotificationRoute (the same decoder a default-tap handler uses)
  // extracts the URL, which openDeepLink then routes.
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .today,
    todayString: { "2026-05-23" }
  )
  let habitID = LorvexPreviewSeedID.dailyReviewHabit
  let occurrence = DueHabitReminderOccurrence(
    policy: HabitReminderPolicy(
      id: "policy-1", habitID: habitID, habitName: "Daily Review", reminderTime: "09:00",
      enabled: true, createdAt: "", updatedAt: ""),
    fireDate: Date(timeIntervalSince1970: 1_800_000_000)
  )
  let reminder = ScheduledHabitReminder(occurrence: occurrence, body: "Time for your habit")
  let route = try #require(LorvexNotificationRoute(userInfo: reminder.notificationRequest.content.userInfo))

  store.openDeepLink(route.url)

  #expect(store.selectedTab == .habits)
  #expect(store.selectedHabitID == habitID)
  #expect(store.habitsRoutePath == [.habit(habitID)])
}

@MainActor
@Test
func mobileStoreQuickCaptureActionPresentsCaptureSheet() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .tasks,
    todayString: { "2026-05-23" }
  )

  store.performQuickAction(.quickCapture)

  // The "Quick Capture" quick action must raise the capture sheet, not merely
  // navigate to another tab.
  #expect(store.isPresentingCapture)
  #expect(store.selectedTab == .tasks)
}

@MainActor
@Test
func mobileStoreOpenTodayActionRoutesToTodayWithoutCaptureSheet() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .tasks,
    todayString: { "2026-05-23" }
  )

  store.performQuickAction(.openToday)

  #expect(store.selectedTab == .today)
  #expect(store.routePath.isEmpty)
  #expect(!store.isPresentingCapture)
}

@MainActor
@Test
func mobileStoreOpensTaskRouteOnTodayStack() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .today,
    todayString: { "2026-05-23" }
  )
  store.routePath = [.task("today-parent")]

  store.openTaskRouteOnCurrentStack("child")

  #expect(store.selectedTab == .today)
  #expect(store.routePath == [.task("today-parent"), .task("child")])
  #expect(store.selectedTaskID == "child")
}

@MainActor
@Test
func mobileStoreOpensTaskRouteOnMoreStackWithoutTabTeleport() async throws {
  let store = MobileStore(
    core: try await makeSeededInMemoryCore(),
    selectedTab: .more,
    todayString: { "2026-05-23" }
  )

  store.openTaskRouteOnCurrentStack("child")

  #expect(store.selectedTab == .more)
  #expect(store.pendingListRoute == .task("child"))
  #expect(store.selectedTaskID == "child")
}
