import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// CK-4: the non-destructive bulk-import path resolves presence-and-write in ONE
/// transaction and refuses to resurrect a deleted entity.
///
/// Two hazards, both closed by the `import…IfAbsent` / `import…RecordTransactionally`
/// entry points:
///   1. **Race in the gap.** A concurrent create landing between a separate
///      presence read and the write would let a stale backup overwrite it. Each
///      test seeds a live row directly (models the create that won the gap) and
///      asserts the same-id import with DIFFERENT content leaves the row
///      unchanged, reports `imported == false`, and mints NO outbox envelope (no
///      dominating HLC — nothing to re-propagate the stale copy fleet-wide).
///   2. **Resurrection.** A backup is by construction older than any post-backup
///      delete, so a fresh dominating import HLC would beat the death version and
///      re-propagate the row. Each tombstone test creates → deletes an entity
///      (row gone + `sync_tombstones` row) and asserts the same-id import does not
///      re-create it.
///
/// The idempotent `import*` methods stay overwrite-on-reimport LWW-upserts (pinned
/// by `SwiftLorvexCoreServiceImportTests` / `SwiftLorvexCoreServiceImportLwwTests`);
/// the skip lives only in the `…IfAbsent` / `…Transactionally` entry points the
/// bulk importer calls.
final class SwiftLorvexCoreServiceImportAtomicityTests: XCTestCase {

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

  private func uuid() -> String { UUID().uuidString.lowercased() }

  /// A plausible, non-future HLC version so a directly seeded row reads as a live
  /// local row (format: `{physicalMs}_{counter}_{deviceHex}`).
  private static let seedVersion = "1700000000000_0000_0000000000000000"
  private static let seedTime = "2026-01-01T00:00:00.000Z"

  private func seed(_ service: SwiftLorvexCoreService, _ sql: String, _ args: StatementArguments)
    throws
  {
    try service.write { db in try db.execute(sql: sql, arguments: args) }
  }

  private func assertNoOutbound(
    _ service: SwiftLorvexCoreService, file: StaticString = #filePath, line: UInt = #line
  ) throws {
    XCTAssertTrue(
      try service.pendingOutbound().isEmpty,
      "a skipped import must mint no outbox envelope (no dominating HLC)", file: file, line: line)
  }

  // MARK: - (a) Atomic skip-if-exists — one per aggregate

  func testImportListIfAbsentSkipsLiveRow() async throws {
    let service = try makeService()
    let id = uuid()
    try seed(
      service,
      "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES (?, ?, ?, ?, ?)",
      [id, "Original", Self.seedVersion, Self.seedTime, Self.seedTime])

    let (row, imported) = try await service.importListIfAbsent(
      id: id, name: "Changed", description: "new", color: nil, icon: nil, aiNotes: nil,
      archivedAt: nil, position: nil)

    XCTAssertFalse(imported)
    XCTAssertNil(row)
    let name = try service.read {
      try String.fetchOne($0, sql: "SELECT name FROM lists WHERE id = ?", arguments: [id])
    }
    XCTAssertEqual(name, "Original")
    try assertNoOutbound(service)
  }

  func testImportTagIfAbsentSkipsLiveRow() async throws {
    let service = try makeService()
    let id = uuid()
    try seed(
      service,
      "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?, ?)",
      [id, "Original", "original", Self.seedVersion, Self.seedTime, Self.seedTime])

    let imported = try await service.importTagIfAbsent(ExportTag(id: id, displayName: "Changed"))

    XCTAssertFalse(imported)
    let name = try service.read {
      try String.fetchOne($0, sql: "SELECT display_name FROM tags WHERE id = ?", arguments: [id])
    }
    XCTAssertEqual(name, "Original")
    try assertNoOutbound(service)
  }

  func testImportCalendarEventIfAbsentSkipsLiveRow() async throws {
    let service = try makeService()
    let id = uuid()
    try seed(
      service,
      "INSERT INTO calendar_events (id, title, start_date, all_day, event_type, content_version, "
        + "recurrence_topology_version, version, created_at, updated_at) "
        + "VALUES (?, ?, '2026-05-01', 1, 'event', ?, ?, ?, ?, ?)",
      [
        id, "Original", Self.seedVersion, Self.seedVersion, Self.seedVersion,
        Self.seedTime, Self.seedTime,
      ])

    let (event, imported) = try await service.importCalendarEventIfAbsent(
      id: id, title: "Changed", startDate: "2026-05-01", startTime: nil, endDate: nil, endTime: nil,
      allDay: true, location: nil, notes: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil, timezone: nil, recurrence: nil,
      seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
      recurrenceGeneration: nil)

    XCTAssertFalse(imported)
    XCTAssertNil(event)
    let title = try service.read {
      try String.fetchOne($0, sql: "SELECT title FROM calendar_events WHERE id = ?", arguments: [id])
    }
    XCTAssertEqual(title, "Original")
    try assertNoOutbound(service)
  }

