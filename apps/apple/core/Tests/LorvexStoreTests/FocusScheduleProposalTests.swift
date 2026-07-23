import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// The Rust `focus_schedule_proposal` module ships no `#[test]` cases; these
/// lock the ported packer's contract (error branches + a no-event packing run)
/// against the Rust algorithm.
final class FocusScheduleProposalTests: XCTestCase {
  private func seedFocusHeader(_ db: Database, _ date: String) throws {
    try db.execute(
      sql: """
        INSERT INTO current_focus (date, timezone, version, created_at, updated_at) \
        VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', \
        '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')
        """,
      arguments: [date])
  }

  private func seedFocusItem(_ db: Database, _ date: String, _ position: Int, _ taskId: String)
    throws
  {
    try db.execute(
      sql: "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, ?2, ?3)",
      arguments: [date, position, taskId])
  }

  private func seedTask(
    _ db: Database, _ id: String, _ title: String, status: String = "open",
    estimatedMinutes: Int64? = nil
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, list_id, estimated_minutes, version, created_at, \
        updated_at, defer_count) \
        VALUES (?, ?, ?, 'inbox', ?, '0000000000000_0000_a0a0a0a0a0a0a0a0', \
        '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', 0)
        """,
      arguments: [id, title, status, estimatedMinutes])
  }

  private enum CalendarFixtureSource {
    case canonical
    case provider
  }

  private struct CalendarFixture {
    let source: CalendarFixtureSource
    let id: String
    let title: String
    let start: String
    let end: String
  }

  private func seedCalendarFixture(_ db: Database, _ fixture: CalendarFixture) throws {
    switch fixture.source {
    case .canonical:
      try CalendarEventWriteRepo.createCalendarEvent(
        db,
        params: CalendarEventCreateParams(
          id: fixture.id, title: fixture.title, timezone: "UTC",
          startDate: "2026-03-29", startTime: fixture.start,
          endDate: "2026-03-29", endTime: fixture.end,
          allDay: false, eventType: "event",
          seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
          recurrenceGeneration: nil,
          recurrenceTopologyVersion: "0000000000000_0000_a0a0a0a0a0a0a0a0",
          version: "0000000000000_0000_a0a0a0a0a0a0a0a0",
          now: "2026-03-29T00:00:00Z"))
    case .provider:
      try db.execute(
        sql: """
          INSERT OR REPLACE INTO provider_scope_runtime_state
            (provider_kind, provider_scope, availability_state,
             last_refresh_success_at, last_refresh_result)
          VALUES ('eventkit', 'device', 'enabled',
                  '2026-03-29T00:00:00Z', 'success')
          """)
      try db.execute(
        sql: """
          INSERT INTO provider_calendar_events
            (provider_kind, provider_scope, provider_event_key, title,
             start_date, start_time, end_date, end_time, all_day,
             last_seen_at)
          VALUES ('eventkit', 'device', ?, ?, '2026-03-29', ?,
                  '2026-03-29', ?, 0, '2026-03-29T00:00:00Z')
          """,
        arguments: [fixture.id, fixture.title, fixture.start, fixture.end])
    }
  }

  private func overlappingProposal(
    _ db: Database, fixtures: [CalendarFixture]
  ) throws -> FocusScheduleProposal.Proposal {
    let taskID = "20000000-0000-7000-8000-000000000001"
    try seedWorkingHoursPreference(db, #""09:00-12:00""#)
    try seedFocusHeader(db, "2026-03-29")
    try seedTask(db, taskID, "One-hour task", estimatedMinutes: 60)
    try seedFocusItem(db, "2026-03-29", 0, taskID)
    for fixture in fixtures {
      try seedCalendarFixture(db, fixture)
    }
    return try FocusScheduleProposal.proposeFocusSchedule(
      db, date: "2026-03-29", anchorTimezone: "UTC", accessMode: .fullDetails)
  }

  private func assertOverlapUsesUnion(
    _ proposal: FocusScheduleProposal.Proposal,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(proposal.calendarEventsCount, 2, file: file, line: line)
    XCTAssertEqual(
      proposal.totalMinutesAvailable, 90,
      "09:30–11:00 overlap union occupies 90 of the 180 working minutes",
      file: file, line: line)
    XCTAssertEqual(proposal.slots.first?.startTime.asString, "11:00", file: file, line: line)
    XCTAssertEqual(proposal.slots.first?.endTime.asString, "12:00", file: file, line: line)
  }

  func testRejectsInvalidDate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try FocusScheduleProposal.proposeFocusSchedule(
          db, date: "not-a-date", anchorTimezone: "UTC", accessMode: .busyOnly)
      ) { error in
        guard case let StoreError.validation(message) = error else {
          return XCTFail("expected validation error, got \(error)")
        }
        XCTAssertTrue(message.contains("invalid focus schedule date: not-a-date"))
      }
    }
  }

  func testRejectsWhenNoFocusSet() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try FocusScheduleProposal.proposeFocusSchedule(
          db, date: "2026-03-29", anchorTimezone: "UTC", accessMode: .busyOnly)
      ) { error in
        guard case let StoreError.validation(message) = error else {
          return XCTFail("expected validation error, got \(error)")
        }
        XCTAssertTrue(message.contains("no current focus set for this date"))
      }
    }
  }

  func testPacksTasksSequentiallyWithBufferAndNoEvents() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db -> FocusScheduleProposal.Proposal in
      try self.seedFocusHeader(db, "2026-03-29")
      try self.seedTask(db, "t-1", "First", estimatedMinutes: 60)
      try self.seedTask(db, "t-2", "Second", estimatedMinutes: 30)
      try self.seedFocusItem(db, "2026-03-29", 0, "t-1")
      try self.seedFocusItem(db, "2026-03-29", 1, "t-2")
      return try FocusScheduleProposal.proposeFocusSchedule(
        db, date: "2026-03-29", anchorTimezone: "UTC", accessMode: .off)
    }

    // Default working hours 09:00–18:00 → 540 minutes available, no events.
    XCTAssertEqual(proposal.totalMinutesAvailable, 540)
    XCTAssertEqual(proposal.calendarEventsCount, 0)
    XCTAssertEqual(proposal.unscheduled.count, 0)
    XCTAssertEqual(proposal.slots.count, 2)

    // First task at 09:00–10:00, buffer 10:00–10:10, second 10:10–10:40.
    XCTAssertEqual(proposal.slots[0].task.id, "t-1")
    XCTAssertEqual(proposal.slots[0].startTime.asString, "09:00")
    XCTAssertEqual(proposal.slots[0].endTime.asString, "10:00")
    XCTAssertEqual(proposal.slots[1].task.id, "t-2")
    XCTAssertEqual(proposal.slots[1].startTime.asString, "10:10")
    XCTAssertEqual(proposal.slots[1].endTime.asString, "10:40")

    // Each placed task is followed by a buffer while the window has room
    // (the second task ends at 10:40, far before 18:00), so both tasks get a
    // trailing buffer: task, buffer, task, buffer — sorted by start_time.
    let blockTypes = proposal.blocks.map(\.blockType)
    XCTAssertEqual(blockTypes, ["task", "buffer", "task", "buffer"])
  }

  private func seedWorkingHoursPreference(_ db: Database, _ storedValue: String) throws {
    try db.execute(
      sql: """
        INSERT INTO preferences (key, value, version, updated_at) \
        VALUES ('working_hours', ?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', \
        '2026-03-29T00:00:00Z')
        """,
      arguments: [storedValue])
  }

  /// The hyphen-string `working_hours` form (`"HH:MM-HH:MM"`) is the seeded /
  /// default stored shape; `loadWorkingHours` must accept it as well as the
  /// JSON object form so `propose_daily_schedule` does not reject it.
  func testReadsHyphenStringWorkingHoursPreference() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db -> FocusScheduleProposal.Proposal in
      // Stored verbatim by complete_setup / set_preference: a JSON string literal.
      try self.seedWorkingHoursPreference(db, #""10:00-12:00""#)
      try self.seedFocusHeader(db, "2026-03-29")
      try self.seedTask(db, "t-1", "First", estimatedMinutes: 60)
      try self.seedFocusItem(db, "2026-03-29", 0, "t-1")
      return try FocusScheduleProposal.proposeFocusSchedule(
        db, date: "2026-03-29", anchorTimezone: "UTC", accessMode: .off)
    }
    // 10:00–12:00 window → 120 minutes available; first slot opens at 10:00.
    XCTAssertEqual(proposal.totalMinutesAvailable, 120)
    XCTAssertEqual(proposal.slots.first?.startTime.asString, "10:00")
  }

  func testDefaultsToThirtyMinutesWhenNoEstimate() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db -> FocusScheduleProposal.Proposal in
      try self.seedFocusHeader(db, "2026-03-29")
      try self.seedTask(db, "t-1", "No estimate")
      try self.seedFocusItem(db, "2026-03-29", 0, "t-1")
      return try FocusScheduleProposal.proposeFocusSchedule(
        db, date: "2026-03-29", anchorTimezone: "UTC", accessMode: .off)
    }
    XCTAssertEqual(proposal.slots.count, 1)
    XCTAssertEqual(proposal.slots[0].startTime.asString, "09:00")
    XCTAssertEqual(proposal.slots[0].endTime.asString, "09:30")
  }

  func testCanonicalOverlapPreservesBothIdentitiesAndUsesOccupancyUnion() throws {
    let store = try TestSupport.freshStore()
    let firstID = "10000000-0000-7000-8000-000000000001"
    let secondID = "10000000-0000-7000-8000-000000000002"
    let proposal = try store.writer.write { db in
      try self.overlappingProposal(
        db,
        fixtures: [
          CalendarFixture(
            source: .canonical, id: firstID, title: "Canonical A",
            start: "09:30", end: "10:30"),
          CalendarFixture(
            source: .canonical, id: secondID, title: "Canonical B",
            start: "10:00", end: "11:00"),
        ])
    }

    assertOverlapUsesUnion(proposal)
    let eventBlocks = proposal.blocks.filter { $0.blockType == "event" }
    XCTAssertEqual(eventBlocks.map(\.eventSource), [.canonical, .canonical])
    XCTAssertEqual(eventBlocks.map(\.calendarEventId), [firstID, secondID])
    XCTAssertEqual(eventBlocks.map(\.title), ["Canonical A", "Canonical B"])
  }

  func testCanonicalProviderOverlapPreservesEachSourceAndUsesOccupancyUnion() throws {
    let store = try TestSupport.freshStore()
    let canonicalID = "10000000-0000-7000-8000-000000000003"
    let proposal = try store.writer.write { db in
      try self.overlappingProposal(
        db,
        fixtures: [
          CalendarFixture(
            source: .canonical, id: canonicalID, title: "Canonical",
            start: "09:30", end: "10:30"),
          CalendarFixture(
            source: .provider, id: "provider-a", title: "Provider",
            start: "10:00", end: "11:00"),
        ])
    }

    assertOverlapUsesUnion(proposal)
    let eventBlocks = proposal.blocks.filter { $0.blockType == "event" }
    XCTAssertEqual(eventBlocks.map(\.eventSource), [.canonical, .provider])
    XCTAssertEqual(eventBlocks.map(\.calendarEventId), [canonicalID, nil])
    XCTAssertEqual(eventBlocks.map(\.title), ["Canonical", "Provider"])
  }

  func testRecurringCanonicalBlockUsesStableSeriesEventIdentity() throws {
    let store = try TestSupport.freshStore()
    let seriesID = "10000000-0000-7000-8000-000000000004"
    let taskID = "20000000-0000-7000-8000-000000000004"
    let generation = "0000000000000_0000_a0a0a0a0a0a0a0a0"
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-12:00""#)
      try self.seedFocusHeader(db, "2026-03-29")
      try self.seedTask(db, taskID, "One-hour task", estimatedMinutes: 60)
      try self.seedFocusItem(db, "2026-03-29", 0, taskID)
      try CalendarEventWriteRepo.createCalendarEvent(
        db,
        params: CalendarEventCreateParams(
          id: seriesID, title: "Recurring standup",
          recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
          timezone: "UTC",
          startDate: "2026-03-28", startTime: "09:30",
          endDate: "2026-03-28", endTime: "10:00",
          allDay: false, eventType: "event",
          seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
          recurrenceGeneration: generation,
          recurrenceTopologyVersion: generation,
          version: generation, now: "2026-03-29T00:00:00Z"))
      return try FocusScheduleProposal.proposeFocusSchedule(
        db, date: "2026-03-29", anchorTimezone: "UTC", accessMode: .fullDetails)
    }

    let eventBlock = try XCTUnwrap(proposal.blocks.first { $0.blockType == "event" })
    XCTAssertEqual(eventBlock.eventSource, .canonical)
    XCTAssertEqual(eventBlock.calendarEventId, seriesID)
    XCTAssertNotEqual(
      eventBlock.calendarEventId,
      CalendarOccurrenceDecisionID.make(
        seriesId: seriesID, recurrenceGeneration: generation,
        recurrenceInstanceDate: "2026-03-29"))
  }

  func testProviderOverlapPreservesBothBlocksAndUsesOccupancyUnion() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.overlappingProposal(
        db,
        fixtures: [
          CalendarFixture(
            source: .provider, id: "provider-a", title: "Provider A",
            start: "09:30", end: "10:30"),
          CalendarFixture(
            source: .provider, id: "provider-b", title: "Provider B",
            start: "10:00", end: "11:00"),
        ])
    }

    assertOverlapUsesUnion(proposal)
    let eventBlocks = proposal.blocks.filter { $0.blockType == "event" }
    XCTAssertEqual(eventBlocks.map(\.eventSource), [.provider, .provider])
    XCTAssertEqual(eventBlocks.map(\.calendarEventId), [nil, nil])
    XCTAssertEqual(eventBlocks.map(\.title), ["Provider A", "Provider B"])
  }

  func testIndistinguishableProviderEventsRemainTwoOrderedBlocksButOccupyTimeOnce() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.overlappingProposal(
        db,
        fixtures: [
          CalendarFixture(
            source: .provider, id: "calendar-a-event", title: "Standup",
            start: "09:30", end: "10:30"),
          CalendarFixture(
            source: .provider, id: "calendar-b-event", title: "Standup",
            start: "09:30", end: "10:30"),
        ])
    }

    XCTAssertEqual(proposal.calendarEventsCount, 2)
    XCTAssertEqual(proposal.totalMinutesAvailable, 120)
    XCTAssertEqual(proposal.slots.first?.startTime.asString, "10:30")
    let eventBlocks = proposal.blocks.filter { $0.blockType == "event" }
    XCTAssertEqual(eventBlocks.count, 2)
    XCTAssertEqual(eventBlocks.map(\.eventSource), [.provider, .provider])
    XCTAssertEqual(eventBlocks.map(\.calendarEventId), [nil, nil])
    XCTAssertEqual(eventBlocks.map(\.title), ["Standup", "Standup"])
    XCTAssertEqual(eventBlocks.map(\.startTime.asString), ["09:30", "09:30"])
    XCTAssertEqual(eventBlocks.map(\.endTime.asString), ["10:30", "10:30"])
  }
}
