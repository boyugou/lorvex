import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

actor RecordingContentSearchIndexer: ContentSearchIndexing {
  private var indexedListIDs: [String] = []
  private var indexedHabitIDs: [String] = []
  private var indexedReviewDate: String? = nil
  private var indexedCalendarEventIDs: [String] = []
  private var indexedCalendarEventTitles: [String: String] = [:]
  private var reviewIndexCallCount = 0

  func replaceIndexedLists(_ lists: [LorvexList]) async throws {
    indexedListIDs = lists.map(\.id)
  }

  func replaceIndexedHabits(_ habits: [LorvexHabit]) async throws {
    indexedHabitIDs = habits.map(\.id)
  }

  func replaceIndexedDailyReview(_ review: DailyReviewEntry?) async throws {
    indexedReviewDate = review?.date
    reviewIndexCallCount += 1
  }

  func replaceIndexedCalendarEvents(_ events: [CalendarTimelineEvent]) async throws {
    indexedCalendarEventIDs = events.map(\.eventID)
    indexedCalendarEventTitles = Dictionary(
      uniqueKeysWithValues: events.map { ($0.eventID, $0.title) })
  }

  func lastIndexedListIDs() -> [String] { indexedListIDs }
  func lastIndexedHabitIDs() -> [String] { indexedHabitIDs }
  func lastIndexedReviewDate() -> String? { indexedReviewDate }
  func lastIndexedCalendarEventIDs() -> [String] { indexedCalendarEventIDs }
  func lastIndexedCalendarEventTitle(id: String) -> String? { indexedCalendarEventTitles[id] }
  func reviewCallCount() -> Int { reviewIndexCallCount }
}

actor FailingTaskSearchIndexer: TaskSearchIndexing {
  struct Failure: Error, LocalizedError {
    var errorDescription: String? { "task spotlight failed" }
  }

  func replaceIndexedTasks(_ tasks: [LorvexTask]) async throws {
    throw Failure()
  }
}

actor FailingCalendarContentSearchIndexer: ContentSearchIndexing {
  struct Failure: Error, LocalizedError {
    var errorDescription: String? { "calendar spotlight failed" }
  }

  func replaceIndexedLists(_ lists: [LorvexList]) async throws {}
  func replaceIndexedHabits(_ habits: [LorvexHabit]) async throws {}
  func replaceIndexedDailyReview(_ review: DailyReviewEntry?) async throws {}

  func replaceIndexedCalendarEvents(_ events: [CalendarTimelineEvent]) async throws {
    throw Failure()
  }
}

@MainActor
@Test
func appStoreIndexesListsOnRefresh() async throws {
  let contentIndexer = RecordingContentSearchIndexer()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    contentSearchIndexer: contentIndexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )

  await store.refresh()

  let expectedIDs = store.lists?.lists.map(\.id) ?? []
  #expect(!expectedIDs.isEmpty)
  #expect(await contentIndexer.lastIndexedListIDs() == expectedIDs)
}

@MainActor
@Test
func appStoreIndexesActiveHabitsOnRefresh() async throws {
  let contentIndexer = RecordingContentSearchIndexer()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    contentSearchIndexer: contentIndexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )

  await store.refresh()

  let activeHabitIDs = (store.habits?.habits ?? []).filter { !$0.archived }.map(\.id)
  #expect(!activeHabitIDs.isEmpty)
  #expect(await contentIndexer.lastIndexedHabitIDs() == activeHabitIDs)
}

@MainActor
@Test
func appStoreIndexesDailyReviewOnRefresh() async throws {
  let contentIndexer = RecordingContentSearchIndexer()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    contentSearchIndexer: contentIndexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )

  await store.refresh()

  #expect(await contentIndexer.reviewCallCount() == 1)
}

@MainActor
@Test
func appStoreIndexesCalendarEventsOnRefresh() async throws {
  let contentIndexer = RecordingContentSearchIndexer()
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    contentSearchIndexer: contentIndexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )

  await store.refresh()

  let expectedIDs = try await store.calendarEventsForSpotlight().map(\.eventID)
  #expect(!expectedIDs.isEmpty)
  #expect(await contentIndexer.lastIndexedCalendarEventIDs() == expectedIDs)
}

