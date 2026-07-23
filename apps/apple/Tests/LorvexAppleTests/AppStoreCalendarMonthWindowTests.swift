import Foundation
import LorvexCore
import Testing

@testable import LorvexApple

/// The Month grid needs a wider timeline window than the day/week default
/// (up to 42 days to cover its leading/trailing weeks); these tests cover the
/// `refreshCalendarTimeline(dayCount:)` parameter and
/// `refreshCurrentCalendarTimeline()`'s preservation of whatever span is
/// currently loaded, independent of the Month grid's own SwiftUI plumbing.

@MainActor
@Test
func refreshCalendarTimelineLoadsTheRequestedDayCountWindow() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian)
  comps.timeZone = .current
  comps.year = 2026
  comps.month = 2
  comps.day = 1
  let anchor = try #require(comps.date)

  try await store.refreshCalendarTimeline(anchorDate: anchor, dayCount: 42)

  #expect(store.calendarTimeline?.from == "2026-02-01")
  #expect(store.calendarTimeline?.to == "2026-03-15")
}

@MainActor
@Test
func refreshCalendarTimelineDefaultsToTheFourteenDayWindow() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian)
  comps.timeZone = .current
  comps.year = 2026
  comps.month = 2
  comps.day = 1
  let anchor = try #require(comps.date)

  try await store.refreshCalendarTimeline(anchorDate: anchor)

  #expect(store.calendarTimeline?.to == "2026-02-15")
}

/// After loading a Month-sized window, a mutation-triggered refresh (create /
/// edit / delete / drag all call `refreshCurrentCalendarTimeline()`) must
/// reload the SAME ~42-day span, not silently narrow back to the day/week
/// default of 14 — otherwise switching to Month, then editing an event near
/// the grid's trailing edge, would truncate the grid on the very next render.
@MainActor
@Test
func refreshCurrentCalendarTimelinePreservesAWiderMonthWindow() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian)
  comps.timeZone = .current
  comps.year = 2026
  comps.month = 2
  comps.day = 1
  let anchor = try #require(comps.date)
  try await store.refreshCalendarTimeline(anchorDate: anchor, dayCount: 42)

  try await store.refreshCurrentCalendarTimeline()

  #expect(store.calendarTimeline?.from == "2026-02-01")
  #expect(store.calendarTimeline?.to == "2026-03-15")
}

@MainActor
@Test
func refreshCurrentCalendarTimelinePreservesTheDefaultFourteenDayWindow() async throws {
  let store = AppStore(core: try await makeSeededInMemoryCore())
  var comps = DateComponents()
  comps.calendar = Calendar(identifier: .gregorian)
  comps.timeZone = .current
  comps.year = 2026
  comps.month = 2
  comps.day = 1
  let anchor = try #require(comps.date)
  try await store.refreshCalendarTimeline(anchorDate: anchor)

  try await store.refreshCurrentCalendarTimeline()

  #expect(store.calendarTimeline?.from == "2026-02-01")
  #expect(store.calendarTimeline?.to == "2026-02-15")
}
