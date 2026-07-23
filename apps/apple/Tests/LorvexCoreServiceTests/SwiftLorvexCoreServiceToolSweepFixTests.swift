import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// Regression coverage for on-disk `SwiftLorvexCoreService` fixes that the
/// in-memory fake masked: scoped-edit duration preservation, the delete-list
/// active-only guard, and reminder reads reporting the effective due date.
final class SwiftLorvexCoreServiceToolSweepFixTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func makeServiceAndStore() throws -> (SwiftLorvexCoreService, LorvexStore) {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return (SwiftLorvexCoreService(store: store), store)
  }

  // MARK: - edit_scoped this_only preserves duration

  /// Editing a single occurrence's start_time without an end_time must shift
  /// the end to preserve the original duration, not keep the old end (which
  /// produced "end_time must be after start_time").
  func testScopedThisOnlyEditPreservesDurationWhenOnlyStartMoves() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Daily standup", startDate: "2026-06-22", endDate: nil,
      startTime: "09:00", endTime: "09:15", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY","INTERVAL":1}"#),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(startTime: "09:30"))

    let replacement = try XCTUnwrap(result.replacementEvent)
    XCTAssertEqual(replacement.startTime, "09:30")
    XCTAssertEqual(replacement.endTime, "09:45", "15-minute duration must be preserved")
  }

  // MARK: - C9 part 2: typed calendar recurrence boundary

  /// The calendar service boundary carries the typed ``TaskRecurrenceRule`` (not
  /// a JSON string). It serializes to canonical JSON — including the multi-day
  /// BYMONTHDAY array shape, sorted + deduped — before storage, and the stored
  /// rule round-trips through normalization unchanged.
  func testCreateCalendarEventAcceptsTypedRecurrenceWithMultiDayBymonthday() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Payroll", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule(freq: .monthly, byMonthDay: [15, 1]),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)

    let raw = try XCTUnwrap(event.recurrenceRule)
    guard case .object(let rule)? = JSONValue.parse(raw) else {
      return XCTFail("recurrence should be a JSON object, got \(raw)")
    }
    guard case .string("MONTHLY")? = rule["FREQ"] else {
      return XCTFail("FREQ should be MONTHLY, got \(String(describing: rule["FREQ"]))")
    }
    guard case .array(let days)? = rule["BYMONTHDAY"] else {
      return XCTFail(
        "BYMONTHDAY should be an array, got \(String(describing: rule["BYMONTHDAY"]))")
    }
    let ints: [Int64] = days.compactMap { if case .int(let n) = $0 { return n } else { return nil } }
    XCTAssertEqual(ints, [1, 15], "typed byMonthDay [15, 1] normalizes to the sorted array [1, 15]")
  }

  func testCalendarWeeklyBydayMustIncludeStartDateWeekday() async throws {
    let service = try makeService()

    do {
      _ = try await service.createCalendarEvent(
        title: "Mismatch recurrence",
        startDate: "2026-06-09",
        endDate: nil,
        startTime: "08:00",
        endTime: "09:00",
        allDay: false,
        location: nil,
        notes: nil,
        recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"WEEKLY","BYDAY":["MO"]}"#),
        timezone: "America/Los_Angeles",
        url: nil,
        color: nil,
        eventType: nil,
        personName: nil,
        attendees: nil)
      XCTFail("Expected weekly BYDAY mismatch to be rejected.")
    } catch {
      XCTAssertTrue(String(describing: error).contains("BYDAY"))
    }
  }

  func testScopedThisOnlyEditInheritsAttendeesWhenUnset() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Design review", startDate: "2026-06-22", endDate: nil,
      startTime: "10:00", endTime: "11:00", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY","INTERVAL":1}"#),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil,
      attendees: [
        CalendarEventAttendee(email: "alex@example.com", name: "Alex")
      ])

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-23", scope: "this_only",
      updates: ScopedCalendarEventUpdates(title: "Design review / follow-up"))

    let replacement = try XCTUnwrap(result.replacementEvent)
    let attendee = try XCTUnwrap(replacement.attendees?.first)
    XCTAssertEqual(attendee.email, "alex@example.com")
    XCTAssertEqual(attendee.name, "Alex")
    // Native Lorvex attendees carry no RSVP status; the scoped edit preserves the
    // annotation (email + name), not a status.
    XCTAssertNil(attendee.status)
  }

  func testScopedThisAndFollowingEditPreservesTotalCountBoundedOccurrences() async throws {
    let service = try makeService()
    let event = try await service.createCalendarEvent(
      title: "Daily count", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY","COUNT":5}"#),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Daily count shifted"))

    let replacement = try XCTUnwrap(result.replacementEvent)
    let raw = try XCTUnwrap(replacement.recurrenceRule)
    guard case .object(let recurrence)? = JSONValue.parse(raw) else {
      return XCTFail("replacement recurrence should be a JSON object")
    }
    guard case .int(let count)? = recurrence["COUNT"] else {
      return XCTFail("replacement recurrence should carry COUNT")
    }
    XCTAssertEqual(count, 3)
  }

  func testScopedThisAndFollowingDoesNotRewriteFutureStampedPredecessor() async throws {
    let (service, store) = try makeServiceAndStore()
    let event = try await service.createCalendarEvent(
      title: "Future series", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY","COUNT":5}"#),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    let futureVersion = "9000000000000_0000_aaaaaaaaaaaaaaaa"
    try await store.writer.write { db in
      try db.execute(
        sql: "UPDATE calendar_events SET version = ? WHERE id = ?",
        arguments: [futureVersion, event.id])
    }

    let split = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-03", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Future tail"))

    let replacement = try XCTUnwrap(split.replacementEvent)
    let state = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT root.version AS root_version, root.recurrence AS root_recurrence,
                 cutover.version AS cutover_version, cutover.state AS cutover_state
          FROM calendar_events root
          JOIN calendar_series_cutovers cutover ON cutover.id = ?
          WHERE root.id = ?
          """,
        arguments: [replacement.id, event.id])!
    }
    XCTAssertEqual(state["root_version"] as String, futureVersion)
    XCTAssertEqual(state["root_recurrence"] as String?, event.recurrenceRule)
    XCTAssertEqual(state["cutover_state"] as String, "active")
    XCTAssertNoThrow(try Hlc.parseCanonical(state["cutover_version"] as String))
  }

  func testScopedThisAndFollowingAtFirstOccurrencePreservesCalendarLink() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Linked task", notes: "")
    let event = try await service.createCalendarEvent(
      title: "Linked series", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY","COUNT":3}"#),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    try seedTaskCalendarEventLink(service, taskID: task.id, eventID: event.id)

    let result = try await service.editScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-01", scope: "this_and_following",
      updates: ScopedCalendarEventUpdates(title: "Replacement"))

    XCTAssertEqual(result.replacementEvent?.id, event.id)
    XCTAssertFalse(
      try hasTaskCalendarEventLinkDeleteEnvelope(
        service, taskID: task.id, eventID: event.id))
    let retained = try service.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM task_calendar_event_links
          WHERE task_id = ? AND calendar_event_id = ?
          """,
        arguments: [task.id, event.id]) ?? 0
    }
    XCTAssertEqual(retained, 1)
  }

  func testGenericDeleteNonRecurringEmitsCalendarLinkTombstone() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Linked task", notes: "")
    let event = try await service.createCalendarEvent(
      title: "One-off", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false, location: nil, notes: nil,
      recurrence: nil, timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    try seedTaskCalendarEventLink(service, taskID: task.id, eventID: event.id)

    _ = try await service.deleteCalendarEvent(id: event.id)

    XCTAssertTrue(try hasTaskCalendarEventLinkDeleteEnvelope(service, taskID: task.id, eventID: event.id))
  }

  func testScopedDeleteCollapseEmitsCalendarLinkTombstone() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Linked task", notes: "")
    let event = try await service.createCalendarEvent(
      title: "Daily collapse", startDate: "2026-06-01", endDate: nil,
      startTime: "09:00", endTime: "09:30", allDay: false, location: nil, notes: nil,
      recurrence: TaskRecurrenceRule.bridgeRule(from: #"{"FREQ":"DAILY","COUNT":3}"#),
      timezone: "America/Los_Angeles",
      url: nil, color: nil, eventType: nil, personName: nil, attendees: nil)
    try seedTaskCalendarEventLink(service, taskID: task.id, eventID: event.id)

    _ = try await service.deleteScopedCalendarEvent(
      eventID: event.id, occurrenceDate: "2026-06-01", scope: "this_and_following")

    XCTAssertTrue(try hasTaskCalendarEventLinkDeleteEnvelope(service, taskID: task.id, eventID: event.id))
  }

  func testBatchCreateCalendarEventsRollsBackEntireBatchOnFailure() async throws {
    let service = try makeService()
    let before = try calendarEventCount(service)

    do {
      _ = try await service.batchCreateCalendarEvents([
        CalendarEventCreateDraft(
          title: "Valid prefix", startDate: "2026-06-01",
          startTime: "09:00", endTime: "09:30"),
        CalendarEventCreateDraft(
          title: "", startDate: "2026-06-02",
          startTime: "09:00", endTime: "09:30"),
      ])
      XCTFail("Expected invalid batch calendar event to roll back the transaction.")
    } catch {
      // expected
    }

    XCTAssertEqual(try calendarEventCount(service), before)
  }

  private func seedTaskCalendarEventLink(
    _ service: SwiftLorvexCoreService, taskID: String, eventID: String
  ) throws {
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO task_calendar_event_links
            (task_id, calendar_event_id, version, created_at, updated_at)
          VALUES (?1, ?2, '1711234567890_0000_a1b2c3d4a1b2c3d4',
                  '2026-06-01T08:00:00.000Z', '2026-06-01T08:00:00.000Z')
          """,
        arguments: [taskID, eventID])
    }
  }

  private func hasTaskCalendarEventLinkDeleteEnvelope(
    _ service: SwiftLorvexCoreService, taskID: String, eventID: String
  ) throws -> Bool {
    let edgeId = "\(taskID):\(eventID)"
    return try service.pendingOutbound().contains { pending in
      pending.envelope.entityType == .taskCalendarEventLink
        && pending.envelope.entityId == edgeId
        && pending.envelope.operation == .delete
    }
  }

  private func calendarEventCount(_ service: SwiftLorvexCoreService) throws -> Int {
    try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM calendar_events") ?? 0
    }
  }

  // MARK: - delete_list hard-blocks any assigned task; archive preserves history

  /// `delete_list` is a hard delete for genuinely empty lists. Any non-archived
  /// task assigned to it — open OR completed/cancelled — blocks deletion. A
  /// finished list with history is set aside by
  /// archiving the whole list (which keeps its tasks under the list name); the
  /// archived list leaves the active catalog and can be restored.
  func testDeleteListHardBlocksAssignedTasksAndArchiveSetsAside() async throws {
    let service = try makeService()

    // A cancelled (non-archived) task blocks deletion.
    let closing = try await service.createList(
      name: "Closing", description: nil, color: nil, icon: nil)
    let doneTask = try await service.createTask(title: "Wrap up", notes: "")
    _ = try await service.moveTask(id: doneTask.id, toListID: closing.id)
    _ = try await service.cancelTask(id: doneTask.id)
    do {
      try await service.deleteList(id: closing.id)
      XCTFail("deleting a list with a cancelled task should throw (hard block)")
    } catch {
      // expected
    }

    // Archiving sets the list aside: it leaves the active catalog, appears in the
    // archived catalog, and its task stays assigned to it (history preserved).
    let archived = try await service.archiveList(id: closing.id)
    XCTAssertNotNil(archived.archivedAt)
    let active = try await service.loadLists().lists
    XCTAssertFalse(active.contains { $0.id == closing.id })
    let archivedCatalog = try await service.loadArchivedLists().lists
    XCTAssertTrue(archivedCatalog.contains { $0.id == closing.id })
    let stillAssigned = try await service.loadTask(id: doneTask.id)
    XCTAssertEqual(stillAssigned.listID, closing.id)

    // Unarchiving restores it to the active catalog.
    _ = try await service.unarchiveList(id: closing.id)
    let restored = try await service.loadLists().lists
    XCTAssertTrue(restored.contains { $0.id == closing.id })

    // A genuinely empty list deletes cleanly.
    let empty = try await service.createList(
      name: "Empty", description: nil, color: nil, icon: nil)
    try await service.deleteList(id: empty.id)
    let afterDelete = try await service.loadLists().lists
    XCTAssertFalse(afterDelete.contains { $0.id == empty.id })
  }

  /// The workspace must always retain at least one list — `default_list_id`
  /// points at it and task creation resolves through it. Deleting the last
  /// remaining list (a fresh store has only `inbox`) is rejected; once a second
  /// list exists, a non-last list deletes cleanly.
  func testDeleteListRejectsDeletingTheLastRemainingList() async throws {
    let service = try makeService()
    let initial = try await service.loadLists().lists
    XCTAssertEqual(initial.count, 1, "a fresh store seeds exactly one list (inbox)")
    do {
      try await service.deleteList(id: initial[0].id)
      XCTFail("deleting the last remaining list should throw")
    } catch {
      // expected
    }
    let afterReject = try await service.loadLists().lists
    XCTAssertEqual(afterReject.count, 1, "the list must survive")

    let extra = try await service.createList(
      name: "Extra", description: nil, color: nil, icon: nil)
    try await service.deleteList(id: extra.id)
    let afterDelete = try await service.loadLists().lists
    XCTAssertEqual(afterDelete.count, 1, "a non-last list deletes cleanly")
  }

  // MARK: - dependency graph keeps cross-list blockers visible

  func testListScopedDependencyGraphIncludesExternalBlockers() async throws {
    let service = try makeService()
    let project = try await service.createList(
      name: "Project", description: nil, color: nil, icon: nil)
    let external = try await service.createList(
      name: "External", description: nil, color: nil, icon: nil)
    let blocked = try await service.createTask(title: "Ship proposal", notes: "")
    let blocker = try await service.createTask(title: "Get legal approval", notes: "")
    _ = try await service.moveTask(id: blocked.id, toListID: project.id)
    _ = try await service.moveTask(id: blocker.id, toListID: external.id)
    _ = try await service.updateTask(
      id: blocked.id, title: blocked.title, notes: blocked.notes, priority: blocked.priority,
      estimatedMinutes: blocked.estimatedMinutes, dueDate: blocked.dueDate,
      plannedDate: blocked.plannedDate, tags: blocked.tags, dependsOn: [blocker.id])

    let graph = try await service.getDependencyGraph(
      rootTaskID: nil, listID: project.id, includeInactive: false)

    XCTAssertTrue(graph.nodes.contains { $0.id == blocked.id })
    XCTAssertTrue(graph.nodes.contains { $0.id == blocker.id })
    XCTAssertTrue(
      graph.edges.contains {
        $0.from == blocked.id && $0.to == blocker.id
      })
    XCTAssertTrue(graph.blocked.contains(blocked.id))
  }

  // MARK: - reminder reads keep due and planned dates distinct

  /// get_due_task_reminders must not label planned_date as task_due_date.
  func testDueRemindersReportDueAndPlannedDatesSeparately() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Call dentist", notes: "")
    let planned = try XCTUnwrap(
      SwiftLorvexTaskDeserializers.plannedDateFormatter.date(from: "2026-06-25"))
    _ = try await service.updateTask(
      id: task.id, title: task.title, notes: task.notes, priority: task.priority,
      estimatedMinutes: task.estimatedMinutes, plannedDate: planned, tags: task.tags,
      dependsOn: task.dependsOn)
    _ = try await service.addTaskReminder(taskID: task.id, reminderAt: "2026-06-20T10:00:00Z")

    let due = try await service.getDueTaskReminders(asOf: "2026-06-21T00:00:00Z", limit: 50)
    let reminder = try XCTUnwrap(due.first { $0.taskID == task.id })
    XCTAssertNil(reminder.taskDueDate)
    XCTAssertEqual(reminder.taskPlannedDate, "2026-06-25")
  }

  // MARK: - daily review replacement and scalar-only preservation

  func testUpsertDailyReviewFullyReplacesOptionalFieldsAndExplicitlyClearsLinks() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Review-linked task", notes: "")
    let list = try await service.createList(name: "Review-linked list", description: nil, color: nil, icon: nil)

    let first = try await service.upsertDailyReview(
      date: nil,
      summary: "Initial review",
      mood: 4,
      energyLevel: 3,
      wins: "Shipped",
      blockers: "Waiting",
      learnings: "Keep replacement semantics explicit",
      linkedTaskIDs: [task.id],
      linkedListIDs: [list.id])

    XCTAssertEqual(first.linkedTaskIDs, [task.id])
    XCTAssertEqual(first.linkedListIDs, [list.id])
    XCTAssertEqual(first.mood, 4)
    XCTAssertEqual(first.energyLevel, 3)
    XCTAssertEqual(first.wins, "Shipped")
    XCTAssertEqual(first.blockers, "Waiting")
    XCTAssertEqual(first.learnings, "Keep replacement semantics explicit")

    let replacement = try await service.upsertDailyReview(
      date: first.date,
      summary: "Replacement review",
      mood: nil,
      energyLevel: nil,
      wins: nil,
      blockers: nil,
      learnings: nil,
      linkedTaskIDs: [],
      linkedListIDs: [])

    XCTAssertTrue(replacement.linkedTaskIDs.isEmpty)
    XCTAssertTrue(replacement.linkedListIDs.isEmpty)
    XCTAssertNil(replacement.mood)
    XCTAssertNil(replacement.energyLevel)
    XCTAssertNil(replacement.wins)
    XCTAssertNil(replacement.blockers)
    XCTAssertNil(replacement.learnings)
  }

  func testUpsertDailyReviewPreservingLinksKeepsTransactionCurrentLinks() async throws {
    let service = try makeService()
    let loadedTask = try await service.createTask(title: "Initially linked task", notes: "")
    let latestTask = try await service.createTask(title: "Concurrently linked task", notes: "")
    let loadedList = try await service.createList(
      name: "Initially linked list", description: nil, color: nil, icon: nil)
    let latestList = try await service.createList(
      name: "Concurrently linked list", description: nil, color: nil, icon: nil)
    let initial = try await service.upsertDailyReview(
      date: nil, summary: "Initial scalar state", mood: 3, energyLevel: 3,
      wins: nil, blockers: nil, learnings: nil,
      linkedTaskIDs: [loadedTask.id], linkedListIDs: [loadedList.id])

    // Represents an MCP/CloudKit write after a scalar-only surface loaded.
    _ = try await service.amendDailyReview(
      date: initial.date,
      patch: DailyReviewPatch(
        linkedTaskIDs: [latestTask.id], linkedListIDs: [latestList.id]))

    let saved = try await service.upsertDailyReviewPreservingLinks(
      date: initial.date, summary: "New scalar state", mood: 5, energyLevel: nil,
      wins: "Edited by a human", blockers: nil, learnings: nil)

    XCTAssertEqual(saved.summary, "New scalar state")
    XCTAssertEqual(saved.linkedTaskIDs, [latestTask.id])
    XCTAssertEqual(saved.linkedListIDs, [latestList.id])
  }

  // MARK: - focus references do not outlive their targets

  func testArchivingTaskRemovesItFromCurrentFocusAndFocusSchedule() async throws {
    let (service, store) = try makeServiceAndStore()
    let keep = try await service.createTask(title: "Keep in focus", notes: "")
    let archived = try await service.createTask(title: "Archive out of focus", notes: "")

    _ = try await service.setCurrentFocus(
      date: "2026-06-26",
      taskIDs: [archived.id, keep.id],
      briefing: "Two-task plan",
      timezone: "America/Los_Angeles")
    _ = try await service.saveFocusSchedule(
      date: "2026-06-26",
      blocks: [
        FocusScheduleBlock(
          blockType: "task", startTime: "09:00", endTime: "10:00",
          taskID: archived.id, title: archived.title),
        FocusScheduleBlock(
          blockType: "buffer", startTime: "10:00", endTime: "10:15",
          title: "Buffer"),
      ],
      rationale: "Regression")

    _ = try await service.archiveTask(id: archived.id)

    let loadedFocus = try await service.loadCurrentFocus(date: "2026-06-26")
    let focus = try XCTUnwrap(loadedFocus)
    XCTAssertEqual(focus.taskIDs, [keep.id])

    let loadedSchedule = try await service.loadFocusSchedule(date: "2026-06-26")
    let schedule = try XCTUnwrap(loadedSchedule)
    XCTAssertEqual(schedule.blocks.count, 1)
    XCTAssertEqual(schedule.blocks.first?.blockType, "buffer")
    XCTAssertNil(schedule.blocks.first?.taskID)

    try await store.writer.read { db in
      let currentRefs = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?",
        arguments: [archived.id]) ?? 0
      let scheduleRefs = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = ?",
        arguments: [archived.id]) ?? 0
      XCTAssertEqual(currentRefs, 0)
      XCTAssertEqual(scheduleRefs, 0)
    }

    do {
      _ = try await service.setCurrentFocus(
        date: "2026-06-27",
        taskIDs: [archived.id],
        briefing: nil,
        timezone: "America/Los_Angeles")
      XCTFail("archived tasks must not be accepted into current focus")
    } catch {
      // Expected.
    }

    let rejectedBlock = FocusScheduleBlock(
      blockType: "task", startTime: "09:00", endTime: "10:00",
      taskID: archived.id, title: archived.title)
    do {
      _ = try await service.saveFocusSchedule(
        date: "2026-06-28", blocks: [rejectedBlock], rationale: nil)
      XCTFail("archived tasks must not be accepted into a locally-authored focus schedule")
    } catch {
      let persisted = try await service.loadFocusSchedule(date: "2026-06-28")
      XCTAssertNil(persisted)
    }

    let importedBlock = ExportFocusScheduleBlock(
      position: 0, blockType: "task", startMinutes: 540, endMinutes: 600,
      taskID: archived.id, title: archived.title)
    do {
      try await service.importFocusSchedule(
        ExportFocusSchedule(date: "2026-06-29", blocks: [importedBlock]))
      XCTFail("archived tasks must not be accepted by overwrite-style schedule import")
    } catch {
      let persisted = try await service.loadFocusSchedule(date: "2026-06-29")
      XCTAssertNil(persisted)
    }
    let importedIfAbsent = try await service.importFocusScheduleIfAbsent(
      ExportFocusSchedule(date: "2026-06-30", blocks: [importedBlock]))
    XCTAssertFalse(importedIfAbsent)
    let persistedIfAbsent = try await service.loadFocusSchedule(date: "2026-06-30")
    XCTAssertNil(persistedIfAbsent)
  }

  func testRemoveFromCurrentFocusSucceedsWhenSiblingIsNoLongerActive() async throws {
    let service = try makeService()
    let keep = try await service.createTask(title: "Keep", notes: "")
    let drop = try await service.createTask(title: "Drop", notes: "")
    _ = try await service.setCurrentFocus(
      date: "2026-06-26", taskIDs: [keep.id, drop.id],
      briefing: nil, timezone: "America/Los_Angeles")
    // A focus sibling completes — it is no longer in an "active" status. Removing
    // a DIFFERENT item must not re-validate (and choke on) the survivor: a pure
    // removal introduces no new id to validate.
    _ = try await service.completeTask(id: keep.id)
    let focus = try await service.removeFromCurrentFocus(date: "2026-06-26", taskID: drop.id)
    let plan = try XCTUnwrap(focus)
    XCTAssertEqual(plan.taskIDs, [keep.id])
  }

  func testDeletingCalendarEventRemovesItFromFocusSchedule() async throws {
    let (service, store) = try makeServiceAndStore()
    let event = try await service.createCalendarEvent(
      title: "Planning block",
      startDate: "2026-06-26",
      endDate: nil,
      startTime: "11:00",
      endTime: "11:30",
      allDay: false,
      location: nil,
      notes: nil,
      recurrence: nil,
      timezone: "America/Los_Angeles",
      url: nil,
      color: nil,
      eventType: nil,
      personName: nil,
      attendees: nil)

    _ = try await service.saveFocusSchedule(
      date: "2026-06-26",
      blocks: [
        FocusScheduleBlock(
          blockType: "event", startTime: "11:00", endTime: "11:30",
          calendarEventID: event.id, eventSource: .canonical, title: event.title),
        FocusScheduleBlock(
          blockType: "buffer", startTime: "11:30", endTime: "11:45",
          title: "Reset"),
      ],
      rationale: "Calendar-linked plan")

    try await service.deleteCalendarEvent(id: event.id)

    let loadedSchedule = try await service.loadFocusSchedule(date: "2026-06-26")
    let schedule = try XCTUnwrap(loadedSchedule)
    XCTAssertEqual(schedule.blocks.count, 1)
    XCTAssertEqual(schedule.blocks.first?.blockType, "buffer")
    XCTAssertNil(schedule.blocks.first?.calendarEventID)

    try await store.writer.read { db in
      let refs = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE calendar_event_id = ?",
        arguments: [event.id]) ?? 0
      XCTAssertEqual(refs, 0)
    }
  }

  func testFocusScheduleReadPreservesSoftReferencesBeforeTargetsArrive() async throws {
    let (service, store) = try makeServiceAndStore()
    let task = try await service.createTask(title: "Dangling task block", notes: "")
    let event = try await service.createCalendarEvent(
      title: "Dangling event block",
      startDate: "2026-06-27",
      endDate: nil,
      startTime: "13:00",
      endTime: "13:30",
      allDay: false,
      location: nil,
      notes: nil,
      recurrence: nil,
      timezone: "America/Los_Angeles",
      url: nil,
      color: nil,
      eventType: nil,
      personName: nil,
      attendees: nil)

    _ = try await service.saveFocusSchedule(
      date: "2026-06-27",
      blocks: [
        FocusScheduleBlock(
          blockType: "task", startTime: "09:00", endTime: "10:00",
          taskID: task.id, title: task.title),
        FocusScheduleBlock(
          blockType: "event", startTime: "10:00", endTime: "10:30",
          calendarEventID: event.id, eventSource: .canonical, title: event.title),
        FocusScheduleBlock(
          blockType: "event", startTime: "10:30", endTime: "11:00",
          eventSource: .freeform, title: "Freeform event"),
        FocusScheduleBlock(
          blockType: "buffer", startTime: "11:00", endTime: "11:15",
          title: "Reset"),
      ],
      rationale: "Dangling read regression")

    try await store.writer.write { db in
      try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [task.id])
      try db.execute(sql: "DELETE FROM calendar_events WHERE id = ?", arguments: [event.id])
    }

    let loadedSchedule = try await service.loadFocusSchedule(date: "2026-06-27")
    let loaded = try XCTUnwrap(loadedSchedule)

    XCTAssertEqual(
      loaded.blocks.map(\.title),
      [task.title, event.title, "Freeform event", "Reset"])
    XCTAssertEqual(loaded.blocks[0].taskID, task.id)
    XCTAssertEqual(loaded.blocks[1].calendarEventID, event.id)
    XCTAssertEqual(loaded.blocks[1].eventSource, .canonical)
    XCTAssertEqual(loaded.blocks[2].eventSource, .freeform)
  }

  // MARK: - someday no-op does not pollute the changelog

  func testMarkSomedayOnAlreadySomedayDoesNotLogChangelog() async throws {
    let (service, store) = try makeServiceAndStore()
    let task = try await service.createTask(title: "Park me", notes: "")
    _ = try await service.markTaskSomeday(id: task.id)
    _ = try await service.markTaskSomeday(id: task.id)  // already someday → no-op
    let somedayLogs = try await store.writer.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE operation = 'someday'") ?? 0
    }
    XCTAssertEqual(
      somedayLogs, 1,
      "re-marking an already-someday task must not log a second changelog row")
  }

  func testUpdateListWithEmptyPatchDoesNotWriteSyncOrChangelog() async throws {
    let (service, store) = try makeServiceAndStore()
    let list = try await service.createList(
      name: "Project", description: "Original", color: nil, icon: nil, aiNotes: nil)
    let before = try await store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT
            (SELECT version FROM lists WHERE id = ?1) AS version,
            (SELECT COUNT(*) FROM sync_outbox) AS outbox_count,
            (SELECT COUNT(*) FROM ai_changelog) AS changelog_count,
            (SELECT value FROM local_counters WHERE name = 'local_change_seq') AS local_seq
          """,
        arguments: [list.id])!
    }

    let result = try await service.updateList(
      id: list.id, name: nil, description: nil, color: nil, icon: nil, aiNotes: nil)

    XCTAssertEqual(result.id, list.id)
    XCTAssertEqual(result.name, "Project")
    let after = try await store.writer.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT
            (SELECT version FROM lists WHERE id = ?1) AS version,
            (SELECT COUNT(*) FROM sync_outbox) AS outbox_count,
            (SELECT COUNT(*) FROM ai_changelog) AS changelog_count,
            (SELECT value FROM local_counters WHERE name = 'local_change_seq') AS local_seq
          """,
        arguments: [list.id])!
    }
    XCTAssertEqual(after["version"] as String, before["version"] as String)
    XCTAssertEqual(after["outbox_count"] as Int64, before["outbox_count"] as Int64)
    XCTAssertEqual(after["changelog_count"] as Int64, before["changelog_count"] as Int64)
    XCTAssertEqual(after["local_seq"] as Int64, before["local_seq"] as Int64)
  }

  func testSnapshotsExposeRealLocalChangeSequence() async throws {
    let (service, store) = try makeServiceAndStore()
    let task = try await service.createTask(title: "Focus me", notes: "")
    let expectedAfterCreate = try await store.writer.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT value FROM local_counters WHERE name = 'local_change_seq'")
    }
    let todaySequence = try await service.loadToday().localChangeSequence
    XCTAssertEqual(todaySequence, Int(expectedAfterCreate ?? -1))

    _ = try await service.setCurrentFocus(
      date: "2026-06-28", taskIDs: [task.id], briefing: nil, timezone: "UTC")
    let expectedAfterFocus = try await store.writer.read { db in
      try Int64.fetchOne(
        db, sql: "SELECT value FROM local_counters WHERE name = 'local_change_seq'")
    }
    let loadedFocusSequence = try await service.loadCurrentFocus(date: "2026-06-28")?
      .localChangeSequence
    XCTAssertEqual(loadedFocusSequence, Int(expectedAfterFocus ?? -1))
  }

  // MARK: - recurrence-exception no-op does not bump version / sync / changelog

  /// A single entity's write-observable state: its stored row `version`, the
  /// pending sync-outbox envelope version for that entity, and the total
  /// `ai_changelog` count. The `sync_outbox` row coalesces per entity, so its
  /// row count is not a reliable "did an enqueue happen" signal — the pending
  /// envelope's version is, since a genuine upsert re-stamps it while a no-op
  /// leaves it (and the stored row version) untouched.
  private func writeObservables(
    _ service: SwiftLorvexCoreService, _ store: LorvexStore,
    table: String, entityType: EntityKind, entityId: String
  ) async throws -> (rowVersion: String, outboxVersion: Hlc?, changelog: Int64) {
    let (rowVersion, changelog) = try await store.writer.read { db -> (String, Int64) in
      let version = try String.fetchOne(
        db, sql: "SELECT version FROM \(table) WHERE id = ?", arguments: [entityId])!
      let changelog = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      return (version, changelog)
    }
    let outboxVersion =
      try service.pendingOutbound()
      .first { $0.envelope.entityType == entityType && $0.envelope.entityId == entityId }?
      .envelope.version
    return (rowVersion, outboxVersion, changelog)
  }

  private func taskObservables(
    _ service: SwiftLorvexCoreService, _ store: LorvexStore, taskID: String
  ) async throws -> (rowVersion: String, outboxVersion: Hlc?, changelog: Int64) {
    try await writeObservables(service, store, table: "tasks", entityType: .task, entityId: taskID)
  }

  private func listObservables(
    _ service: SwiftLorvexCoreService, _ store: LorvexStore, listID: String
  ) async throws -> (rowVersion: String, outboxVersion: Hlc?, changelog: Int64) {
    try await writeObservables(service, store, table: "lists", entityType: .list, entityId: listID)
  }

  private func recurringTask(_ service: SwiftLorvexCoreService) async throws -> LorvexTask {
    let task = try await service.createTask(title: "Water the plants", notes: "")
    return try await service.setTaskRecurrence(
      taskID: task.id, rule: TaskRecurrenceRule(freq: .daily, interval: 1))
  }

  /// Adding an EXDATE that is already present must not bump the task version,
  /// re-stamp the pending upsert, or write a changelog row — the exception set
  /// does not change, so it is a true no-op (matching the someday / value-level
  /// no-op guards).
  func testAddRecurrenceExceptionDuplicateIsNoOp() async throws {
    let (service, store) = try makeServiceAndStore()
    let task = try await recurringTask(service)
    _ = try await service.addTaskRecurrenceException(taskID: task.id, exceptionDate: "2026-07-04")

    let before = try await taskObservables(service, store, taskID: task.id)
    _ = try await service.addTaskRecurrenceException(taskID: task.id, exceptionDate: "2026-07-04")
    let after = try await taskObservables(service, store, taskID: task.id)

    XCTAssertEqual(after.rowVersion, before.rowVersion, "duplicate EXDATE must not bump version")
    XCTAssertEqual(
      after.outboxVersion, before.outboxVersion, "duplicate EXDATE must not re-stamp the upsert")
    XCTAssertEqual(
      after.changelog, before.changelog, "duplicate EXDATE must not log a changelog row")
  }

  /// Removing an EXDATE that is not present must be a true no-op (no version
  /// bump, no re-stamped upsert, no changelog row).
  func testRemoveRecurrenceExceptionAbsentIsNoOp() async throws {
    let (service, store) = try makeServiceAndStore()
    let task = try await recurringTask(service)
    _ = try await service.addTaskRecurrenceException(taskID: task.id, exceptionDate: "2026-07-04")

    let before = try await taskObservables(service, store, taskID: task.id)
    _ = try await service.removeTaskRecurrenceException(taskID: task.id, exceptionDate: "2026-12-25")
    let after = try await taskObservables(service, store, taskID: task.id)

    XCTAssertEqual(after.rowVersion, before.rowVersion, "absent-remove must not bump version")
    XCTAssertEqual(
      after.outboxVersion, before.outboxVersion, "absent-remove must not re-stamp the upsert")
    XCTAssertEqual(
      after.changelog, before.changelog, "absent-remove must not log a changelog row")
  }

  /// A genuine add / remove that changes the exception set must still bump the
  /// version, re-stamp the task upsert, and log a changelog row (regression
  /// guard so the no-op gate does not swallow real edits).
  func testGenuineRecurrenceExceptionAddAndRemoveStillWrite() async throws {
    let (service, store) = try makeServiceAndStore()
    let task = try await recurringTask(service)

    let beforeAdd = try await taskObservables(service, store, taskID: task.id)
    _ = try await service.addTaskRecurrenceException(taskID: task.id, exceptionDate: "2026-07-04")
    let afterAdd = try await taskObservables(service, store, taskID: task.id)
    XCTAssertNotEqual(afterAdd.rowVersion, beforeAdd.rowVersion, "a genuine add must bump version")
    XCTAssertNotEqual(
      afterAdd.outboxVersion, beforeAdd.outboxVersion, "a genuine add must re-stamp the upsert")
    XCTAssertEqual(
      afterAdd.changelog, beforeAdd.changelog + 1, "a genuine add must log a changelog row")

    let beforeRemove = try await taskObservables(service, store, taskID: task.id)
    _ = try await service.removeTaskRecurrenceException(taskID: task.id, exceptionDate: "2026-07-04")
    let afterRemove = try await taskObservables(service, store, taskID: task.id)
    XCTAssertNotEqual(
      afterRemove.rowVersion, beforeRemove.rowVersion, "a genuine remove must bump version")
    XCTAssertNotEqual(
      afterRemove.outboxVersion, beforeRemove.outboxVersion, "a genuine remove must re-stamp the upsert")
    XCTAssertEqual(
      afterRemove.changelog, beforeRemove.changelog + 1, "a genuine remove must log a changelog row")
  }

  // MARK: - update_list value-level no-op does not bump version / sync / changelog

  /// A patch whose values equal the current row (e.g. renaming a list to its
  /// existing name, re-setting the same color/icon) must not bump the version,
  /// re-stamp the upsert, or write a changelog row.
  func testUpdateListWithIdenticalValuesIsNoOp() async throws {
    let (service, store) = try makeServiceAndStore()
    let list = try await service.createList(
      name: "Project", description: "Original", color: "#FF0000", icon: "star", aiNotes: nil)

    let before = try await listObservables(service, store, listID: list.id)
    let result = try await service.updateList(
      id: list.id, name: "Project", description: "Original", color: "#FF0000", icon: "star",
      aiNotes: nil)
    let after = try await listObservables(service, store, listID: list.id)

    XCTAssertEqual(result.id, list.id)
    XCTAssertEqual(result.name, "Project")
    XCTAssertEqual(after.rowVersion, before.rowVersion, "identical patch must not bump version")
    XCTAssertEqual(
      after.outboxVersion, before.outboxVersion, "identical patch must not re-stamp the upsert")
    XCTAssertEqual(
      after.changelog, before.changelog, "identical patch must not log a changelog row")
  }

  /// A patch that changes at least one value must still bump the version,
  /// re-stamp the upsert, and write a changelog row (regression guard).
  func testUpdateListWithChangedValueStillWrites() async throws {
    let (service, store) = try makeServiceAndStore()
    let list = try await service.createList(
      name: "Project", description: "Original", color: "#FF0000", icon: "star", aiNotes: nil)

    let before = try await listObservables(service, store, listID: list.id)
    let result = try await service.updateList(
      id: list.id, name: "Project", description: "Original", color: "#00FF00", icon: "star",
      aiNotes: nil)
    let after = try await listObservables(service, store, listID: list.id)

    XCTAssertEqual(result.color, "#00FF00")
    XCTAssertNotEqual(after.rowVersion, before.rowVersion, "a genuine change must bump version")
    XCTAssertNotEqual(
      after.outboxVersion, before.outboxVersion, "a genuine change must re-stamp the upsert")
    XCTAssertEqual(
      after.changelog, before.changelog + 1, "a genuine change must log a changelog row")
  }

  func testRemovingChecklistItemMintsDominatingDeleteTombstoneVersion() async throws {
    let (service, store) = try makeServiceAndStore()
    let task = try await service.createTask(title: "Checklist tombstone", notes: "")
    let withItem = try await service.addTaskChecklistItem(taskID: task.id, text: "Preserve me")
    let itemID = try XCTUnwrap(withItem.checklistItems.first?.id)
    let rowVersionValue = try await store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT version FROM task_checklist_items WHERE id = ?", arguments: [itemID])
    }
    let rowVersion = try XCTUnwrap(rowVersionValue)
    _ = try await service.removeTaskChecklistItem(itemID: itemID)

    let (outboxPayload, tombstoneVersion) = try await store.writer.read { db in
      let payload = try String.fetchOne(
        db,
        sql: """
          SELECT payload FROM sync_outbox
          WHERE entity_type = 'task_checklist_item' AND entity_id = ? AND operation = 'delete'
          """,
        arguments: [itemID])
      let tombstone = try String.fetchOne(
        db,
        sql: """
          SELECT version FROM sync_tombstones
          WHERE entity_type = 'task_checklist_item' AND entity_id = ?
          """,
        arguments: [itemID])
      return (payload, tombstone)
    }
    let payload = try XCTUnwrap(outboxPayload.flatMap(JSONValue.parse))
    guard case .object(let object) = payload else {
      return XCTFail("Expected checklist tombstone payload object")
    }
    XCTAssertEqual(object["id"], .string(itemID))
    guard case .string(let deleteVersion)? = object["version"] else {
      return XCTFail("Expected checklist tombstone version string")
    }
    XCTAssertGreaterThan(try Hlc.parseCanonical(deleteVersion), try Hlc.parseCanonical(rowVersion))
    XCTAssertEqual(tombstoneVersion, deleteVersion)
  }

}