@MainActor
@Test
func appStoreCalendarSpotlightIndexesWideRangeIndependentOfTimelineWindow() async throws {
  let contentIndexer = RecordingContentSearchIndexer()
  let core = try await makeSeededInMemoryCore()
  let anchor = try #require(AppStore.ymdFormatter.date(from: "2026-06-28"))
  let store = AppStore(
    core: core,
    contentSearchIndexer: contentIndexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    now: { anchor }
  )
  let futureEvent = try await core.createCalendarEvent(
    title: "Quarter planning",
    startDate: "2026-10-01",
    endDate: nil,
    startTime: "10:00",
    endTime: "11:00",
    allDay: false,
    location: nil,
    notes: nil,
    recurrence: nil,
    timezone: "UTC",
    url: nil,
    color: nil,
    eventType: nil,
    personName: nil,
    attendees: nil
  )
  store.calendarTimeline = CalendarTimelineSnapshot(
    from: "2026-06-28",
    to: "2026-07-12",
    events: [],
    truncated: false,
    nextOffset: nil
  )

  await store.reindexContentForSpotlight()

  #expect(await contentIndexer.lastIndexedCalendarEventIDs().contains(futureEvent.id))
  #expect(store.lastSpotlightIndexedCalendarEventCount >= 1)
}

@MainActor
@Test
func appStoreCalendarSpotlightIndexesOneStableDocumentPerRecurringSegment() async throws {
  let contentIndexer = RecordingContentSearchIndexer()
  let core = try await makeSeededInMemoryCore()
  let anchor = try #require(AppStore.ymdFormatter.date(from: "2026-06-28"))
  let store = AppStore(
    core: core,
    contentSearchIndexer: contentIndexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher(),
    now: { anchor }
  )
  let series = try await core.createCalendarEvent(
    title: "Recurring Spotlight identity",
    startDate: "2026-06-28",
    endDate: nil,
    startTime: "09:00",
    endTime: "09:30",
    allDay: false,
    location: nil,
    notes: nil,
    recurrence: TaskRecurrenceRule(freq: .daily, count: 3),
    timezone: "UTC",
    url: nil,
    color: nil,
    eventType: nil,
    personName: nil,
    attendees: nil)
  _ = try await core.editScopedCalendarEvent(
    eventID: series.eventID,
    occurrenceDate: "2026-06-28",
    scope: CalendarEventEditScope.thisEvent.rawValue,
    updates: ScopedCalendarEventUpdates(title: "One-off Spotlight replacement"))

  await store.reindexContentForSpotlight()

  let indexedIDs = await contentIndexer.lastIndexedCalendarEventIDs()
  #expect(indexedIDs.filter { $0 == series.id }.count == 1)
  #expect(
    await contentIndexer.lastIndexedCalendarEventTitle(id: series.id)
      == "Recurring Spotlight identity")
}

@MainActor
@Test
func appStoreTaskSpotlightFailureDoesNotOverwriteSuccessfulCount() async throws {
  let core = try await makeSeededInMemoryCore()
  let page = try await core.listTasks(
    status: "all", listID: nil, priority: nil, text: nil, limit: 10, offset: 0)
  let store = AppStore(
    core: core,
    taskSearchIndexer: FailingTaskSearchIndexer(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )
  store.lastSpotlightIndexedTaskCount = 9

  await store.reindexTasksForSpotlight(tasks: page.tasks)

  #expect(store.lastSpotlightIndexedTaskCount == 9)
  #expect(store.appleSurfaceDiagnostics.spotlightStatus.contains("Failed"))
  #expect(store.appleSurfaceDiagnostics.spotlightStatus.contains("task spotlight failed"))
}

@MainActor
@Test
func appStoreCalendarSpotlightFailureDoesNotOverwriteSuccessfulCount() async throws {
  let store = AppStore(
    core: try await makeSeededInMemoryCore(),
    contentSearchIndexer: FailingCalendarContentSearchIndexer(),
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )
  store.lastSpotlightIndexedCalendarEventCount = 7

  await store.reindexContentForSpotlight()

  #expect(store.lastSpotlightIndexedCalendarEventCount == 7)
  #expect(store.appleSurfaceDiagnostics.spotlightStatus.contains("Failed"))
  #expect(store.appleSurfaceDiagnostics.spotlightStatus.contains("calendar spotlight failed"))
}

@MainActor
@Test
func appStoreTaskSpotlightIndexesTasksOutsideStaleTodaySnapshot() async throws {
  let taskIndexer = RecordingTaskSearchIndexer()
  let core = try await makeSeededInMemoryCore()
  let store = AppStore(
    core: core,
    taskSearchIndexer: taskIndexer,
    widgetSnapshotPublisher: RecordingWidgetSnapshotPublisher()
  )

  await store.refresh()
  let created = try await core.createTask(title: "Spotlight stale outside task", notes: "")
  #expect(store.today.tasks.contains { $0.id == created.id } == false)

  await store.reindexTasksForSpotlight()

  #expect(await taskIndexer.lastIndexedIDs().contains(created.id))
}
