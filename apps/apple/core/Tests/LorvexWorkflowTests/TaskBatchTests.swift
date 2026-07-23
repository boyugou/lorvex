import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// Parity-implied regression tests for the multi-row task batch
/// surfaces:
///
/// - ``TaskBatchCreate/batchCreateTasks`` — pre-flight guards (empty,
///   cap, id list shape), aggregated sync effects across rows,
///   pre-completed row routing through the completion lifecycle,
///   cross-row dependency edge resolution in the two-pass loop.
/// - ``TaskBatchCancel/batchCancelTasksInList`` — list-not-found,
///   empty-candidates short-circuit, candidate cap, default status
///   filter, external-dependent filtering (cancelled siblings are not
///   "external"), cancel cascade.
/// - ``TaskBatchUpdate/batchUpdateTasks`` — pre-flight guards
///   (empty, cap, duplicate id, malformed id), per-row patch
///   dispatched through the shared single-row apply, deferred
///   dependency-cycle revalidation against the final edge state.
///
/// Per-row error handling is fail-fast across all three — the first
/// throw aborts the batch and unwinds the surrounding transaction.
final class TaskBatchTests: XCTestCase {

  // MARK: - test helpers

  private final class MonotonicHlc: HlcStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt64 = 1
    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      let value = counter
      counter &+= 1
      return try! Hlc(
        physicalMs: 1_700_000_000_000,
        counter: UInt32(value & 0xFFFFFFFF),
        deviceSuffix: "a0a0a0a0a0a0a0a0")
    }
  }

  private func makeSession() -> HlcSession { HlcSession(handle: MonotonicHlc()) }

  private func freshStore() throws -> LorvexStore {
    let s = try WorkflowTestSupport.freshStore()
    try s.writer.write { db in
      try db.execute(
        sql:
          "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES ('inbox', 'Inbox', '0000000000000_0000_0000000000000aaa', "
          + "        '2026-04-01T00:00:00Z', '2026-04-01T00:00:00Z')")
    }
    return s
  }

  private func seedTask(
    _ store: LorvexStore, hlc: HlcSession, title: String,
    completed: Bool = false, dependsOn: [String] = []
  ) throws -> String {
    try store.writer.write { db in
      var input = TaskCreateInput(title: title, dependsOn: dependsOn.isEmpty ? nil : dependsOn)
      if completed { input.completed = true }
      let result = try TaskCreate.createTask(
        db, hlc: hlc,
        input: CreateTaskInput(task: input))
      return result.taskId.asString
    }
  }

  // MARK: - batch_create: guards

  func testBatchCreateRejectsEmptyInput() throws {
    let store = try freshStore()
    let session = makeSession()
    XCTAssertThrowsError(
      try store.writer.write { db in
        _ = try TaskBatchCreate.batchCreateTasks(
          db, hlc: session,
          input: BatchCreateTasksInput(tasks: []))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(m, "tasks must contain at least one item")
    }
  }

  func testBatchCreateRejectsOverCap() throws {
    let store = try freshStore()
    let session = makeSession()
    let many = Array(repeating: TaskCreateInput(title: "T"), count: 501)
    XCTAssertThrowsError(
      try store.writer.write { db in
        _ = try TaskBatchCreate.batchCreateTasks(
          db, hlc: session,
          input: BatchCreateTasksInput(tasks: many))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.contains("at most 500"), m)
    }
  }

  func testBatchCreateRejectsIdLengthMismatch() throws {
    let store = try freshStore()
    let session = makeSession()
    XCTAssertThrowsError(
      try store.writer.write { db in
        _ = try TaskBatchCreate.batchCreateTasks(
          db, hlc: session,
          input: BatchCreateTasksInput(
            ids: ["01966a3f-7c8b-7d4e-8f3a-000000000001"],
            tasks: [TaskCreateInput(title: "A"), TaskCreateInput(title: "B")]))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.contains("expected 2 pre-generated ids"), m)
    }
  }

  func testBatchCreateRejectsDuplicateIds() throws {
    let store = try freshStore()
    let session = makeSession()
    let dup = "01966a3f-7c8b-7d4e-8f3a-000000000001"
    XCTAssertThrowsError(
      try store.writer.write { db in
        _ = try TaskBatchCreate.batchCreateTasks(
          db, hlc: session,
          input: BatchCreateTasksInput(
            ids: [dup, dup],
            tasks: [TaskCreateInput(title: "A"), TaskCreateInput(title: "B")]))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.contains("duplicate id"), m)
    }
  }

  // MARK: - batch_create: happy path

  func testBatchCreateAggregatesSyncEffectsAndSummary() throws {
    let store = try freshStore()
    let session = makeSession()
    let result = try store.writer.write { db in
      try TaskBatchCreate.batchCreateTasks(
        db, hlc: session,
        input: BatchCreateTasksInput(
          tasks: [
            TaskCreateInput(title: "Alpha", tags: ["x"]),
            TaskCreateInput(title: "Beta"),
            TaskCreateInput(title: "Gamma"),
          ]))
    }
    XCTAssertEqual(result.createdIds.count, 3)
    XCTAssertEqual(result.syncEffects.taskUpsertIds.count, 3)
    XCTAssertEqual(result.syncEffects.taskUpsertIds, result.createdIds)
    XCTAssertEqual(result.syncEffects.tagUpsertIds.count, 1)
    XCTAssertEqual(result.syncEffects.taskTagEdgeUpsertIds.count, 1)
    XCTAssertTrue(result.summary.hasPrefix("Created 3 tasks:"))
    XCTAssertTrue(result.summary.contains("'Alpha'"))
    XCTAssertTrue(result.summary.contains("'Beta'"))
    XCTAssertTrue(result.summary.contains("'Gamma'"))
  }

  func testBatchCreateSingularSummary() throws {
    let store = try freshStore()
    let session = makeSession()
    let result = try store.writer.write { db in
      try TaskBatchCreate.batchCreateTasks(
        db, hlc: session,
        input: BatchCreateTasksInput(
          tasks: [TaskCreateInput(title: "Solo")]))
    }
    XCTAssertEqual(result.summary, "Created 1 task: 'Solo'")
  }

  func testBatchCreateRespectsIntraBatchDependencies() throws {
    // depends_on references a sibling in the same batch — the
    // two-pass loop (rows first, edges after) must let this resolve.
    let store = try freshStore()
    let session = makeSession()
    let firstId = "01966a3f-7c8b-7d4e-8f3a-aaaaaaaaaaaa"
    let secondId = "01966a3f-7c8b-7d4e-8f3a-bbbbbbbbbbbb"
    let result = try store.writer.write { db in
      try TaskBatchCreate.batchCreateTasks(
        db, hlc: session,
        input: BatchCreateTasksInput(
          ids: [firstId, secondId],
          tasks: [
            TaskCreateInput(title: "Parent"),
            TaskCreateInput(title: "Child", dependsOn: [firstId]),
          ]))
    }
    XCTAssertEqual(result.syncEffects.dependencyEdgeUpsertIds,
      ["\(secondId):\(firstId)"])
  }

  func testBatchCreatePreCompletedRoutesThroughCompletionLifecycle() throws {
    let store = try freshStore()
    let session = makeSession()
    var preCompleted = TaskCreateInput(title: "Done at intake")
    preCompleted.completed = true
    let result = try store.writer.write { db in
      try TaskBatchCreate.batchCreateTasks(
        db, hlc: session,
        input: BatchCreateTasksInput(tasks: [preCompleted]))
    }
    // No recurrence — no successor — but completion lifecycle still
    // ran (no spawn means cancelledReminderIds may be empty, but the
    // surface still produced exactly one task upsert).
    XCTAssertEqual(result.createdIds.count, 1)
    XCTAssertEqual(result.syncEffects.taskUpsertIds.count, 1)
    XCTAssertTrue(result.syncEffects.spawnedSuccessors.isEmpty)
  }

  // MARK: - batch_cancel: guards / short-circuits

  func testBatchCancelRejectsUnknownList() throws {
    let store = try freshStore()
    let session = makeSession()
    XCTAssertThrowsError(
      try store.writer.write { db in
        _ = try TaskBatchCancel.batchCancelTasksInList(
          db, hlc: session,
          input: BatchCancelInListInput(
            listId: ListId(trusted: "does-not-exist")))
      }
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.contains("does not exist"), m)
    }
  }

  func testBatchCancelEmptyCandidatesShortCircuits() throws {
    let store = try freshStore()
    let session = makeSession()
    let result = try store.writer.write { db in
      try TaskBatchCancel.batchCancelTasksInList(
        db, hlc: session,
        input: BatchCancelInListInput(listId: ListId(trusted: "inbox")))
    }
    XCTAssertTrue(result.taskIds.isEmpty)
    XCTAssertNil(result.summary)
    if case .object(let obj) = result.payload,
      case .int(let n) = obj["cancelled_count"] ?? .null
    {
      XCTAssertEqual(n, 0)
    } else {
      XCTFail("expected cancelled_count")
    }
  }

  func testBatchCancelCancelsCandidatesAndSummarizes() throws {
    let store = try freshStore()
    let session = makeSession()
    let a = try seedTask(store, hlc: session, title: "Alpha")
    let b = try seedTask(store, hlc: session, title: "Beta")
    let _ = try seedTask(store, hlc: session, title: "Done", completed: true)

    let result = try store.writer.write { db in
      try TaskBatchCancel.batchCancelTasksInList(
        db, hlc: session,
        input: BatchCancelInListInput(listId: ListId(trusted: "inbox")))
    }
    XCTAssertEqual(Set(result.taskIds.map { $0.asString }), Set([a, b]))
    XCTAssertEqual(result.syncEffects.taskUpsertIds.count, 2)
    XCTAssertTrue(result.syncEffects.affectedDependentIds.isEmpty)
    XCTAssertNotNil(result.summary)
    XCTAssertTrue(result.summary!.hasPrefix("Cancelled 2 tasks in"), result.summary!)
  }

  func testBatchCancelFiltersExternalDependentsAgainstInListSet() throws {
    // a depends on b; both cancelled together in the same batch.
    // The cancel of b would normally bubble up `a` as an "affected
    // dependent", but since `a` is also being cancelled here it must
    // NOT appear in affected_dependent_ids.
    let store = try freshStore()
    let session = makeSession()
    let b = try seedTask(store, hlc: session, title: "Parent")
    let a = try seedTask(store, hlc: session, title: "Child", dependsOn: [b])
    let result = try store.writer.write { db in
      try TaskBatchCancel.batchCancelTasksInList(
        db, hlc: session,
        input: BatchCancelInListInput(listId: ListId(trusted: "inbox")))
    }
    XCTAssertEqual(Set(result.taskIds.map { $0.asString }), Set([a, b]))
    XCTAssertFalse(
      result.syncEffects.affectedDependentIds.contains(a),
      "in-list dependent must not surface as external")
    XCTAssertFalse(
      result.syncEffects.affectedDependentIds.contains(b),
      "in-list dependent must not surface as external")
  }

  // MARK: - batch_update: guards

  func testBatchUpdateRejectsEmptyInput() throws {
    let store = try freshStore()
    let session = makeSession()
    XCTAssertThrowsError(
      try TaskBatchUpdate.batchUpdateTasks(
        store.writer, hlc: session,
        input: BatchUpdateTasksInput(updates: []))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertEqual(m, "updates must contain at least one item")
    }
  }

  func testBatchUpdateRejectsOverCap() throws {
    let store = try freshStore()
    let session = makeSession()
    let many = (0..<501).map { i in
      TaskUpdateInput(id: String(format: "01966a3f-7c8b-7d4e-8f3a-%012x", i))
    }
    XCTAssertThrowsError(
      try TaskBatchUpdate.batchUpdateTasks(
        store.writer, hlc: session,
        input: BatchUpdateTasksInput(updates: many))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.contains("at most 500"), m)
    }
  }

  func testBatchUpdateRejectsDuplicateIds() throws {
    let store = try freshStore()
    let session = makeSession()
    let dup = "01966a3f-7c8b-7d4e-8f3a-000000000001"
    XCTAssertThrowsError(
      try TaskBatchUpdate.batchUpdateTasks(
        store.writer, hlc: session,
        input: BatchUpdateTasksInput(updates: [
          TaskUpdateInput(id: dup),
          TaskUpdateInput(id: dup),
        ]))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation, got \(e)"); return
      }
      XCTAssertTrue(m.contains("duplicate id"), m)
    }
  }

  func testBatchUpdateRejectsMalformedId() throws {
    let store = try freshStore()
    let session = makeSession()
    XCTAssertThrowsError(
      try TaskBatchUpdate.batchUpdateTasks(
        store.writer, hlc: session,
        input: BatchUpdateTasksInput(updates: [
          TaskUpdateInput(id: "not-a-uuid")
        ]))
    ) { e in
      guard case StoreError.validation = e else {
        XCTFail("expected validation, got \(e)"); return
      }
    }
  }

  // MARK: - batch_update: happy path

  func testBatchUpdateAppliesPerRowPatches() throws {
    let store = try freshStore()
    let session = makeSession()
    let a = try seedTask(store, hlc: session, title: "Alpha")
    let b = try seedTask(store, hlc: session, title: "Beta")
    let result = try TaskBatchUpdate.batchUpdateTasks(
      store.writer, hlc: session,
      input: BatchUpdateTasksInput(updates: [
        TaskUpdateInput(id: a, title: .set("Alpha v2")),
        TaskUpdateInput(id: b, priority: .set(2)),
      ]))
    XCTAssertEqual(result.updatedIds, [a, b])
    XCTAssertEqual(result.syncEffects.taskUpsertIds.count, 2)
    XCTAssertEqual(
      result.summary,
      "Updated 2 tasks: 'Alpha v2', 'Beta'")
  }

  func testBatchUpdateRevalidatesDependencyCyclesAtEnd() throws {
    // Build a -> b (a depends on b). Then attempt a batch that
    // makes b depend on a (creating a cycle). The cross-row cycle
    // re-validation runs once at the end and must throw.
    let store = try freshStore()
    let session = makeSession()
    let b = try seedTask(store, hlc: session, title: "Parent")
    let a = try seedTask(store, hlc: session, title: "Child", dependsOn: [b])
    XCTAssertThrowsError(
      try TaskBatchUpdate.batchUpdateTasks(
        store.writer, hlc: session,
        input: BatchUpdateTasksInput(updates: [
          TaskUpdateInput(id: b, dependsOn: [a])
        ]))
    ) { e in
      guard case StoreError.validation(let m) = e else {
        XCTFail("expected validation cycle error, got \(e)"); return
      }
      XCTAssertTrue(
        m.contains("batch_update_tasks") || m.contains("cycle")
          || m.contains("dependency"),
        m)
    }
  }
}
