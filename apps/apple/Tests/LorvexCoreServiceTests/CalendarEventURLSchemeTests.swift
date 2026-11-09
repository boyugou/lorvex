import GRDB
import XCTest

@testable import LorvexCore

/// A calendar event's link is held to the rule the sync wire carries (http, https, webcal) at the
/// write itself. A link the writer took but the outbox refused failed the whole write afterward
/// with a sync-contract message, and a link from another scheme must say what is accepted.
final class CalendarEventURLSchemeTests: XCTestCase {
  private func create(_ service: SwiftLorvexCoreService, url: String?) async throws
    -> CalendarTimelineEvent
  {
    try await service.createCalendarEvent(
      title: "Call", startDate: "2026-11-03", endDate: nil, startTime: "09:00",
      endTime: "10:00", allDay: false, location: nil, notes: nil, recurrence: nil,
      timezone: "America/Los_Angeles", url: url, color: nil, eventType: nil, personName: nil,
      attendees: nil)
  }

  private func update(_ service: SwiftLorvexCoreService, id: String, url: String) async throws {
    _ = try await service.updateCalendarEvent(
      id: id, title: nil, startDate: nil, endDate: nil, startTime: nil, endTime: nil,
      allDay: nil, location: nil, notes: nil, recurrence: .unset, timezone: nil, url: url,
      color: nil, eventType: nil, personName: nil, attendees: .unset)
  }

  private func eventCount(_ service: SwiftLorvexCoreService) throws -> Int {
    try service.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events") ?? 0 }
  }

  private func queuedEventRows(_ service: SwiftLorvexCoreService, id: String) throws -> Int {
    try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'calendar_event' AND entity_id = ?",
        arguments: [id]) ?? 0
    }
  }

  func testALinkTheWireCarriesIsStoredAndQueuedForSync() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    for (given, stored) in [
      ("https://example.invalid/a", "https://example.invalid/a"),
      ("http://example.invalid/a", "http://example.invalid/a"),
      ("WEBCAL://Example.invalid/feed.ics", "webcal://Example.invalid/feed.ics"),
    ] {
      let event = try await create(service, url: given)
      XCTAssertEqual(event.url, stored, given)
      XCTAssertGreaterThan(try queuedEventRows(service, id: event.eventID), 0, given)
    }
  }

  func testALinkFromAnotherSchemeIsRefusedWithTheAcceptedSchemes() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    for link in ["tel:+15555555555", "mailto:someone@example.invalid", "ftp://example.invalid/a"] {
      do {
        _ = try await create(service, url: link)
        XCTFail("\(link) was accepted")
      } catch {
        let message = "\(error)"
        XCTAssertTrue(
          message.contains("http, https, or webcal"), "\(link) was refused with: \(message)")
        XCTAssertFalse(message.contains("sync payload contract"), message)
      }
    }
    XCTAssertEqual(try eventCount(service), 0)
  }

  func testAnUpdateHoldsALinkToTheSameRule() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service, url: "https://example.invalid/a")

    try await update(service, id: event.id, url: "webcal://example.invalid/b")
    var stored = try await service.getCalendarEvent(id: event.id)
    XCTAssertEqual(stored?.url, "webcal://example.invalid/b")

    do {
      try await update(service, id: event.id, url: "tel:+15555555555")
      XCTFail("tel: was accepted on update")
    } catch {
      XCTAssertTrue("\(error)".contains("http, https, or webcal"), "\(error)")
    }
    stored = try await service.getCalendarEvent(id: event.id)
    XCTAssertEqual(stored?.url, "webcal://example.invalid/b")
  }
}
