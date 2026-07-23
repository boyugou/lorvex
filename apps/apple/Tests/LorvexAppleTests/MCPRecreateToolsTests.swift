import Foundation
import GRDB
import MCP
import Testing

@testable import LorvexCore
@testable import LorvexMCPHost

private func rcall(
  _ registry: ToolRegistry, _ name: String, _ arguments: [String: Value] = [:]
) async throws -> CallTool.Result {
  try await registry.call(CallTool.Parameters(name: name, arguments: arguments))
}

/// A caller-supplied original id. Exported Lorvex records carry canonical
/// hyphenated lowercase UUIDs (the sync outbox rejects any other id shape), so
/// re-create fixtures mint the same shape.
private func rid() -> String { UUID().uuidString.lowercased() }

/// Create a task and a Lorvex-owned calendar event at caller-supplied ids so
/// the canonical `link_task_to_event` / `unlink_task_from_event` pair has real
/// records to bind.
private func seedLinkableTaskAndEvent(
  _ registry: ToolRegistry, taskID: String, eventID: String
) async throws {
  _ = try await rcall(registry, "create_task", ["title": .string("Prep"), "original_id": .string(taskID)])
  _ = try await rcall(
    registry, "create_calendar_event",
    ["title": .string("Review"), "start_date": .string("2026-06-20"),
     "all_day": .bool(true), "original_id": .string(eventID)])
}

/// The number of canonical-link `ai_changelog` rows and the edge's current
/// `version`, read together so idempotency checks can compare across a re-link.
private func linkAuditCountAndVersion(
  _ service: SwiftLorvexCoreService, taskID: String, eventID: String
) throws -> (audits: Int, version: String?) {
  try service.read { db in
    let audits =
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE summary LIKE 'Linked task%'") ?? 0
    let version = try String.fetchOne(
      db,
      sql:
        "SELECT version FROM task_calendar_event_links WHERE task_id = ? AND calendar_event_id = ?",
      arguments: [taskID, eventID])
    return (audits, version)
  }
}

/// Coverage for the id/key-preserving re-create surface that makes an exported
/// Lorvex dataset restorable through domain tools alone (the AI-migration
/// enabler): `original_id` on the create tools (B1), the canonical
/// `link_task_to_event` link tool (B2), historical timestamps + status at
/// create (B3), and per-item batch failure collection (B4).
@Suite("MCP re-create (id/key-preserving restore) tools")
struct MCPRecreateToolsTests {

  // MARK: B1 — original_id preserves the caller-supplied id on create

