import CoreSpotlight
import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

@Test
func spotlightTaskDocumentIndexesTitleAndDueDateOnly() {
  let task = LorvexTask(
    id: "task-spotlight",
    title: "Index native Lorvex tasks",
    notes: "Make Spotlight useful.",
    aiNotes: "Prefer system search over custom-only search.",
    priority: .p1,
    status: .open,
    dueDate: Date(timeIntervalSince1970: 1_779_494_400),
    estimatedMinutes: 30,
    tags: ["apple", "spotlight", "apple"],
    checklistItems: [
      TaskChecklistItem(
        id: "check-1",
        taskID: "task-spotlight",
        position: 0,
        text: "Build searchable item",
        completedAt: nil
      )
    ]
  )

  let document = SpotlightTaskDocument(task: task)

  #expect(document.identifier == "lorvex-task:task-spotlight")
  #expect(document.title == "Index native Lorvex tasks")
  #expect(document.dueDate == task.dueDate)
  #expect(document.deepLink.absoluteString == "lorvex://task/task-spotlight")

  // Only the title and structured due date are indexed; notes, ai_notes,
  // checklist text, and tags never reach the system index.
  let attributes = document.searchableItem.attributeSet
  #expect(attributes.title == "Index native Lorvex tasks")
  #expect(attributes.dueDate == task.dueDate)
  #expect(attributes.contentDescription == nil)
  #expect(attributes.keywords == nil)
}

@Test
func spotlightTaskDocumentEscapesDeepLinkTaskIdentifiers() {
  let task = LorvexTask(
    id: "task with/slash",
    title: "Escaped Spotlight task",
    notes: "",
    aiNotes: nil,
    priority: .p3,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: [],
    checklistItems: []
  )

  let document = SpotlightTaskDocument(task: task)

  #expect(document.deepLink.absoluteString == "lorvex://task/task%20with%2Fslash")
  #expect(LorvexDeepLinkRoute(url: document.deepLink) == .task("task with/slash"))
}

@Test
func deepLinkRouteParsesDestinationsAndTasks() throws {
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://open/tasks")!) == .destination(.tasks))
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://calendar")!) == .destination(.calendar))
  #expect(LorvexDeepLinkRoute(url: URL(string: "lorvex://task/task-123")!) == .task("task-123"))
  #expect(LorvexDeepLinkRoute(url: URL(string: "https://lorvex/task/task-123")!) == nil)
}

@Test
func deepLinkRouteBuildsCanonicalURLs() {
  #expect(LorvexDeepLinkRoute.scheme == "lorvex")
  #expect(LorvexDeepLinkRoute.openHost == "open")
  #expect(LorvexDeepLinkRoute.taskHost == "task")
  #expect(LorvexDeepLinkRoute.scheme == LorvexDeepLinkContract.scheme)
  #expect(LorvexDeepLinkRoute.openHost == LorvexDeepLinkContract.openHost)
  #expect(LorvexDeepLinkRoute.taskHost == LorvexDeepLinkContract.taskHost)
  #expect(
    LorvexDeepLinkContract.destinationURL(.calendar).absoluteString == "lorvex://open/calendar")
  #expect(
    LorvexDeepLinkContract.taskURL("task with/slash").absoluteString
      == "lorvex://task/task%20with%2Fslash")
  #expect(LorvexDeepLinkRoute.destination(.calendar).url.absoluteString == "lorvex://open/calendar")
  #expect(LorvexDeepLinkRoute.task("task-123").url.absoluteString == "lorvex://task/task-123")
  #expect(
    LorvexDeepLinkRoute.task("task with/slash").url.absoluteString
      == "lorvex://task/task%20with%2Fslash")
}

@MainActor
@Test
func appStoreRoutesDeepLinksToDestinationAndTask() async throws {
  let suiteName = "appStoreRoutesDeepLinksToDestinationAndTask.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)

  await store.refresh()
  await store.openDeepLink(URL(string: "lorvex://open/memory")!)
  #expect(store.selection == .memory)

  let taskID = try #require(store.today.tasks.first?.id)
  await store.openDeepLink(URL(string: "lorvex://task/\(taskID)")!)
  #expect(store.selection == .tasks)
  #expect(store.selectedTaskID == taskID)
}

// MARK: - Deep link routing to a specific habit / list / review entity
//
// The shared resolver always parsed `habit`/`review` payloads, but
// `applyRouteNavigation` dropped the associated value and only opened the
// Habits/Reviews workspace index. These assert the specific entity opens, not
// just its section — and that a malformed URL is rejected rather than trusted.

