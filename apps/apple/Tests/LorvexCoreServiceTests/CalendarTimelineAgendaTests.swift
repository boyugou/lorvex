import Foundation
import XCTest

import LorvexCore

/// Covers the shared "today's schedule" derivation (``CalendarTimelineSnapshot/eventsOccurring(on:)``)
/// and the focus-block kind classification both used by the Today schedule surfaces.
final class CalendarTimelineAgendaTests: XCTestCase {

  private func event(
    id: String,
    title: String = "Event",
    startDate: String,
    startTime: String? = nil,
    endDate: String? = nil,
    endTime: String? = nil,
    allDay: Bool = false,
    source: String = "canonical"
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: id, title: title, source: source, editable: true,
      startDate: startDate, startTime: startTime, endDate: endDate, endTime: endTime,
      allDay: allDay, location: nil, color: nil, eventType: "event",
      timezone: nil, isRecurring: false)
  }

  private func snapshot(_ events: [CalendarTimelineEvent]) -> CalendarTimelineSnapshot {
    CalendarTimelineSnapshot(
      from: "2026-06-01", to: "2026-06-30", events: events, truncated: false, nextOffset: nil)
  }

  func testEventsOccurringFiltersToDay() {
    let snap = snapshot([
      event(id: "today-am", startDate: "2026-06-15", startTime: "09:00"),
      event(id: "tomorrow", startDate: "2026-06-16", startTime: "10:00"),
      event(id: "yesterday", startDate: "2026-06-14", startTime: "08:00"),
    ])
    XCTAssertEqual(snap.eventsOccurring(on: "2026-06-15").map(\.id), ["today-am"])
  }

  func testMultiDayEventAppearsOnEverySpannedDay() {
    let snap = snapshot([
      event(id: "trip", startDate: "2026-06-14", endDate: "2026-06-16", allDay: true)
    ])
    XCTAssertEqual(snap.eventsOccurring(on: "2026-06-14").map(\.id), ["trip"])
    XCTAssertEqual(snap.eventsOccurring(on: "2026-06-15").map(\.id), ["trip"])
    XCTAssertEqual(snap.eventsOccurring(on: "2026-06-16").map(\.id), ["trip"])
    XCTAssertTrue(snap.eventsOccurring(on: "2026-06-17").isEmpty)
  }

  func testAgendaOrdersAllDayThenTimedAscending() {
    let snap = snapshot([
      event(id: "late", startDate: "2026-06-15", startTime: "16:00"),
      event(id: "allday", startDate: "2026-06-15", allDay: true),
      event(id: "early", startDate: "2026-06-15", startTime: "08:30"),
    ])
    XCTAssertEqual(snap.eventsOccurring(on: "2026-06-15").map(\.id), ["allday", "early", "late"])
  }

  func testCarriedOverEventLeadsLikeUnderway() {
    // An event that started before today and spans into it should lead the
    // agenda (it is already underway), ahead of a same-day timed event.
    let snap = snapshot([
      event(id: "timed-today", startDate: "2026-06-15", startTime: "09:00"),
      event(
        id: "carryover", startDate: "2026-06-14", startTime: "23:00", endDate: "2026-06-15"),
    ])
    XCTAssertEqual(snap.eventsOccurring(on: "2026-06-15").map(\.id), ["carryover", "timed-today"])
  }

  func testEventWithoutTimeSortsAfterTimed() {
    let snap = snapshot([
      event(id: "untimed", startDate: "2026-06-15", startTime: nil),
      event(id: "timed", startDate: "2026-06-15", startTime: "11:00"),
    ])
    XCTAssertEqual(snap.eventsOccurring(on: "2026-06-15").map(\.id), ["timed", "untimed"])
  }

  func testFocusScheduleBlockKindClassification() {
    func kind(_ blockType: String) -> FocusScheduleBlock.Kind {
      FocusScheduleBlock(blockType: blockType, startTime: "09:00", endTime: "10:00").kind
    }
    XCTAssertEqual(kind("task"), .task)
    XCTAssertEqual(kind("event"), .calendarEvent)
    XCTAssertEqual(kind("buffer"), .buffer)
    XCTAssertEqual(kind("future_kind"), .unknown)
  }
}