  func testImportDailyReviewIfAbsentSkipsLiveRow() async throws {
    let service = try makeService()
    let date = "2026-06-01"
    try seed(
      service,
      "INSERT INTO daily_reviews (date, summary, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?)",
      [date, "Original", Self.seedVersion, Self.seedTime, Self.seedTime])

    let imported = try await service.importDailyReviewIfAbsent(
      date: date, summary: "Changed", mood: nil, energyLevel: nil, wins: nil, blockers: nil,
      learnings: nil, timezone: nil, updatedAt: nil, linkedTaskIDs: nil,
      linkedListIDs: nil)

    XCTAssertFalse(imported)
    let summary = try service.read {
      try String.fetchOne(
        $0, sql: "SELECT summary FROM daily_reviews WHERE date = ?", arguments: [date])
    }
    XCTAssertEqual(summary, "Original")
    try assertNoOutbound(service)
  }

  func testImportCurrentFocusIfAbsentSkipsLiveRow() async throws {
    let service = try makeService()
    let date = "2026-06-02"
    try seed(
      service,
      "INSERT INTO current_focus (date, briefing, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?)",
      [date, "Original", Self.seedVersion, Self.seedTime, Self.seedTime])

    let imported = try await service.importCurrentFocusIfAbsent(
      ExportCurrentFocus(date: date, briefing: "Changed"))

    XCTAssertFalse(imported)
    let briefing = try service.read {
      try String.fetchOne(
        $0, sql: "SELECT briefing FROM current_focus WHERE date = ?", arguments: [date])
    }
    XCTAssertEqual(briefing, "Original")
    try assertNoOutbound(service)
  }

  func testImportFocusScheduleIfAbsentSkipsLiveRow() async throws {
    let service = try makeService()
    let date = "2026-06-03"
    try seed(
      service,
      "INSERT INTO focus_schedule (date, rationale, version, created_at, updated_at) "
        + "VALUES (?, ?, ?, ?, ?)",
      [date, "Original", Self.seedVersion, Self.seedTime, Self.seedTime])

    let imported = try await service.importFocusScheduleIfAbsent(
      ExportFocusSchedule(date: date, rationale: "Changed"))

    XCTAssertFalse(imported)
    let rationale = try service.read {
      try String.fetchOne(
        $0, sql: "SELECT rationale FROM focus_schedule WHERE date = ?", arguments: [date])
    }
    XCTAssertEqual(rationale, "Original")
    try assertNoOutbound(service)
  }

  func testImportMemoryEntryIfAbsentSkipsLiveRow() async throws {
    let service = try makeService()
    let id = uuid()
    let key = "notes"
    try seed(
      service,
      "INSERT INTO memories (id, key, content, version, updated_at) VALUES (?, ?, ?, ?, ?)",
      [id, key, "Original", Self.seedVersion, Self.seedTime])

    let (entry, imported) = try await service.importMemoryEntryIfAbsent(
      ExportMemoryEntry(id: id, key: key, content: "Changed",
        updatedAt: "2026-06-05T00:00:00Z"))

    XCTAssertFalse(imported)
    XCTAssertNil(entry)
    let content = try service.read {
      try String.fetchOne($0, sql: "SELECT content FROM memories WHERE key = ?", arguments: [key])
    }
    XCTAssertEqual(content, "Original")
    try assertNoOutbound(service)
  }

  // MARK: - (c) Habit atomic entry stays skip-if-exists, never unconditional-overwrite

  func testImportHabitRecordTransactionallySkipsLiveRow() async throws {
    let service = try makeService()
    let id = uuid()
    try seed(
      service,
      "INSERT INTO habits (id, name, target_count, version, created_at, updated_at) "
        + "VALUES (?, ?, 2, ?, ?, ?)",
      [id, "Original", Self.seedVersion, Self.seedTime, Self.seedTime])

    let imported = try await service.importHabitRecordTransactionally(
      ExportHabit(id: id, name: "Changed", cue: "", frequencyType: "daily", targetCount: 5))

    XCTAssertFalse(imported)
    let (name, target) = try service.read {
      (
        try String.fetchOne($0, sql: "SELECT name FROM habits WHERE id = ?", arguments: [id]),
        try Int.fetchOne($0, sql: "SELECT target_count FROM habits WHERE id = ?", arguments: [id])
      )
    }
    XCTAssertEqual(name, "Original", "importHabitRecordTransactionally must not overwrite a live row")
    XCTAssertEqual(target, 2)
    try assertNoOutbound(service)
  }