@MainActor
@Test
func appStoreDeepLinkOpensSpecificHabitEntity() async throws {
  let suiteName = "appStoreDeepLinkOpensSpecificHabitEntity.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()

  await store.openDeepLink(URL(string: "lorvex://habit/\(LorvexPreviewSeedID.dailyReviewHabit)")!)

  #expect(store.selection == .habits)
  #expect(store.selectedHabitID == LorvexPreviewSeedID.dailyReviewHabit)
}

@MainActor
@Test
func appStoreDeepLinkOpensSpecificListEntity() async throws {
  let suiteName = "appStoreDeepLinkOpensSpecificListEntity.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()

  await store.openDeepLink(URL(string: "lorvex://list/\(LorvexPreviewSeedID.appleNativeList)")!)

  #expect(store.selection == .lists)
  #expect(store.selectedListID == LorvexPreviewSeedID.appleNativeList)
}

@MainActor
@Test
func appStoreDeepLinkOpensSpecificReviewDay() async throws {
  let suiteName = "appStoreDeepLinkOpensSpecificReviewDay.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()

  await store.openDeepLink(URL(string: "lorvex://review/2026-05-20")!)

  #expect(store.selection == .reviews)
  #expect(store.selectedReviewDate == "2026-05-20")
}

@MainActor
@Test
func appStoreIgnoresMalformedDeepLinkURLs() async throws {
  let suiteName = "appStoreIgnoresMalformedDeepLinkURLs.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()
  store.selection = .tasks

  // An impossible calendar date, an empty habit id, and a foreign scheme must
  // all be safely ignored rather than trusted into navigation state.
  await store.openDeepLink(URL(string: "lorvex://review/2026-02-30")!)
  await store.openDeepLink(URL(string: "lorvex://habit/")!)
  await store.openDeepLink(URL(string: "https://lorvex/habit/\(LorvexPreviewSeedID.dailyReviewHabit)")!)

  #expect(store.selection == .tasks)
  #expect(store.selectedHabitID == nil)
}

@MainActor
@Test
func appStoreOpensSpecificHabitFromScheduledReminderNotificationPayload() async throws {
  // The real habit-notification pipeline, end to end: a due occurrence maps to
  // a UNNotificationRequest whose userInfo carries the habit deep link;
  // LorvexNotificationRoute (the same decoder a default-tap handler uses)
  // extracts the URL, which openDeepLink then routes.
  let suiteName = "appStoreOpensSpecificHabitFromScheduledReminderNotificationPayload.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
  await store.refresh()

  let habitID = LorvexPreviewSeedID.dailyReviewHabit
  let occurrence = DueHabitReminderOccurrence(
    policy: HabitReminderPolicy(
      id: "policy-1", habitID: habitID, habitName: "Daily Review", reminderTime: "09:00",
      enabled: true, createdAt: "", updatedAt: ""),
    fireDate: Date(timeIntervalSince1970: 1_800_000_000)
  )
  let reminder = ScheduledHabitReminder(occurrence: occurrence, body: "Time for your habit")
  let route = try #require(LorvexNotificationRoute(userInfo: reminder.notificationRequest.content.userInfo))

  await store.openDeepLink(route.url)

  #expect(store.selection == .habits)
  #expect(store.selectedHabitID == habitID)
}

@MainActor
@Test
func appStoreDeepLinkReusesLoadedTaskPoolBeforeLazyLoading() async throws {
  let suiteName = "appStoreDeepLinkReusesLoadedTaskPoolBeforeLazyLoading.\(UUID().uuidString)"
  let defaults = UserDefaults(suiteName: suiteName)!
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(core: core, defaults: defaults)
  await store.refresh()

  let task = try await core.createTask(title: "Loaded offscreen route target", notes: "")
  store.replaceTask(task)

  let load = store.applyRouteNavigation(.task(task.id))

  #expect(load == nil)
  #expect(store.selection == .tasks)
  #expect(store.selectedTaskID == task.id)
  #expect(store.selectedTask?.id == task.id)
}

@MainActor
@Test
func appStoreKeepsDeepLinkedOffPoolTaskSelectedAcrossRefreshReconcile() async throws {
  let core = StubFocusCoreService(preview: try await makeSeededInMemoryCore())
  let suiteName = "appStoreKeepsDeepLinkedOffPoolTaskSelected.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defaults.removePersistentDomain(forName: suiteName)
  defer { defaults.removePersistentDomain(forName: suiteName) }
  let store = AppStore(core: core, defaults: defaults)

  await store.refresh()
  let task = try #require(store.today.tasks.first)

  // Simulate a deep-link/Spotlight/Handoff open: the route lands on the .tasks
  // surface and loads the task into loadedTasksByID, while the Tasks workspace
  // stays unloaded (so its pool is today.tasks). With today now empty the task
  // is off every visible pool — the pre-fix reconcile would clear the selection
  // and close the just-opened inspector.
  store.taskDetailStorage.loadedTasksByID[task.id] = task
  store.selectedTaskID = task.id
  store.selection = .tasks
  core.todayOverride = TodaySnapshot(
    focusTitle: "Today",
    summary: "All clear for today",
    tasks: [],
    localChangeSequence: 7
  )

  await store.refresh()

  #expect(store.selection == .tasks)
  #expect(!store.taskWorkspaceHasLoaded)
  #expect(store.today.tasks.isEmpty)
  #expect(store.selectedTaskID == task.id)
  #expect(store.selectedTask?.id == task.id)
}

