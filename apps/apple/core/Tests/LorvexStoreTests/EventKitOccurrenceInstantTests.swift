import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class EventKitOccurrenceInstantTests: XCTestCase {
  private let now = "2026-11-01T00:00:00Z"

  func testExactInstantsSurviveStoreProjectionAndPrivacyTiers() throws {
    let vectors = [
      ("2026-11-01T05:45:00Z", "2026-11-01T06:15:00Z", "America/New_York", "01:45", "01:15"),
      ("2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "America/New_York", "01:30", "01:30"),
      ("2026-11-01T06:10:12Z", "2026-11-01T06:40:24Z", "America/New_York", "01:10", "01:40"),
      ("2026-03-08T06:30:00Z", "2026-03-08T07:30:00Z", "America/New_York", "01:30", "03:30"),
      ("2026-04-04T14:50:00Z", "2026-04-04T15:10:00Z", "Australia/Lord_Howe", "01:50", "01:40"),
    ]
    for (start, end, zone, startClock, endClock) in vectors {
      for tier in [CalendarAiAccessMode.fullDetails, .busyOnly] {
        let store = try TestSupport.freshStore()
        let event = fetched(start: start, end: end, zone: zone)
        let row = try XCTUnwrap(
          EventKitIngest.providerRows(
            from: [event], scope: "device", accessMode: tier
          ).first)
        try store.writer.write { db in
          XCTAssertEqual(try ProviderRepo.upsertProviderEvent(db, event: row, now: now), .inserted)
          try ProviderRepo.updateProviderScopeState(
            db, providerKind: "eventkit", providerScope: "device",
            transition: .refreshSuccess(now: now))
          let item = try XCTUnwrap(
            try CalendarTimelineQueries.getCalendarTimeline(
              db, from: event.startDate, to: event.startDate, accessMode: tier, anchorTimezone: zone
            ).first)
          XCTAssertEqual(item.projection?.start, instant(start))
          XCTAssertEqual(item.projection?.end, instant(end))
          XCTAssertEqual(item.startTime?.asString, startClock)
          XCTAssertEqual(item.endTime?.asString, endClock)
          XCTAssertEqual(item.timezone, zone)
          XCTAssertEqual(item.eventId, "eventkit:device:series")
          let reprojected = try CalendarTimeline.projectItemToAnchor(item, "Asia/Tokyo")
          XCTAssertEqual(reprojected.projection?.start, instant(start))
          XCTAssertEqual(reprojected.projection?.end, instant(end))
          if tier == .busyOnly {
            XCTAssertEqual(row.title, "Busy")
            XCTAssertNil(row.description)
            XCTAssertNil(row.location)
            XCTAssertNil(row.attendeesJson)
            XCTAssertNil(row.videoCallUrl)
          }
          if tier == .fullDetails {
            let match = try XCTUnwrap(
              CalendarTimelineQueries.searchProviderCalendarEvents(
                db, predicate: CalendarSearchPredicate(query: "Private"), limit: 10
              ).first)
            XCTAssertEqual(match.projection?.start, instant(start))
            XCTAssertEqual(match.startTime?.asString, startClock)
            XCTAssertEqual(match.timezone, zone)
          }
          XCTAssertNotNil(row.occurrenceInstants)
          XCTAssertFalse(row.occurrenceInstants?.contains("Private") ?? true)
          let blocks = try CalendarTimelineQueries.getDayBlockingRanges(
            db, date: event.startDate, anchorTimezone: zone, accessMode: tier)
          XCTAssertFalse(blocks.isEmpty)
        }
      }
    }
  }

  func testSeriesUsesObservedOccurrencesWithoutInventingCancelledSlots() throws {
    let store = try TestSupport.freshStore()
    let observations = [
      ProviderOccurrenceInstant(
        date: "2026-10-25", start: instant("2026-10-25T05:45:00Z"),
        end: instant("2026-10-25T06:15:00Z")),
      ProviderOccurrenceInstant(
        date: "2026-11-01", start: instant("2026-11-01T05:45:00Z"),
        end: instant("2026-11-01T06:15:00Z")),
      ProviderOccurrenceInstant(
        date: "2026-11-08", start: instant("2026-11-08T06:45:00Z"),
        end: instant("2026-11-08T07:15:00Z")),
    ]
    let event = fetched(
      start: "2026-10-25T05:45:00Z", end: "2026-10-25T06:15:00Z",
      rule: #"{"FREQ":"WEEKLY","COUNT":4}"#, occurrences: observations)
    let row = try XCTUnwrap(
      EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .fullDetails).first)
    try store.writer.write { db in
      _ = try ProviderRepo.upsertProviderEvent(db, event: row, now: now)
      try ProviderRepo.updateProviderScopeState(
        db, providerKind: "eventkit", providerScope: "device",
        transition: .refreshSuccess(now: now))
      let items = try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-10-24", to: "2026-11-22", accessMode: .fullDetails,
        anchorTimezone: "America/New_York")
      XCTAssertEqual(items.count, 3)
      XCTAssertTrue(items.allSatisfy { $0.startTime?.asString == "01:45" && $0.isRecurring })
      XCTAssertEqual(
        items.map(\.id), observations.map { "eventkit:device:series:occurrence:\($0.date)" })
      XCTAssertEqual(items.map { $0.projection?.start }, observations.map { $0.start })
      XCTAssertEqual(Set(items.map(\.eventId)), ["eventkit:device:series"])
      XCTAssertEqual(items[1].endTime?.asString, "01:15")
      XCTAssertEqual(items[2].endTime?.asString, "02:15")
      XCTAssertEqual(row.sourceTzid, "America/New_York")
      XCTAssertEqual(row.startDate, "2026-10-25")
      XCTAssertEqual(row.recurrence, event.recurrence)
      let match = try XCTUnwrap(
        CalendarTimelineQueries.searchProviderCalendarEvents(
          db, predicate: CalendarSearchPredicate(query: "Private"), limit: 10
        ).first)
      XCTAssertEqual(match.id, "eventkit:device:series")
      XCTAssertEqual(match.eventId, "eventkit:device:series")
      XCTAssertEqual(match.projection?.start, observations.first?.start)
    }
  }

  func testWindowRefreshKeepsOtherWeeksAndEmptyRefreshClearsItsWeek() throws {
    let store = try TestSupport.freshStore()
    let first = fetched(
      start: "2026-10-25T13:00:00Z", end: "2026-10-25T13:30:00Z", rule: #"{"FREQ":"WEEKLY"}"#)
    let second = fetched(
      start: "2026-11-01T14:00:00Z", end: "2026-11-01T14:30:00Z", rule: first.recurrence)
    let rows = EventKitIngest.providerRows(
      from: [first, second], scope: "device", accessMode: .fullDetails)
    try store.writer.write { db in
      _ = try ProviderRepo.upsertProviderEvent(db, event: rows[0], now: now)
      let window = DateInterval(
        start: instant("2026-11-01T04:00:00Z"), end: instant("2026-11-02T05:00:00Z"))
      let merged = try XCTUnwrap(
        ProviderRepo.reconcileOccurrenceInstants(
          db, events: [rows[1]], providerKind: "eventkit", scope: "device", window: window, now: now
        ).first)
      XCTAssertEqual(
        try decoded(merged.occurrenceInstants).map(\.date), ["2026-10-25", "2026-11-01"])
      _ = try ProviderRepo.upsertProviderEvent(db, event: merged, now: now)
      _ = try ProviderRepo.reconcileOccurrenceInstants(
        db, events: [], providerKind: "eventkit", scope: "device", window: window,
        now: "2026-10-01T00:00:00Z")
      XCTAssertEqual(
        try decoded(
          String.fetchOne(
            db,
            sql: "SELECT occurrence_instants FROM provider_calendar_events")
        ).count, 2)
      _ = try ProviderRepo.reconcileOccurrenceInstants(
        db, events: [], providerKind: "eventkit", scope: "device", window: window, now: now)
      let json = try String.fetchOne(
        db, sql: "SELECT occurrence_instants FROM provider_calendar_events")
      XCTAssertEqual(try decoded(json).map(\.date), ["2026-10-25"])
    }
  }

  func testStableEncodingAndChangesOfRepeatedHourAreDetected() throws {
    let first = ProviderOccurrenceInstant(
      date: "2026-11-01", start: instant("2026-11-01T05:10:00Z"),
      end: instant("2026-11-01T05:40:00Z"))
    let second = ProviderOccurrenceInstant(
      date: first.date, start: instant("2026-11-01T06:10:00Z"), end: instant("2026-11-01T06:40:00Z")
    )
    XCTAssertEqual(
      ProviderOccurrenceInstant.encode([first, first]), ProviderOccurrenceInstant.encode([first]))
    let store = try TestSupport.freshStore()
    var row = try XCTUnwrap(
      EventKitIngest.providerRows(
        from: [fetched(start: "2026-11-01T05:10:00Z", end: "2026-11-01T05:40:00Z")],
        scope: "device", accessMode: .fullDetails
      ).first)
    try store.writer.write { db in
      XCTAssertEqual(try ProviderRepo.upsertProviderEvent(db, event: row, now: now), .inserted)
      XCTAssertEqual(try ProviderRepo.upsertProviderEvent(db, event: row, now: now), .unchanged)
      row.occurrenceInstants = ProviderOccurrenceInstant.encode([second])
      XCTAssertEqual(try ProviderRepo.upsertProviderEvent(db, event: row, now: now), .updated)
      row.occurrenceInstants = ProviderOccurrenceInstant.encode([first])
      XCTAssertEqual(
        try ProviderRepo.upsertProviderEvent(db, event: row, now: "2026-10-01T00:00:00Z"),
        .unchanged)
      XCTAssertEqual(
        try decoded(
          String.fetchOne(db, sql: "SELECT occurrence_instants FROM provider_calendar_events")),
        [second])
    }
  }

  func testFloatingAndAllDayDoNotAcquireAbsoluteSemantics() throws {
    for allDay in [false, true] {
      let event = EventKitFetchedEvent(
        key: "floating", title: nil, notes: nil,
        startDate: "2026-11-01", startTime: allDay ? nil : "01:45", endDate: nil, endTime: nil,
        allDay: allDay, location: nil, timezone: nil,
        occurrenceInstants: [
          ProviderOccurrenceInstant(
            date: "2026-11-01", start: instant("2026-11-01T05:45:00Z"), end: nil)
        ])
      let row = try XCTUnwrap(
        EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .fullDetails).first)
      XCTAssertNil(row.occurrenceInstants)
      XCTAssertEqual(row.sourceTimeKind, "floating")
    }
    XCTAssertNil(
      ProviderOccurrenceInstant.decode("[{\"date\":\"2026-11-01\",\"start\":2,\"end\":1}]"))
  }

  private func decoded(_ json: String?) throws -> [ProviderOccurrenceInstant] {
    try XCTUnwrap(ProviderOccurrenceInstant.decode(try XCTUnwrap(json)))
  }

  private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

  private func fetched(
    start: String, end: String, zone: String = "America/New_York",
    rule: String? = nil, occurrences: [ProviderOccurrenceInstant]? = nil
  ) -> EventKitFetchedEvent {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: zone)!
    formatter.dateFormat = "yyyy-MM-dd"
    let date = formatter.string(from: instant(start))
    let endDate = formatter.string(from: instant(end))
    formatter.dateFormat = "HH:mm"
    return EventKitFetchedEvent(
      key: "series", title: "Private meeting", notes: "Private note",
      startDate: date, startTime: formatter.string(from: instant(start)),
      endDate: endDate, endTime: formatter.string(from: instant(end)), allDay: false,
      location: "Private place", timezone: zone, recurrence: rule,
      url: "https://example.com/private",
      occurrenceInstants: occurrences ?? [
        ProviderOccurrenceInstant(date: date, start: instant(start), end: instant(end))
      ])
  }
}
