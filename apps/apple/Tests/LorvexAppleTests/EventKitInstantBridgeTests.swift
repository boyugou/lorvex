@preconcurrency import EventKit
import Foundation
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexApple
@testable import LorvexCore
@testable import LorvexMobile

/// Keep real EKEvent normalization in XCTest's serial phase. Nothing is saved
/// to EventKit; the complete import round trip uses an in-memory Lorvex store.
@MainActor
final class EventKitInstantBridgeTests: XCTestCase {
  func testBothPlatformMappersPreserveBothReadingsOfRepeatedClocks() async throws {
    let eventStore = EKEventStore()
    for (start, end, zone) in [
      ("2026-11-01T05:45:00Z", "2026-11-01T06:15:00Z", "America/New_York"),
      ("2026-11-01T05:30:00Z", "2026-11-01T06:30:00Z", "America/New_York"),
      ("2026-11-01T06:10:00Z", "2026-11-01T06:40:00Z", "America/New_York"),
      ("2026-04-04T14:50:00Z", "2026-04-04T15:10:00Z", "Australia/Lord_Howe"),
    ] {
      let event = EKEvent(eventStore: eventStore)
      event.timeZone = TimeZone(identifier: zone)
      event.startDate = instant(start)
      event.endDate = instant(end)
      event.title = "Imported fold"
      for fetched in [
        LiveEventKitAccess.fetchedEvent(from: event),
        MobileLiveEventKitAccess.fetchedEvent(from: event),
      ] {
        let fetched = try XCTUnwrap(fetched)
        XCTAssertEqual(fetched.occurrenceInstants?.first?.start, instant(start))
        XCTAssertEqual(fetched.occurrenceInstants?.first?.end, instant(end))
        let core = try await service(zone: zone)
        try ingest([fetched], into: core, from: fetched.startDate, to: fetched.startDate)
        let snapshot = try await core.loadCalendarTimeline(
          from: fetched.startDate, to: fetched.startDate)
        let displayed = try XCTUnwrap(snapshot.events.first { $0.source == "provider" })
        XCTAssertEqual(displayed.projection?.start, instant(start))
        XCTAssertEqual(displayed.projection?.end, instant(end))
        XCTAssertEqual(
          displayed.elapsedMinutes, Int(instant(end).timeIntervalSince(instant(start)) / 60))
        XCTAssertTrue(displayed.whenLines(allDay: "All day").second?.contains("GMT") == true)
      }
    }
  }

  func testAssemblyKeepsExactOccurrencesWithMasterOutsideWindowAndDetachedMove() async throws {
    let rule = #"{"FREQ":"WEEKLY","COUNT":4}"#
    let master = fetched(
      day: "2026-10-25", start: "2026-10-25T05:45:00Z", end: "2026-10-25T06:15:00Z", rule: rule)
    let fold = fetched(
      day: "2026-11-01", start: "2026-11-01T05:45:00Z", end: "2026-11-01T06:15:00Z", rule: rule)
    let moved = fetched(
      day: "2026-11-09", start: "2026-11-09T06:45:00Z", end: "2026-11-09T07:15:00Z", rule: rule)
    let assembled = EventKitSeriesAssembly.assemble(
      [
        EventKitOccurrence(event: fold, isDetached: false, occurrenceYmd: "2026-11-01"),
        EventKitOccurrence(event: fold, isDetached: false, occurrenceYmd: "2026-11-01"),
        EventKitOccurrence(event: moved, isDetached: true, occurrenceYmd: "2026-11-08"),
      ], seriesStarts: [master.key: master], windowEndYmd: "2026-11-15")
    XCTAssertEqual(assembled.count, 2)
    XCTAssertEqual(assembled[0].startDate, "2026-10-25")
    XCTAssertEqual(assembled[0].timezone, "America/New_York")
    XCTAssertEqual(assembled[0].recurrence, rule)
    XCTAssertEqual(assembled[1].key, "series:2026-11-08")
    let core = try await service()
    try ingest(assembled, into: core, from: "2026-11-01", to: "2026-11-15")
    let snapshot = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-15")
    let events = snapshot.events.filter { $0.source == "provider" }
    XCTAssertEqual(events.count, 2)
    XCTAssertEqual(
      events.map(\.eventID), ["eventkit:device:series", "eventkit:device:series:2026-11-08"])
    XCTAssertEqual(events[0].projection?.start, instant("2026-11-01T05:45:00Z"))
    XCTAssertEqual(events[0].projection?.end, instant("2026-11-01T06:15:00Z"))
    XCTAssertEqual(events[1].projection?.start, instant("2026-11-09T06:45:00Z"))
    XCTAssertEqual(events[0].id, "eventkit:device:series:occurrence:2026-11-01")
  }

