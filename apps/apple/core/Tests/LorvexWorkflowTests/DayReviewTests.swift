import GRDB
import LorvexStore
import XCTest

@testable import LorvexWorkflow

/// Covers `DayReview.loadDaySummary` — the single-day evidence read backing the
/// Review-surface day panel. Seeding uses raw INSERTs (no Swift builder fixture)
/// and pins the workflow timezone to `America/Los_Angeles` so the local-day UTC
/// bounds differ from UTC and the boundary cases (a 23:59-local completion, an
/// all-day multi-day event) exercise the same window math `WeeklyReview` uses.
final class DayReviewTests: XCTestCase {
  private static let version = "0000000000000_0000_0000000000000000"
  // 2026-04-05 in America/Los_Angeles (PDT, UTC-7): the local day spans
  // [2026-04-05T07:00:00Z, 2026-04-06T07:00:00Z).
  private static let day = "2026-04-05"

  private func setLosAngelesTimezone(_ db: Database) throws {
    try db.execute(
      sql: "INSERT INTO preferences (key, value, version, updated_at) "
        + "VALUES ('timezone', '\"America/Los_Angeles\"', ?, '2026-04-01T00:00:00Z')",
      arguments: [Self.version])
  }

  private func insertList(_ db: Database, id: String) throws {
    try db.execute(
      sql: "INSERT INTO lists (id, name, version, created_at, updated_at) "
        + "VALUES (?, 'List', ?, '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
      arguments: [id, Self.version])
  }

  private func insertTask(
    _ db: Database, id: String, title: String, status: String, priority: Int? = nil,
    dueDate: String? = nil, completedAt: String? = nil, createdAt: String = "2026-04-01T00:00:00Z",
    archivedAt: String? = nil
  ) throws {
    try db.execute(
      sql: "INSERT INTO tasks (id, title, status, list_id, priority, due_date, completed_at, "
        + "archived_at, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, 'l1', ?, ?, ?, ?, ?, ?, ?)",
      arguments: [
        id, title, status, priority, dueDate, completedAt, archivedAt, Self.version, createdAt,
        createdAt,
      ])
  }

  private func insertHabit(_ db: Database, id: String, target: Int, archived: Int = 0) throws {
    try db.execute(
      sql: "INSERT INTO habits (id, name, frequency_type, target_count, archived, lookup_key, "
        + "version, created_at, updated_at) "
        + "VALUES (?, ?, 'daily', ?, ?, ?, ?, '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
      arguments: [id, id, target, archived, id, Self.version])
  }

  private func insertHabitCompletion(_ db: Database, habitId: String, date: String, value: Int)
    throws
  {
    try db.execute(
      sql: "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, "
        + "updated_at) VALUES (?, ?, ?, ?, '2026-04-05T12:00:00Z', '2026-04-05T12:00:00Z')",
      arguments: [habitId, date, value, Self.version])
  }

  private func insertCalendarEvent(
    _ db: Database, id: String, startDate: String, endDate: String?, allDay: Int = 0
  ) throws {
    let startTime: String? = allDay == 0 ? "09:00" : nil
    let endTime: String? = allDay == 0 && endDate != nil ? "10:00" : nil
    try db.execute(
      sql: "INSERT INTO calendar_events (id, title, start_date, start_time, end_date, end_time, "
        + "all_day, recurrence_topology_version, content_version, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
        + "'2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
      arguments: [
        id, id, startDate, startTime, endDate, endTime, allDay,
        Self.version, Self.version, Self.version,
      ])
  }

  private func insertProviderEvent(
    _ db: Database, key: String, startDate: String, endDate: String?
  ) throws {
    try db.execute(
      sql: "INSERT INTO provider_calendar_events (provider_kind, provider_scope, "
        + "provider_event_key, title, start_date, end_date, all_day, last_seen_at) "
        + "VALUES ('eventkit', 'default', ?, ?, ?, ?, 0, "
        + "'2026-04-05T00:00:00Z')",
      arguments: [key, key, startDate, endDate])
  }

  func testLoadDaySummaryCountsEvidenceWithBoundaryCases() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertList(db, id: "l1")

      // Completed: a 23:59-local completion (2026-04-05T06:59Z next-UTC-day)
      // counts for 2026-04-05; a UTC-day-Apr-5 instant that is actually
      // 2026-04-04 local does NOT; an archived completion does NOT.
      try insertTask(
        db, id: "done-late", title: "Done late", status: "completed", priority: 2,
        completedAt: "2026-04-06T06:59:00Z")
      try insertTask(
        db, id: "done-early", title: "Done early", status: "completed", priority: 1,
        completedAt: "2026-04-05T07:30:00Z")
      try insertTask(
        db, id: "done-prev-local", title: "Prev local", status: "completed",
        completedAt: "2026-04-05T06:00:00Z")  // = 2026-04-04T23:00 PDT
      try insertTask(
        db, id: "done-archived", title: "Archived", status: "completed",
        completedAt: "2026-04-05T20:00:00Z", archivedAt: "2026-04-06T00:00:00Z")

      // Created on the local day (07:30Z) vs created previous local day (06:00Z).
      try insertTask(
        db, id: "created-today", title: "Created today", status: "open",
        createdAt: "2026-04-05T07:30:00Z")
      try insertTask(
        db, id: "created-prev", title: "Created prev", status: "open",
        createdAt: "2026-04-05T06:00:00Z")

