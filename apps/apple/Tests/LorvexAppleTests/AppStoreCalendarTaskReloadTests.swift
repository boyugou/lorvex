import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// A task change adds no calendar event, so the Calendar window that a task
/// mutation reloads comes from the store without fetching EventKit again, and
/// completing a block reloads that window once.

@MainActor
private func makeIngestCountingStore(
  core: any LorvexCoreServicing, provider: FakeEventKitProvider
) -> AppStore {
  let coordinator = EventKitCoordinator(
    access: FakeEventKitAccess(), provider: provider,
    loadAccessMode: { .busyOnly }, isEnabled: { true })
  return AppStore(core: core, eventKitCoordinator: coordinator)
}

@MainActor
@Test
func completingATaskWithTheCalendarShownReloadsItsWindowWithoutFetchingEventKit() async throws {
  let core = try await makeSeededInMemoryCore()
  let task = try await core.createTask(title: "Send the weekly status update", notes: "")
  let provider = FakeEventKitProvider()
  let store = makeIngestCountingStore(core: core, provider: provider)
  await store.refresh()
  try await planTask(
    core, task.id, on: store.logicalTodayDateString, time: 10 * 60 + 55..<11 * 60 + 55)
  store.selection = .calendar
  try await store.refreshCalendarTimeline()
  let ingestsBeforeTheChange = provider.ingestedWindows.count
  #expect(ingestsBeforeTheChange > 0, "an explicit refresh fetches EventKit")
  #expect(store.calendarScheduledTasks?.first { $0.id == task.id }?.status == .open)

  await store.completeTask(id: task.id)

  #expect(store.calendarScheduledTasks?.first { $0.id == task.id }?.status == .completed)
  #expect(provider.ingestedWindows.count == ingestsBeforeTheChange)
}

@MainActor
@Test
func refreshingTheCurrentCalendarWindowFetchesEventKitUnlessToldNotTo() async throws {
  let provider = FakeEventKitProvider()
  let store = makeIngestCountingStore(
    core: try await makeSeededInMemoryCore(), provider: provider)
  store.selection = .calendar
  try await store.refreshCalendarTimeline()
  let ingestsAfterTheFirstLoad = provider.ingestedWindows.count

  try await store.refreshCurrentCalendarTimeline()
  #expect(provider.ingestedWindows.count == ingestsAfterTheFirstLoad + 1)

  try await store.refreshCurrentCalendarTimeline(ingestingEventKit: false)
  #expect(provider.ingestedWindows.count == ingestsAfterTheFirstLoad + 1)
}

@MainActor
@Test
func completingACalendarBlockReloadsTheWindowOnceWhetherOrNotTheCalendarIsShown() async throws {
  var loadsPerCompletion: [SidebarSelection: Int] = [:]
  for selection in [SidebarSelection.calendar, .today] {
    let core = StubCoreService(preview: try await makeSeededInMemoryCore())
    let task = try await core.createTask(title: "Send the weekly status update", notes: "")
    let store = AppStore(core: core)
    await store.refresh()
    try await planTask(
      core, task.id, on: store.logicalTodayDateString, time: 10 * 60 + 55..<11 * 60 + 55)
    try await store.refreshCalendarTimeline()
    store.selection = selection
    let loadsBefore = core.loadCalendarTimelineCallCount

    await store.toggleCalendarTaskCompletion(id: task.id)

    loadsPerCompletion[selection] = core.loadCalendarTimelineCallCount - loadsBefore
    #expect(store.calendarScheduledTasks?.first { $0.id == task.id }?.status == .completed)
  }

  #expect(loadsPerCompletion[.calendar] == loadsPerCompletion[.today])
  #expect(loadsPerCompletion[.today, default: 0] >= 1)
}
