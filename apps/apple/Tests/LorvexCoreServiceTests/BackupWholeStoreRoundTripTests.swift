import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexCore

/// Restoring a backup into an empty store reproduces every backed-up table.
///
/// One store is filled through the public write API so that each backed-up
/// table holds rows with non-default values: every task lifecycle state,
/// checklists, reminders, recurrence, dependencies, habit cadences with
/// completions and a reminder policy, a recurring calendar series with a
/// cancelled occurrence, a one-off override and a split, a task-to-event link,
/// reviews, briefings, memory, and preferences. The single-file JSON backup
/// and the ZIP backup are each restored into a fresh store, and the two
/// databases are compared column by column.
///
/// The table lists are exhaustive. A table added to the schema fails
/// ``testEveryTableIsDeclaredBackedUpOrLocal`` until it is declared either
/// backed up or local, and a column of a backed-up table that does not travel
/// in the backup fails the comparison until it is declared re-stamped.
final class BackupWholeStoreRoundTripTests: XCTestCase {
  /// Tables whose rows a backup carries and a restore reproduces.
  private static let backedUpTables: Set<String> = [
    "lists", "tasks", "habits", "tags", "calendar_series_cutovers", "calendar_events",
    "preferences", "memories", "daily_reviews", "daily_briefings", "task_tags",
    "task_dependencies", "task_calendar_event_links", "habit_completions", "habit_skips",
    "habit_weekdays",
    "task_recurrence_exceptions", "daily_review_task_links", "daily_review_list_links",
    "task_reminders", "task_checklist_items", "habit_reminder_policies",
  ]

  /// Tables a backup deliberately leaves out: sync, audit and idempotency
  /// bookkeeping, device-local runtime state, provider (EventKit) mirrors and
  /// links whose identity is specific to one device, and search indexes the
  /// store rebuilds from the rows above.
  private static let localTables: Set<String> = [
    "task_provider_event_links", "provider_calendar_events", "provider_scope_runtime_state",
    "device_state", "task_reminder_delivery_state", "habit_reminder_delivery_state",
    "error_logs", "schema_migrations", "mcp_idempotency", "ai_changelog",
    "ai_changelog_entities",
  ]

  private static let localTablePrefixes = ["sync_", "audit_", "local_", "tasks_fts", "calendar_events_fts"]

  /// Timestamp columns the backup carries no value for, so a restore stamps the
  /// restore instant. Every column named `version` or ending in `_version` is
  /// a hybrid-logical-clock stamp, which a restore mints for the destination
  /// device, and is skipped as well.
  private static let restampedTimestampColumns: [String: Set<String>] = [
    "lists": ["created_at", "updated_at"],
    "calendar_events": ["created_at", "updated_at"],
    "calendar_series_cutovers": ["created_at", "updated_at"],
    "daily_review_list_links": ["created_at"],
    "daily_review_task_links": ["created_at"],
    "habits": ["updated_at"],
    "preferences": ["updated_at"],
  ]

  private static func isLocal(_ table: String) -> Bool {
    localTables.contains(table) || localTablePrefixes.contains { table.hasPrefix($0) }
  }

  private static func isVersionColumn(_ column: String) -> Bool {
    column == "version" || column.hasSuffix("_version")
  }

  // MARK: - Tests

  func testEveryTableIsDeclaredBackedUpOrLocal() throws {
    let core = try SwiftLorvexCoreService.inMemory()
    let tables = try core.read { try Self.tableNames($0) }
    let undeclared = tables.filter { !Self.backedUpTables.contains($0) && !Self.isLocal($0) }
    XCTAssertEqual(
      undeclared, [],
      "declare each new table as backed up (and cover it in the seed) or as local")
    let missing = Self.backedUpTables.subtracting(tables)
    XCTAssertTrue(missing.isEmpty, "backed-up tables the schema no longer has: \(missing)")
  }

