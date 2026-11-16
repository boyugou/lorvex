import Foundation
import LorvexDomain
import XCTest

@testable import LorvexStore

final class CalendarTimelineFoldTests: XCTestCase {
  func testValidUtcSpanSurvivesReversedDisplayClocks() throws {
    let item = try fixture(start: "05:45", end: "06:15")
    let projected = try CalendarTimeline.projectItemToAnchor(item, "America/New_York")
    XCTAssertEqual(projected.startTime?.asString, "01:45")
    XCTAssertEqual(projected.endTime?.asString, "01:15")
    XCTAssertEqual(projected.projection?.end?.timeIntervalSince(projected.projection!.start), 1_800)
    // Display coordinates do not weaken the source timing's validation.
    XCTAssertEqual(projected.timing, item.timing)
    let again = try CalendarTimeline.projectItemToAnchor(projected, "Asia/Tokyo")
    XCTAssertEqual(again.startTime?.asString, "14:45")
    XCTAssertEqual(again.endTime?.asString, "15:15")
  }

  func testTimelineAndBlockingKeepBothSidesOfFallBack() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      for (id, start, end) in [("reverse", "05:45", "06:15"), ("equal", "05:30", "06:30")] {
        try CalendarEventWriteRepo.createCalendarEvent(
          db, params: CalendarEventCreateParams(
            id: id, title: id, timezone: "UTC", startDate: "2026-11-01", startTime: start,
            endDate: "2026-11-01", endTime: end, allDay: false, eventType: "event",
            seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
            recurrenceGeneration: nil, recurrenceTopologyVersion: "1800000000000_0000_1111111111111111",
            version: "1800000000000_0000_1111111111111111", now: "2026-10-01T00:00:00Z"))
      }
      let items = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-11-01", to: "2026-11-01", accessMode: .off,
        anchorTimezone: "America/New_York")
      XCTAssertEqual(Set(items.map(\.id)), ["reverse", "equal"])
      let ranges = try CalendarTimelineQueries.getDayBlockingRanges(
        db, date: "2026-11-01", anchorTimezone: "America/New_York", accessMode: .off)
      XCTAssertEqual(ranges.filter { $0.canonicalEventId == "reverse" }.map { [$0.startMinutes, $0.endMinutes] },
        [[60, 75], [105, 120]])
      XCTAssertEqual(ranges.filter { $0.canonicalEventId == "equal" }.map { [$0.startMinutes, $0.endMinutes] },
        [[60, 120]])
    }
  }

  func testSourceReversedClocksRemainInvalid() throws {
    XCTAssertThrowsError(try fixture(start: "01:45", end: "01:15"))
  }

  func testProviderAndRecurringOccurrencesKeepTheirIdentityAndBusyRanges() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let version = "1800000000000_0000_1111111111111111"
      try CalendarEventWriteRepo.createCalendarEvent(
        db, params: CalendarEventCreateParams(
          id: "series-fold", title: "Series fold", recurrence: #"{"FREQ":"DAILY","COUNT":2}"#,
          timezone: "UTC", startDate: "2026-10-31", startTime: "05:45", endDate: nil, endTime: "06:15",
          allDay: false, eventType: "event", seriesId: nil, recurrenceInstanceDate: nil,
          occurrenceState: nil, recurrenceGeneration: version, recurrenceTopologyVersion: version,
          version: version, now: "2026-10-01T00:00:00Z"))
      try db.execute(sql: """
        INSERT INTO provider_calendar_events
          (provider_kind, provider_scope, provider_event_key, title, start_date, start_time,
           end_date, end_time, all_day, source_time_kind, last_seen_at)
        VALUES ('eventkit', 'device', 'fold', 'Provider fold', '2026-11-01', '05:45',
                '2026-11-01', '06:15', 0, 'utc', '2026-10-01T00:00:00Z')
        """)
      try db.execute(sql: """
        INSERT INTO provider_scope_runtime_state
          (provider_kind, provider_scope, availability_state, last_refresh_success_at, last_refresh_result)
        VALUES ('eventkit', 'device', 'enabled', '2000-01-01T00:00:00Z', 'success')
        """)
      let timeline = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-11-01", to: "2026-11-01", accessMode: .fullDetails, anchorTimezone: "America/New_York")
      XCTAssertEqual(timeline.count, 2)
      let series = try XCTUnwrap(timeline.first { $0.source == .canonical })
      XCTAssertEqual(series.eventId, "series-fold")
      XCTAssertEqual(series.recurrenceInstanceDate, "2026-11-01")
      XCTAssertNotEqual(series.id, series.eventId)
      XCTAssertEqual(series.startTime?.asString, "01:45")
      XCTAssertEqual(series.endTime?.asString, "01:15")
      let busy = try CalendarTimelineQueries.getDayBlockingRanges(
        db, date: "2026-11-01", anchorTimezone: "America/New_York", accessMode: .busyOnly)
      XCTAssertEqual(busy.filter { $0.canonicalEventId == "series-fold" }.count, 2)
      XCTAssertEqual(busy.filter { $0.source == .provider }.count, 2)
      XCTAssertTrue(busy.filter { $0.source == .provider }.allSatisfy(\.stale))
      XCTAssertFalse(busy.contains { $0.title == "Provider fold" })
      let stored = try XCTUnwrap(CalendarTimelineQueries.getCalendarEvent(db, id: "series-fold"))
      XCTAssertEqual(stored.startTime?.asString, "05:45")
      XCTAssertEqual(stored.endTime?.asString, "06:15")
    }
  }

  private func fixture(start: String, end: String) throws -> CalendarTimelineItem {
    try CalendarTimelineItem.make(
      source: .canonical, editable: true, id: "fold", title: "Fold",
      startDate: LorvexDate.parse("2026-11-01").get(), startTime: TimeOfDay.parse(start).get(),
      endDate: nil, endTime: TimeOfDay.parse(end).get(), allDay: false,
      location: nil, color: nil, eventType: "event", personName: nil, timezone: "UTC",
      providerKind: nil, providerScope: nil, isRecurring: false,
      sourceTimeKind: nil, sourceTzid: nil, url: nil, attendeesJson: nil).get()
  }
}
