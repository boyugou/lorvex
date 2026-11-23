import XCTest

@testable import LorvexCore

/// `getCalendarEvents(ids:)` reads many canonical events in one transaction and
/// must answer exactly as `getCalendarEvent(id:)` answers for each id.
final class CalendarEventBatchReadTests: XCTestCase {
  private func create(_ service: SwiftLorvexCoreService, _ title: String) async throws
    -> CalendarTimelineEvent
  {
    try await service.createCalendarEvent(
      title: title, startDate: "2026-11-03", endDate: nil, startTime: "09:00",
      endTime: "10:00", allDay: false, location: "Room 1", notes: "Agenda", recurrence: nil,
      timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil, personName: nil,
      attendees: nil)
  }

  func testEachIdAnswersAsTheSingleReadDoes() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let first = try await create(service, "Standup")
    let second = try await create(service, "Review")
    let missing = "00000000-0000-4000-8000-000000000000"

    let events = try await service.getCalendarEvents(ids: [second.id, missing, first.id, second.id])

    XCTAssertEqual(Set(events.keys), [first.id, second.id])
    let single = try await service.getCalendarEvent(id: first.id)
    XCTAssertEqual(events[first.id], single)
    XCTAssertEqual(events[second.id]?.title, "Review")
    XCTAssertEqual(events[second.id]?.location, "Room 1")
  }

  func testADeletedEventAnswersAsTheSingleReadDoes() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let kept = try await create(service, "Standup")
    let deleted = try await create(service, "Cancelled")
    _ = try await service.deleteCalendarEvent(id: deleted.id)

    let single = try await service.getCalendarEvent(id: deleted.id)
    let events = try await service.getCalendarEvents(ids: [deleted.id, kept.id])

    XCTAssertEqual(events[deleted.id], single)
    XCTAssertEqual(Set(events.keys), single == nil ? [kept.id] : [kept.id, deleted.id])
  }

  func testNoIdsReturnNothing() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    _ = try await create(service, "Standup")
    let events = try await service.getCalendarEvents(ids: [])
    XCTAssertTrue(events.isEmpty)
  }
}