@Test
func scheduledTaskReminderDefaultsToFallbackBodyHidingNotes() throws {
  // Privacy default: freeform notes never render on the lock screen / banner
  // unless the caller explicitly opts in via `includeNotes`.
  let fireDate = try #require(ISO8601DateFormatter().date(from: "2030-05-23T17:00:00Z"))
  let task = LorvexTask(
    id: "task-reminder",
    title: "Review Apple reminder bridge",
    notes: "Make system notification useful.",
    priority: .p1,
    status: .open,
    dueDate: nil,
    estimatedMinutes: 15,
    tags: [],
    reminders: [
      TaskReminder(
        id: "reminder-1",
        reminderAt: "2030-05-23T17:00:00Z",
        status: "pending"
      )
    ]
  )

  let reminder = try #require(
    ScheduledTaskReminder(
      task: task,
      reminder: task.reminders[0],
      now: Date(timeIntervalSince1970: 1_779_552_000),
      fallbackBody: "Lorvex task reminder"
    )
  )

  #expect(reminder.identifier == "lorvex-reminder:reminder-1")
  #expect(reminder.taskID == "task-reminder")
  #expect(reminder.title == "Review Apple reminder bridge")
  #expect(reminder.body == "Lorvex task reminder")
  #expect(reminder.fireDate == fireDate)
  #expect(
    reminder.notificationRequest.content.userInfo[
      LorvexNotificationRoute.deepLinkUserInfoKey
    ] as? String == "lorvex://task/task-reminder"
  )
}

@Test
func scheduledTaskReminderShowsNotesOnlyWhenIncludeNotesIsTrue() throws {
  let task = LorvexTask(
    id: "task-reminder",
    title: "Review Apple reminder bridge",
    notes: "Make system notification useful.",
    priority: .p1,
    status: .open,
    dueDate: nil,
    estimatedMinutes: 15,
    tags: [],
    reminders: [
      TaskReminder(
        id: "reminder-1",
        reminderAt: "2030-05-23T17:00:00Z",
        status: "pending"
      )
    ]
  )

  let reminder = try #require(
    ScheduledTaskReminder(
      task: task,
      reminder: task.reminders[0],
      now: Date(timeIntervalSince1970: 1_779_552_000),
      includeNotes: true
    )
  )

  #expect(reminder.body == "Make system notification useful.")
}

@Test
func scheduledTaskReminderSkipsPastAndClosedTasks() {
  let reminder = TaskReminder(
    id: "reminder-1",
    reminderAt: "2030-05-23T17:00:00Z",
    status: "pending"
  )
  let completed = LorvexTask(
    id: "task-done",
    title: "Done",
    notes: "",
    priority: .p2,
    status: .completed,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: [],
    reminders: [reminder]
  )
  let pastOpen = LorvexTask(
    id: "task-past",
    title: "Past",
    notes: "",
    priority: .p2,
    status: .open,
    dueDate: nil,
    estimatedMinutes: nil,
    tags: [],
    reminders: [reminder]
  )

  #expect(ScheduledTaskReminder.reminders(for: [completed], now: .distantPast).isEmpty)
  #expect(ScheduledTaskReminder.reminders(for: [pastOpen], now: .distantFuture).isEmpty)
}

@Test
func notificationRoutePrefersValidatedDeepLinkAndFallsBackToTaskID() throws {
  let explicit = try #require(
    LorvexNotificationRoute(userInfo: [
      LorvexNotificationRoute.deepLinkUserInfoKey: "lorvex://open/today",
      LorvexNotificationRoute.taskIDUserInfoKey: "task-123",
    ])
  )
  #expect(explicit.url.absoluteString == "lorvex://open/today")

  let fallback = try #require(
    LorvexNotificationRoute(userInfo: [
      LorvexNotificationRoute.taskIDUserInfoKey: "task-123"
    ])
  )
  #expect(fallback.url.absoluteString == "lorvex://task/task-123")

  #expect(
    LorvexNotificationRoute(userInfo: [
      LorvexNotificationRoute.deepLinkUserInfoKey: "https://example.com/task-123"
    ]) == nil
  )
}