      // dueOpen: open task due that day counts; completed task due that day
      // does NOT; archived open task does NOT.
      try insertTask(
        db, id: "due-open", title: "Due open", status: "open", dueDate: Self.day)
      try insertTask(
        db, id: "due-done", title: "Due done", status: "completed", dueDate: Self.day,
        completedAt: "2026-04-05T08:00:00Z")

      // Habits: hb1 met target (1/1) on the day; hb2 under target (1/2);
      // hb3 archived but completed (excluded from both counts).
      try insertHabit(db, id: "hb1", target: 1)
      try insertHabit(db, id: "hb2", target: 2)
      try insertHabit(db, id: "hb3", target: 1, archived: 1)
      try insertHabitCompletion(db, habitId: "hb1", date: Self.day, value: 1)
      try insertHabitCompletion(db, habitId: "hb2", date: Self.day, value: 1)
      try insertHabitCompletion(db, habitId: "hb3", date: Self.day, value: 1)

      // Events: a same-day canonical event; an all-day multi-day canonical
      // event spanning the day; a canonical event ending before the day; a
      // provider event covering the day.
      try insertCalendarEvent(db, id: "ev-same", startDate: Self.day, endDate: Self.day)
      try insertCalendarEvent(
        db, id: "ev-span", startDate: "2026-04-03", endDate: "2026-04-07", allDay: 1)
      try insertCalendarEvent(db, id: "ev-past", startDate: "2026-04-01", endDate: "2026-04-04")
      try insertProviderEvent(
        db, key: "pev-cover", startDate: "2026-04-04", endDate: "2026-04-06")
    }

    let summary = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5)
    }

    XCTAssertEqual(summary.date, Self.day)
    // done-late + done-early + due-done = 3 (done-prev-local and archived excluded).
    XCTAssertEqual(summary.completedCount, 3)
    // Canonical sort: priority ASC, due_date ASC NULLS LAST, id ASC.
    // due-done (p4, due 2026-04-05), done-early (p1), done-late (p2) →
    // done-early, done-late, due-done.
    XCTAssertEqual(summary.topCompleted.map { $0.id }, ["done-early", "done-late", "due-done"])
    XCTAssertEqual(summary.createdCount, 1)  // only created-today
    XCTAssertEqual(summary.dueOpenCount, 1)  // only due-open
    XCTAssertEqual(summary.habitsTotal, 2)  // hb1, hb2 (hb3 archived)
    XCTAssertEqual(summary.habitsCompleted, 1)  // hb1 met target
    XCTAssertEqual(summary.eventCount, 3)  // ev-same, ev-span, pev-cover
  }

  func testLoadDaySummaryClampsCompletedLimit() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertList(db, id: "l1")
      for i in 0..<4 {
        try insertTask(
          db, id: "done-\(i)", title: "Done \(i)", status: "completed", priority: 1,
          completedAt: "2026-04-05T08:00:00Z")
      }
    }

    let summary = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 2)
    }
    XCTAssertEqual(summary.completedCount, 4)
    XCTAssertEqual(summary.topCompleted.count, 2)
  }

  func testEventCountUsesActiveOccurrenceDecisionVisibility() throws {
    let store = try WorkflowTestSupport.freshStore()
    let generation = "1800000000000_0001_1111111111111111"
    let topology = "1800000000000_0002_2222222222222222"
    let decisionId = CalendarOccurrenceDecisionID.make(
      seriesId: "review-series", recurrenceGeneration: generation,
      recurrenceInstanceDate: Self.day)
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try CalendarEventWriteRepo.createCalendarEvent(
        db,
        params: CalendarEventCreateParams(
          id: "review-series", title: "Daily review series",
          recurrence: #"{"FREQ":"DAILY"}"#, timezone: "America/Los_Angeles",
          startDate: Self.day, startTime: "09:00", endDate: Self.day,
          endTime: "09:30", allDay: false, eventType: "event",
          seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
          recurrenceGeneration: generation, recurrenceTopologyVersion: topology,
          version: topology, now: "2026-04-01T00:00:00Z"))
      try CalendarEventWriteRepo.createCalendarEvent(
        db,
        params: CalendarEventCreateParams(
          id: decisionId, title: "Cancelled snapshot",
          timezone: "America/Los_Angeles", startDate: Self.day, startTime: "09:00",
          endDate: Self.day, endTime: "09:30", allDay: false, eventType: "event",
          seriesId: "review-series", recurrenceInstanceDate: Self.day,
          occurrenceState: .cancelled, recurrenceGeneration: generation,
          recurrenceTopologyVersion: nil,
          version: "1800000000000_0003_3333333333333333",
          now: "2026-04-02T00:00:00Z"))
    }

    let cancelled = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5)
    }
    XCTAssertEqual(cancelled.eventCount, 0)

    try store.writer.write { db in
      try CalendarEventWriteRepo.applyCalendarEventUpdate(
        db,
        patch: CalendarEventUpdatePatch(
          eventId: decisionId, occurrenceState: .set(.inherit),
          version: "1800000000000_0004_4444444444444444",
          now: "2026-04-03T00:00:00Z"))
    }
    let inherited = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5)
    }
    XCTAssertEqual(inherited.eventCount, 1)
  }

  func testLoadDaySummaryRejectsOutOfRangeLimit() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in try setLosAngelesTimezone(db) }
    try store.writer.read { db in
      XCTAssertThrowsError(try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 0))
      XCTAssertThrowsError(try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 51))
    }
  }
}
