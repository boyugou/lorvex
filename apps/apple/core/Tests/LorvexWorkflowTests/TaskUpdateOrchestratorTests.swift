import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexWorkflow

/// End-to-end regression tests for the single-row `update_task`
/// orchestrator. Ports `task_update/tests.rs` byte-for-byte.
///
/// Targets:
///
/// - #4533: an empty patch must produce zero outbox enqueues.
/// - title-only patch still trips the outbox gate.
/// - #4512: a joint patch carrying BOTH a recurrence change AND a
///   reopen-from-completed applies the new rule to the parent before
///   the lifecycle owner reads it.
/// - #4583 B19: a joint reopen + `Patch.clear` recurrence cancels any
///   previously-spawned successor before wiping the rule.
final class TaskUpdateOrchestratorTests: XCTestCase {

  // MARK: - test helpers

  /// Deterministic HLC handle that emits a fresh, monotonically
  /// advancing stamp on every call. Mirrors the Rust `MonotonicHlc`
  /// fixture — tests don't care about exact stamps, only that
  /// strictly-increasing values flow into LWW writes.
  private final class MonotonicHlc: HlcStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private var counter: UInt64 = 1
    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      let value = counter
      counter &+= 1
      // physicalMs steady, counter advancing — keeps strict order.
      return try! Hlc(
        physicalMs: 1_700_000_000_000, counter: UInt32(value & 0xFFFFFFFF),
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

  /// Insert a minimal `tasks` row with the supplied fields. Mirrors
  /// the Rust `TaskBuilder` slice the orchestrator tests use.
  private func insertTask(
    _ store: LorvexStore,
    id: String,
    title: String = "Untouched",
    status: String = StatusName.open,
    dueDate: String? = nil,
    canonicalOccurrenceDate: String? = nil,
    recurrence: String? = nil,
    recurrenceGroupId: String? = nil,
    completedAt: String? = nil,
    spawnedFrom: String? = nil,
    spawnedFromVersion: String? = nil,
    recurrenceSuccessorId: String? = nil,
    version: String = "0000000000000_0000_0000000000000001"
  ) throws {
    let terminal = status == StatusName.completed || status == StatusName.cancelled
    let rolloverState: String
    if recurrence != nil && terminal {
      rolloverState = recurrenceSuccessorId == nil ? "ended" : "authorized"
    } else {
      rolloverState = "none"
    }
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks
          (id, title, status, list_id, due_date, canonical_occurrence_date,
           recurrence, recurrence_group_id, completed_at, spawned_from,
           spawned_from_version, content_version, schedule_version,
           lifecycle_version, archive_version, recurrence_rollover_state,
           recurrence_successor_id, version, created_at, updated_at, defer_count)
          VALUES (?, ?, ?, 'inbox', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)
          """,
        arguments: [
          id, title, status, dueDate, canonicalOccurrenceDate,
          recurrence, recurrenceGroupId, completedAt, spawnedFrom,
          spawnedFrom == nil ? nil : (spawnedFromVersion ?? version),
          version, version, version, version, rolloverState,
          recurrenceSuccessorId, version,
          "2026-04-01T00:00:00Z", "2026-04-01T00:00:00Z",
        ])
    }
  }

  private func emptyUpdate(_ id: String) -> TaskUpdateInput {
    return TaskUpdateInput(id: id)
  }

  private func deeplyNestedJSON(depth: Int) -> JSONValue {
    var value: JSONValue = .null
    for _ in 0..<depth {
      value = .array([value])
    }
    return value
  }

  // MARK: - empty patch / title-only

  /// An empty patch must not push the row id onto `task_upsert_ids`.
  func testEmptyPatchProducesZeroOutboxEnqueues() throws {
    let store = try freshStore()
    let id = "01966a3f-7c8b-7d4e-8f3a-000000000001"
    try insertTask(store, id: id, title: "Untouched")

    let outcome = try TaskUpdate.updateTask(
      store.writer, hlc: makeSession(),
      input: emptyUpdate(id))

    XCTAssertTrue(
      outcome.syncEffects.taskUpsertIds.isEmpty,
      "empty patch must not push a phantom task_upsert id; "
        + "got \(outcome.syncEffects.taskUpsertIds)")
    XCTAssertTrue(outcome.syncEffects.tagUpsertIds.isEmpty)
    XCTAssertTrue(outcome.syncEffects.dependencyEdgeUpsertIds.isEmpty)
    XCTAssertTrue(outcome.syncEffects.spawnedSuccessors.isEmpty)
    XCTAssertTrue(outcome.syncEffects.cancelledSuccessors.isEmpty)
  }

  /// A trivial title-only patch trips the gate via
  /// `hasPrimaryRowPatch` and pushes one id onto `taskUpsertIds`.
  func testTitleOnlyPatchStillProducesOneOutboxEnqueue() throws {
    let store = try freshStore()
    let id = "01966a3f-7c8b-7d4e-8f3a-000000000002"
    try insertTask(store, id: id, title: "Old Title")

    var patch = emptyUpdate(id)
    patch.title = .set("New Title")

    let outcome = try TaskUpdate.updateTask(
      store.writer, hlc: makeSession(),
      input: patch)
    XCTAssertEqual(
      outcome.syncEffects.taskUpsertIds, [id],
      "title change must enqueue exactly one task_upsert")
  }

  func testRecurrenceUpdateRejectsUncanonicalizableJSONInsteadOfClearing() throws {
    let store = try freshStore()
    let id = "01966a3f-7c8b-7d4e-8f3a-000000000020"
    let originalRecurrence = #"{"FREQ":"DAILY","INTERVAL":1}"#
    try insertTask(
      store, id: id, title: "Recurring", dueDate: "2026-04-01",
      canonicalOccurrenceDate: "2026-04-01", recurrence: originalRecurrence,
      recurrenceGroupId: "grp-validation-regression")

    var patch = emptyUpdate(id)
    patch.recurrence = .set(deeplyNestedJSON(depth: maxJSONDepth + 1))

    XCTAssertThrowsError(
      try TaskUpdate.updateTask(store.writer, hlc: makeSession(), input: patch)
    ) { error in
      guard case StoreError.validation = error else {
        return XCTFail("expected validation error, got \(error)")
      }
    }

    let recurrence = try store.writer.read { db in
      try String.fetchOne(db, sql: "SELECT recurrence FROM tasks WHERE id = ?", arguments: [id])
    }
    XCTAssertEqual(recurrence, originalRecurrence)
  }

  // MARK: - recurrence-vs-status co-application

  /// #4512: a joint patch that BOTH changes the recurrence rule AND
  /// reopens the parent from `completed` applies the recurrence patch
  /// FIRST so the lifecycle owner's reopen pass sees the new rule.
  func testJointReopenPlusRecurrenceChangeAppliesRecurrenceBeforeReopen() throws {
    let store = try freshStore()
    let id = "01966a3f-7c8b-7d4e-8f3a-000000000003"
    try insertTask(
      store, id: id, title: "Recurring parent",
      status: StatusName.completed,
      dueDate: "2026-04-01",
      canonicalOccurrenceDate: "2026-04-01",
      recurrence: #"{"FREQ":"WEEKLY","INTERVAL":1}"#,
      recurrenceGroupId: "grp-parent-rec",
      completedAt: "2026-04-01T08:00:00Z")

    var patch = emptyUpdate(id)
    patch.status = .set("open")
    patch.recurrence = .set(.object(["FREQ": .string("MONTHLY")]))

    let outcome = try TaskUpdate.updateTask(
      store.writer, hlc: makeSession(),
      input: patch)

    // The after-row carries the monthly recurrence.
    let afterRecurrence: String
    if case .object(let obj) = outcome.updatedTask,
      let v = obj["recurrence"], case .string(let s) = v
    {
      afterRecurrence = s
    } else {
      XCTFail("after-task must carry a recurrence string")
      return
    }
    let parsedFreq: String? = parseFreq(afterRecurrence)
    XCTAssertEqual(
      parsedFreq, "MONTHLY",
      "post-patch parent must carry monthly recurrence; got \(afterRecurrence)")

    XCTAssertTrue(
      outcome.syncEffects.taskUpsertIds.contains(id),
      "parent id must reach taskUpsertIds on a recurrence change")

    // Cross-check the DB row directly.
    let stored: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?", arguments: [id])
    }
    XCTAssertNotNil(stored)
    XCTAssertEqual(parseFreq(stored ?? ""), "MONTHLY", "DB row must store the new monthly rule")
  }

  func testJointReopenPlusRecurrenceEnableEndsThenActivatesSeries() throws {
    let store = try freshStore()
    let id = "01966a3f-7c8b-7d4e-8f3a-000000000004"
    try insertTask(
      store, id: id, title: "Completed one-off",
      status: StatusName.completed,
      dueDate: "2026-04-01",
      completedAt: "2026-04-01T08:00:00Z")

    var patch = emptyUpdate(id)
    patch.status = .set(StatusName.open)
    patch.recurrence = .set(.object(["FREQ": .string("DAILY")]))

    _ = try TaskUpdate.updateTask(
      store.writer, hlc: makeSession(), input: patch)

    let row = try store.writer.read { db in
      try Row.fetchOne(
        db,
        sql:
          "SELECT status, recurrence, recurrence_group_id, "
          + "recurrence_rollover_state, recurrence_successor_id "
          + "FROM tasks WHERE id = ?1",
        arguments: [id])
    }
    XCTAssertEqual(row?[0] as String?, StatusName.open)
    XCTAssertNotNil(row?[1] as String?)
    XCTAssertNotNil(row?[2] as String?)
    XCTAssertEqual(row?[3] as String?, "none")
    XCTAssertNil(row?[4] as String?)
  }

  /// #4583 B19: a joint patch that BOTH clears the recurrence
  /// (`Patch.clear`) AND reopens the parent must cancel any
  /// previously-spawned successor BEFORE the recurrence rule is wiped.
  func testJointReopenPlusRecurrenceClearCancelsPreSpawnedSuccessor() throws {
    let store = try freshStore()
    let parentId = "01966a3f-7c8b-7d4e-8f3a-000000000010"
    let groupId = "grp-clear-rec"
    let successorId = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentId, recurrenceGroupId: groupId)
    try insertTask(
      store, id: parentId, title: "Recurring parent",
      status: StatusName.completed,
      dueDate: "2026-04-01",
      canonicalOccurrenceDate: "2026-04-01",
      recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
      recurrenceGroupId: groupId,
      completedAt: "2026-04-01T08:00:00Z",
      recurrenceSuccessorId: successorId)
    try insertTask(
      store, id: successorId, title: "Recurring parent",
      dueDate: "2026-04-02",
      canonicalOccurrenceDate: "2026-04-02",
      recurrence: #"{"FREQ":"DAILY","INTERVAL":1}"#,
      recurrenceGroupId: groupId,
      spawnedFrom: parentId,
      spawnedFromVersion: "0000000000000_0000_0000000000000001",
      version: "0000000000000_0000_0000000000000010")

    var patch = emptyUpdate(parentId)
    patch.status = .set("open")
    patch.recurrence = .clear

    let outcome = try TaskUpdate.updateTask(
      store.writer, hlc: makeSession(),
      input: patch)

    let cancelled = outcome.syncEffects.cancelledSuccessors.map { $0.successorId }
    XCTAssertTrue(
      cancelled.contains(successorId),
      "spawned successor must be cancelled by the reopen pass; got \(cancelled)")

    // The successor's status row flipped to cancelled.
    let succStatus: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT status FROM tasks WHERE id = ?",
        arguments: [successorId])
    }
    XCTAssertEqual(succStatus, StatusName.cancelled)

    // The parent's recurrence is cleared.
    let parentRecurrence: String? = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT recurrence FROM tasks WHERE id = ?",
        arguments: [parentId])
    }
    XCTAssertNil(
      parentRecurrence,
      "parent recurrence must be cleared post-patch; got \(String(describing: parentRecurrence))")
  }

  private func parseFreq(_ json: String) -> String? {
    guard let data = json.data(using: .utf8),
      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let freq = obj["FREQ"] as? String
    else { return nil }
    return freq
  }
}
