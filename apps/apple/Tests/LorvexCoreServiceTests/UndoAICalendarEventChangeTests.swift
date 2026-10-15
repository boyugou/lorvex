import GRDB
import XCTest

@testable import LorvexCore

/// Undoing an assistant's update to a one-off calendar event puts back the fields that change
/// moved, as long as they still hold what the change set. The date, times, all-day flag, and time
/// zone go back together; an event that repeats is refused.
final class UndoAICalendarEventChangeTests: XCTestCase {
  private func create(
    _ service: SwiftLorvexCoreService, start: String = "2026-11-03", end: String? = nil,
    startTime: String? = "09:00", endTime: String? = "10:00", location: String? = "Clinic",
    notes: String? = "Bring forms", timezone: String? = "America/Los_Angeles",
    recurrence: TaskRecurrenceRule? = nil, attendees: [CalendarEventAttendee]? = nil
  ) async throws -> CalendarTimelineEvent {
    try await service.createCalendarEvent(
      title: "Dentist", startDate: start, endDate: end, startTime: startTime, endTime: endTime,
      allDay: startTime == nil, location: location, notes: notes, recurrence: recurrence,
      timezone: timezone, url: nil, color: nil, eventType: nil, personName: nil,
      attendees: attendees)
  }

  /// An update by an assistant, as an MCP tool call makes it.
  private func assistantEdit(
    _ service: SwiftLorvexCoreService, _ id: String, title: String? = nil,
    startDate: String? = nil, endDate: String? = nil, startTime: String? = nil,
    endTime: String? = nil, allDay: Bool? = nil, location: String? = nil, notes: String? = nil,
    timezone: String? = nil, url: String? = nil, color: String? = nil, personName: String? = nil,
    attendees: CalendarEventAttendeesPatch = .unset
  ) async throws {
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.updateCalendarEvent(
        id: id, title: title, startDate: startDate, endDate: endDate, startTime: startTime,
        endTime: endTime, allDay: allDay, location: location, notes: notes, recurrence: .unset,
        timezone: timezone, url: url, color: color, eventType: nil, personName: personName,
        attendees: attendees)
    }
  }

  /// A person's edit, after the assistant's.
  private func personEdit(
    _ service: SwiftLorvexCoreService, _ id: String, location: String? = nil,
    timezone: String? = nil
  ) async throws {
    _ = try await service.updateCalendarEvent(
      id: id, title: nil, startDate: nil, endDate: nil, startTime: nil, endTime: nil, allDay: nil,
      location: location, notes: nil, recurrence: .unset, timezone: timezone, url: nil,
      color: nil, eventType: nil, personName: nil, attendees: .unset)
  }

  private func latestUpdateID(_ service: SwiftLorvexCoreService, event: String) throws -> String {
    try XCTUnwrap(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT id FROM ai_changelog
            WHERE entity_id = ? AND operation = 'update' ORDER BY timestamp DESC, id DESC LIMIT 1
            """,
          arguments: [event])
      })
  }

  private func changelogCount(_ service: SwiftLorvexCoreService) throws -> Int {
    try service.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1 }
  }

  private func refusal(_ service: SwiftLorvexCoreService, _ id: String) async -> String? {
    do {
      _ = try await service.undoAIChange(changelogID: id)
      return nil
    } catch let LorvexCoreError.validation(field, message) {
      XCTAssertEqual(field, "changelog_id")
      return message
    } catch {
      return "unexpected \(error)"
    }
  }

  func testUndoPutsBackEveryFieldTheChangeMoved() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(
      service, attendees: [CalendarEventAttendee(email: "ana@example.com", name: "Ana")])
    try await assistantEdit(
      service, event.id, title: "Dentist (moved)", startDate: "2026-11-05", startTime: "14:00",
      endTime: "15:30", location: "Annex", notes: "Bring forms and card",
      url: "https://example.com/visit", color: "#FF8800", personName: "Dr. Lee",
      attendees: .set([CalendarEventAttendee(email: "bo@example.com", name: "Bo")]))
    let id = try latestUpdateID(service, event: event.id)
    let before = try changelogCount(service)

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.event)
    XCTAssertNil(result.task)
    XCTAssertEqual(
      Set(result.reverted),
      ["title", "description", "schedule", "location", "url", "color", "person_name", "attendees"])
    XCTAssertTrue(result.kept.isEmpty)
    XCTAssertEqual(restored.title, "Dentist")
    XCTAssertEqual(restored.notes, "Bring forms")
    XCTAssertEqual(restored.startDate, "2026-11-03")
    XCTAssertEqual(restored.startTime, "09:00")
    XCTAssertEqual(restored.endTime, "10:00")
    XCTAssertEqual(restored.location, "Clinic")
    XCTAssertNil(restored.url)
    XCTAssertNil(restored.color)
    XCTAssertNil(restored.personName)
    XCTAssertEqual(restored.attendees?.map(\.email), ["ana@example.com"])
    XCTAssertEqual(try changelogCount(service), before + 1, "the undo is itself a logged change")
    let stored = try service.read { db in
      try Row.fetchOne(
        db, sql: "SELECT title, start_date, start_time, location FROM calendar_events WHERE id = ?",
        arguments: [event.id])
    }
    XCTAssertEqual(stored?["title"] as String?, "Dentist")
    XCTAssertEqual(stored?["start_date"] as String?, "2026-11-03")
    XCTAssertEqual(stored?["start_time"] as String?, "09:00")
    XCTAssertEqual(stored?["location"] as String?, "Clinic")
  }

  func testTheLogSaysTheUpdateTookAChangeBack() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service)
    try await assistantEdit(service, event.id, title: "Dentist (moved)")
    let id = try latestUpdateID(service, event: event.id)

    _ = try await service.undoAIChange(changelogID: id)

    let summary = try service.read { db in
      try String.fetchOne(
        db,
        sql: """
          SELECT summary FROM ai_changelog
          WHERE entity_id = ? AND operation = 'update' ORDER BY timestamp DESC, id DESC LIMIT 1
          """,
        arguments: [event.id])
    }
    XCTAssertEqual(summary, "Took back an earlier change to calendar event 'Dentist'")
  }

  func testAFieldEditedSinceIsKeptAndTheRestIsPutBack() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service)
    try await assistantEdit(service, event.id, title: "Dentist (moved)", location: "Annex")
    let id = try latestUpdateID(service, event: event.id)
    try await personEdit(service, event.id, location: "Main office")

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.event)
    XCTAssertEqual(result.reverted, ["title"])
    XCTAssertEqual(result.kept, ["location"])
    XCTAssertEqual(restored.title, "Dentist")
    XCTAssertEqual(restored.location, "Main office", "a later edit is never overwritten")
  }

  func testTheScheduleGoesBackOrStaysAsOneValue() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service)
    // The assistant moves the start time only; a person then changes the time zone, so the
    // time is no longer the value the assistant left. It stays, whole.
    try await assistantEdit(service, event.id, startTime: "11:00", endTime: "12:00")
    let id = try latestUpdateID(service, event: event.id)
    try await personEdit(service, event.id, timezone: "America/New_York")

    let result = try await service.undoAIChange(changelogID: id)

    let kept = try XCTUnwrap(result.event)
    XCTAssertTrue(result.reverted.isEmpty)
    XCTAssertEqual(result.kept, ["schedule"])
    XCTAssertEqual(kept.startTime, "11:00")
    XCTAssertEqual(kept.timezone, "America/New_York")
  }

  func testATimedEventTurnedAllDayGetsItsTimesBack() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service)
    try await assistantEdit(service, event.id, allDay: true)
    let id = try latestUpdateID(service, event: event.id)

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.event)
    XCTAssertEqual(result.reverted, ["schedule"])
    XCTAssertFalse(restored.allDay)
    XCTAssertEqual(restored.startTime, "09:00")
    XCTAssertEqual(restored.endTime, "10:00")
  }

  func testAnAllDayEventMadeTimedGoesBackToAllDay() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service, startTime: nil, endTime: nil, timezone: nil)
    try await assistantEdit(service, event.id, startTime: "09:00", endTime: "10:00", allDay: false)
    let id = try latestUpdateID(service, event: event.id)

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.event)
    XCTAssertEqual(result.reverted, ["schedule"])
    XCTAssertTrue(restored.allDay)
    XCTAssertNil(restored.startTime)
    XCTAssertNil(restored.endTime)
  }

  func testASingleDayEventWithAStoredSameDayEndDateMovesBack() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(
      service, start: "2026-09-18", end: "2026-09-18", startTime: "00:55", endTime: nil)
    try await assistantEdit(service, event.id, startDate: "2026-11-05")
    let id = try latestUpdateID(service, event: event.id)

    let result = try await service.undoAIChange(changelogID: id)

    let restored = try XCTUnwrap(result.event)
    XCTAssertEqual(result.reverted, ["schedule"])
    XCTAssertEqual(restored.startDate, "2026-09-18")
    XCTAssertEqual(restored.startTime, "00:55")
  }

  func testUndoingTwiceChangesNothingTheSecondTime() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service)
    try await assistantEdit(service, event.id, title: "Dentist (moved)")
    let id = try latestUpdateID(service, event: event.id)
    _ = try await service.undoAIChange(changelogID: id)
    let afterFirst = try changelogCount(service)

    let second = try await service.undoAIChange(changelogID: id)

    XCTAssertTrue(second.reverted.isEmpty)
    XCTAssertEqual(second.event?.title, "Dentist")
    XCTAssertEqual(try changelogCount(service), afterFirst, "nothing was written")
  }

  func testAnEventThatRepeatsIsRefused() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service, recurrence: TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))
    try await assistantEdit(service, event.id, title: "Dentist (moved)")
    let id = try latestUpdateID(service, event: event.id)

    let message = await refusal(service, id)

    XCTAssertEqual(message?.contains("one-off calendar event"), true, "\(message ?? "")")
    let stored = try service.read { db in
      try String.fetchOne(db, sql: "SELECT title FROM calendar_events WHERE id = ?", arguments: [event.id])
    }
    XCTAssertEqual(stored, "Dentist (moved)", "nothing was changed")
  }

  func testAnEventDeletedSinceIsRefused() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service)
    try await assistantEdit(service, event.id, title: "Dentist (moved)")
    let id = try latestUpdateID(service, event: event.id)
    _ = try await service.deleteCalendarEvent(id: event.id)

    let message = await refusal(service, id)

    XCTAssertEqual(message?.contains("no longer exists"), true, "\(message ?? "")")
  }

  func testAPersonsEditToAnEventCannotBeUndone() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let event = try await create(service)
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.user
    ) {
      try await service.updateCalendarEvent(
        id: event.id, title: "Mine", startDate: nil, endDate: nil, startTime: nil, endTime: nil,
        allDay: nil, location: nil, notes: nil, recurrence: .unset, timezone: nil, url: nil,
        color: nil, eventType: nil, personName: nil, attendees: .unset)
    }
    let id = try latestUpdateID(service, event: event.id)

    let message = await refusal(service, id)

    XCTAssertEqual(message?.contains("not made by an assistant"), true, "\(message ?? "")")
  }
}