  func testPortableTaskDeferredFinalizeRefusesToOverwritePostCreateEdit() async throws {
    let service = try makeService()
    let taskID = uuid()
    let dependencyID = uuid()
    _ = try await service.importRemoteTask(
      id: dependencyID, title: "Dependency", notes: "", aiNotes: nil,
      rawInput: nil, priority: .p2, status: .open, estimatedMinutes: nil,
      dueDate: nil, plannedDate: nil, availableFrom: nil, tags: [], dependsOn: [])
    try service.write { db in try db.execute(sql: "DELETE FROM sync_outbox") }

    let backup = ExportTask(
      id: taskID, title: "Backup title", notes: "Backup notes", priority: "P2",
      status: "open", dueDate: nil, estimatedMinutes: nil,
      dependsOn: [dependencyID], deferCount: 4,
      lastDeferReason: "needs_info", updatedAt: "2026-01-01T00:00:00.000Z")
    let creation = try await service.importTaskRecordTransactionally(
      backup, priority: .p2, dueDate: nil, plannedDate: nil,
      availableFrom: nil, dependenciesToApply: [])
    let witness = try XCTUnwrap(creation)

    _ = try await service.updateTask(
      TaskUpdateDraft(id: taskID, title: "Concurrent user edit", notes: "Keep me"))

    let result = try await service.finalizeImportedTaskRecordTransactionally(
      backup, creationWitness: witness)

    XCTAssertFalse(result.matchedCreationWitness)
    XCTAssertTrue(result.failures.isEmpty)
    let preserved = try await service.loadTask(id: taskID)
    XCTAssertEqual(preserved.title, "Concurrent user edit")
    XCTAssertEqual(preserved.notes, "Keep me")
    XCTAssertEqual(preserved.deferCount, 0)
    XCTAssertTrue(preserved.dependsOn.isEmpty)
  }

