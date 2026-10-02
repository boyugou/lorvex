@preconcurrency import EventKit
import Foundation
import LorvexCore
import XCTest

@testable import LorvexApple

/// The Lorvex-calendar mirror of an event is rewritten in place on every edit.
/// EventKit normalizes dates against the all-day flag already set on a reused
/// event, so these run as XCTest, outside Swift Testing's parallel phase
/// (EventKit's unsaved-event normalization uses framework-global state).
final class EventKitAllDayWriteBackTests: XCTestCase {
  private func timelineEvent(
    startDate: String, startTime: String?, endDate: String?, endTime: String?, allDay: Bool
  ) -> CalendarTimelineEvent {
    CalendarTimelineEvent(
      id: "event-mirror", title: "Conference", source: "lorvex", editable: true,
      startDate: startDate, startTime: startTime, endDate: endDate, endTime: endTime,
      allDay: allDay, location: nil, color: nil, eventType: "event", timezone: nil,
      isRecurring: false)
  }

  private func instant(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) throws
    -> Date
  {
    try XCTUnwrap(
      Calendar.current.date(
        from: DateComponents(
          year: 2030, month: 5, day: day, hour: hour, minute: minute, second: second)))
  }

  func testRewritingAMirrorKeepsAnAllDaySpanAndATimedEditKeepsItsTimes() async throws {
    let store = FakeEKEventStore()
    store.sourceList = [EKEventStore().sources.first ?? EKSource()]
    let box = CalendarIDBox()
    let access = LiveEventKitAccess(
      store: store, loadCalendarID: { box.get() }, saveCalendarID: { box.set($0) })
    let allDay = try XCTUnwrap(
      CalendarEventExport(
        event: timelineEvent(
          startDate: "2030-05-24", startTime: nil, endDate: "2030-05-26", endTime: nil,
          allDay: true),
        notes: nil))
    func write(_ export: CalendarEventExport) async throws -> EKEvent {
      _ = try await access.upsertLorvexEvent(
        existingKey: nil, title: export.title, start: export.startDate, end: export.endDate,
        isAllDay: export.isAllDay, location: nil, notes: nil, recurrence: nil,
        lorvexEventID: "lorvex-mirror")
      let saved = try XCTUnwrap(store.savedEvents.last?.0)
      // The next write finds this mirror by its notes marker and reuses it.
      store.fakeEvents = [saved]
      return saved
    }

    let created = try await write(allDay)
    XCTAssertTrue(created.isAllDay)
    XCTAssertEqual(created.startDate, try instant(24))
    XCTAssertEqual(created.endDate, try instant(26, 23, 59, 59))

    let rewritten = try await write(allDay)
    XCTAssertTrue(rewritten === created)
    XCTAssertEqual(rewritten.endDate, try instant(26, 23, 59, 59), "a rewrite must not add a day")

    let timed = try XCTUnwrap(
      CalendarEventExport(
        event: timelineEvent(
          startDate: "2030-05-24", startTime: "09:00", endDate: nil, endTime: "10:00",
          allDay: false),
        notes: nil))
    let retimed = try await write(timed)
    XCTAssertFalse(retimed.isAllDay)
    XCTAssertEqual(retimed.startDate, try instant(24, 9))
    XCTAssertEqual(retimed.endDate, try instant(24, 10))
  }
}