  func testJSONBackupRestoreReproducesBackedUpTables() async throws {
    let source = try SwiftLorvexCoreService.inMemory()
    try await seed(source)
    let json = try await source.exportData(entities: [], format: "json")
    let target = try await restore(Data(json.utf8))
    try assertBackedUpTablesMatch(source, target)

    // Restoring the same backup again leaves the tables as they are.
    let payload = try LorvexDataImporter.decode(Data(json.utf8))
    let again = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: target)
    XCTAssertTrue(again.issues.isEmpty, "second restore reported \(again.issues)")
    try assertBackedUpTablesMatch(source, target)
  }

  func testZipBackupRestoreReproducesBackedUpTables() async throws {
    let source = try SwiftLorvexCoreService.inMemory()
    try await seed(source)
    let zip = try await source.exportDataZip(
      entities: [], generatedAt: "2026-10-08T00:00:00.000Z", appVersion: "test")
    let target = try await restore(zip)
    try assertBackedUpTablesMatch(source, target)
  }

  // MARK: - Restore and comparison

  private func restore(_ backup: Data) async throws -> SwiftLorvexCoreService {
    let payload = try LorvexDataImporter.decode(backup)
    let target = try SwiftLorvexCoreService.inMemory()
    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: target)
    XCTAssertTrue(summary.issues.isEmpty, "restore reported \(summary.issues)")
    return target
  }

  private func assertBackedUpTablesMatch(
    _ source: SwiftLorvexCoreService, _ target: SwiftLorvexCoreService,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    for table in Self.backedUpTables.sorted() {
      let expected = try source.read { try Self.rows($0, table) }
      let restored = try target.read { try Self.rows($0, table) }
      XCTAssertFalse(
        expected.isEmpty, "the seed leaves \(table) empty, so its restore is untested",
        file: file, line: line)
      XCTAssertEqual(
        Set(restored.keys).symmetricDifference(expected.keys).sorted(), [],
        "\(table): rows present on only one side", file: file, line: line)
      let skipped = Self.restampedTimestampColumns[table] ?? []
      for (key, row) in expected {
        guard let restoredRow = restored[key] else { continue }
        for column in row.keys.sorted()
        where !Self.isVersionColumn(column) && !skipped.contains(column) {
          XCTAssertEqual(
            restoredRow[column], row[column], "\(table) \(key) column \(column)",
            file: file, line: line)
        }
      }
    }
  }

  private static func tableNames(_ db: Database) throws -> [String] {
    try String.fetchAll(
      db,
      sql: """
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name
        """)
  }

  /// Every row of `table` keyed by its primary key, each value rendered as text.
  private static func rows(_ db: Database, _ table: String) throws -> [String: [String: String]] {
    let info = try Row.fetchAll(db, sql: "PRAGMA table_info(\"\(table)\")")
    let primaryKey =
      info.filter { ($0["pk"] as Int) > 0 }
      .sorted { ($0["pk"] as Int) < ($1["pk"] as Int) }
      .map { $0["name"] as String }
    var out: [String: [String: String]] = [:]
    for row in try Row.fetchAll(db, sql: "SELECT * FROM \"\(table)\"") {
      var values: [String: String] = [:]
      for (column, value) in row { values[column] = value.description }
      let key =
        primaryKey.isEmpty
        ? values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
        : primaryKey.map { values[$0] ?? "" }.joined(separator: "|")
      out[key] = values
    }
    return out
  }

  // MARK: - Seed

  private func seed(_ core: SwiftLorvexCoreService) async throws {
    let today = LorvexDateFormatters.ymd.string(from: Date())
    func day(_ offset: Int) -> String {
      LorvexDateFormatters.ymdUTCAddingDays(today, days: offset) ?? today
    }
    func date(_ offset: Int) -> Date { LorvexDateFormatters.ymdUTC.date(from: day(offset)) ?? Date() }

    let planning = try await core.createList(
      name: "Planning", description: "Quarter plan", color: "#FF375F", icon: "paperplane.fill")
    _ = try await core.setListAINotes(id: planning.id, notes: "Assistant note on the list")
    let shelved = try await core.createList(
      name: "Shelved", description: nil, color: "#123456", icon: "tray.fill")
    _ = try await core.createTask(.init(title: "Lives in a shelved list", listID: shelved.id))
    _ = try await core.archiveList(id: shelved.id)

    // Notes with CR LF, tabs, trailing blanks, RTL and emoji must come back byte for byte.
    let awkwardNotes =
      "## Heading\r\n\r\n- item\twith a tab \r\n> quote 🚀 مرحبا שלום\r\n\r\ntrailing blank lines\n\n"
    let rich = try await core.createTask(
      .init(
        title: "Rich task — with 日本語", notes: awkwardNotes, listID: planning.id, priority: .p1,
        estimatedMinutes: 45, dueDate: date(3), plannedDate: date(1),
        plannedTime: (9 * 60)..<(9 * 60 + 45), tags: ["alpha", "beta", "日本語"]))
    _ = try await core.setTaskAINotes(taskID: rich.id, notes: "Assistant note")
    _ = try await core.setTaskReminders(
      taskID: rich.id, reminderAts: ["\(day(2))T09:00:00.000Z", "\(day(2))T15:30:00.000Z"])
    let withChecklist = try await core.addTaskChecklistItem(taskID: rich.id, text: "first")
    _ = try await core.addTaskChecklistItem(taskID: rich.id, text: "second")
    if let first = withChecklist.checklistItems.first {
      try await core.toggleTaskChecklistItem(itemID: first.id, completed: true)
    }

    let started = try await core.createTask(title: "In progress", notes: "")
    _ = try await core.startTask(id: started.id)
    let paused = try await core.createTask(title: "Paused", notes: "")
    _ = try await core.startTask(id: paused.id)
    _ = try await core.pauseTask(id: paused.id)
    let cancelled = try await core.createTask(title: "Cancelled", notes: "")
    _ = try await core.cancelTask(id: cancelled.id)
    let deferred = try await core.createTask(
      .init(title: "Deferred", priority: .p3, dueDate: date(2)))
    try await core.deferTask(id: deferred.id, until: date(9), reason: "blocked", note: "revisit")
    let someday = try await core.createTask(title: "Someday", notes: "")
    _ = try await core.markTaskSomeday(id: someday.id)
    let reopened = try await core.createTask(title: "Completed then reopened", notes: "")
    _ = try await core.completeTask(id: reopened.id)
    _ = try await core.reopenTask(id: reopened.id)
    let archived = try await core.createTask(title: "Archived", notes: "")
    _ = try await core.completeTask(id: archived.id)
    _ = try await core.archiveTask(id: archived.id)

    let weekly = try await core.createTask(
      .init(
        title: "Weekly, completed once", priority: .p3, dueDate: date(0),
        recurrence: TaskRecurrenceRule(freq: .weekly, interval: 1)))
    _ = try await core.completeTask(id: weekly.id)
    let daily = try await core.createTask(
      .init(
        title: "Daily with a skipped day", priority: .p2, dueDate: date(0),
        recurrence: TaskRecurrenceRule(freq: .daily)))
    try await core.addTaskRecurrenceException(taskID: daily.id, exceptionDate: day(2))
    let blockerA = try await core.createTask(title: "Blocker A", notes: "")
    let blockerB = try await core.createTask(title: "Blocker B", notes: "")
    _ = try await core.createTask(
      .init(title: "Waits on two", dueDate: date(5), dependsOn: [blockerA.id, blockerB.id]))

    let cadences: [(String, HabitCadenceInput)] = [
      ("Daily habit", .daily),
      ("Weekdays habit", HabitCadenceInput(frequencyType: "weekly", weekdays: [0, 2, 4])),
      ("Three a week", HabitCadenceInput(frequencyType: "times_per_week", perPeriodTarget: 3)),
      ("Monthly habit", HabitCadenceInput(frequencyType: "monthly", dayOfMonth: 15)),
    ]
    var firstHabit: LorvexHabit?
    for (name, cadence) in cadences {
      let habit = try await core.createHabit(
        name: name, cue: "After coffee", icon: "star.fill", color: "#ABCDEF", targetCount: 2,
        cadence: cadence, milestoneTarget: 30)
      _ = try await core.completeHabit(id: habit.id, date: day(-1))
      _ = try await core.completeHabit(id: habit.id, date: day(-2))
      try await core.adjustHabitCompletion(id: habit.id, date: day(-2), delta: 1)
      firstHabit = firstHabit ?? habit
    }
    let reminded = try XCTUnwrap(firstHabit)
    _ = try await core.skipHabit(id: reminded.id, date: day(-3))
    _ = try await core.upsertHabitReminderPolicy(
      id: reminded.id,
      policy: HabitReminderPolicy(
        id: "", habitID: reminded.id, habitName: reminded.name, reminderTime: "08:30",
        enabled: true, createdAt: "", updatedAt: ""))
    let retired = try await core.createHabit(
      name: "Retired habit", cue: nil, icon: nil, color: nil, targetCount: 1, cadence: .daily,
      milestoneTarget: nil)
    _ = try await core.completeHabit(id: retired.id, date: day(-3))
    _ = try await core.updateHabit(
      id: retired.id, name: nil, cue: .unset, color: nil, icon: nil, targetCount: nil,
      archived: true)

    let series = try await core.createCalendarEvent(
      title: "Daily standup", startDate: day(-5), endDate: nil, startTime: "09:00",
      endTime: "09:15", allDay: false, location: "Room 1", notes: "Series notes",
      recurrence: TaskRecurrenceRule(freq: .daily), timezone: "America/Los_Angeles",
      url: "https://example.com/standup", color: "#FF0000", eventType: "anniversary",
      personName: "Pat",
      attendees: [CalendarEventAttendee(email: "guest", name: "Guest", status: "accepted")])
    _ = try await core.deleteScopedCalendarEvent(
      eventID: series.id, occurrenceDate: day(-2), scope: "this_only")
    _ = try await core.editScopedCalendarEvent(
      eventID: series.id, occurrenceDate: day(-1), scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "One-off title", location: "Room 9"))
    _ = try await core.editScopedCalendarEvent(
      eventID: series.id, occurrenceDate: day(1), scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(
        title: "Standup, moved", startTime: "09:30", endTime: "09:45"))
    _ = try await core.createCalendarEvent(
      title: "Offsite", startDate: day(2), endDate: day(4), startTime: nil, endTime: nil,
      allDay: true, location: nil, notes: nil, recurrence: nil, timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    _ = try await core.importTaskCalendarEventLink(
      ExportTaskCalendarEventLink(taskID: rich.id, calendarEventID: series.eventID))

    _ = try await core.upsertDailyReview(
      date: day(-1), summary: "A review", mood: 4, energyLevel: 3, wins: "Wins",
      blockers: "Blockers", learnings: "Learnings", linkedTaskIDs: [reopened.id, started.id],
      linkedListIDs: [planning.id])
    _ = try await core.upsertDailyReview(
      date: day(-2), summary: "Another review", mood: nil, energyLevel: nil, wins: nil,
      blockers: nil, learnings: nil, linkedTaskIDs: [], linkedListIDs: [])
    try await core.setDailyBriefingForMcp(date: day(0), briefing: "Today's briefing")
    try await core.setDailyBriefingForMcp(date: day(-3), briefing: "An older briefing")

    _ = try await core.upsertMemory(key: "travel", content: "Prefers aisle seats.\n\nBooks early.")
    _ = try await core.upsertMemory(key: "emoji_and_scripts", content: "🚀 مرحبا שלום 你好")
    _ = try await core.setPreference(key: "working_hours", value: "09:00-17:00")
    _ = try await core.setPreference(key: "timezone", value: "America/Los_Angeles")
  }
}
