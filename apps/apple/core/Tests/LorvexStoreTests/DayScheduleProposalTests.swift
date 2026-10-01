import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// The day-times suggestion: the day's tasks, in Today's order, packed into
/// the free working time around calendar events.
final class DayScheduleProposalTests: XCTestCase {
  private static let day = "2026-03-29"

  private func seedTask(
    _ db: Database, _ id: String, _ title: String, status: String = "open",
    estimatedMinutes: Int64? = nil, plannedDate: String? = day, plannedTime: Range<Int64>? = nil
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, list_id, estimated_minutes, planned_date, \
        planned_start_minutes, planned_end_minutes, completed_at, version, created_at, \
        updated_at, defer_count) \
        VALUES (?, ?, ?, 'inbox', ?, ?, ?, ?, ?, '0000000000000_0000_a0a0a0a0a0a0a0a0', \
        '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', 0)
        """,
      arguments: [
        id, title, status, estimatedMinutes, plannedDate, plannedTime?.lowerBound,
        plannedTime?.upperBound, status == "completed" ? "2026-03-29T12:50:00Z" : nil,
      ])
  }

  /// Stores a `working_hours` preference. Tests whose arithmetic is easier
  /// to read in a nine-to-six window seed `"09:00-18:00"` instead of relying
  /// on the default day hours.
  private func seedWorkingHoursPreference(_ db: Database, _ storedValue: String) throws {
    try db.execute(
      sql: """
        INSERT INTO preferences (key, value, version, updated_at) \
        VALUES ('working_hours', ?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', \
        '2026-03-29T00:00:00Z')
        """,
      arguments: [storedValue])
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
          startDate: Self.day, startTime: fixture.start,
          endDate: Self.day, endTime: fixture.end,
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

  private func propose(
    _ db: Database, accessMode: CalendarAiAccessMode = .fullDetails, notBefore: String? = nil
  ) throws -> DayScheduleProposal.Proposal {
    try DayScheduleProposal.propose(
      db, date: Self.day, anchorTimezone: "UTC", accessMode: accessMode,
      notBefore: try notBefore.map { try TimeOfDay.parse($0).get() })
  }

  private func hhmm(_ minutes: Int64) -> String { TimeOfDay.rangeBoundString(Int(minutes)) }

  private func starts(_ proposal: DayScheduleProposal.Proposal) -> [String] {
    proposal.slots.map { hhmm($0.start) }
  }

  private func ends(_ proposal: DayScheduleProposal.Proposal) -> [String] {
    proposal.slots.map { hhmm($0.end) }
  }

  // MARK: - Validation

  func testRejectsInvalidDate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try DayScheduleProposal.propose(
          db, date: "not-a-date", anchorTimezone: "UTC", accessMode: .busyOnly)
      ) { error in
        guard case let StoreError.validation(message) = error else {
          return XCTFail("expected validation error, got \(error)")
        }
        XCTAssertTrue(message.contains("invalid schedule date: not-a-date"), message)
      }
    }
  }

  // MARK: - Packing

  func testADayWithNoOpenTasksPlacesNothingAndStillListsItsEvents() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedTask(db, "t-done", "Finished", status: "completed")
      try self.seedTask(db, "t-later", "Tomorrow", plannedDate: "2026-03-30")
      try self.seedCalendarFixture(
        db,
        CalendarFixture(
          source: .canonical, id: "e-standup", title: "Standup", start: "10:00", end: "10:30"))
      return try self.propose(db)
    }
    XCTAssertTrue(proposal.slots.isEmpty)
    XCTAssertTrue(proposal.unscheduled.isEmpty)
    XCTAssertEqual(proposal.events.map(\.title), ["Standup"])
    XCTAssertEqual(proposal.events.map { hhmm($0.start) }, ["10:00"])
  }

  func testPacksTheDaysTasksInOrderWithBreaksAndNoEvents() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedTask(db, "t-1", "First", estimatedMinutes: 60)
      try self.seedTask(db, "t-2", "Second", estimatedMinutes: 30)
      return try self.propose(db, accessMode: .off)
    }

    XCTAssertEqual(proposal.totalMinutesAvailable, 900, "default day hours 08:00–23:00")
    XCTAssertTrue(proposal.events.isEmpty)
    XCTAssertTrue(proposal.unscheduled.isEmpty)
    XCTAssertEqual(proposal.slots.map(\.task.id), ["t-1", "t-2"])
    XCTAssertEqual(starts(proposal), ["08:00", "09:10"], "a ten-minute break follows each task")
    XCTAssertEqual(ends(proposal), ["09:00", "09:40"])
  }

  func testAShortTaskFillsAnEarlierGapThatALongerTaskAheadOfItDidNotFit() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, "t-1", "Long", estimatedMinutes: 90)
      try self.seedTask(db, "t-2", "Short", estimatedMinutes: 30)
      try self.seedCalendarFixture(
        db,
        CalendarFixture(
          source: .canonical, id: "40000000-0000-7000-8000-000000000005", title: "Standup",
          start: "10:00", end: "11:00"))
      return try self.propose(db)
    }

    XCTAssertEqual(
      proposal.slots.map(\.task.title), ["Short", "Long"],
      "the hour before the standup holds the short task instead of staying empty")
    XCTAssertEqual(starts(proposal), ["09:00", "11:00"])
    XCTAssertEqual(ends(proposal), ["09:30", "12:30"])
    XCTAssertTrue(proposal.unscheduled.isEmpty)
  }

  func testStartedTasksArePlacedFirst() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedTask(db, "t-1", "Planned", estimatedMinutes: 30)
      try self.seedTask(
        db, "t-2", "Started yesterday", status: "in_progress", estimatedMinutes: 30,
        plannedDate: nil)
      return try self.propose(db, accessMode: .off)
    }

    XCTAssertEqual(
      proposal.slots.map(\.task.title), ["Started yesterday", "Planned"],
      "a started task belongs to today even without a date, and it leads")
  }

  func testReadsHyphenStringWorkingHoursPreference() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""10:00-12:00""#)
      try self.seedTask(db, "t-1", "First", estimatedMinutes: 60)
      return try self.propose(db, accessMode: .off)
    }
    XCTAssertEqual(proposal.totalMinutesAvailable, 120)
    XCTAssertEqual(starts(proposal), ["10:00"])
  }

  func testDefaultsToThirtyMinutesWhenThereIsNoEstimateOrTime() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, "t-1", "No estimate")
      return try self.propose(db, accessMode: .off)
    }
    XCTAssertEqual(starts(proposal), ["09:00"])
    XCTAssertEqual(ends(proposal), ["09:30"])
  }

  func testUsesTheSavedTimesLengthWhenThereIsNoEstimate() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, "t-1", "Timed", plannedTime: 840..<885)
      return try self.propose(db, accessMode: .off)
    }
    XCTAssertEqual(starts(proposal), ["09:00"], "without a time under way, saved times are replaced")
    XCTAssertEqual(ends(proposal), ["09:45"], "the task keeps the length of its saved time")
  }

  func testSavedTimesAreReplacedWithoutNotBefore() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, Self.briefTaskID, "Write the brief", estimatedMinutes: 60)
      try self.seedTask(
        db, Self.emailTaskID, "Answer email", estimatedMinutes: 30, plannedTime: 750..<810)
      return try self.propose(db)
    }

    XCTAssertEqual(proposal.slots.map(\.task.title), ["Write the brief", "Answer email"])
    XCTAssertEqual(starts(proposal), ["09:00", "10:10"])
  }

  // MARK: - Suggesting the rest of the day

  private static let briefTaskID = "30000000-0000-7000-8000-000000000011"
  private static let emailTaskID = "30000000-0000-7000-8000-000000000012"

  func testNotBeforePacksFromThatTimeInsteadOfTheWorkingHoursStart() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, "t-1", "One-hour task", estimatedMinutes: 60)
      return try self.propose(db, notBefore: "13:00")
    }

    XCTAssertEqual(starts(proposal), ["13:00"])
    XCTAssertEqual(ends(proposal), ["14:00"])
    XCTAssertEqual(proposal.totalMinutesAvailable, 300, "13:00–18:00 is what is left")
    XCTAssertEqual(
      proposal.workingHours.start.asString, "09:00", "the reported hours stay the preference")
  }

  func testNotBeforeLeavesOutEndedEventsAndKeepsARunningEventsStart() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, "t-1", "One-hour task", estimatedMinutes: 60)
      for fixture in [
        CalendarFixture(
          source: .canonical, id: "40000000-0000-7000-8000-000000000001", title: "Standup",
          start: "09:00", end: "10:00"),
        CalendarFixture(
          source: .canonical, id: "40000000-0000-7000-8000-000000000002", title: "Review",
          start: "12:30", end: "13:30"),
        CalendarFixture(
          source: .canonical, id: "40000000-0000-7000-8000-000000000003", title: "Sync",
          start: "15:00", end: "16:00"),
      ] {
        try self.seedCalendarFixture(db, fixture)
      }
      return try self.propose(db, notBefore: "13:00")
    }

    XCTAssertEqual(proposal.events.map(\.title), ["Review", "Sync"], "the ended standup is left out")
    XCTAssertEqual(
      proposal.events.first.map { hhmm($0.start) }, "12:30", "a running event keeps its real start")
    XCTAssertEqual(starts(proposal), ["13:30"], "work waits for the review to end")
    XCTAssertEqual(
      proposal.totalMinutesAvailable, 210,
      "300 minutes left minus the review's last 30 and the sync's 60")
  }

  func testNotBeforeAfterWorkingHoursLeavesEveryTaskUnscheduled() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, "t-1", "One-hour task", estimatedMinutes: 60)
      try self.seedCalendarFixture(
        db,
        CalendarFixture(
          source: .canonical, id: "40000000-0000-7000-8000-000000000004", title: "Dinner",
          start: "17:30", end: "19:00"))
      return try self.propose(db, notBefore: "18:30")
    }

    XCTAssertTrue(proposal.slots.isEmpty)
    XCTAssertTrue(proposal.events.isEmpty)
    XCTAssertEqual(proposal.unscheduled.map(\.title), ["One-hour task"])
    XCTAssertEqual(proposal.totalMinutesAvailable, 0)
  }

  func testNotBeforeEarlierThanWorkingHoursChangesNothing() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-18:00""#)
      try self.seedTask(db, "t-1", "One-hour task", estimatedMinutes: 60)
      return try self.propose(db, notBefore: "07:00")
    }

    XCTAssertEqual(starts(proposal), ["09:00"])
    XCTAssertEqual(proposal.totalMinutesAvailable, 540)
  }

  func testNotBeforeKeepsTheTimeUnderWayAndPacksTheRestAfterIt() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedTask(db, Self.briefTaskID, "Write the brief", estimatedMinutes: 60)
      try self.seedTask(
        db, Self.emailTaskID, "Answer email", estimatedMinutes: 30, plannedTime: 750..<810)
      return try self.propose(db, notBefore: "13:00")
    }

    XCTAssertEqual(proposal.slots.map(\.task.title), ["Answer email", "Write the brief"])
    XCTAssertEqual(
      starts(proposal), ["12:30", "13:40"],
      "the time under way keeps its real start, and the next task follows a break")
    XCTAssertEqual(ends(proposal).first, "13:30", "it keeps its saved length, not the estimate")
    XCTAssertTrue(proposal.unscheduled.isEmpty)
  }

  func testNotBeforeFillsTheGapBetweenTheTimeUnderWayAndTheNextEvent() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedTask(db, "t-1", "Draft the agenda", estimatedMinutes: 90)
      try self.seedTask(db, "t-2", "Renew the registration", estimatedMinutes: 20)
      try self.seedTask(db, "t-3", "Reply to Maya", estimatedMinutes: 15)
      try self.seedTask(db, "t-4", "Status update", estimatedMinutes: 60, plannedTime: 655..<715)
      try self.seedCalendarFixture(
        db,
        CalendarFixture(
          source: .canonical, id: "40000000-0000-7000-8000-000000000006", title: "1:1",
          start: "13:00", end: "13:30"))
      return try self.propose(db, notBefore: "11:20")
    }

    XCTAssertEqual(
      proposal.slots.map(\.task.title),
      ["Status update", "Renew the registration", "Reply to Maya", "Draft the agenda"])
    XCTAssertEqual(
      starts(proposal), ["10:55", "12:05", "12:35", "13:30"],
      "the two short tasks use the 55 minutes before the 1:1 that the agenda does not fit")
    XCTAssertEqual(ends(proposal), ["11:55", "12:25", "12:50", "15:00"])
    XCTAssertTrue(proposal.unscheduled.isEmpty)
  }

  func testNotBeforeReplansTimesThatAreNotUnderWayAndSkipsFinishedTasks() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.seedTask(
        db, Self.briefTaskID, "Write the brief", estimatedMinutes: 60, plannedTime: 600..<660)
      try self.seedTask(
        db, Self.emailTaskID, "Answer email", status: "completed", estimatedMinutes: 30,
        plannedTime: 765..<795)
      return try self.propose(db, notBefore: "13:00")
    }

    XCTAssertEqual(
      proposal.slots.map(\.task.title), ["Write the brief"], "the completed task is not replanned")
    XCTAssertEqual(
      starts(proposal), ["13:00"], "a time that already ended does not hold its task in the past")
  }

  func testATimeOnAnotherDayIsNotUnderWay() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      // Overdue from yesterday, with yesterday's time still on it.
      try self.seedTask(
        db, "t-1", "Overdue", estimatedMinutes: 30, plannedDate: "2026-03-28",
        plannedTime: 750..<810)
      try db.execute(sql: "UPDATE tasks SET due_date = '2026-03-28' WHERE id = 't-1'")
      return try self.propose(db, notBefore: "13:00")
    }

    XCTAssertEqual(starts(proposal), ["13:00"], "yesterday's 12:30 is not under way today")
    XCTAssertEqual(ends(proposal), ["13:30"])
  }

  // MARK: - Calendar events

  private func overlappingProposal(
    _ db: Database, fixtures: [CalendarFixture]
  ) throws -> DayScheduleProposal.Proposal {
    try seedWorkingHoursPreference(db, #""09:00-12:00""#)
    try seedTask(db, "20000000-0000-7000-8000-000000000001", "One-hour task", estimatedMinutes: 60)
    for fixture in fixtures {
      try seedCalendarFixture(db, fixture)
    }
    return try propose(db)
  }

  private func assertOverlapUsesUnion(
    _ proposal: DayScheduleProposal.Proposal,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(proposal.events.count, 2, file: file, line: line)
    XCTAssertEqual(
      proposal.totalMinutesAvailable, 90,
      "09:30–11:00 overlap union occupies 90 of the 180 working minutes",
      file: file, line: line)
    XCTAssertEqual(starts(proposal).first, "11:00", file: file, line: line)
    XCTAssertEqual(ends(proposal).first, "12:00", file: file, line: line)
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
            source: .canonical, id: firstID, title: "Canonical A", start: "09:30", end: "10:30"),
          CalendarFixture(
            source: .canonical, id: secondID, title: "Canonical B", start: "10:00", end: "11:00"),
        ])
    }

    assertOverlapUsesUnion(proposal)
    XCTAssertEqual(proposal.events.map(\.source), [.canonical, .canonical])
    XCTAssertEqual(proposal.events.map(\.calendarEventId), [firstID, secondID])
    XCTAssertEqual(proposal.events.map(\.title), ["Canonical A", "Canonical B"])
  }

  func testCanonicalProviderOverlapPreservesEachSourceAndUsesOccupancyUnion() throws {
    let store = try TestSupport.freshStore()
    let canonicalID = "10000000-0000-7000-8000-000000000003"
    let proposal = try store.writer.write { db in
      try self.overlappingProposal(
        db,
        fixtures: [
          CalendarFixture(
            source: .canonical, id: canonicalID, title: "Canonical", start: "09:30",
            end: "10:30"),
          CalendarFixture(
            source: .provider, id: "provider-a", title: "Provider", start: "10:00", end: "11:00"),
        ])
    }

    assertOverlapUsesUnion(proposal)
    XCTAssertEqual(proposal.events.map(\.source), [.canonical, .provider])
    XCTAssertEqual(proposal.events.map(\.calendarEventId), [canonicalID, nil])
    XCTAssertEqual(proposal.events.map(\.title), ["Canonical", "Provider"])
  }

  func testRecurringCanonicalEventUsesStableSeriesEventIdentity() throws {
    let store = try TestSupport.freshStore()
    let seriesID = "10000000-0000-7000-8000-000000000004"
    let generation = "0000000000000_0000_a0a0a0a0a0a0a0a0"
    let proposal = try store.writer.write { db in
      try self.seedWorkingHoursPreference(db, #""09:00-12:00""#)
      try self.seedTask(
        db, "20000000-0000-7000-8000-000000000004", "One-hour task", estimatedMinutes: 60)
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
      return try self.propose(db)
    }

    let event = try XCTUnwrap(proposal.events.first)
    XCTAssertEqual(event.source, .canonical)
    XCTAssertEqual(event.calendarEventId, seriesID)
    XCTAssertNotEqual(
      event.calendarEventId,
      CalendarOccurrenceDecisionID.make(
        seriesId: seriesID, recurrenceGeneration: generation,
        recurrenceInstanceDate: "2026-03-29"))
  }

  func testProviderOverlapPreservesBothEventsAndUsesOccupancyUnion() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.overlappingProposal(
        db,
        fixtures: [
          CalendarFixture(
            source: .provider, id: "provider-a", title: "Provider A", start: "09:30",
            end: "10:30"),
          CalendarFixture(
            source: .provider, id: "provider-b", title: "Provider B", start: "10:00",
            end: "11:00"),
        ])
    }

    assertOverlapUsesUnion(proposal)
    XCTAssertEqual(proposal.events.map(\.source), [.provider, .provider])
    XCTAssertEqual(proposal.events.map(\.calendarEventId), [nil, nil])
    XCTAssertEqual(proposal.events.map(\.title), ["Provider A", "Provider B"])
  }

  func testIndistinguishableProviderEventsRemainTwoOrderedEventsButOccupyTimeOnce() throws {
    let store = try TestSupport.freshStore()
    let proposal = try store.writer.write { db in
      try self.overlappingProposal(
        db,
        fixtures: [
          CalendarFixture(
            source: .provider, id: "calendar-a-event", title: "Standup", start: "09:30",
            end: "10:30"),
          CalendarFixture(
            source: .provider, id: "calendar-b-event", title: "Standup", start: "09:30",
            end: "10:30"),
        ])
    }

    XCTAssertEqual(proposal.events.count, 2)
    XCTAssertEqual(proposal.totalMinutesAvailable, 120)
    XCTAssertEqual(starts(proposal).first, "10:30")
    XCTAssertEqual(proposal.events.map(\.source), [.provider, .provider])
    XCTAssertEqual(proposal.events.map(\.calendarEventId), [nil, nil])
    XCTAssertEqual(proposal.events.map(\.title), ["Standup", "Standup"])
    XCTAssertEqual(proposal.events.map { self.hhmm($0.start) }, ["09:30", "09:30"])
    XCTAssertEqual(proposal.events.map { self.hhmm($0.end) }, ["10:30", "10:30"])
  }
}
