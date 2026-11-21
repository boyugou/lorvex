import Foundation
import LorvexCore
import Testing
import os

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

@MainActor
@Test func todayWorkKeepsItsMeetingWhenBrowsingADistantWeekAndRechecksOnTap() async throws {
  let core = try makeInMemoryCore()
  let morning = morningWallClock(in: .current)()
  let clock = OSAllocatedUnfairLock(initialState: morning)
  let store = MobileStore(core: core, now: { clock.withLock { $0 } })
  let day = try #require(try await core.loadToday().logicalDay)
  let planned = try #require(LorvexDateFormatters.ymdUTC.date(from: day))
  let task = try await core.createTask(TaskCreateDraft(title: "Edit the field notes",
    plannedDate: planned, plannedTime: 480..<600))
  _ = try await core.createCalendarEvent(title: "Editorial call", startDate: day, endDate: day,
    startTime: "08:30", endTime: "09:00", allDay: false, location: nil, notes: nil)
  await store.refresh()
  let far = try #require(LorvexDateFormatters.ymdUTCAddingDays(day, days: 42))
  await store.refreshCalendarTimeline(from: far, to: far)
  #expect(store.calendarTimeline?.from == far)
  func cue(at tick: Date) -> TodayWorkCue? { store.todayWorkCue(for: store.calmToday(at: tick), at: tick) }
  let first = try #require(cue(at: morning))
  #expect(first.action == .start)
  #expect(first.upcoming?.minutesAway == 30)
  #expect(cue(at: morning.addingTimeInterval(1800))?.action == .reviewConflict(event: "Editorial call"))
  clock.withLock { $0 = morning.addingTimeInterval(1800) }
  await store.openTodayWork(first)
  #expect(store.routePath.isEmpty)
  #expect(try await core.loadTask(id: task.id).status == .open)
  clock.withLock { $0 = morning }
  await store.openTodayWork(first)
  #expect(store.routePath == [.task(task.id)])
  #expect(try await core.loadTask(id: task.id).status == .inProgress)
  store.routePath = []
  await store.openTodayWork(first)
  #expect(store.routePath.isEmpty)
  let resume = try #require(cue(at: morning.addingTimeInterval(3600)))
  #expect(resume.action == .resume)
  clock.withLock { $0 = morning.addingTimeInterval(3600) }
  await store.openTodayWork(resume)
  #expect(store.routePath == [.task(task.id)])
  store.separateTodayTimeline = nil
  #expect(cue(at: morning) == nil)
}
