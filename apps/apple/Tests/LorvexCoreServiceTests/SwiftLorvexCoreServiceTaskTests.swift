import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// End-to-end coverage for the real `LorvexTaskServicing` implementation on
/// `SwiftLorvexCoreService`, exercising the write-side orchestration adapter
/// (HLC minting, immediate transaction, `ai_changelog`, `local_change_seq`) and
/// the `TaskRow`/enriched-JSON → `LorvexTask` mapping against a temp store.
final class SwiftLorvexCoreServiceTaskTests: XCTestCase {

  /// Build a service backed by a fresh temp SQLite file seeded with the
  /// authoritative `schema/schema.sql`.
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    // Use the in-memory store seam: the on-disk `LorvexStore.open` applies the
    // schema inside one transaction, which rejects `schema.sql`'s leading
    // `PRAGMA journal_mode = WAL` (WAL can't be set mid-transaction), so these
    // tests open the schema in memory instead.
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func mutationCounts(_ service: SwiftLorvexCoreService) throws
    -> (outbox: Int64, changelog: Int64)
  {
    try service.read { db in
      let outbox = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? 0
      let changelog = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? 0
      return (outbox, changelog)
    }
  }

  func testCreateTaskWithVisuallyEmptyTitleClassifiesAsEmptyTitle() async throws {
    let service = try makeService()
    do {
      _ = try await service.createTask(title: "   ", notes: "")
      XCTFail("expected an empty-title rejection")
    } catch {
      // The core raises the typed `ValidationError.empty("title")`; the write
      // adapter classifies by that typed case, so the surfaced error is
      // `.emptyTitle` regardless of the underlying message wording.
      guard case LorvexCoreError.emptyTitle = error else {
        XCTFail("expected LorvexCoreError.emptyTitle, got \(error)")
        return
      }
    }
  }

  func testAppendToTaskBodyDoesNotDuplicateExistingBody() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Notes test", notes: "First line.")

    let appended = try await service.appendToTaskBody(
      taskID: task.id, additionalNotes: "Second line.")
    XCTAssertEqual(appended.notes, "First line.\n\nSecond line.")

