import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@MainActor
@Suite("Calendar edits preserve the event's source time zone")
struct CalendarTimeZoneEditingTests {
  private func fixture(recurring: Bool = false) async throws -> (
    SwiftLorvexCoreService, CalendarTimelineEvent
  ) {
    let core = try await makeSeededInMemoryCore()
    _ = try await core.setPreference(key: "timezone", value: "America/Los_Angeles")
    let event = try await core.createCalendarEvent(
      title: "New York meeting", startDate: "2026-11-16", endDate: nil,
      startTime: "09:00", endTime: "10:00", allDay: false, location: nil, notes: nil,
      recurrence: recurring ? TaskRecurrenceRule(freq: .weekly, interval: 1) : nil,
      timezone: "America/New_York", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-16", to: "2026-11-30")
    let projected = try #require(timeline.events.first { $0.eventID == event.id })
    #expect(projected.startTime == "06:00")
    return (core, projected)
  }

  @Test(arguments: [false, true])
  func editingProjectedTimeSavesTheIntendedInstant(mobile: Bool) async throws {
    let (core, event) = try await fixture()
    if mobile {
      let store = MobileStore(core: core)
      await store.refresh()
      await store.refreshCalendarTimeline(from: "2026-11-16", to: "2026-11-30")
      store.prepareCalendarDraft(for: event)
      let timing = store.calendarDraft.timing
      store.calendarDraft.timing.moveStart(to: try #require(
        timing.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: timing.start)))
      #expect(await store.updateCalendarEvent(event))
      #expect(store.calendarTimeline?.events.first { $0.id == event.id }?.startTime == "07:00")
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      await store.refresh()
      store.prepareCalendarDraft(for: event)
      let timing = store.draftCalendarTiming
      store.draftCalendarTiming.moveStart(to: try #require(
        timing.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: timing.start)))
      await store.updateCalendarEvent(event)
      #expect(store.errorMessage == nil)
    }
    let stored = try #require(await core.getCalendarEvent(id: event.eventID))
    #expect(stored.timezone == "America/New_York")
    #expect(stored.startTime == "10:00")
    #expect(stored.endTime == "11:00")
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-16", to: "2026-11-16")
    #expect(timeline.events.first { $0.id == event.id }?.startTime == "07:00")
  }

  @Test(arguments: [false, true])
  func draggingUsesTheDisplayedClockAndMacUndoKeepsTheSourceZone(mobile: Bool) async throws {
    let (core, event) = try await fixture()
    let day = try #require(LorvexDateFormatters.ymd.date(from: "2026-11-16"))
    let calendar = CalendarEventTiming.deviceCalendar
    let start = try #require(calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day))
    let end = try #require(calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day))
    if mobile {
      let store = MobileStore(core: core)
      await store.refresh()
      await store.refreshCalendarTimeline(from: "2026-11-16", to: "2026-11-30")
      #expect(await store.rescheduleCalendarEvent(event, newStart: start, newEnd: end))
      #expect(store.calendarTimeline?.events.first { $0.id == event.id }?.startTime == "07:00")
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      await store.refresh()
      let undo = UndoManager()
      undo.groupsByEvent = false
      undo.beginUndoGrouping()
      await store.rescheduleCalendarEvent(event, newStart: start, newEnd: end, undoManager: undo)
      undo.endUndoGrouping()
      #expect(try #require(await core.getCalendarEvent(id: event.eventID)).startTime == "10:00")
      #expect(await store.setLogicalTimeZone("Asia/Tokyo"))
      undo.undo()
      try await waitForTime("09:00", eventID: event.eventID, core: core)
      undo.redo()
      try await waitForTime("10:00", eventID: event.eventID, core: core)
      #expect(store.errorMessage == nil)
    }
    let stored = try #require(await core.getCalendarEvent(id: event.eventID))
    #expect(stored.startTime == "10:00")
    #expect(stored.timezone == "America/New_York")
  }

  @Test(arguments: [false, true], [.thisEvent, .thisAndFollowing, .allEvents] as [CalendarEventEditScope])
  func aLaterRecurringOccurrenceKeepsItsSourceAnchor(
    mobile: Bool, scope: CalendarEventEditScope
  ) async throws {
    let (core, first) = try await fixture(recurring: true)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-23", to: "2026-11-23")
    let event = try #require(timeline.events.first { $0.eventID == first.eventID })
    if mobile {
      let store = MobileStore(core: core)
      store.prepareCalendarDraft(for: event)
      let timing = store.calendarDraft.timing
      store.calendarDraft.timing.moveStart(to: try #require(
        timing.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: timing.start)))
      #expect(await store.saveScopedCalendarEvent(event, scope: scope))
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      store.prepareCalendarDraft(for: event)
      let timing = store.draftCalendarTiming
      store.draftCalendarTiming.moveStart(to: try #require(
        timing.calendar.date(bySettingHour: 7, minute: 0, second: 0, of: timing.start)))
      await store.saveScopedCalendarEvent(event, scope: scope)
      #expect(store.errorMessage == nil)
    }
    let updated = try await core.loadCalendarTimeline(from: "2026-11-16", to: "2026-11-30")
    let meetings = updated.events.filter { $0.title == first.title }
    #expect(meetings.count == 3)
    #expect(meetings.first { $0.startDate == "2026-11-23" }?.startTime == "07:00")
    #expect(meetings.first { $0.startDate == "2026-11-16" }?.startTime ==
      (scope == .allEvents ? "07:00" : "06:00"))
    #expect(meetings.first { $0.startDate == "2026-11-30" }?.startTime ==
      (scope == .thisEvent ? "06:00" : "07:00"))
    #expect(meetings.allSatisfy { $0.timezone == "America/New_York" })
  }

  @Test(arguments: [false, true])
  func editingDetailsOfAnOvernightSeriesDoesNotMoveItsFirstDay(mobile: Bool) async throws {
    let (core, first) = try await fixture(recurring: true)
    _ = try await core.updateCalendarEvent(
      id: first.eventID, title: nil, startDate: nil, endDate: "2026-11-17",
      startTime: "23:30", endTime: "00:30", allDay: nil, location: nil, notes: nil)
    _ = try await core.setPreference(key: "timezone", value: "Asia/Tokyo")
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-24", to: "2026-11-24")
    let event = try #require(timeline.events.first { $0.eventID == first.eventID })
    #expect(event.occurrenceDate == "2026-11-23")
    #expect(event.startDate == "2026-11-24")
    #expect(event.startTime == "13:30")
    let timing = CalendarEventTiming(event: event, fallbackDay: .distantPast)
    #expect(timing.keepsSeriesFirstDay(of: event))
    #expect(timing.keepsDaySpan(of: event))
    if mobile {
      let store = MobileStore(core: core)
      store.prepareCalendarDraft(for: event)
      store.calendarDraft.title = "Renamed meeting"
      #expect(await store.saveScopedCalendarEvent(event, scope: .allEvents))
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      store.prepareCalendarDraft(for: event)
      store.draftCalendarTitle = "Renamed meeting"
      await store.saveScopedCalendarEvent(event, scope: .allEvents)
      #expect(store.errorMessage == nil)
    }
    let stored = try #require(await core.getCalendarEvent(id: first.eventID))
    #expect(stored.startDate == "2026-11-16")
    #expect(stored.endDate == "2026-11-17")
    #expect(stored.startTime == "23:30")
    #expect(stored.endTime == "00:30")
  }

  @Test(arguments: [false, true])
  func creatingUsesTheDraftZoneEvenIfThePreferenceChanges(mobile: Bool) async throws {
    let (core, _) = try await fixture()
    _ = try await core.setPreference(key: "timezone", value: "Asia/Tokyo")
    let now = try #require(ISO8601DateFormatter().date(from: "2026-11-15T23:10:00Z"))
    if mobile {
      let store = MobileStore(core: core, now: { now })
      await store.refresh()
      store.beginCreateCalendarDraft()
      #expect(store.calendarDraft.timing.startDate == "2026-11-16")
      #expect(store.calendarDraft.timing.startTime == "09:00")
      store.calendarDraft.title = "Tokyo morning"
      #expect(await store.setLogicalTimeZone("America/Los_Angeles"))
      #expect(await store.createDraftCalendarEvent())
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off, now: { now })
      await store.refresh()
      store.beginCreateCalendarDraft()
      #expect(store.draftCalendarTiming.startDate == "2026-11-16")
      #expect(store.draftCalendarTiming.startTime == "09:00")
      store.draftCalendarTitle = "Tokyo morning"
      #expect(await store.setLogicalTimeZone("America/Los_Angeles"))
      await store.createDraftCalendarEvent()
      #expect(store.errorMessage == nil)
    }
    let events = try await core.searchCalendarEvents(query: "Tokyo morning", from: nil, to: nil, limit: 10)
    let stored = try #require(events.first)
    #expect(stored.timezone == "Asia/Tokyo")
    #expect(stored.startDate == "2026-11-16")
    #expect(stored.startTime == "09:00")
  }

  @Test func aFallBackProjectionKeepsTheSecondOccurrenceOfTheHour() async throws {
    let (core, _) = try await fixture()
    let original = try await core.createCalendarEvent(
      title: "After fall back", startDate: "2026-11-01", endDate: nil,
      startTime: "09:30", endTime: "10:30", allDay: false, location: nil, notes: nil,
      recurrence: nil, timezone: "UTC", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-01")
    let event = try #require(timeline.events.first { $0.eventID == original.id })
    #expect(event.startTime == "01:30")
    let timing = CalendarEventTiming(event: event, fallbackDay: .distantPast)
    #expect(timing.start == ISO8601DateFormatter().date(from: "2026-11-01T09:30:00Z"))
    let store = MobileStore(core: core)
    store.prepareCalendarDraft(for: event)
    store.calendarDraft.timing.setEndTime(try #require(
      timing.calendar.date(bySettingHour: 3, minute: 0, second: 0, of: timing.end)))
    #expect(await store.updateCalendarEvent(event))
    let stored = try #require(await core.getCalendarEvent(id: event.eventID))
    #expect(stored.startTime == "09:30")
    #expect(stored.endTime == "11:00")
  }

  @Test func aGridChoiceDoesNotUseTheDeviceZonesSpringForwardGap() throws {
    let device = LorvexDateFormatters.gregorianCalendar(
      timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")))
    let day = try #require(device.date(from: DateComponents(year: 2026, month: 3, day: 8)))
    let timing = CalendarEventTiming.timed(
      on: day, atMinute: 150, timeZone: try #require(TimeZone(identifier: "Asia/Kathmandu")),
      dayCalendar: device)
    #expect(timing.startDate == "2026-03-08")
    #expect(timing.startTime == "02:30")
    #expect(timing.endTime == "03:30")
    #expect(timing.calendar.timeZone.secondsFromGMT(for: timing.start) == 5 * 3600 + 45 * 60)
  }

  @Test(arguments: [false, true])
  func resizingInTheGridKeepsAnUnchangedSecondFallBackHour(mobile: Bool) async throws {
    let (core, _) = try await fixture()
    let original = try await core.createCalendarEvent(
      title: "Resize after fall back", startDate: "2026-11-01", endDate: nil,
      startTime: "09:30", endTime: "10:30", allDay: false, location: nil, notes: nil,
      recurrence: nil, timezone: "UTC", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-01")
    let event = try #require(timeline.events.first { $0.eventID == original.id })
    let grid = CalendarEventTiming(
      event: event, fallbackDay: .distantPast, calendar: CalendarEventTiming.deviceCalendar)
    let end = try #require(grid.calendar.date(bySettingHour: 3, minute: 0, second: 0, of: grid.end))
    if mobile {
      let store = MobileStore(core: core)
      #expect(await store.rescheduleCalendarEvent(event, newStart: grid.start, newEnd: end))
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      await store.rescheduleCalendarEvent(event, newStart: grid.start, newEnd: end)
      #expect(store.errorMessage == nil)
    }
    let stored = try #require(await core.getCalendarEvent(id: event.eventID))
    #expect(stored.startTime == "09:30")
    #expect(stored.endTime == "11:00")
  }

  @Test(arguments: [false, true])
  func turningAllDayOffUsesTheProductClockWithoutMovingTheChosenDay(mobile: Bool) async throws {
    let (core, _) = try await fixture()
    _ = try await core.setPreference(key: "timezone", value: "Asia/Tokyo")
    let event = try await core.createCalendarEvent(
      title: "Trip", startDate: "2026-11-16", endDate: nil,
      startTime: nil, endTime: nil, allDay: true, location: nil, notes: nil,
      recurrence: nil, timezone: "America/New_York", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    if mobile {
      let store = MobileStore(core: core)
      await store.refresh()
      store.prepareCalendarDraft(for: event)
      store.calendarDraft.timing.allDay = false
      #expect(store.calendarDraft.timing.startDate == "2026-11-16")
      #expect(store.calendarDraft.timing.startTime == "09:00")
      #expect(await store.updateCalendarEvent(event))
    } else {
      let store = AppStore(core: core, cloudSyncMode: .off)
      await store.refresh()
      store.prepareCalendarDraft(for: event)
      store.draftCalendarTiming.allDay = false
      #expect(store.draftCalendarTiming.startDate == "2026-11-16")
      #expect(store.draftCalendarTiming.startTime == "09:00")
      await store.updateCalendarEvent(event)
      #expect(store.errorMessage == nil)
    }
    let timeline = try await core.loadCalendarTimeline(from: "2026-11-16", to: "2026-11-16")
    let displayed = try #require(timeline.events.first { $0.id == event.id })
    #expect(displayed.startDate == "2026-11-16")
    #expect(displayed.startTime == "09:00")
    #expect(displayed.endTime == "10:00")
    #expect(displayed.timezone == "America/New_York")
  }

  @Test func floatingTimesAndAllDayDatesAreNotConvertedOnSave() throws {
    var event = CalendarTimelineEvent(
      id: "floating", title: "Local lunch", source: "canonical", editable: true,
      startDate: "2026-11-16", startTime: "12:00", endDate: nil, endTime: "13:00",
      allDay: false, location: nil, color: nil, eventType: "event", timezone: nil,
      isRecurring: false)
    let zone = try #require(TimeZone(identifier: "Asia/Kathmandu"))
    let floating = CalendarEventTiming(event: event, fallbackDay: .distantPast, fallbackTimeZone: zone)
    #expect(floating.storing(for: event).startTime == "12:00")
    event.allDay = true
    event.timezone = "America/New_York"
    let allDay = CalendarEventTiming(event: event, fallbackDay: .distantPast, fallbackTimeZone: zone)
    #expect(allDay.storing(for: event).startDate == "2026-11-16")
    #expect(allDay.storing(for: event).startTime == nil)
  }

  @Test func aCommittedEditStaysSuccessfulIfItsProjectedWindowCannotReload() async throws {
    let (core, event) = try await fixture()
    let stub = StubCoreService(preview: core)
    stub.forwardsCalendarUpdates = true
    let store = MobileStore(core: stub)
    await store.refreshCalendarTimeline(from: "2026-11-16", to: "2026-11-30")
    store.prepareCalendarDraft(for: event)
    store.calendarDraft.title = "Saved despite a read failure"
    stub.loadCalendarTimelineError = .unsupportedOperation("Injected timeline read failure.")
    #expect(await store.updateCalendarEvent(event))
    #expect(store.errorMessage == nil)
    #expect(try #require(await core.getCalendarEvent(id: event.eventID)).title ==
      "Saved despite a read failure")
    #expect(store.calendarTimeline?.events.first { $0.id == event.id }?.startTime == "06:00")
    let logs = try await core.loadRecentLogs(
      limit: 10, offset: 0, since: nil, levels: nil, sources: ["error_log"], redact: false)
    #expect(logs.entries.contains { $0.origin == "ios.calendar.mutation.reconcile" })
  }

  private func waitForTime(_ time: String, eventID: String, core: SwiftLorvexCoreService) async throws {
    let deadline = ContinuousClock.now + .seconds(30)
    while ContinuousClock.now < deadline {
      if try await core.getCalendarEvent(id: eventID)?.startTime == time { return }
      try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("Calendar undo did not restore \(time)")
  }
}
