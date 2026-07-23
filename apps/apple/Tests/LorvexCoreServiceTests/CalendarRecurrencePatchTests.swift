import Foundation
import GRDB
import LorvexStore
import XCTest

@testable import LorvexCore

/// The calendar update boundary is intentionally three-state: omitted keeps the
/// current series, null stops recurrence, and an object replaces the rule. These
/// tests pin the distinction through the real SQLite workflow, including
/// occurrence-decision and scoped-series side effects that a fake could miss.
final class CalendarRecurrencePatchTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func makeDailySeries(
    _ service: SwiftLorvexCoreService,
    count: Int? = nil
  ) async throws -> CalendarTimelineEvent {
    try await service.createCalendarEvent(
      title: "Daily planning", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .daily, interval: 1, count: count),
      timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
  }

  private func update(
    _ service: SwiftLorvexCoreService,
    id: String,
    title: String? = nil,
    recurrence: CalendarEventRecurrencePatch
  ) async throws -> CalendarTimelineEvent {
    try await service.updateCalendarEvent(
      id: id, title: title, startDate: nil, endDate: nil, startTime: nil,
      endTime: nil, allDay: nil, location: nil, notes: nil,
      recurrence: recurrence, timezone: nil, url: nil, color: nil,
      eventType: nil, personName: nil, attendees: .unset)
  }

  func testUpdateDistinguishesUnsetSetAndClear() async throws {
    let service = try makeService()
    let event = try await makeDailySeries(service)
    _ = try await service.addCalendarEventException(eventID: event.id, date: "2026-06-02")

    let preserved = try await update(
      service, id: event.id, title: "Renamed planning", recurrence: .unset)
    XCTAssertEqual(preserved.title, "Renamed planning")
    XCTAssertTrue(preserved.isRecurring)
    XCTAssertEqual(try exceptionCount(service, eventID: event.id), 1)

    let replaced = try await update(
      service, id: event.id,
      recurrence: .set(TaskRecurrenceRule(freq: .daily, interval: 2)))
    XCTAssertTrue(replaced.isRecurring)
    XCTAssertEqual(TaskRecurrenceRule.bridgeRule(from: replaced.recurrenceRule)?.interval, 2)
    XCTAssertEqual(
      try exceptionCount(service, eventID: event.id), 0,
      "replacing a recurrence rule invalidates the old occurrence-decision generation")

    _ = try await service.addCalendarEventException(eventID: event.id, date: "2026-06-03")
    let cleared = try await update(service, id: event.id, recurrence: .clear)
    XCTAssertFalse(cleared.isRecurring)
    XCTAssertNil(cleared.recurrenceRule)
    XCTAssertEqual(try exceptionCount(service, eventID: event.id), 0)
  }

  func testAllSeriesClearSweepsOverridesAndExceptions() async throws {
    let service = try makeService()
    let event = try await makeDailySeries(service)
    _ = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-02", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "One moved occurrence"))

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-02", scope: "all_in_series",
      updates: ScopedCalendarEventUpdates(recurrence: .clear))

    let updated = try XCTUnwrap(result.replacementEvent)
    XCTAssertFalse(updated.isRecurring)
    XCTAssertNil(updated.recurrenceRule)
    let decisions = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE series_id = ?",
        arguments: [event.id]) ?? -1
    }
    XCTAssertEqual(decisions, 0)
  }

  func testThisAndFollowingClearCreatesOneOffReplacement() async throws {
    let service = try makeService()
    let event = try await makeDailySeries(service, count: 5)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "One-off replacement", recurrence: .clear))

    let original = try XCTUnwrap(result.originalEvent)
    let replacement = try XCTUnwrap(result.replacementEvent)
    XCTAssertTrue(original.isRecurring, "the two occurrences before the split remain a series")
    XCTAssertEqual(original.id, event.id)
    XCTAssertFalse(replacement.isRecurring)
    XCTAssertNil(replacement.recurrenceRule)
    XCTAssertEqual(replacement.startDate, "2026-06-03")
    XCTAssertEqual(replacement.title, "One-off replacement")
  }

  func testThisOnlySetRejectsBeforeWritingExceptionOrOverride() async throws {
    let service = try makeService()
    let event = try await makeDailySeries(service)

    do {
      _ = try await service.editScopedCalendarEvent(
        eventID: event.id, occurrenceDate: "2026-06-02", scope: "this_only",
        updates: ScopedCalendarEventUpdates(
          recurrence: .set(TaskRecurrenceRule(freq: .weekly, byDay: ["TU"]))))
      XCTFail("a one-off override must not become a recurring series")
    } catch let error as LorvexCoreError {
      guard case .validation(let field, _) = error else {
        return XCTFail("expected typed validation, got \(error)")
      }
      XCTAssertEqual(field, "recurrence")
    }

    let decisions = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM calendar_events WHERE series_id = ?",
        arguments: [event.id]) ?? -1
    }
    XCTAssertEqual(decisions, 0)
  }

  func testScopedSplitRejectsNonOccurrenceAndDateBeyondCountAtomically() async throws {
    let service = try makeService()
    let weekly = try await service.createCalendarEvent(
      title: "Monday series", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false,
      location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .weekly, byDay: ["MO"]),
      timezone: "America/Los_Angeles", url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil)
    let bounded = try await makeDailySeries(service, count: 2)
    let before = try mutationState(service)

    for operation in ["edit-weekday", "delete-weekday", "edit-after-count"] {
      do {
        switch operation {
        case "edit-weekday":
          _ = try await service.editScopedCalendarEvent(
            eventID: weekly.id, occurrenceDate: "2026-06-02",
            scope: "this_and_following",
            updates: ScopedCalendarEventUpdates(title: "Invalid Tuesday split"))
        case "delete-weekday":
          _ = try await service.deleteScopedCalendarEvent(
            eventID: weekly.id, occurrenceDate: "2026-06-02",
            scope: "this_and_following")
        default:
          _ = try await service.editScopedCalendarEvent(
            eventID: bounded.id, occurrenceDate: "2026-06-03",
            scope: "this_and_following",
            updates: ScopedCalendarEventUpdates(title: "Past bounded tail"))
        }
        XCTFail("\(operation) should reject a date outside the series")
      } catch let error as LorvexCoreError {
        guard case .validation(let field, _) = error else {
          return XCTFail("expected occurrence-date validation, got \(error)")
        }
        XCTAssertEqual(field, "occurrence_date")
      } catch {
        XCTFail("expected typed occurrence-date validation, got \(error)")
      }
    }

    XCTAssertEqual(try mutationState(service), before)
    let weeklyAfter = try await service.getCalendarEvent(id: weekly.id)
    let boundedAfter = try await service.getCalendarEvent(id: bounded.id)
    XCTAssertNotNil(weeklyAfter)
    XCTAssertNotNil(boundedAfter)
  }

  private func exceptionCount(
    _ service: SwiftLorvexCoreService,
    eventID: String
  ) throws -> Int {
    try service.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*)
          FROM calendar_events decision
          JOIN calendar_events master ON master.id = decision.series_id
          WHERE master.id = ?
            AND decision.recurrence_generation = master.recurrence_generation
            AND decision.occurrence_state IN ('replacement', 'cancelled')
          """,
        arguments: [eventID]) ?? 0
    }
  }

  private func mutationState(
    _ service: SwiftLorvexCoreService
  ) throws -> [Int] {
    try service.read { db in
      [
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1,
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM calendar_events WHERE series_id IS NOT NULL") ?? -1,
      ]
    }
  }
}
