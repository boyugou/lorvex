import Foundation
import LorvexCore
import Testing

@testable import LorvexApple
@testable import LorvexMobile

@Suite("Conservative calendar display grouping")
struct CalendarDuplicateGroupingTests {
  static func event(_ id: String, calendar: String = "a") -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, title: "Standup", source: "provider", editable: false,
      startDate: "2026-11-16", startTime: "10:00", endDate: "2026-11-16", endTime: "11:00",
      allDay: false, location: "Room B", notes: "Agenda", color: nil,
      eventType: "event", timezone: nil, isRecurring: false,
      origin: CalendarEventOrigin(calendarID: calendar, calendarTitle: calendar))
  }

  @Test func strictCombinesDistinctCalendarsAndOffRestoresEveryCopy() {
    let a = Self.event("one")
    let b = Self.event("two", calendar: "b")
    let combined = CalendarDuplicateGrouping.strict.events([b, a])
    #expect(combined.count == 1)
    #expect(combined.first?.id == a.id)
    #expect(combined.first?.displayCopies == [a, b])
    #expect(CalendarDuplicateGrouping.off.events(combined) == [a, b])
    #expect(CalendarDuplicateGrouping.strict.events(combined) == combined)
    #expect(a.combinedEventCopies.isEmpty)
  }

  @Test(arguments: [
    "location", "notes", "url", "organizer", "attendee", "response", "recurrence", "sourceContext",
    "timezone",
  ])
  func differingDetailsRequireExplicitTitleAndTimeMode(_ field: String) {
    var a = Self.event("one")
    var b = Self.event("two", calendar: "b")
    a.attendees = [.init(email: "participant", status: "accepted")]
    b.attendees = a.attendees
    switch field {
    case "location": b.location = "Room A and Room B"
    case "notes": b.notes = "Different agenda"
    case "url": b.url = "https://example.invalid/another-room"
    case "organizer": b.personName = "another-organizer"
    case "attendee": b.attendees = [.init(email: "another-participant", status: "accepted")]
    case "response": b.attendees?[0].status = "declined"
    case "recurrence": b.isRecurring = true
    case "sourceContext":
      b.origin = .init(
        calendarID: "b", calendarTitle: "b", contentSignature: "different-rule-or-alarm")
    case "timezone":
      // Floating and zoned clocks are distinct even in the relaxed mode.
      b.timezone = "UTC"
    default: break
    }
    #expect(CalendarDuplicateGrouping.strict.events([a, b]).count == 2)
    #expect(
      CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == (field == "timezone" ? 2 : 1))
  }

  @Test func sameCalendarDuplicatesMakeTheWholeCandidateSetAmbiguous() {
    let events = [Self.event("one"), Self.event("two"), Self.event("three", calendar: "b")]
    #expect(CalendarDuplicateGrouping.strict.events(events) == events)
    #expect(CalendarDuplicateGrouping.titleAndTime.events(events) == events)
  }

  @Test func unknownOriginsOwnedEventsAndHiddenDetailNeverCombine() {
    let a = Self.event("one")
    var b = Self.event("two", calendar: "b")
    b.origin = nil
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
    b.origin = a.origin
    b.source = "canonical"
    b.editable = true
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
  }

  @Test func titleOverlapAndOpenEndedEventsDoNotMatch() {
    let a = Self.event("one")
    var b = Self.event("two", calendar: "b")
    b.title = "standup"
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
    b.title = a.title
    b.endTime = "11:01"
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
    b.endTime = nil
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
  }

  @Test func allDaySpansUseCivilDatesAndDoNotMixWithTimedEvents() {
    var a = Self.event("one")
    var b = Self.event("two", calendar: "b")
    a.allDay = true
    a.startTime = nil
    a.endTime = nil
    b.allDay = true
    b.startTime = nil
    b.endTime = nil
    #expect(CalendarDuplicateGrouping.strict.events([a, b]).count == 1)
    b.endDate = "2026-11-17"
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
    b = Self.event("two", calendar: "b")
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
  }

  @Test func exactInstantsDistinguishRepeatedHourAndIgnoreDisplayZone() {
    var a = Self.event("one")
    var b = Self.event("two", calendar: "b")
    let start = Date(timeIntervalSince1970: 1_793_523_600)
    a.timezone = "America/Los_Angeles"
    b.timezone = a.timezone
    a.projection = .init(
      timezone: "America/Los_Angeles", start: start, end: start.addingTimeInterval(1800))
    b.projection = a.projection
    #expect(CalendarDuplicateGrouping.strict.events([a, b]).count == 1)
    b.projection = .init(
      timezone: "America/Los_Angeles", start: start.addingTimeInterval(3600),
      end: start.addingTimeInterval(5400))
    #expect(CalendarDuplicateGrouping.titleAndTime.events([a, b]).count == 2)
    b.projection = .init(timezone: "Asia/Tokyo", start: start, end: start.addingTimeInterval(1800))
    #expect(CalendarDuplicateGrouping.strict.events([a, b]).count == 1)
  }

  @Test func colorAndAttendeeOrderingAreNotEventContentDifferences() {
    var a = Self.event("one")
    var b = Self.event("two", calendar: "b")
    a.color = "#FF0000"
    b.color = "#0000FF"
    a.attendees = [.init(email: "first"), .init(email: "second")]
    b.attendees = Array((a.attendees ?? []).reversed())
    #expect(CalendarDuplicateGrouping.strict.events([a, b]).count == 1)
  }

  @Test @MainActor func mobileSettingIsImmediateReversibleAndRemembered() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = MobileStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
    store.calendarTimeline = .init(
      from: "2026-11-16", to: "2026-11-16",
      events: [Self.event("one"), Self.event("two", calendar: "b")], truncated: false,
      nextOffset: nil)
    #expect(store.calendarTimeline?.events.count == 1)
    store.calendarDuplicateGrouping = .off
    #expect(store.calendarTimeline?.events.count == 2)
    #expect(CalendarDuplicateGrouping.remembered(in: defaults) == .off)
    store.calendarDuplicateGrouping = .strict
    #expect(store.calendarTimeline?.events.count == 1)
    #expect(store.rawCalendarTimeline?.events.count == 2)
  }

  @Test @MainActor func macSettingAndSelectionRetainAllCopies() async throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = AppStore(core: try await makeSeededInMemoryCore(), defaults: defaults)
    let a = Self.event("one")
    let b = Self.event("two", calendar: "b")
    store.calendarTimeline = .init(
      from: "2026-11-16", to: "2026-11-16", events: [a, b],
      truncated: false, nextOffset: nil)
    store.selectCalendarEvent(b)
    #expect(Set(store.selectedCalendarEvent?.displayCopies.map(\.id) ?? []) == [a.id, b.id])
    #expect(store.selectedCalendarEvent?.id == b.id)
    store.calendarDuplicateGrouping = .off
    #expect(store.calendarTimeline?.events == [a, b])
    #expect(store.selectedCalendarEvent?.id == "two")
    store.calendarDuplicateGrouping = .strict
    #expect(Set(store.selectedCalendarEvent?.displayCopies.map(\.id) ?? []) == [a.id, b.id])
    #expect(CalendarDuplicateGrouping.remembered(in: defaults) == .strict)
  }
}