  func testNavigationRetainsOtherWeeksAndCancellationClearsOnlyTheFetchedWeek() async throws {
    let core = try await service()
    let rule = #"{"FREQ":"WEEKLY"}"#
    let first = fetched(
      day: "2026-10-25", start: "2026-10-25T05:45:00Z", end: "2026-10-25T06:15:00Z", rule: rule)
    let second = fetched(
      day: "2026-11-01", start: "2026-11-01T05:45:00Z", end: "2026-11-01T06:15:00Z", rule: rule)
    try ingest([first], into: core, from: "2026-10-25", to: "2026-10-25")
    // An unavailable master lookup must not hide observations already cached
    // before the latest representative's source start_date.
    try ingest([second], into: core, from: "2026-11-01", to: "2026-11-01")
    let before = try await core.loadCalendarTimeline(from: "2026-10-25", to: "2026-11-01")
    XCTAssertEqual(before.events.filter { $0.source == "provider" }.count, 2)
    try ingest([], into: core, from: "2026-11-01", to: "2026-11-01")
    let after = try await core.loadCalendarTimeline(from: "2026-10-25", to: "2026-11-01")
    let remaining = after.events.filter { $0.source == "provider" }
    XCTAssertEqual(remaining.count, 1)
    XCTAssertEqual(remaining.first?.projection?.start, instant("2026-10-25T05:45:00Z"))
    XCTAssertEqual(try core.recurringEventKitMirrorKeys(), ["series"])
  }

  func testFloatingAndAllDayMappersRemainCivil() throws {
    let store = EKEventStore()
    let floating = EKEvent(eventStore: store)
    floating.startDate = instant("2026-11-01T05:45:00Z")
    floating.endDate = instant("2026-11-01T06:15:00Z")
    floating.timeZone = nil
    XCTAssertNil(try XCTUnwrap(LiveEventKitAccess.fetchedEvent(from: floating)).occurrenceInstants)
    XCTAssertNil(
      try XCTUnwrap(MobileLiveEventKitAccess.fetchedEvent(from: floating)).occurrenceInstants)
    floating.timeZone = TimeZone(identifier: "America/New_York")
    floating.isAllDay = true
    XCTAssertTrue(floating.isAllDay)
    XCTAssertNil(try XCTUnwrap(LiveEventKitAccess.fetchedEvent(from: floating)).occurrenceInstants)
    XCTAssertNil(
      try XCTUnwrap(MobileLiveEventKitAccess.fetchedEvent(from: floating)).occurrenceInstants)
  }

