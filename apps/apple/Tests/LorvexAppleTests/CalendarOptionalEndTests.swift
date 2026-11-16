import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@MainActor
@Suite("Calendar editors preserve optional ends")
struct CalendarOptionalEndTests {
  @Test(arguments: [false, true], [nil, .thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope?])
  func anEndCanBeExplicitlyAddedAndRemoved(mobile: Bool, scope: CalendarEventEditScope?) async throws {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.setPreference(key: "timezone", value: "America/New_York")
    let raw = try await core.createCalendarEvent(
      title: "Open end", startDate: "2026-03-07", endDate: nil, startTime: "09:00", endTime: nil,
      allDay: false, location: nil, notes: nil,
      recurrence: scope == nil ? nil : TaskRecurrenceRule(freq: .daily, count: 4),
      timezone: "America/New_York", url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    func occurrence() async throws -> CalendarTimelineEvent {
      let events = try await core.loadCalendarTimeline(from: "2026-03-07", to: "2026-03-11").events
      let day = scope == nil ? "2026-03-07" : "2026-03-08"
      return try #require(events.first { $0.title == "Open end" && $0.startDate == day })
    }
    let event = try await occurrence()
    #expect(event.eventID == raw.eventID)
    try await edit(core, event: event, mobile: mobile, scope: scope) { $0.addEndTime() }
    let withEnd = try await occurrence()
    #expect(withEnd.endTime == "10:00")
    #expect(withEnd.endDate == nil)
    try await edit(core, event: withEnd, mobile: mobile, scope: scope) { $0.removeEndTime() }
    let withoutEnd = try await occurrence()
    #expect(withoutEnd.endTime == nil)
    #expect(withoutEnd.endDate == nil)
    #expect(withoutEnd.projection?.end == nil)
    #expect(withoutEnd.startTime == "09:00")
  }

  @Test(arguments: [false, true], [nil, .thisEvent, .thisAndFollowing] as [CalendarEventEditScope?])
  func removingAnOvernightEndAlsoRemovesItsExtraDay(mobile: Bool, scope: CalendarEventEditScope?) async throws {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.setPreference(key: "timezone", value: "America/New_York")
    _ = try await core.createCalendarEvent(
      title: "Overnight", startDate: "2026-03-07", endDate: "2026-03-08",
      startTime: "23:30", endTime: "00:30", allDay: false, location: nil, notes: nil,
      recurrence: scope == nil ? nil : TaskRecurrenceRule(freq: .daily, count: 4),
      timezone: "America/New_York", url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    let day = scope == nil ? "2026-03-07" : "2026-03-08"
    let before = try await core.loadCalendarTimeline(from: day, to: day).events
    let event = try #require(before.first { $0.title == "Overnight" && $0.startDate == day })
    try await edit(core, event: event, mobile: mobile, scope: scope) { $0.removeEndTime() }
    let after = try await core.loadCalendarTimeline(from: day, to: day).events
    let changed = try #require(after.first { $0.title == "Overnight" && $0.startDate == day })
    #expect(changed.startTime == "23:30")
    #expect(changed.endDate == nil && changed.endTime == nil && changed.projection?.end == nil)
  }

  @Test(arguments: [false, true])
  func movingAPointDoesNotGiveItTheGridsVisualLength(mobile: Bool) async throws {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.setPreference(key: "timezone", value: "UTC")
    let raw = try await core.createCalendarEvent(
      title: "Point", startDate: "2026-04-01", endDate: nil, startTime: "09:00", endTime: nil,
      allDay: false, location: nil, notes: nil)
    let events = try await core.loadCalendarTimeline(from: "2026-04-01", to: "2026-04-01").events
    let event = try #require(events.first { $0.eventID == raw.eventID })
    let calendar = CalendarEventTiming.deviceCalendar
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 2, hour: 23, minute: 30)))
    let end = start.addingTimeInterval(3_600)
    if mobile {
      let store = MobileStore(core: core)
      #expect(await store.rescheduleCalendarEvent(event, newStart: start, newEnd: end))
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      await store.rescheduleCalendarEvent(event, newStart: start, newEnd: end)
      #expect(store.errorMessage == nil)
    }
    let moved = try #require(await core.getCalendarEvent(id: event.eventID))
    #expect(moved.startDate == "2026-04-02")
    #expect(moved.startTime == "23:30")
    #expect(moved.endDate == nil)
    #expect(moved.endTime == nil)
  }

  @Test func theProposedEndDoesNotCountAsAnActualEndpoint() throws {
    let event = CalendarTimelineEvent(
      id: "point", title: "Point", source: "canonical", editable: true,
      startDate: "2026-03-07", startTime: "23:30", endDate: nil, endTime: nil,
      allDay: false, location: nil, color: nil, eventType: "event", timezone: "America/New_York", isRecurring: false)
    var timing = CalendarEventTiming(event: event, fallbackDay: .distantPast)
    #expect(!timing.hasEndTime)
    #expect(timing.endDate == nil && timing.endTime == nil && timing.daySpan == 0)
    #expect(timing.isValid)
    timing.moveStart(to: timing.start.addingTimeInterval(3_600))
    #expect(!timing.hasEndTime && timing.endTime == nil)
    let baseline = timing
    timing.allDay = true
    #expect(timing.endDate == nil)
    timing.allDay = false
    #expect(timing.storesSameFields(as: baseline))
    timing.addEndTime()
    #expect(timing.hasEndTime && timing.endTime != nil)
    timing.removeEndTime()
    #expect(timing.storesSameFields(as: baseline))
  }

  @Test func resizingAPointAddsAnEndAndUndoRestoresItsAbsence() async throws {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.setPreference(key: "timezone", value: "UTC")
    let raw = try await core.createCalendarEvent(
      title: "Point", startDate: "2026-04-01", endDate: nil, startTime: "09:00", endTime: nil,
      allDay: false, location: nil, notes: nil)
    let events = try await core.loadCalendarTimeline(from: "2026-04-01", to: "2026-04-01").events
    let event = try #require(events.first { $0.eventID == raw.eventID })
    let calendar = CalendarEventTiming.deviceCalendar
    let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9)))
    let store = AppStore(core: core, cloudSyncMode: .off)
    let undo = UndoManager()
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    await store.rescheduleCalendarEvent(
      event, newStart: start, newEnd: start.addingTimeInterval(3_600), isResize: true, undoManager: undo)
    undo.endUndoGrouping()
    #expect(try #require(await core.getCalendarEvent(id: raw.eventID)).endTime == "10:00")
    _ = try await core.updateCalendarEvent(
      id: raw.eventID, title: "Renamed", startDate: nil, endDate: nil, startTime: nil,
      endTime: nil, allDay: nil, location: nil, notes: nil)
    func waitForEnd(_ expected: String?) async throws -> Bool {
      for _ in 0..<600 {
        if try #require(await core.getCalendarEvent(id: raw.eventID)).endTime == expected { return true }
        try await Task.sleep(for: .milliseconds(50))
      }
      return false
    }
    undo.undo()
    #expect(try await waitForEnd(nil))
    #expect(try #require(await core.getCalendarEvent(id: raw.eventID)).title == "Renamed")
    undo.redo()
    #expect(try await waitForEnd("10:00"))
    #expect(store.errorMessage == nil)
  }

  private func edit(
    _ core: SwiftLorvexCoreService, event: CalendarTimelineEvent,
    mobile: Bool, scope: CalendarEventEditScope?, change: (inout CalendarEventTiming) -> Void
  ) async throws {
    if mobile {
      let store = MobileStore(core: core)
      store.prepareCalendarDraft(for: event)
      change(&store.calendarDraft.timing)
      if let scope { #expect(await store.saveScopedCalendarEvent(event, scope: scope)) }
      else { #expect(await store.updateCalendarEvent(event)) }
      #expect(store.errorMessage == nil)
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      store.prepareCalendarDraft(for: event)
      change(&store.draftCalendarTiming)
      if let scope { await store.saveScopedCalendarEvent(event, scope: scope) }
      else { await store.updateCalendarEvent(event) }
      #expect(store.errorMessage == nil)
    }
  }
}