  func testTaskImportCannotReparentAnotherTasksChecklistIdentity() async throws {
    let service = try makeService()
    let original = try await service.createTask(title: "Original parent", notes: "")
    let withItem = try await service.addTaskChecklistItem(
      taskID: original.id, text: "Keep this child")
    let childID = try XCTUnwrap(withItem.checklistItems.first?.id)
    try service.write { db in try db.execute(sql: "DELETE FROM sync_outbox") }
    let importedID = uuid()

    await XCTAssertThrowsErrorAsync(
      try await service.importTaskRecordTransactionally(
        ExportTask(
          id: importedID, title: "Hostile parent", notes: "", priority: "P2",
          status: "open", dueDate: nil, estimatedMinutes: nil,
          checklist: [
            ExportChecklistItem(
              id: childID, position: 0, text: "Stolen child", completed: false)
          ]),
        priority: .p2, dueDate: nil, plannedDate: nil, availableFrom: nil,
        dependenciesToApply: []))

    try service.read { db in
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [importedID]))
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT task_id, text FROM task_checklist_items WHERE id = ?",
          arguments: [childID]))
      XCTAssertEqual(row["task_id"] as String, original.id)
      XCTAssertEqual(row["text"] as String, "Keep this child")
    }
    try assertNoOutbound(service)
  }

  func testTaskImportCannotResurrectATombstonedChecklistIdentity() async throws {
    let service = try makeService()
    let original = try await service.createTask(title: "Original parent", notes: "")
    let withItem = try await service.addTaskChecklistItem(
      taskID: original.id, text: "Delete this child")
    let childID = try XCTUnwrap(withItem.checklistItems.first?.id)
    _ = try await service.removeTaskChecklistItem(itemID: childID)
    try service.write { db in try db.execute(sql: "DELETE FROM sync_outbox") }
    let importedID = uuid()

    await XCTAssertThrowsErrorAsync(
      try await service.importTaskRecordTransactionally(
        ExportTask(
          id: importedID, title: "Resurrection attempt", notes: "", priority: "P2",
          status: "open", dueDate: nil, estimatedMinutes: nil,
          checklist: [
            ExportChecklistItem(
              id: childID, position: 0, text: "Back again", completed: false)
          ]),
        priority: .p2, dueDate: nil, plannedDate: nil, availableFrom: nil,
        dependenciesToApply: []))

    try service.read { db in
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [importedID]))
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM task_checklist_items WHERE id = ?",
          arguments: [childID]))
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.taskChecklistItem, entityId: childID))
    }
    try assertNoOutbound(service)
  }

  func testTaskImportRejectsDuplicateChildIdentitiesBeforeCreatingRoot() async throws {
    let service = try makeService()
    let importedID = uuid()
    let childID = uuid()

    await XCTAssertThrowsErrorAsync(
      try await service.importTaskRecordTransactionally(
        ExportTask(
          id: importedID, title: "Duplicate children", notes: "", priority: "P2",
          status: "open", dueDate: nil, estimatedMinutes: nil,
          checklist: [
            ExportChecklistItem(id: childID, position: 0, text: "One", completed: false),
            ExportChecklistItem(id: childID, position: 1, text: "Two", completed: false),
          ]),
        priority: .p2, dueDate: nil, plannedDate: nil, availableFrom: nil,
        dependenciesToApply: []))

    try service.read { db in
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [importedID]))
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_checklist_items"), 0)
    }
    try assertNoOutbound(service)
  }

  func testHabitImportCannotReparentAnotherHabitsReminderPolicy() async throws {
    let service = try makeService()
    let original = try await service.createHabit(
      name: "Original habit", cue: nil, targetCount: 1)
    let policyID = uuid()
    let policy = ExportHabitReminderPolicy(
      id: policyID, reminderTime: "09:00", enabled: true,
      createdAt: Self.seedTime, updatedAt: Self.seedTime)
    try await service.importHabitReminderPolicy(habitID: original.id, policy: policy)
    try service.write { db in try db.execute(sql: "DELETE FROM sync_outbox") }
    let importedID = uuid()

    await XCTAssertThrowsErrorAsync(
      try await service.importHabitRecordTransactionally(
        ExportHabit(
          id: importedID, name: "Hostile habit", cue: "", frequencyType: "daily",
          targetCount: 1, reminderPolicies: [policy])))

    try service.read { db in
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM habits WHERE id = ?", arguments: [importedID]))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT habit_id FROM habit_reminder_policies WHERE id = ?",
          arguments: [policyID]),
        original.id)
    }
    try assertNoOutbound(service)
  }

  // MARK: - (b) Tombstone no-resurrect

  func testImportListIfAbsentSkipsTombstonedId() async throws {
    let service = try makeService()
    let id = uuid()
    _ = try await service.importList(
      id: id, name: "Doomed", description: nil, color: nil, icon: nil)
    try await service.deleteList(id: id)

    let (row, imported) = try await service.importListIfAbsent(
      id: id, name: "Resurrected", description: nil, color: nil, icon: nil, aiNotes: nil,
      archivedAt: nil, position: nil)

    XCTAssertFalse(imported)
    XCTAssertNil(row)
    try service.read { db in
      XCTAssertNil(
        try Int.fetchOne(db, sql: "SELECT 1 FROM lists WHERE id = ?", arguments: [id]),
        "a deleted list must not be resurrected by a restore")
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.list, entityId: id))
    }
  }

  func testImportCalendarEventIfAbsentSkipsTombstonedId() async throws {
    let service = try makeService()
    let id = uuid()
    _ = try await service.importCalendarEvent(
      id: id, title: "Doomed", startDate: "2026-05-01", startTime: nil, endDate: nil, endTime: nil,
      allDay: true, location: nil, notes: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil, timezone: nil, recurrence: nil,
      seriesId: nil, recurrenceInstanceDate: nil)
    _ = try await service.deleteCalendarEvent(id: id)

    let (event, imported) = try await service.importCalendarEventIfAbsent(
      id: id, title: "Resurrected", startDate: "2026-05-01", startTime: nil, endDate: nil,
      endTime: nil, allDay: true, location: nil, notes: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil, timezone: nil, recurrence: nil,
      seriesId: nil, recurrenceInstanceDate: nil, occurrenceState: nil,
      recurrenceGeneration: nil)

    XCTAssertFalse(imported)
    XCTAssertNil(event)
    try service.read { db in
      XCTAssertNil(
        try Int.fetchOne(db, sql: "SELECT 1 FROM calendar_events WHERE id = ?", arguments: [id]))
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.calendarEvent, entityId: id))
    }
  }

  func testImportHabitRecordTransactionallySkipsTombstonedId() async throws {
    let service = try makeService()
    let id = uuid()
    _ = try await service.importHabit(
      id: id, name: "Doomed", cue: nil, frequencyType: "daily", weekdays: [], perPeriodTarget: nil,
      dayOfMonth: nil, targetCount: 1)
    _ = try await service.deleteHabit(id: id)

    let imported = try await service.importHabitRecordTransactionally(
      ExportHabit(id: id, name: "Resurrected", cue: "", frequencyType: "daily", targetCount: 1))

    XCTAssertFalse(imported)
    try service.read { db in
      XCTAssertNil(try Int.fetchOne(db, sql: "SELECT 1 FROM habits WHERE id = ?", arguments: [id]))
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.habit, entityId: id))
    }
  }

  func testImportMemoryEntryIfAbsentSkipsTombstonedId() async throws {
    let service = try makeService()
    let id = uuid()
    let key = "doomed-notes"
    _ = try await service.importMemoryEntry(
      ExportMemoryEntry(id: id, key: key, content: "gone",
        updatedAt: "2026-06-01T00:00:00Z"))
    _ = try await service.deleteMemory(key: key)

    let (entry, imported) = try await service.importMemoryEntryIfAbsent(
      ExportMemoryEntry(id: id, key: key, content: "resurrected",
        updatedAt: "2026-06-05T00:00:00Z"))

    XCTAssertFalse(imported)
    XCTAssertNil(entry)
    try service.read { db in
      XCTAssertNil(try Int.fetchOne(db, sql: "SELECT 1 FROM memories WHERE key = ?", arguments: [key]))
      XCTAssertTrue(try Tombstone.isTombstoned(db, entityType: EntityName.memory, entityId: id))
    }
  }

  func testImportCurrentFocusIfAbsentSkipsTombstonedDate() async throws {
    let service = try makeService()
    let date = "2026-07-01"
    try await service.importCurrentFocus(ExportCurrentFocus(date: date, briefing: "Doomed"))
    _ = try await service.clearCurrentFocus(date: date)

    let imported = try await service.importCurrentFocusIfAbsent(
      ExportCurrentFocus(date: date, briefing: "Resurrected"))

    XCTAssertFalse(imported)
    try service.read { db in
      XCTAssertNil(
        try Int.fetchOne(db, sql: "SELECT 1 FROM current_focus WHERE date = ?", arguments: [date]))
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.currentFocus, entityId: date))
    }
  }

  // MARK: - (d) Links: import refuses resurrection, an explicit assistant relink succeeds

  func testTombstonedLinkNotResurrectedViaImporterButRelinkedViaAssistant() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Linked task", notes: "")
    let eventID = uuid()
    _ = try await service.importCalendarEvent(
      id: eventID, title: "Linked event", startDate: "2026-05-01", startTime: nil, endDate: nil,
      endTime: nil, allDay: true, location: nil, notes: nil, url: nil, color: nil, eventType: nil,
      personName: nil, attendees: nil, timezone: nil, recurrence: nil,
      seriesId: nil, recurrenceInstanceDate: nil)
    let link = ExportTaskCalendarEventLink(taskID: task.id, calendarEventID: eventID)

    _ = try await service.importTaskCalendarEventLink(link)
    let removed = try await service.unlinkTaskCalendarEventLink(
      taskID: task.id, calendarEventID: eventID)
    XCTAssertTrue(removed)
    try service.read { db in
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EdgeName.taskCalendarEventLink, entityId: "\(task.id):\(eventID)"))
    }

    // Direction 1 — a data-file restore (import provenance) must not resurrect it.
    let payload = LorvexDataExportPayload(taskCalendarEventLinks: [link])
    let plan = LorvexDataImporter.plan(for: payload)
    let summary = await LorvexDataImporter.apply(plan: plan, payload: payload, using: service)
    let linkResult = summary.results.first { $0.category == .taskCalendarEventLinks }
    XCTAssertEqual(linkResult?.imported, 0)
    XCTAssertEqual(linkResult?.skipped, 1, "the tombstoned link is skipped under import provenance")
    try service.read { db in
      XCTAssertNil(
        try Int.fetchOne(
          db,
          sql: "SELECT 1 FROM task_calendar_event_links WHERE task_id = ? AND calendar_event_id = ?",
          arguments: [task.id, eventID]),
        "a data-file restore must not resurrect an unlinked pair")
    }

    // Direction 2 — an explicit assistant relink (assistant provenance) re-creates it.
    let relinked = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.importTaskCalendarEventLink(link)
    }
    XCTAssertTrue(relinked, "an explicit assistant link intentionally re-links a tombstoned pair")
    try service.read { db in
      XCTAssertNotNil(
        try Int.fetchOne(
          db,
          sql: "SELECT 1 FROM task_calendar_event_links WHERE task_id = ? AND calendar_event_id = ?",
          arguments: [task.id, eventID]))
    }
  }
}