  @Test("create_task original_id restores the task at the caller's id, in the given list")
  func createTaskPreservesOriginalIDAndList() async throws {
    let registry = try mcpInMemoryRegistry()
    let listID = rid()
    let taskID = rid()
    _ = try await rcall(registry, "create_list", ["name": .string("Projects"), "original_id": .string(listID)])
    let result = try await rcall(
      registry, "create_task",
      ["title": .string("Restored"), "original_id": .string(taskID), "list_id": .string(listID)])
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["id"]?.stringValue == taskID)
    #expect(result.structuredContent?.objectValue?["list_id"]?.stringValue == listID)
    // The preserved id is immediately addressable.
    let fetched = try await rcall(registry, "get_task", ["id": .string(taskID)])
    #expect(fetched.structuredContent?.objectValue?["id"]?.stringValue == taskID)
  }

  @Test("create_task original_id restores a depends_on cross-reference without an old→new id map")
  func createTaskOriginalIDRestoresDependencyEdge() async throws {
    let registry = try mcpInMemoryRegistry()
    let blockerID = rid()
    let dependentID = rid()
    _ = try await rcall(registry, "create_task", ["title": .string("Blocker"), "original_id": .string(blockerID)])
    let dependent = try await rcall(
      registry, "create_task",
      ["title": .string("Blocked"), "original_id": .string(dependentID),
       "depends_on": .array([.string(blockerID)])])
    #expect(dependent.isError != true)
    #expect(dependent.structuredContent?.objectValue?["id"]?.stringValue == dependentID)
    let deps = dependent.structuredContent?.objectValue?["depends_on"]?.arrayValue?
      .compactMap(\.stringValue)
    #expect(deps == [blockerID])
  }

  @Test("create_list / create_habit / create_calendar_event honor original_id")
  func createDomainEntitiesPreserveOriginalID() async throws {
    let registry = try mcpInMemoryRegistry()
    let listID = rid()
    let habitID = rid()
    let eventID = rid()
    let list = try await rcall(
      registry, "create_list", ["name": .string("Home"), "original_id": .string(listID)])
    #expect(list.structuredContent?.objectValue?["id"]?.stringValue == listID)

    let habit = try await rcall(
      registry, "create_habit",
      ["name": .string("Read"), "original_id": .string(habitID),
       "frequency_type": .string("daily")])
    #expect(habit.structuredContent?.objectValue?["id"]?.stringValue == habitID)

    let event = try await rcall(
      registry, "create_calendar_event",
      ["title": .string("Standup"), "start_date": .string("2026-06-15"),
       "all_day": .bool(true), "original_id": .string(eventID)])
    #expect(event.structuredContent?.objectValue?["id"]?.stringValue == eventID)
  }

  @Test("create_habit original_id lets exported completion history re-attach to the habit")
  func createHabitOriginalIDReattachesCompletion() async throws {
    let registry = try mcpInMemoryRegistry()
    let habitID = rid()
    _ = try await rcall(
      registry, "create_habit",
      ["name": .string("Water"), "original_id": .string(habitID),
       "frequency_type": .string("daily")])
    // A completion keyed by the preserved id lands on the restored habit.
    let completed = try await rcall(
      registry, "complete_habit",
      ["id": .string(habitID), "date": .string("2026-06-15")])
    #expect(completed.isError != true)
  }

  // MARK: B2 — canonical link_task_to_event

  @Test("link_task_to_event creates the canonical synced task↔event edge")
  func linkTaskToEventCreatesCanonicalEdge() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let taskID = rid()
    let eventID = rid()
    _ = try await rcall(registry, "create_task", ["title": .string("Prep"), "original_id": .string(taskID)])
    _ = try await rcall(
      registry, "create_calendar_event",
      ["title": .string("Review"), "start_date": .string("2026-06-20"),
       "all_day": .bool(true), "original_id": .string(eventID)])

    let result = try await rcall(
      registry, "link_task_to_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["linked"]?.boolValue == true)
    #expect(result.structuredContent?.objectValue?["task_id"]?.stringValue == taskID)
    #expect(result.structuredContent?.objectValue?["calendar_event_id"]?.stringValue == eventID)

    // The canonical link lands in `task_calendar_event_links` (the synced,
    // exportable table) — verified through the export surface, since the
    // get_linked_* read tools only surface device-local provider links.
    let links = try await service.loadTaskCalendarEventLinksForDataExport()
    #expect(links.contains { $0.taskID == taskID && $0.calendarEventID == eventID })

    // Re-linking the same pair is a no-op (idempotent upsert), not a duplicate.
    _ = try await rcall(
      registry, "link_task_to_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])
    let after = try await service.loadTaskCalendarEventLinksForDataExport()
    #expect(after.filter { $0.taskID == taskID && $0.calendarEventID == eventID }.count == 1)
  }

  @Test("link_task_to_event validates required ids")
  func linkTaskToEventRejectsMissingIds() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await rcall(registry, "link_task_to_event", ["task_id": .string("t")])
    expectMCPStructuredError(result, code: "validation", tool: "link_task_to_event")
  }

  /// A live assistant `link_task_to_event` records `assistant` provenance, not
  /// the `import` the shared id-preserving importer would otherwise stamp — the
  /// MCP host binds `assistant` for the tool call and the importer inherits it.
  @Test("link_task_to_event records assistant provenance, not import")
  func linkTaskToEventRecordsAssistantProvenance() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let taskID = rid()
    let eventID = rid()
    try await seedLinkableTaskAndEvent(registry, taskID: taskID, eventID: eventID)
    _ = try await rcall(
      registry, "link_task_to_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])

    let initiatedBy = try service.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? AND summary LIKE 'Linked task%' ORDER BY timestamp DESC",
        arguments: [taskID])
    }
    #expect(initiatedBy == "assistant")
  }

  /// Re-linking an already-linked pair is a true no-op (the catalog contract):
  /// it writes no second `ai_changelog` row and bumps no version — so it
  /// enqueues nothing to sync. Only the genuine first link is recorded.
  @Test("link_task_to_event re-link is a true no-op: no second changelog, no version bump")
  func linkTaskToEventIdempotentReLinkSyncsNothing() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let taskID = rid()
    let eventID = rid()
    try await seedLinkableTaskAndEvent(registry, taskID: taskID, eventID: eventID)

    _ = try await rcall(
      registry, "link_task_to_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])
    let (audits1, version1) = try linkAuditCountAndVersion(service, taskID: taskID, eventID: eventID)
    #expect(audits1 == 1)
    #expect(version1 != nil)

    let result = try await rcall(
      registry, "link_task_to_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])
    #expect(result.isError != true)
    let (audits2, version2) = try linkAuditCountAndVersion(service, taskID: taskID, eventID: eventID)
    #expect(audits2 == 1)
    #expect(version2 == version1)
  }

  // MARK: B2b — canonical unlink_task_from_event

  @Test("unlink_task_from_event removes the canonical edge, syncs the delete, and returns a rich result")
  func unlinkTaskFromEventRemovesCanonicalEdge() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let taskID = rid()
    let eventID = rid()
    try await seedLinkableTaskAndEvent(registry, taskID: taskID, eventID: eventID)
    _ = try await rcall(
      registry, "link_task_to_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])

    let result = try await rcall(
      registry, "unlink_task_from_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])
    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    #expect(object?["deleted"]?.boolValue == true)
    #expect(object?["task_id"]?.stringValue == taskID)
    #expect(object?["calendar_event_id"]?.stringValue == eventID)

    // The canonical edge is gone from the synced/exportable table.
    let links = try await service.loadTaskCalendarEventLinksForDataExport()
    #expect(!links.contains { $0.taskID == taskID && $0.calendarEventID == eventID })

    // The removal propagates as a synced Delete tombstone (coalesced onto the
    // edge's outbox row — `entity_type` is the singular kind string, not the
    // table name) and records exactly one delete changelog row.
    let (tombstones, deleteAudits) = try service.read { db -> (Int, Int) in
      let t =
        try Int.fetchOne(
          db,
          sql:
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ? AND operation = ?",
          arguments: ["task_calendar_event_link", "\(taskID):\(eventID)", "delete"]) ?? 0
      let a =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE entity_id = ? AND operation = ?",
          arguments: [taskID, "delete"]) ?? 0
      return (t, a)
    }
    #expect(tombstones == 1)
    #expect(deleteAudits == 1)
  }

  @Test("unlink_task_from_event no-ops honestly on a pair that was never linked")
  func unlinkTaskFromEventNoOpOnMissingLink() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let taskID = rid()
    let eventID = rid()
    try await seedLinkableTaskAndEvent(registry, taskID: taskID, eventID: eventID)

    let changelogBefore = try service.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
    }
    let result = try await rcall(
      registry, "unlink_task_from_event",
      ["task_id": .string(taskID), "event_id": .string(eventID)])
    #expect(result.isError != true)
    #expect(result.structuredContent?.objectValue?["deleted"]?.boolValue == false)

    let (deleteAudits, changelogAfter) = try service.read { db -> (Int, Int) in
      let a =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE operation = ?", arguments: ["delete"])
        ?? 0
      let c = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      return (a, c)
    }
    #expect(deleteAudits == 0)
    #expect(changelogAfter == changelogBefore)
  }

  @Test("unlink_task_from_event validates required ids")
  func unlinkTaskFromEventRejectsMissingIds() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await rcall(registry, "unlink_task_from_event", ["task_id": .string("t")])
    expectMCPStructuredError(result, code: "validation", tool: "unlink_task_from_event")
  }

  // MARK: B3 — historical timestamps + status at create

  @Test("create_task with original_id + status/created_at/completed_at restores terminal state and chronology")
  func createTaskRestoresStatusAndTimestamps() async throws {
    let registry = try mcpInMemoryRegistry()
    let taskID = rid()
    let created = "2024-03-01T08:00:00.000Z"
    let completed = "2024-03-02T09:30:00.000Z"
    let result = try await rcall(
      registry, "create_task",
      ["title": .string("Done last year"), "original_id": .string(taskID),
       "status": .string("completed"), "created_at": .string(created),
       "completed_at": .string(completed)])
    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    #expect(object?["id"]?.stringValue == taskID)
    #expect(object?["status"]?.stringValue == "completed")
    #expect(object?["created_at"]?.stringValue == created)
    #expect(object?["completed_at"]?.stringValue == completed)
  }

  @Test("create_task status=cancelled re-creates an already-cancelled task")
  func createTaskCancelledStatus() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await rcall(
      registry, "create_task",
      ["title": .string("Abandoned"), "original_id": .string(rid()),
       "status": .string("cancelled")])
    #expect(result.structuredContent?.objectValue?["status"]?.stringValue == "cancelled")
  }

  @Test("create_task rejects an unknown status rather than coercing to open")
  func createTaskRejectsUnknownStatus() async throws {
    let registry = try mcpInMemoryRegistry()
    let result = try await rcall(
      registry, "create_task",
      ["title": .string("Bad status"), "status": .string("archived")])
    #expect(result.isError == true)
    #expect(result.structuredContent?.objectValue?["code"]?.stringValue == "validation")
  }

  // MARK: B4 — structured per-item batch failure

  @Test("batch_create_tasks collects per-item failures and creates the valid rows")
  func batchCreateTasksPartialFailure() async throws {
    let registry = try mcpInMemoryRegistry()
    let okID = rid()
    let tasks: Value = .array([
      .object(["title": .string("Valid one"), "original_id": .string(okID)]),
      .object(["title": .string("")]),  // empty title → skipped
      .object(["title": .string("Bad list"), "list_id": .string("does-not-exist")]),  // create throws → skipped
    ])
    let result = try await rcall(registry, "batch_create_tasks", ["tasks": tasks])
    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    #expect(object?["count"]?.intValue == 1)
    #expect(object?["results"]?.arrayValue?.count == 1)
    let skipped = object?["skipped"]?.arrayValue
    #expect(skipped?.count == 2)
    // Each skip carries {id, reason}.
    for entry in skipped ?? [] {
      #expect(entry.objectValue?["id"]?.stringValue != nil)
      #expect(entry.objectValue?["reason"]?.stringValue?.isEmpty == false)
    }
    // The valid row still landed at its preserved id.
    let fetched = try await rcall(registry, "get_task", ["id": .string(okID)])
    #expect(fetched.structuredContent?.objectValue?["id"]?.stringValue == okID)
  }

  @Test("batch_create_calendar_events collects per-item failures and creates the valid rows")
  func batchCreateCalendarEventsPartialFailure() async throws {
    let registry = try mcpInMemoryRegistry()
    let events: Value = .array([
      .object(["title": .string("Good"), "start_date": .string("2026-06-15"), "all_day": .bool(true)]),
      .object(["start_date": .string("2026-06-16")]),  // missing title → skipped
    ])
    let result = try await rcall(registry, "batch_create_calendar_events", ["events": events])
    #expect(result.isError != true)
    let object = result.structuredContent?.objectValue
    #expect(object?["count"]?.intValue == 1)
    #expect(object?["results"]?.arrayValue?.count == 1)
    #expect(object?["skipped"]?.arrayValue?.count == 1)
    #expect(object?["skipped"]?.arrayValue?.first?.objectValue?["id"]?.stringValue != nil)
    #expect(object?["skipped"]?.arrayValue?.first?.objectValue?["reason"]?.stringValue?.isEmpty == false)
  }

  // MARK: Fix 2 — original_id validation + non-destructive collision

  @Test("create_* reject a non-canonical original_id (a ':' breaks composite-edge sync)")
  func createRejectsMalformedOriginalID() async throws {
    let registry = try mcpInMemoryRegistry()
    func code(_ r: CallTool.Result) -> String? {
      r.structuredContent?.objectValue?["code"]?.stringValue
    }
    // A ':' in the id would break CompositeEdge.splitCompositeEdgeId (which needs
    // exactly one ':') once the row becomes half of a tag/dependency/link edge.
    let colon = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa:tag"
    let task = try await rcall(
      registry, "create_task", ["title": .string("T"), "original_id": .string(colon)])
    #expect(task.isError == true)
    #expect(code(task) == "validation")
    let list = try await rcall(
      registry, "create_list", ["name": .string("L"), "original_id": .string(colon)])
    #expect(list.isError == true)
    #expect(code(list) == "validation")
    let habit = try await rcall(
      registry, "create_habit",
      ["name": .string("H"), "frequency_type": .string("daily"), "original_id": .string(colon)])
    #expect(habit.isError == true)
    #expect(code(habit) == "validation")
    let event = try await rcall(
      registry, "create_calendar_event",
      ["title": .string("E"), "start_date": .string("2026-06-15"), "all_day": .bool(true),
       "original_id": .string(colon)])
    #expect(event.isError == true)
    #expect(code(event) == "validation")
    // A non-UUID with no colon is also refused — the id must be the canonical shape.
    let bad = try await rcall(
      registry, "create_task", ["title": .string("T"), "original_id": .string("not-a-uuid")])
    #expect(bad.isError == true)
    #expect(code(bad) == "validation")
  }

  @Test("a valid original_id restores tag edges that apply cleanly on a peer")
  func validOriginalIDEdgesApplyOnPeer() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let taskID = rid()
    let created = try await rcall(
      registry, "create_task",
      ["title": .string("Tagged"), "original_id": .string(taskID),
       "tags": .array([.string("work")])])
    #expect(created.isError != true)

    // Ship service A's outbound to a fresh peer B and apply it. The task_tag edge
    // id is `taskID:tagID`, which splits cleanly on apply only because the ids are
    // colon-free canonical UUIDs — the exact property Fix 2 enforces at create.
    let peer = try SwiftLorvexCoreService.inMemory()
    let envelopes = try service.pendingOutbound().map(\.envelope)
    _ = try peer.applyInbound(envelopes, undecodable: 0)
    let peerTask = try await peer.loadTask(id: taskID)
    #expect(peerTask.tags.contains("work"))
  }

  @Test("create with a colliding original_id is a non-destructive skip, not an overwrite")
  func createCollidingOriginalIDSkips() async throws {
    let registry = try mcpInMemoryRegistry()
    let listID = rid()
    _ = try await rcall(
      registry, "create_list", ["name": .string("Original"), "original_id": .string(listID)])
    // A second create at the same id returns the EXISTING list untouched instead of
    // overwriting its name (the shared non-destructive contract).
    let again = try await rcall(
      registry, "create_list",
      ["name": .string("Stale overwrite"), "original_id": .string(listID)])
    #expect(again.isError != true)
    #expect(again.structuredContent?.objectValue?["id"]?.stringValue == listID)
    // Name is prompt-injection fenced in the response; assert the preserved value,
    // not the stale one, survives.
    let name = again.structuredContent?.objectValue?["name"]?.stringValue ?? ""
    #expect(name.contains("Original"))
    #expect(!name.contains("Stale overwrite"))
  }

  @Test("original_id never resurrects a deleted task, list, habit, or calendar event")
  func originalIDRefusesTombstonedEntities() async throws {
    let (registry, service) = try mcpInMemoryRegistryWithService()
    let taskID = rid()
    let listID = rid()
    let habitID = rid()
    let eventID = rid()

    _ = try await rcall(
      registry, "create_task", ["title": .string("Task"), "original_id": .string(taskID)])
    _ = try await rcall(
      registry, "create_list", ["name": .string("List"), "original_id": .string(listID)])
    _ = try await rcall(
      registry, "create_habit",
      ["name": .string("Habit"), "frequency_type": .string("daily"),
       "original_id": .string(habitID)])
    _ = try await rcall(
      registry, "create_calendar_event",
      ["title": .string("Event"), "start_date": .string("2026-06-15"),
       "all_day": .bool(true), "original_id": .string(eventID)])

    _ = try await service.archiveTask(id: taskID)
    try await service.deleteTask(id: taskID)
    try await service.deleteList(id: listID)
    _ = try await service.deleteHabit(id: habitID)
    try await service.deleteCalendarEvent(id: eventID)

    let task = try await rcall(
      registry, "create_task", ["title": .string("Stale"), "original_id": .string(taskID)])
    let list = try await rcall(
      registry, "create_list", ["name": .string("Stale"), "original_id": .string(listID)])
    let habit = try await rcall(
      registry, "create_habit",
      ["name": .string("Stale"), "frequency_type": .string("daily"),
       "original_id": .string(habitID)])
    let event = try await rcall(
      registry, "create_calendar_event",
      ["title": .string("Stale"), "start_date": .string("2026-06-15"),
       "all_day": .bool(true), "original_id": .string(eventID)])

    expectMCPStructuredError(task, code: "conflict", tool: "create_task")
    expectMCPStructuredError(list, code: "conflict", tool: "create_list")
    expectMCPStructuredError(habit, code: "conflict", tool: "create_habit")
    expectMCPStructuredError(event, code: "conflict", tool: "create_calendar_event")
  }

  @Test("create_task original_id preserves in_progress state")
  func createTaskOriginalIDPreservesInProgress() async throws {
    let registry = try mcpInMemoryRegistry()
    let task = try await rcall(
      registry, "create_task",
      ["title": .string("Under way"), "status": .string("in_progress"),
       "original_id": .string(rid())])
    #expect(task.isError != true)
    #expect(task.structuredContent?.objectValue?["status"]?.stringValue == "in_progress")
  }
}