  func testDetachedMoveIntoAnotherWeekRemovesTheCachedOriginalSlot() async throws {
    let core = try await service()
    let rule = #"{"FREQ":"WEEKLY"}"#
    let original = fetched(
      day: "2026-11-01", start: "2026-11-01T05:45:00Z",
      end: "2026-11-01T06:15:00Z", rule: rule)
    try ingest([original], into: core, from: "2026-11-01", to: "2026-11-01")
    let moved = fetched(
      day: "2026-11-09", start: "2026-11-09T06:45:00Z",
      end: "2026-11-09T07:15:00Z", rule: rule)
    let rows = EventKitSeriesAssembly.assemble(
      [
        EventKitOccurrence(event: moved, isDetached: true, occurrenceYmd: "2026-11-01")
      ], seriesStarts: [original.key: original], windowEndYmd: "2026-11-09")
    XCTAssertEqual(rows.first?.occurrenceInstants, [])
    try ingest(rows, into: core, from: "2026-11-09", to: "2026-11-09")
    let snapshot = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-09")
    let events = snapshot.events.filter { $0.source == "provider" }
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.eventID, "eventkit:device:series:2026-11-01")
    XCTAssertEqual(events.first?.projection?.start, instant("2026-11-09T06:45:00Z"))
  }

  func testZoneSwitchDuringFetchDoesNotChangeTheReconciliationWindow() async throws {
    let core = try await service()
    let rule = #"{"FREQ":"DAILY"}"#
    let beforeWindow = fetched(
      day: "2026-10-31", start: "2026-11-01T01:00:00Z",
      end: "2026-11-01T01:30:00Z", rule: rule)
    let inWindow = fetched(
      day: "2026-11-01", start: "2026-11-01T05:45:00Z",
      end: "2026-11-01T06:15:00Z", rule: rule)
    try ingest([beforeWindow], into: core, from: "2026-10-31", to: "2026-10-31")
    try ingest([inWindow], into: core, from: "2026-11-01", to: "2026-11-01")
    let requested = DateInterval(
      start: instant("2026-11-01T04:00:00Z"), end: instant("2026-11-02T05:00:00Z"))
    _ = try await core.setPreference(key: "timezone", value: "Asia/Tokyo")
    let provider: any EventKitProviderServicing = core
    _ = try provider.ingestEventKitEvents(
      [], builtAtMode: .fullDetails,
      windowStart: "2026-11-01", windowEnd: "2026-11-01", fetchedWindow: requested)
    let snapshot = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-01")
    let events = snapshot.events.filter { $0.source == "provider" }
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?.projection?.start, instant("2026-11-01T01:00:00Z"))
  }

  func testOneOffReconciliationUsesInstantsAcrossSourceAndProductZones() async throws {
    let core = try await service()
    let before = fetched(
      key: "before", day: "2026-11-01", start: "2026-11-01T01:00:00Z",
      end: "2026-11-01T01:30:00Z", zone: "UTC", rule: nil)
    let inside = fetched(
      key: "inside", day: "2026-11-01", start: "2026-11-01T05:45:00Z",
      end: "2026-11-01T06:15:00Z", zone: "UTC", rule: nil)
    try ingest([before, inside], into: core, from: "2026-10-31", to: "2026-11-01")
    _ = try await core.setPreference(key: "timezone", value: "Asia/Tokyo")
    _ = try core.ingestEventKitEvents(
      [], builtAtMode: .fullDetails,
      windowStart: "2026-11-01", windowEnd: "2026-11-01",
      fetchedWindow: DateInterval(
        start: instant("2026-11-01T04:00:00Z"), end: instant("2026-11-02T05:00:00Z")))
    let snapshot = try await core.loadCalendarTimeline(from: "2026-11-01", to: "2026-11-01")
    XCTAssertEqual(
      snapshot.events.filter { $0.source == "provider" }.map(\.eventID), ["eventkit:device:before"])
  }

  private func service(zone: String = "America/New_York") async throws -> SwiftLorvexCoreService {
    let core = try SwiftLorvexCoreService.inMemory()
    _ = try await core.setPreference(key: "timezone", value: zone)
    _ = try await core.setPreference(
      key: PreferenceKeys.devCalendarAiAccessMode, value: CalendarAiAccessMode.fullDetails.asString)
    return core
  }

  private func ingest(
    _ events: [EventKitFetchedEvent], into core: SwiftLorvexCoreService, from: String, to: String
  ) throws {
    let rows = EventKitIngest.providerRows(from: events, scope: "device", accessMode: .fullDetails)
    _ = try core.ingestEventKitEvents(
      rows, builtAtMode: .fullDetails, windowStart: from, windowEnd: to)
  }

  private func fetched(
    key: String = "series", day: String, start: String, end: String,
    zone: String = "America/New_York", rule: String?
  ) -> EventKitFetchedEvent {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: zone)
    formatter.dateFormat = "HH:mm"
    return EventKitFetchedEvent(
      key: key, title: "Series", notes: nil,
      startDate: day, startTime: formatter.string(from: instant(start)),
      endDate: day, endTime: formatter.string(from: instant(end)), allDay: false, location: nil,
      timezone: zone, recurrence: rule,
      occurrenceInstants: [
        ProviderOccurrenceInstant(date: day, start: instant(start), end: instant(end))
      ])
  }

  private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
}
