import Foundation
import LorvexStore
import Testing

@testable import LorvexApple

/// The series assembler renders moved and cancelled occurrences of recurring
/// external events correctly: a master row with recurrence exceptions plus
/// standalone rows for moved occurrences — never the raw first-occurrence
/// projection.
@Suite("EventKit series assembly")
struct EventKitSeriesAssemblyTests {
  private let weekly = #"{"FREQ":"WEEKLY"}"#

  private func event(
    key: String = "ext-1", startDate: String, recurrence: String? = nil,
    color: String? = nil, organizerEmail: String? = nil, url: String? = nil,
    attendees: [EventKitFetchedAttendee] = []
  ) -> EventKitFetchedEvent {
    EventKitFetchedEvent(
      key: key, title: "Standup", notes: nil,
      startDate: startDate, startTime: "09:00",
      endDate: startDate, endTime: "09:30",
      allDay: false, location: nil, timezone: nil,
      recurrence: recurrence, recurrenceExceptions: nil,
      color: color, organizerEmail: organizerEmail, url: url,
      attendees: attendees)
  }

  @Test("a moved occurrence becomes an exception plus a standalone row")
  func movedOccurrence() {
    let occurrences = [
      EventKitOccurrence(
        event: event(startDate: "2026-01-05", recurrence: weekly),
        isDetached: false, occurrenceYmd: "2026-01-05"),
      EventKitOccurrence(
        event: event(startDate: "2026-01-13", recurrence: weekly),
        isDetached: true, occurrenceYmd: "2026-01-12"),
      EventKitOccurrence(
        event: event(startDate: "2026-01-19", recurrence: weekly),
        isDetached: false, occurrenceYmd: "2026-01-19"),
      EventKitOccurrence(
        event: event(startDate: "2026-01-26", recurrence: weekly),
        isDetached: false, occurrenceYmd: "2026-01-26"),
    ]

    let rows = EventKitSeriesAssembly.assemble(occurrences, windowEndYmd: "2026-01-26")

    #expect(rows.count == 2)
    let master = rows[0]
    #expect(master.key == "ext-1")
    #expect(master.recurrence == weekly)
    #expect(master.recurrenceExceptions == #"["2026-01-12"]"#)

    let moved = rows[1]
    #expect(moved.key == "ext-1:2026-01-12")
    #expect(moved.startDate == "2026-01-13")
    #expect(moved.recurrence == nil)
    #expect(moved.recurrenceExceptions == nil)
  }

  @Test("a cancelled occurrence (absent from enumeration) becomes an exception")
  func cancelledOccurrence() {
    let occurrences = ["2026-01-05", "2026-01-19", "2026-01-26"].map {
      EventKitOccurrence(
        event: event(startDate: $0, recurrence: weekly),
        isDetached: false, occurrenceYmd: $0)
    }

    let rows = EventKitSeriesAssembly.assemble(occurrences, windowEndYmd: "2026-01-26")

    #expect(rows.count == 1)
    #expect(rows[0].recurrenceExceptions == #"["2026-01-12"]"#)
  }

  @Test("an unmodified series carries the rule with no exceptions")
  func unmodifiedSeries() {
    let occurrences = ["2026-01-05", "2026-01-12", "2026-01-19"].map {
      EventKitOccurrence(
        event: event(startDate: $0, recurrence: weekly),
        isDetached: false, occurrenceYmd: $0)
    }

    let rows = EventKitSeriesAssembly.assemble(occurrences, windowEndYmd: "2026-01-19")

    #expect(rows.count == 1)
    #expect(rows[0].recurrence == weekly)
    #expect(rows[0].recurrenceExceptions == nil)
  }

  @Test("a non-recurring event passes through unchanged")
  func singleEventPassesThrough() {
    let single = event(key: "ext-2", startDate: "2026-02-01")
    let rows = EventKitSeriesAssembly.assemble(
      [EventKitOccurrence(event: single, isDetached: false, occurrenceYmd: "2026-02-01")],
      windowEndYmd: "2026-12-31")
    #expect(rows == [single])
  }

  @Test("series reconstruction preserves metadata on the master and detached rows")
  func seriesReconstructionPreservesMetadata() throws {
    let masterAttendee = EventKitFetchedAttendee(
      email: "master@example.com", name: "Master", status: .accepted)
    let detachedAttendee = EventKitFetchedAttendee(
      email: "moved@example.com", name: "Moved", status: .tentative)
    let occurrences = [
      EventKitOccurrence(
        event: event(
          startDate: "2026-01-05", recurrence: weekly,
          color: "#112233", organizerEmail: "owner@example.com",
          url: "https://example.com/master", attendees: [masterAttendee]),
        isDetached: false, occurrenceYmd: "2026-01-05"),
      EventKitOccurrence(
        event: event(
          startDate: "2026-01-13", recurrence: weekly,
          color: "#445566", organizerEmail: "moved-owner@example.com",
          url: "https://example.com/moved", attendees: [detachedAttendee]),
        isDetached: true, occurrenceYmd: "2026-01-12"),
    ]

    let rows = EventKitSeriesAssembly.assemble(
      occurrences, windowEndYmd: "2026-01-19")
    let master = try #require(rows.first)
    let detached = try #require(rows.dropFirst().first)

    #expect(rows.count == 2)
    #expect(master.color == "#112233")
    #expect(master.organizerEmail == "owner@example.com")
    #expect(master.url == "https://example.com/master")
    #expect(master.attendees == [masterAttendee])
    #expect(detached.color == "#445566")
    #expect(detached.organizerEmail == "moved-owner@example.com")
    #expect(detached.url == "https://example.com/moved")
    #expect(detached.attendees == [detachedAttendee])
  }

  @Test("a series whose rule the bridge could not express keeps one representative row")
  func unbridgeableRuleKeepsFirstRow() {
    let occurrences = ["2026-01-05", "2026-01-12", "2026-01-19"].map {
      EventKitOccurrence(
        event: event(startDate: $0), isDetached: false, occurrenceYmd: $0)
    }
    let rows = EventKitSeriesAssembly.assemble(occurrences, windowEndYmd: "2026-01-19")
    #expect(rows.count == 1)
    #expect(rows[0].startDate == "2026-01-05")
  }
}