    // A second append stacks once more — the prior body is never re-appended.
    let again = try await service.appendToTaskBody(
      taskID: task.id, additionalNotes: "Third line.")
    XCTAssertEqual(again.notes, "First line.\n\nSecond line.\n\nThird line.")
  }

  func testRemoveTaskReminderDropsItFromTheTask() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Reminder test", notes: "")
    let withReminder = try await service.addTaskReminder(
      taskID: task.id, reminderAt: "2026-06-22T17:00:00Z")
    XCTAssertEqual(withReminder.reminders.count, 1)
    let reminderID = try XCTUnwrap(withReminder.reminders.first?.id)

    let removed = try await service.removeTaskReminder(taskID: task.id, reminderID: reminderID)
    XCTAssertTrue(removed.reminders.isEmpty, "a removed reminder must not appear on the task")
    let reloaded = try await service.loadTask(id: task.id)
    XCTAssertTrue(reloaded.reminders.isEmpty)
  }

  func testPermanentlyDeleteTaskFoldsInTheArchiveStep() async throws {
    let service = try makeService()

    // The strict `deleteTask` refuses a live (un-archived) task — the two-step
    // guard that stops a single MCP/AI call from destroying live data.
    let strict = try await service.createTask(title: "Strict delete target", notes: "")
    do {
      try await service.deleteTask(id: strict.id)
      XCTFail("deleteTask must refuse an un-archived task")
    } catch {
      // Expected: the task is not archived, so the permanent-delete op rejects it.
    }
    // It survived the refused strict delete.
    _ = try await service.loadTask(id: strict.id)

    // `permanentlyDeleteTask` folds in the archive and removes the row.
    let target = try await service.createTask(title: "Permanent delete target", notes: "")
    try await service.permanentlyDeleteTask(id: target.id)
    do {
      _ = try await service.loadTask(id: target.id)
      XCTFail("permanentlyDeleteTask should have removed the task")
    } catch {
      // Expected: the row is gone.
    }
  }

  func testArchiveTaskUnlocksPermanentDelete() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Archive then delete", notes: "")

    // Strict delete refuses a live task — the two-step guard.
    do {
      try await service.deleteTask(id: task.id)
      XCTFail("deleteTask must refuse an un-archived task")
    } catch {
      // Expected.
    }
    _ = try await service.loadTask(id: task.id)  // survived

    // Archiving moves it to the Trash and returns the task.
    let archived = try await service.archiveTask(id: task.id)
    XCTAssertEqual(archived.id, task.id)

    // Archiving again is rejected — it is already in the Trash.
    do {
      _ = try await service.archiveTask(id: task.id)
      XCTFail("archiving an already-archived task must fail")
    } catch {
      // Expected.
    }

    // With the archive in place the strict delete now removes the row.
    try await service.deleteTask(id: task.id)
    do {
      _ = try await service.loadTask(id: task.id)
      XCTFail("permanent delete should have removed the task")
    } catch {
      // Expected: the row is gone.
    }
  }

  func testUnarchiveTaskRestoresFromTrash() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Archive then restore", notes: "")
    _ = try await service.archiveTask(id: task.id)

    // Restore clears the archive...
    let restored = try await service.unarchiveTask(id: task.id)
    XCTAssertEqual(restored.id, task.id)

    // ...so restoring again is rejected (the task is no longer in the Trash).
    do {
      _ = try await service.unarchiveTask(id: task.id)
      XCTFail("unarchiving a live task must fail")
    } catch {
      // Expected.
    }

    // And the restored task can be archived again — proving the row is live.
    _ = try await service.archiveTask(id: task.id)
  }

  func testSyncStatusReflectsRealOutboxDepth() async throws {
    let service = try makeService()

    // Every write stages a `sync_outbox` row; the diagnostics must count the
    // real backlog rather than the previously-hardcoded 0.
    _ = try await service.createTask(title: "Outbox A", notes: "")
    _ = try await service.createTask(title: "Outbox B", notes: "")

    let status = try await service.loadRuntimeDiagnostics().sync
    XCTAssertGreaterThanOrEqual(
      status.pendingCount, 2,
      "pending sync count must reflect the real outbox depth, not a hardcoded 0")
    XCTAssertNotNil(status.oldestPendingAt)
    XCTAssertNotNil(status.newestPendingAt)
    XCTAssertEqual(status.failedCount, 0)
  }

  func testDeferCompletedTaskDoesNotWriteNoOpChangelog() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Terminal defer no-op", notes: "")
    _ = try await service.completeTask(id: task.id)

    let before = try await service.loadRuntimeDiagnostics().changelog.entries
      .filter { $0.operation == "defer" }.count
    _ = try await service.deferTask(
      id: task.id, until: Date(timeIntervalSince1970: 1_779_494_400), reason: nil)
    let after = try await service.loadRuntimeDiagnostics().changelog.entries
      .filter { $0.operation == "defer" }.count

    XCTAssertEqual(after, before)
  }

  func testBatchDeferChangelogOnlyCountsActuallyDeferredTasks() async throws {
    let service = try makeService()
    let completed = try await service.createTask(title: "Completed batch defer skip", notes: "")
    let open = try await service.createTask(title: "Open batch defer target", notes: "")
    _ = try await service.completeTask(id: completed.id)

    let before = try await service.loadRuntimeDiagnostics().changelog.entries
      .filter { $0.operation == "batch_defer" }.count
    // The diagnostics changelog is an assistant-facing read (`user` rows are
    // filtered out), so drive the batch defer under the assistant binding the
    // MCP host applies for the `batch_defer_tasks` tool.
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.batchDeferTasks(
        ids: [completed.id, open.id],
        until: Date(timeIntervalSince1970: 1_779_494_400),
        reason: nil, note: nil)
    }
    let batchEntries = try await service.loadRuntimeDiagnostics().changelog.entries
      .filter { $0.operation == "batch_defer" }

    XCTAssertEqual(batchEntries.count, before + 1)
    let entry = try XCTUnwrap(batchEntries.first)
    XCTAssertEqual(entry.entityId, open.id)
    XCTAssertTrue(entry.summary.contains("1 task"), "summary was \(entry.summary)")
  }

  /// The free-text defer note (and the structured reason) are captured on the
  /// defer's `ai_changelog` row under the reserved `_defer` object in
  /// `after_json`, and read back through `deferHistory`. Covers the human path
  /// (no bound MCP tool) here; ``testDeferNotePersistedOnAiDeferPath`` covers the
  /// AI path.
  func testDeferNotePersistedToChangelogOnHumanDefer() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Renew passport", notes: "")

    _ = try await service.deferTaskReturningTask(
      id: task.id, until: Date(timeIntervalSince1970: 1_782_000_000),
      reason: "needs_info", note: "  Waiting on the design review  ")

    // The reserved `_defer` object lands in the defer row's after_json…
    let afterJson = try service.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT after_json FROM ai_changelog WHERE entity_id = ? AND operation = 'defer' "
          + "ORDER BY timestamp DESC LIMIT 1",
        arguments: [task.id])
    }
    let unwrapped = try XCTUnwrap(afterJson)
    XCTAssertTrue(unwrapped.contains("\"_defer\""), "after_json was \(unwrapped)")

    // …and reads back (note trimmed, newest-first) through deferHistory.
    let history = try await service.deferHistory(taskID: task.id, limit: 10)
    XCTAssertEqual(history.count, 1)
    let entry = try XCTUnwrap(history.first)
    XCTAssertEqual(entry.note, "Waiting on the design review")
    XCTAssertEqual(entry.structuredReason, "needs_info")
    // The human defer path binds no initiator, so the row reads `user`.
    XCTAssertEqual(entry.initiatedBy, "user")
    XCTAssertFalse(entry.deferredAt.isEmpty)
    // The denormalized coarse enum column still carries the current reason.
    let reloaded = try await service.loadTask(id: task.id)
    XCTAssertEqual(reloaded.lastDeferReason, "needs_info")
  }

  /// Same persistence when the write is attributed to the `defer_task` MCP tool.
  func testDeferNotePersistedOnAiDeferPath() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "AI defer note", notes: "")

    _ = try await SwiftLorvexCoreService.$currentMCPTool.withValue("defer_task") {
      try await service.deferTaskReturningTask(
        id: task.id, until: Date(timeIntervalSince1970: 1_782_000_000),
        reason: nil, note: "Blocked on finance sign-off")
    }

    let history = try await service.deferHistory(taskID: task.id, limit: 10)
    let entry = try XCTUnwrap(history.first)
    XCTAssertEqual(entry.note, "Blocked on finance sign-off")
    XCTAssertNil(entry.structuredReason, "no structured reason was supplied for this defer")

    let mcpTool = try service.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT mcp_tool FROM ai_changelog WHERE entity_id = ? AND operation = 'defer' "
          + "ORDER BY timestamp DESC LIMIT 1",
        arguments: [task.id])
    }
    XCTAssertEqual(mcpTool, "defer_task")
  }

  /// A defer with neither a structured reason nor a free-text note records
  /// nothing extra: no `_defer` object, and the history entry carries nulls.
  func testDeferWithoutNoteRecordsNoDeferDetail() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Plain defer", notes: "")

    _ = try await service.deferTaskReturningTask(
      id: task.id, until: Date(timeIntervalSince1970: 1_782_000_000), reason: nil, note: "   ")

    let afterJson = try service.read { db in
      try String.fetchOne(
        db,
        sql:
          "SELECT after_json FROM ai_changelog WHERE entity_id = ? AND operation = 'defer' "
          + "ORDER BY timestamp DESC LIMIT 1",
        arguments: [task.id])
    }
    XCTAssertFalse(try XCTUnwrap(afterJson).contains("\"_defer\""))

    let history = try await service.deferHistory(taskID: task.id, limit: 10)
    let entry = try XCTUnwrap(history.first)
    XCTAssertNil(entry.note)
    XCTAssertNil(entry.structuredReason)
  }

  /// Multiple defers surface newest-first, and a batch defer of the task is
  /// included (via the `ai_changelog_entities` registry) carrying the reason and
  /// note stamped on the shared batch changelog row.
  func testDeferHistoryNewestFirstIncludesBatch() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Repeatedly deferred", notes: "")

    _ = try await service.deferTaskReturningTask(
      id: task.id, until: Date(timeIntervalSince1970: 1_782_000_000),
      reason: "blocked", note: "first defer")
    _ = try await service.deferTaskReturningTask(
      id: task.id, until: Date(timeIntervalSince1970: 1_782_100_000),
      reason: "low_energy", note: "second defer")
    _ = try await service.batchDeferTasks(
      ids: [task.id], until: Date(timeIntervalSince1970: 1_782_200_000),
      reason: "not_today", note: "batch defer")

    let history = try await service.deferHistory(taskID: task.id, limit: 10)
    XCTAssertEqual(history.count, 3)
    // Newest-first: timestamps are non-increasing down the list. (Exact tie
    // order is left unspecified — same-millisecond rows share a UUIDv7 prefix
    // and break ties on the random id tail, not insertion order.)
    for i in 1..<history.count {
      XCTAssertGreaterThanOrEqual(history[i - 1].deferredAt, history[i].deferredAt)
    }
    // All three defers are captured: the two single-defer detail pairs plus the
    // batch defer, whose reason + note ride the shared batch changelog row and
    // surface for the task via the ai_changelog_entities registry.
    let pairs = Set(history.map { DeferPair(reason: $0.structuredReason, note: $0.note) })
    XCTAssertEqual(
      pairs,
      [
        DeferPair(reason: "blocked", note: "first defer"),
        DeferPair(reason: "low_energy", note: "second defer"),
        DeferPair(reason: "not_today", note: "batch defer"),
      ])
  }

  private struct DeferPair: Hashable {
    let reason: String?
    let note: String?
  }

  func testBatchMoveSkipsStaleLwwNoOpInsteadOfReportingMoved() async throws {
    let service = try makeService()
    let targetList = try await service.createList(name: "Future Move Target", description: nil)
    let task = try await service.createTask(title: "Future-version move no-op", notes: "")
    try service.write { db in
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: ["9999913599999_0000_ffffffffffffffff", task.id])
    }

    let before = try await service.loadRuntimeDiagnostics().changelog.entries
      .filter { $0.operation == "batch_move" }.count
    let moved = try await service.batchMoveTasks(ids: [task.id], toListID: targetList.id)
    let after = try await service.loadRuntimeDiagnostics().changelog.entries
      .filter { $0.operation == "batch_move" }.count

    XCTAssertTrue(moved.moved.isEmpty)
    XCTAssertEqual(moved.skipped, [task.id])
    XCTAssertEqual(after, before)
  }

  func testSetTaskAINotesNoOpDoesNotWriteSyncOrChangelog() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "AI notes no-op", notes: "")
    let written = try await service.setTaskAINotes(taskID: task.id, notes: "Keep this context")
    XCTAssertEqual(written.aiNotes, "Keep this context")
    let before = try mutationCounts(service)

    let unchanged = try await service.setTaskAINotes(taskID: task.id, notes: "  Keep this context  ")
    let after = try mutationCounts(service)

    XCTAssertEqual(unchanged.aiNotes, "Keep this context")
    XCTAssertEqual(after.outbox, before.outbox)
    XCTAssertEqual(after.changelog, before.changelog)
  }

  func testBatchMoveSameListNoOpDoesNotWriteSyncOrChangelog() async throws {
    let service = try makeService()
    let targetList = try await service.createList(name: "No-op move target", description: nil)
    let task = try await service.createTask(title: "Already moved", notes: "")
    let moved = try await service.batchMoveTasks(ids: [task.id], toListID: targetList.id)
    XCTAssertEqual(moved.moved.map(\.id), [task.id])
    let before = try mutationCounts(service)

    let unchanged = try await service.batchMoveTasks(ids: [task.id], toListID: targetList.id)
    let after = try mutationCounts(service)

    XCTAssertTrue(unchanged.moved.isEmpty)
    XCTAssertEqual(unchanged.skipped, [task.id])
    XCTAssertEqual(after.outbox, before.outbox)
    XCTAssertEqual(after.changelog, before.changelog)
  }

  func testRecentLogsMergeFilterAndPaginate() async throws {
    let service = try makeService()
    // Each write lands rows in both ai_changelog and sync_outbox. Recent logs
    // read the ai_changelog source through the assistant-actor filter, so drive
    // the writes under the assistant binding (as the MCP `create_task` tool
    // does) to keep the changelog source populated.
    try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      _ = try await service.createTask(title: "Log source A", notes: "")
      _ = try await service.createTask(title: "Log source B", notes: "")
    }

    // Unfiltered: the merged stream spans both sources and is newest-first.
    let all = try await service.loadRecentLogs(
      limit: 100, offset: 0, since: nil, levels: nil, sources: nil, redact: true)
    XCTAssertFalse(all.entries.isEmpty)
    XCTAssertTrue(all.sourceCounts.keys.contains("ai_changelog"))
    XCTAssertTrue(all.sourceCounts.keys.contains("sync_outbox"))
    let timestamps = all.entries.map { $0.timestamp ?? "" }
    XCTAssertEqual(timestamps, timestamps.sorted(by: >), "stream must be newest-first")

    // Source filter restricts the stream to one source.
    let outboxOnly = try await service.loadRecentLogs(
      limit: 100, offset: 0, since: nil, levels: nil, sources: ["sync_outbox"], redact: true)
    XCTAssertFalse(outboxOnly.entries.isEmpty)
    XCTAssertTrue(outboxOnly.entries.allSatisfy { $0.source == "sync_outbox" })

    // Level filter keeps only matching levels.
    let infoOnly = try await service.loadRecentLogs(
      limit: 100, offset: 0, since: nil, levels: ["info"], sources: nil, redact: true)
    XCTAssertTrue(infoOnly.entries.allSatisfy { $0.level == .info })

    // Pagination: a single-entry page reports the full match count and a next page.
    let firstPage = try await service.loadRecentLogs(
      limit: 1, offset: 0, since: nil, levels: nil, sources: nil, redact: true)
    XCTAssertEqual(firstPage.entries.count, 1)
    XCTAssertGreaterThan(firstPage.totalMatching, 1)
    let secondPage = try await service.loadRecentLogs(
      limit: 1, offset: 1, since: nil, levels: nil, sources: nil, redact: true)
    XCTAssertEqual(secondPage.entries.count, 1)
    XCTAssertNotEqual(firstPage.entries.first?.id, secondPage.entries.first?.id)
  }

  func testCreateReadComplete() async throws {
    let service = try makeService()

    // Create → rich return is the full task, defaulting to P2 / open.
    let created = try await service.createTask(title: "Write the cutover", notes: "Body text")
    XCTAssertFalse(created.id.isEmpty)
    XCTAssertEqual(created.title, "Write the cutover")
    XCTAssertEqual(created.notes, "Body text")
    XCTAssertEqual(created.priority, .p2)
    XCTAssertEqual(created.status, .open)

    // Read-back maps to the same identity + content.
    let loaded = try await service.loadTask(id: created.id)
    XCTAssertEqual(loaded.id, created.id)
    XCTAssertEqual(loaded.title, "Write the cutover")
    XCTAssertEqual(loaded.status, .open)

    // Today reflects the open task.
    let todayBefore = try await service.loadToday()
    XCTAssertTrue(todayBefore.tasks.contains { $0.id == created.id })
    XCTAssertGreaterThan(todayBefore.localChangeSequence, 0)

    // Complete → returns a fresh snapshot; the task is no longer open.
    let snapshot = try await service.completeTask(id: created.id)
    XCTAssertFalse(snapshot.tasks.contains { $0.id == created.id && $0.status == .open })

    // The completed task reads back as completed.
    let afterComplete = try await service.loadTask(id: created.id)
    XCTAssertEqual(afterComplete.status, .completed)
  }

  func testLoadMissingTaskThrowsTaskNotFound() async throws {
    let service = try makeService()
    do {
      _ = try await service.loadTask(id: "does-not-exist")
      XCTFail("Expected taskNotFound")
    } catch let error as LorvexCoreError {
      XCTAssertEqual(error, .taskNotFound)
    }
  }

  func testUpdateTaskRoundTrip() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Original", notes: "")
    let updated = try await service.updateTask(
      id: created.id,
      title: "Renamed",
      notes: "New body",
      priority: .p1,
      estimatedMinutes: 30,
      plannedDate: nil,
      tags: ["alpha", "beta"],
      dependsOn: [])
    XCTAssertEqual(updated.title, "Renamed")
    XCTAssertEqual(updated.notes, "New body")
    XCTAssertEqual(updated.priority, .p1)
    XCTAssertEqual(updated.estimatedMinutes, 30)
    XCTAssertEqual(Set(updated.tags), ["alpha", "beta"])

    let reloaded = try await service.loadTask(id: created.id)
    XCTAssertEqual(reloaded.title, "Renamed")
    XCTAssertEqual(reloaded.priority, .p1)
  }

  func testListTasksReturnsCreatedTask() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Listed task", notes: "")
    let page = try await service.listTasks(
      status: "open", listID: nil, priority: nil, text: nil, limit: 50, offset: 0)
    XCTAssertTrue(page.tasks.contains { $0.id == created.id })
    XCTAssertEqual(page.returned, page.tasks.count)
    XCTAssertGreaterThanOrEqual(page.totalMatching, 1)
  }

  func testChecklistAddSurfacesOnTask() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "With checklist", notes: "")
    let withItem = try await service.addTaskChecklistItem(taskID: created.id, text: "Step one")
    XCTAssertEqual(withItem.checklistItems.count, 1)
    XCTAssertEqual(withItem.checklistItems.first?.text, "Step one")
  }

}
