import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Coverage for the pure EventKit-ingest mapper (`EventKitIngest.providerRows`)
/// and its DB round-trip through the provider timeline read: titleless-event
/// coalescing (so one untitled system event can't abort the refresh) and
/// attendee/organizer serialization into the canonical `attendees_json` shape.
final class EventKitIngestTests: XCTestCase {
  private let now = "2026-06-01T00:00:00Z"

  // MARK: - FIX 1: titleless coalescing

  func testFullDetailsCoalescesNilTitleToUntitled() {
    let event = EventKitFetchedEvent(
      key: "ek-untitled", title: nil, notes: nil,
      startDate: "2026-06-03", startTime: "09:00", endDate: "2026-06-03", endTime: "09:30",
      allDay: false, location: nil, timezone: "America/Los_Angeles")
    let rows = EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .fullDetails)
    XCTAssertEqual(rows.first?.title, "(untitled)")
  }

  func testBusyOnlyKeepsGenericBusyTitleForTitlelessEvent() {
    let event = EventKitFetchedEvent(
      key: "ek-untitled", title: nil, notes: nil,
      startDate: "2026-06-03", startTime: "09:00", endDate: "2026-06-03", endTime: "09:30",
      allDay: false, location: nil, timezone: "America/Los_Angeles")
    let rows = EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .busyOnly)
    XCTAssertEqual(rows.first?.title, "Busy")
  }

  /// A titleless event and a titled event mirror in one batch: the coalesced
  /// row satisfies the NOT NULL `title` column so the single transaction never
  /// aborts and the titled event's row still lands.
  func testTitlelessEventDoesNotAbortBatchRoundTrip() throws {
    let store = try TestSupport.freshStore()
    let batch = [
      EventKitFetchedEvent(
        key: "ek-untitled", title: nil, notes: nil,
        startDate: "2026-06-03", startTime: "09:00", endDate: "2026-06-03", endTime: "09:30",
        allDay: false, location: nil, timezone: "America/Los_Angeles"),
      EventKitFetchedEvent(
        key: "ek-titled", title: "Standup", notes: nil,
        startDate: "2026-06-03", startTime: "10:00", endDate: "2026-06-03", endTime: "10:30",
        allDay: false, location: nil, timezone: "America/Los_Angeles"),
    ]
    let rows = EventKitIngest.providerRows(from: batch, scope: "device", accessMode: .fullDetails)

    let titles = try ingestAndReadTitles(store, rows: rows)
    XCTAssertEqual(titles, ["(untitled)", "Standup"])
  }

  // MARK: - FIX 2: attendee + organizer serialization

  func testFullDetailsSerializesAttendeesInCanonicalShape() {
    let event = attendeeEvent()
    let rows = EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .fullDetails)
    XCTAssertEqual(rows.first?.organizerEmail, "alice@example.com")
    XCTAssertEqual(
      rows.first?.attendeesJson,
      #"[{"email":"alice@example.com","name":"Alice","status":"accepted"},"#
        + #"{"email":"bob@example.com","status":"needs-action"}]"#)
  }

  func testBusyOnlyDropsAttendeesAndOrganizer() {
    let rows = EventKitIngest.providerRows(
      from: [attendeeEvent()], scope: "device", accessMode: .busyOnly)
    XCTAssertNil(rows.first?.attendeesJson)
    XCTAssertNil(rows.first?.organizerEmail)
  }

  func testEmptyAttendeesSerializeToNil() {
    let rows = EventKitIngest.providerRows(
      from: [attendeeEvent(attendees: [])], scope: "device", accessMode: .fullDetails)
    XCTAssertNil(rows.first?.attendeesJson)
  }

  func testFullDetailsCarriesEventURLIntoVideoCallColumn() {
    let event = attendeeEvent(url: "https://example.com/meet/abc")
    let rows = EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .fullDetails)
    XCTAssertEqual(rows.first?.videoCallUrl, "https://example.com/meet/abc")
  }

  func testBusyOnlyDropsEventURL() {
    let event = attendeeEvent(url: "https://example.com/meet/abc")
    let rows = EventKitIngest.providerRows(from: [event], scope: "device", accessMode: .busyOnly)
    XCTAssertNil(rows.first?.videoCallUrl)
  }

  /// The serialized `attendees_json` survives the DB round-trip and reaches the
  /// timeline item unchanged.
  func testAttendeesRoundTripToTimelineItem() throws {
    let store = try TestSupport.freshStore()
    let rows = EventKitIngest.providerRows(
      from: [attendeeEvent()], scope: "device", accessMode: .fullDetails)

    let items = try ingestAndRead(store, rows: rows)
    let item = try XCTUnwrap(items.first { $0.title == "Design sync" })
    let parsed = try XCTUnwrap(JSONValue.parse(try XCTUnwrap(item.attendeesJson)))
    guard case let .array(attendees) = parsed else { return XCTFail("expected JSON array") }
    XCTAssertEqual(attendees.count, 2)
    guard case let .object(alice) = attendees[0] else { return XCTFail("expected object") }
    XCTAssertEqual(alice["email"], .string("alice@example.com"))
    XCTAssertEqual(alice["status"], .string("accepted"))
  }

  // MARK: - Helpers

  private func attendeeEvent(
    url: String? = nil,
    attendees: [EventKitFetchedAttendee] = [
      EventKitFetchedAttendee(email: "alice@example.com", name: "Alice", status: .accepted),
      EventKitFetchedAttendee(email: "bob@example.com", status: .needsAction),
    ]
  ) -> EventKitFetchedEvent {
    EventKitFetchedEvent(
      key: "ek-att", title: "Design sync", notes: nil,
      startDate: "2026-06-04", startTime: "11:00", endDate: "2026-06-04", endTime: "12:00",
      allDay: false, location: nil, timezone: "America/Los_Angeles",
      organizerEmail: "alice@example.com", url: url, attendees: attendees)
  }

  private func ingestAndRead(
    _ store: LorvexStore, rows: [ProviderEventData]
  ) throws -> [CalendarTimelineItem] {
    try store.writer.write { db in
      for event in rows {
        _ = try ProviderRepo.upsertProviderEvent(db, event: event, now: now)
      }
      try ProviderRepo.updateProviderScopeState(
        db, providerKind: ProviderKind.eventkit, providerScope: "device",
        transition: .refreshSuccess(now: now))
    }
    return try store.writer.read { db in
      try CalendarTimelineQueries.getCalendarTimeline(
        db, from: "2026-06-01", to: "2026-06-10", accessMode: .fullDetails, anchorTimezone: "UTC")
    }
  }

  private func ingestAndReadTitles(
    _ store: LorvexStore, rows: [ProviderEventData]
  ) throws -> [String] {
    try ingestAndRead(store, rows: rows).map(\.title).sorted()
  }
}
