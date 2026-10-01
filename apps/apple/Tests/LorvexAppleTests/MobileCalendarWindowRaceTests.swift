import Foundation
import LorvexCore
import Testing

@testable import LorvexMobile

/// The Plan tab asks for its week window as soon as it appears, and the launch
/// refresh can start before that load has committed. The refresh supersedes
/// the week load, so it has to reload the week's window rather than a
/// today-anchored one, or the week would open with its earlier days empty.
@MainActor
@Test
func planningRefreshReloadsTheWindowTheCalendarAskedFor() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  let weekLoad = Task { @MainActor in
    await store.refreshCalendarTimeline(from: "2026-05-17", to: "2026-05-30")
  }
  // Let the week load start, so it has recorded its window and taken a load
  // token, and park at its first await before the refresh begins.
  while store.calendarTimelineLoadToken == 0 { await Task.yield() }
  _ = await store.loadPlanningSnapshotsPreservingLoadedState(date: "2026-05-23")
  await weekLoad.value

  #expect(store.calendarTimeline?.from == "2026-05-17")
  #expect(store.calendarTimeline?.to == "2026-05-30")
}

@MainActor
@Test
func refreshWithoutAnyCalendarLoadUsesTheTodayWindow() async throws {
  let core = try await makeSeededInMemoryCore()
  let store = MobileStore(core: core, todayString: { "2026-05-23" })

  _ = await store.loadPlanningSnapshotsPreservingLoadedState(date: "2026-05-23")

  #expect(store.calendarTimeline?.from == "2026-05-23")
  #expect(store.calendarTimeline?.to == MobileStore.calendarEndDateString(from: "2026-05-23"))
}
