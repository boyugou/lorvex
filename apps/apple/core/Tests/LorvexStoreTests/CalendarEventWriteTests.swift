import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class CalendarEventWriteTests: XCTestCase {

  func testApplyUpdatePartialFields() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let create = CalendarEventCreateParams(
        id: "evt-2", title: "Old Title",
        startDate: "2026-04-01",
        allDay: true,
        eventType: "event",
        seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
        recurrenceGeneration: nil,
        recurrenceTopologyVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000000",
        now: "2026-03-27T00:00:00.000Z")
      try CalendarEventWriteRepo.createCalendarEvent(db, params: create)

      let patch = CalendarEventUpdatePatch(
        eventId: "evt-2",
        title: "New Title",
        description: .set("Added desc"),
        version: "0000000000001_0000_0000000000000000",
        now: "2026-03-27T01:00:00.000Z")
      try CalendarEventWriteRepo.applyCalendarEventUpdate(db, patch: patch)

      let row = try Row.fetchOne(
        db, sql: "SELECT title, description FROM calendar_events WHERE id = ?",
        arguments: ["evt-2"])!
      XCTAssertEqual(row[0] as String, "New Title")
      XCTAssertEqual(row[1] as String?, "Added desc")
    }
  }

  func testApplyUpdateClearNullableField() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let create = CalendarEventCreateParams(
        id: "evt-3", title: "With Location",
        startDate: "2026-04-01",
        allDay: true,
        location: "Room B",
        eventType: "event",
        seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
        recurrenceGeneration: nil,
        recurrenceTopologyVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000000",
        now: "2026-03-27T00:00:00.000Z")
      try CalendarEventWriteRepo.createCalendarEvent(db, params: create)

      let patch = CalendarEventUpdatePatch(
        eventId: "evt-3",
        location: .clear,
        version: "0000000000001_0000_0000000000000000",
        now: "2026-03-27T01:00:00.000Z")
      try CalendarEventWriteRepo.applyCalendarEventUpdate(db, patch: patch)

      let loc = try String.fetchOne(
        db, sql: "SELECT location FROM calendar_events WHERE id = ?",
        arguments: ["evt-3"])
      XCTAssertNil(loc)
    }
  }

  func testCreateRejectsUnknownEventType() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let bad = CalendarEventCreateParams(
        id: "evt-bad", title: "Bad",
        startDate: "2026-04-01",
        allDay: true,
        eventType: "meeting",
        seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
        recurrenceGeneration: nil,
        recurrenceTopologyVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000000",
        now: "2026-04-01T00:00:00.000Z")
      do {
        try CalendarEventWriteRepo.createCalendarEvent(db, params: bad)
        XCTFail("expected validation")
      } catch let err as StoreError {
        guard case .validation(let msg) = err else {
          return XCTFail("expected validation, got \(err)")
        }
        XCTAssertTrue(msg.contains("must be one of"))
      }
    }
  }

  func testApplyUpdateRejectsUnknownEventType() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let create = CalendarEventCreateParams(
        id: "evt-canonical", title: "OK",
        startDate: "2026-04-01",
        allDay: true,
        eventType: "event",
        seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
        recurrenceGeneration: nil,
        recurrenceTopologyVersion: "0000000000000_0000_0000000000000000",
        version: "0000000000000_0000_0000000000000000",
        now: "2026-04-01T00:00:00.000Z")
      try CalendarEventWriteRepo.createCalendarEvent(db, params: create)

      let bad = CalendarEventUpdatePatch(
        eventId: "evt-canonical",
        eventType: .set("meeting"),
        version: "0000000000001_0000_0000000000000000",
        now: "2026-04-01T01:00:00.000Z")
      do {
        try CalendarEventWriteRepo.applyCalendarEventUpdate(db, patch: bad)
        XCTFail("expected validation")
      } catch let err as StoreError {
        guard case .validation(let msg) = err else {
          return XCTFail("expected validation, got \(err)")
        }
        XCTAssertTrue(msg.contains("must be one of"))
      }
    }
  }

  func testCreateRejectsDecisionWhoseIdDoesNotMatchRegisterKey() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try CalendarEventWriteRepo.createCalendarEvent(
          db,
          params: CalendarEventCreateParams(
            id: "random-id", title: "Cancelled snapshot",
            startDate: "2026-08-10", allDay: true, eventType: "event",
            seriesId: "series", recurrenceInstanceDate: "2026-08-10",
            occurrenceState: .cancelled,
            recurrenceGeneration: "1800000000000_0001_1111111111111111",
            recurrenceTopologyVersion: nil,
            version: "1800000000000_0002_2222222222222222",
            now: "2026-08-01T00:00:00Z"))
      }
    ) { error in
      XCTAssertTrue("\(error)".contains("decision id does not match"))
    }
  }

  func testDecisionStateTransitionsByUpdatingTheSameDeterministicRow() throws {
    let store = try TestSupport.freshStore()
    let generation = "1800000000000_0001_1111111111111111"
    let id = CalendarOccurrenceDecisionID.make(
      seriesId: "series", recurrenceGeneration: generation,
      recurrenceInstanceDate: "2026-08-10")
    try store.writer.write { db in
      try CalendarEventWriteRepo.createCalendarEvent(
        db,
        params: CalendarEventCreateParams(
          id: id, title: "Replacement snapshot",
          startDate: "2026-08-10", allDay: true, eventType: "event",
          seriesId: "series", recurrenceInstanceDate: "2026-08-10",
          occurrenceState: .replacement, recurrenceGeneration: generation,
          recurrenceTopologyVersion: nil,
          version: "1800000000000_0002_2222222222222222",
          now: "2026-08-01T00:00:00Z"))
      try CalendarEventWriteRepo.applyCalendarEventUpdate(
        db,
        patch: CalendarEventUpdatePatch(
          eventId: id, occurrenceState: .set(.inherit),
          version: "1800000000000_0003_3333333333333333",
          now: "2026-08-02T00:00:00Z"))

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT occurrence_state FROM calendar_events WHERE id = ?",
          arguments: [id]),
        "inherit")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events WHERE id = ?", arguments: [id]),
        1)
    }
  }
}
