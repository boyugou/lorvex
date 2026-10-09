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

  /// `weekdays` are Monday-first (0=Mon … 6=Sun) and belong to a `weekly` habit;
  /// `dayOfMonth` belongs to a `monthly` one.
  private func insertHabit(
    _ db: Database, id: String, target: Int, archived: Int = 0,
    frequencyType: String = "daily", weekdays: [Int] = [], dayOfMonth: Int? = nil
  ) throws {
    try db.execute(
      sql: "INSERT INTO habits (id, name, frequency_type, target_count, archived, lookup_key, "
        + "day_of_month, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')",
      arguments: [id, id, frequencyType, target, archived, id, dayOfMonth, Self.version])
    for weekday in weekdays {
      try db.execute(
        sql: "INSERT INTO habit_weekdays (habit_id, weekday) VALUES (?, ?)",
        arguments: [id, weekday])
    }
  }

  private func insertHabitCompletion(_ db: Database, habitId: String, date: String, value: Int)
    throws
  {
    try db.execute(
      sql: "INSERT INTO habit_completions (habit_id, completed_date, value, version, created_at, "
        + "updated_at) VALUES (?, ?, ?, ?, '2026-04-05T12:00:00Z', '2026-04-05T12:00:00Z')",
      arguments: [habitId, date, value, Self.version])
  }

  private func insertHabitSkip(_ db: Database, habitId: String, date: String) throws {
    try db.execute(
      sql: "INSERT INTO habit_skips (habit_id, skipped_date, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, '2026-04-05T12:00:00Z', '2026-04-05T12:00:00Z')",
      arguments: [habitId, date, Self.version])
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
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5, dueOpenLimit: 5)
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
    XCTAssertEqual(summary.dueOpenTasks.map { $0.id }, ["due-open"])
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
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 2, dueOpenLimit: 5)
    }
    XCTAssertEqual(summary.completedCount, 4)
    XCTAssertEqual(summary.topCompleted.count, 2)
  }

  func testDueOpenTasksFollowTaskOrderUnderTheirCap() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertList(db, id: "l1")
      try insertTask(db, id: "due-p3", title: "P3", status: "open", priority: 3, dueDate: Self.day)
      try insertTask(db, id: "due-p1", title: "P1", status: "open", priority: 1, dueDate: Self.day)
      try insertTask(
        db, id: "due-p2", title: "P2", status: "in_progress", priority: 2, dueDate: Self.day)
      try insertTask(
        db, id: "due-tomorrow", title: "Tomorrow", status: "open", priority: 1,
        dueDate: "2026-04-06")
      try insertTask(
        db, id: "due-archived", title: "Archived", status: "open", priority: 1,
        dueDate: Self.day, archivedAt: "2026-04-05T12:00:00Z")
    }

    let summary = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5, dueOpenLimit: 2)
    }
    XCTAssertEqual(summary.dueOpenCount, 3)
    XCTAssertEqual(summary.dueOpenTasks.map { $0.id }, ["due-p1", "due-p2"])
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
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5, dueOpenLimit: 5)
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
      try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5, dueOpenLimit: 5)
    }
    XCTAssertEqual(inherited.eventCount, 1)
  }

  /// A habit counts on the days its cadence makes it due: a daily habit and a
  /// weekly one with no pinned weekdays every day, a weekday-pinned one on its
  /// weekdays, a monthly one on its day of the month, and a times-per-week one
  /// on none. 2026-04-06 is a Monday.
  func testLoadDaySummaryCountsEachHabitOnlyOnTheDaysItIsDue() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertHabit(db, id: "gym", target: 1, frequencyType: "weekly", weekdays: [0, 2, 4])
      try insertHabit(db, id: "water", target: 1)
      try insertHabit(db, id: "plan", target: 1, frequencyType: "weekly")
      try insertHabit(db, id: "run", target: 1, frequencyType: "times_per_week")
      try insertHabit(db, id: "rent", target: 1, frequencyType: "monthly", dayOfMonth: 8)
    }
    let totals: [(day: String, total: Int64)] = [
      ("2026-04-06", 3), ("2026-04-07", 2), ("2026-04-08", 4), ("2026-04-09", 2),
      ("2026-04-10", 3), ("2026-04-11", 2), ("2026-04-12", 2),
    ]
    for (day, total) in totals {
      let summary = try store.writer.read { db in
        try DayReview.loadDaySummary(db, date: day, completedLimit: 5, dueOpenLimit: 5)
      }
      XCTAssertEqual(summary.habitsTotal, total, day)
      XCTAssertEqual(summary.habitsCompleted, 0, day)
    }
  }

  /// A check-in on a rest day is counted: the habit is in the day's total, and
  /// in its completed count once the target is met.
  func testLoadDaySummaryKeepsACheckInMadeOnARestDay() throws {
    let store = try WorkflowTestSupport.freshStore()
    let tuesday = "2026-04-07"
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertHabit(db, id: "water", target: 1)
      try insertHabit(db, id: "gym", target: 1, frequencyType: "weekly", weekdays: [0, 2, 4])
      try insertHabit(db, id: "stretch", target: 2, frequencyType: "weekly", weekdays: [0])
      try insertHabit(db, id: "read", target: 1, frequencyType: "weekly", weekdays: [3])
      try insertHabitCompletion(db, habitId: "gym", date: tuesday, value: 1)
      try insertHabitCompletion(db, habitId: "stretch", date: tuesday, value: 1)
    }
    let summary = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: tuesday, completedLimit: 5, dueOpenLimit: 5)
    }

    // water (daily), gym (checked in), stretch (checked in, 1 of 2); read is
    // pinned to Thursday and was not checked in.
    XCTAssertEqual(summary.habitsTotal, 3)
    XCTAssertEqual(summary.habitsCompleted, 1)  // gym met its target
  }

  /// A monthly habit is due on its day of the month, clamped to the month's last
  /// day (the 31st falls on the 30th in April and the 28th in February), and on
  /// the 1st when it names no day.
  func testLoadDaySummaryClampsAMonthlyHabitToTheMonthsLastDay() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertHabit(db, id: "bills", target: 1, frequencyType: "monthly", dayOfMonth: 31)
      try insertHabit(db, id: "rent", target: 1, frequencyType: "monthly")
    }
    let totals: [(day: String, total: Int64)] = [
      ("2026-04-01", 1), ("2026-04-29", 0), ("2026-04-30", 1),
      ("2026-02-28", 1), ("2026-01-30", 0), ("2026-01-31", 1),
    ]
    for (day, total) in totals {
      let summary = try store.writer.read { db in
        try DayReview.loadDaySummary(db, date: day, completedLimit: 5, dueOpenLimit: 5)
      }
      XCTAssertEqual(summary.habitsTotal, total, day)
    }
  }

  /// A times-per-week habit, or a monthly habit on a day other than its own, is
  /// in the day's counts only when it was checked in that day.
  func testLoadDaySummaryCountsAPeriodHabitOnlyOnADayItWasCheckedIn() throws {
    let store = try WorkflowTestSupport.freshStore()
    let tuesday = "2026-04-07"
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertHabit(db, id: "run", target: 1, frequencyType: "times_per_week")
      try insertHabit(db, id: "swim", target: 1, frequencyType: "times_per_week")
      try insertHabit(db, id: "rent", target: 1, frequencyType: "monthly", dayOfMonth: 20)
      try insertHabit(db, id: "bills", target: 1, frequencyType: "monthly", dayOfMonth: 25)
      try insertHabitCompletion(db, habitId: "run", date: tuesday, value: 1)
      try insertHabitCompletion(db, habitId: "rent", date: tuesday, value: 1)
    }
    let summary = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: tuesday, completedLimit: 5, dueOpenLimit: 5)
    }

    // run and rent were checked in; swim has no particular day and bills falls
    // on the 25th.
    XCTAssertEqual(summary.habitsTotal, 2)
    XCTAssertEqual(summary.habitsCompleted, 2)
  }

  /// A skipped day is excused: the habit leaves the day's total, so a skip is
  /// neither a miss nor a completion. A check-in the same day outranks the skip,
  /// and a skip on another day changes nothing. 2026-04-07 is a Tuesday.
  func testLoadDaySummaryExcusesASkippedHabit() throws {
    let store = try WorkflowTestSupport.freshStore()
    let tuesday = "2026-04-07"
    try store.writer.write { db in
      try setLosAngelesTimezone(db)
      try insertHabit(db, id: "water", target: 1)
      try insertHabit(db, id: "cardio", target: 1)
      try insertHabit(db, id: "stretch", target: 1)
      try insertHabit(db, id: "gym", target: 1, frequencyType: "weekly", weekdays: [1])
      try insertHabitSkip(db, habitId: "cardio", date: tuesday)
      try insertHabitSkip(db, habitId: "stretch", date: tuesday)
      try insertHabitCompletion(db, habitId: "stretch", date: tuesday, value: 1)
      try insertHabitSkip(db, habitId: "water", date: "2026-04-06")
    }
    let summary = try store.writer.read { db in
      try DayReview.loadDaySummary(db, date: tuesday, completedLimit: 5, dueOpenLimit: 5)
    }

    // water (its skip is for Monday), stretch (the check-in outranks its skip) and
    // gym (pinned to Tuesday) count; cardio is excused.
    XCTAssertEqual(summary.habitsTotal, 3)
    XCTAssertEqual(summary.habitsCompleted, 1)  // stretch met its target
  }

  func testLoadDaySummaryRejectsOutOfRangeLimit() throws {
    let store = try WorkflowTestSupport.freshStore()
    try store.writer.write { db in try setLosAngelesTimezone(db) }
    try store.writer.read { db in
      XCTAssertThrowsError(
        try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 0, dueOpenLimit: 5))
      XCTAssertThrowsError(
        try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 51, dueOpenLimit: 5))
      XCTAssertThrowsError(
        try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5, dueOpenLimit: 0))
      XCTAssertThrowsError(
        try DayReview.loadDaySummary(db, date: Self.day, completedLimit: 5, dueOpenLimit: 51))
    }
  }
}
