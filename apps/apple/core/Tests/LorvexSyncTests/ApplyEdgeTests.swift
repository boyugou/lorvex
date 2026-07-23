import GRDB
import LorvexDomain
import LorvexWorkflow
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity `#[test]` cases for the composite-edge appliers (Rust
/// `edge/tests.rs`): task_tag insert / LWW-skip / delete, and the full
/// task_dependency surface — upsert insert, delete, and the cycle-break
/// tiebreak (higher-HLC incoming wins, oldest-HLC incoming loses, transitive
/// eviction, self-dependency rejection, conflict-log loser-HLC attribution, and
/// insert-order-independent loser election).
final class ApplyEdgeTests: XCTestCase {

  private let vOld = "1711234567000_0000_dec0000100000001"
  private let vMid = "1711234568000_0000_dec0000100000001"
  private let vNew = "1711234569000_0000_dec0000100000001"
  private let zeroVersion = "0000000000000_0000_0000000000000000"
  private let task1 = "01970000-0000-7000-8000-000000000001"
  private let task2 = "01970000-0000-7000-8000-000000000002"
  private let task3 = "01970000-0000-7000-8000-000000000003"
  private let task4 = "01970000-0000-7000-8000-000000000004"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func insertTask(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: "INSERT INTO tasks (id, title, status, version, created_at, updated_at) VALUES (?, 'T', 'open', ?, '', '')",
      arguments: [id, zeroVersion])
  }

  private func insertTag(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: "INSERT INTO tags (id, display_name, lookup_key, color, version, created_at, updated_at) VALUES (?, 'Tag', ?, NULL, ?, '', '')",
      arguments: [id, id, zeroVersion])
  }

  private func taskTagPayload(_ createdAt: String) -> String { "{\"created_at\":\"\(createdAt)\"}" }

  private func countTaskTags(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM task_tags") ?? -1
  }

  private func countTaskDependencies(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM task_dependencies") ?? -1
  }

  private func taskTagVersion(_ db: Database, _ taskId: String, _ tagId: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT version FROM task_tags WHERE task_id = ? AND tag_id = ?",
      arguments: [taskId, tagId])
  }

  // MARK: - task_tag

  func testTaskTagUpsertInsertsNewEdge() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try self.insertTag(db, "tag-1")
      try ApplyEdge.applyTaskTagUpsert(
        db, entityId: "task-1:tag-1", payload: self.taskTagPayload("2026-01-01T00:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countTaskTags(db), 1)
      XCTAssertEqual(try self.taskTagVersion(db, "task-1", "tag-1"), self.vMid)
    }
  }

  func testTaskTagUpsertSkipsOlderVersion() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try self.insertTag(db, "tag-1")
      try ApplyEdge.applyTaskTagUpsert(
        db, entityId: "task-1:tag-1", payload: self.taskTagPayload("2026-01-01T00:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual)
      try ApplyEdge.applyTaskTagUpsert(
        db, entityId: "task-1:tag-1", payload: self.taskTagPayload("2025-12-01T00:00:00Z"),
        version: self.vOld, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countTaskTags(db), 1)
      XCTAssertEqual(try self.taskTagVersion(db, "task-1", "tag-1"), self.vNew)
    }
  }

  func testTaskTagDeleteRemovesEdge() throws {
    try withDB { db in
      try self.insertTask(db, "task-1")
      try self.insertTag(db, "tag-1")
      try ApplyEdge.applyTaskTagUpsert(
        db, entityId: "task-1:tag-1", payload: self.taskTagPayload("2026-01-01T00:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.countTaskTags(db), 1)
      try ApplyEdge.applyTaskTagDelete(db, entityId: "task-1:tag-1", version: self.vNew)
      XCTAssertEqual(try self.countTaskTags(db), 0)
    }
  }

  // MARK: - task_dependency

  private func depPayload(_ createdAt: String) -> String { "{\"created_at\":\"\(createdAt)\"}" }

  private func depEdges(_ db: Database) throws -> [String] {
    try Row.fetchAll(
      db,
      sql:
        "SELECT task_id, depends_on_task_id FROM task_dependencies ORDER BY task_id, depends_on_task_id"
    ).map { "\($0[0] as String):\($0[1] as String)" }
  }

  private func depTombstoneCount(_ db: Database, _ edgeId: String) throws -> Int64 {
    try Int64.fetchOne(
      db,
      sql:
        "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'task_dependency' AND entity_id = ?",
      arguments: [edgeId]) ?? -1
  }

  func testTaskDependencyUpsertInsertsEdge() throws {
    try withDB { db in
      try self.insertTask(db, self.task1)
      try self.insertTask(db, self.task2)
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-01T00:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual, applyTs: "")
      XCTAssertEqual(try self.countTaskDependencies(db), 1)
    }
  }

  func testTaskDependencyDeleteRemovesEdge() throws {
    try withDB { db in
      try self.insertTask(db, self.task1)
      try self.insertTask(db, self.task2)
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-01T00:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual, applyTs: "")
      XCTAssertEqual(try self.countTaskDependencies(db), 1)
      try ApplyEdge.applyTaskDependencyDelete(
        db, entityId: "\(self.task1):\(self.task2)", version: self.vNew)
      XCTAssertEqual(try self.countTaskDependencies(db), 0)
    }
  }

  func testTaskDependencyUpsertBreaksCycleWhenIncomingHasHigherHlc() throws {
    try withDB { db in
      try self.insertTask(db, self.task1)
      try self.insertTask(db, self.task2)
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-01T00:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual, applyTs: "")
      XCTAssertEqual(try self.countTaskDependencies(db), 1)
      // Incoming reverse edge with newer HLC: cycle would close, but it wins —
      // local forward edge deleted + tombstoned, reverse edge inserted.
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task2):\(self.task1)",
        payload: self.depPayload("2026-01-02T00:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual, applyTs: "")
      XCTAssertEqual(try self.depEdges(db), ["\(self.task2):\(self.task1)"])
      XCTAssertEqual(try self.depTombstoneCount(db, "\(self.task1):\(self.task2)"), 1)
    }
  }

  func testCycleBreakRollsBackWhenLoserDeleteCannotEnterOutbox() throws {
    try withDB { db in
      try self.insertTask(db, self.task1)
      try self.insertTask(db, self.task2)
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-01T00:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual, applyTs: "seed")

      // A cycle-break is not locally complete until its loser Delete is queued
      // for CloudKit. Force that final write to fail and prove the enclosing
      // savepoint retains the old graph without a device-local-only tombstone.
      try db.execute(
        sql: """
          CREATE TEMP TRIGGER fail_cycle_break_outbox
          BEFORE INSERT ON sync_outbox
          WHEN NEW.entity_type = 'task_dependency'
          BEGIN
            SELECT RAISE(ABORT, 'forced cycle-break outbox failure');
          END
          """)
      XCTAssertThrowsError(
        try ApplyEdge.applyTaskDependencyUpsert(
          db, entityId: "\(self.task2):\(self.task1)",
          payload: self.depPayload("2026-01-02T00:00:00Z"),
          version: self.vNew, tieBreak: .rejectEqual, applyTs: "incoming"))
      try db.execute(sql: "DROP TRIGGER fail_cycle_break_outbox")

      XCTAssertEqual(try self.depEdges(db), ["\(self.task1):\(self.task2)"])
      XCTAssertEqual(try self.depTombstoneCount(db, "\(self.task1):\(self.task2)"), 0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = 'task_dependency' AND entity_id = ?
            """,
          arguments: ["\(self.task1):\(self.task2)"]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_conflict_log
            WHERE entity_type = 'task_dependency' AND entity_id = ?
            """,
          arguments: ["\(self.task1):\(self.task2)"]),
        0)
    }
  }

  func testTaskDependencyUpsertRejectsIncomingWhenItsHlcIsOldest() throws {
    try withDB { db in
      try self.insertTask(db, self.task1)
      try self.insertTask(db, self.task2)
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-01T00:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual, applyTs: "")
      // Incoming reverse edge at older HLC: incoming loses.
      XCTAssertThrowsError(
        try ApplyEdge.applyTaskDependencyUpsert(
          db, entityId: "\(self.task2):\(self.task1)",
          payload: self.depPayload("2026-01-02T00:00:00Z"),
          version: self.vOld, tieBreak: .rejectEqual, applyTs: "")
      ) { error in
        // A1: a lost cycle-break is a drop-and-continue convergence outcome, not
        // a batch-fatal .store error — so an inbound batch must not abort on it.
        guard case ApplyError.dependencyCycleRejected = error else {
          return XCTFail("expected dependencyCycleRejected, got \(error)")
        }
      }
      XCTAssertEqual(try self.countTaskDependencies(db), 1)
      XCTAssertEqual(try self.depEdges(db), ["\(self.task1):\(self.task2)"])
    }
  }

  func testTaskDependencyUpsertBreaksTransitiveCycleByEvictingOldest() throws {
    try withDB { db in
      for id in [self.task1, self.task2, self.task3] { try self.insertTask(db, id) }
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-01T00:00:00Z"),
        version: self.vOld, tieBreak: .rejectEqual, applyTs: "")
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task2):\(self.task3)",
        payload: self.depPayload("2026-01-02T00:00:00Z"),
        version: self.vMid, tieBreak: .rejectEqual, applyTs: "")
      // task-3 → task-1 at V_NEW closes a transitive cycle; oldest edge
      // (task-1 → task-2 at V_OLD) is evicted, incoming lands.
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task3):\(self.task1)",
        payload: self.depPayload("2026-01-03T00:00:00Z"),
        version: self.vNew, tieBreak: .rejectEqual, applyTs: "")
      XCTAssertEqual(
        try self.depEdges(db), ["\(self.task2):\(self.task3)", "\(self.task3):\(self.task1)"])
      XCTAssertEqual(try self.depTombstoneCount(db, "\(self.task1):\(self.task2)"), 1)
    }
  }

  /// One incoming edge can close SEVERAL edge-disjoint cycles at once — one per
  /// existing path from its dependsOn back to its task. A single eviction round
  /// removes only that round's SCC-minimum edge; the applier must break and
  /// re-check until no cycle remains, or the DAG invariant collapses with a
  /// live cycle left in the store.
  func testTaskDependencyUpsertBreaksEveryDisjointCycleTheIncomingEdgeCloses() throws {
    let vMid2 = "1711234568500_0000_dec0000100000001"
    try withDB { db in
      for id in [self.task1, self.task2, self.task3, self.task4] {
        try self.insertTask(db, id)
      }
      // Acyclic base: b→c (oldest), c→a, b→d, d→a. Incoming a→b closes BOTH
      // a→b→c→a and a→b→d→a.
      for (edge, version) in [
        ("\(self.task2):\(self.task3)", self.vOld),
        ("\(self.task3):\(self.task1)", self.vMid),
        ("\(self.task2):\(self.task4)", vMid2),
        ("\(self.task4):\(self.task1)", self.vNew),
      ] {
        try ApplyEdge.applyTaskDependencyUpsert(
          db, entityId: edge, payload: self.depPayload("2026-01-01T00:00:00Z"),
          version: version, tieBreak: .rejectEqual, applyTs: "")
      }
      let incoming = "1711234570000_0000_dec0000100000001"
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-02T00:00:00Z"),
        version: incoming, tieBreak: .rejectEqual, applyTs: "")

      // Round 1 evicts the SCC-global minimum (b→c @ vOld); round 2 re-checks,
      // finds the second cycle still closed, and evicts its minimum (b→d @
      // vMid2). The surviving set is acyclic.
      XCTAssertEqual(
        try self.depEdges(db),
        [
          "\(self.task1):\(self.task2)", "\(self.task3):\(self.task1)",
          "\(self.task4):\(self.task1)",
        ])
      XCTAssertEqual(try self.depTombstoneCount(db, "\(self.task2):\(self.task3)"), 1)
      XCTAssertEqual(try self.depTombstoneCount(db, "\(self.task2):\(self.task4)"), 1)
      for task in [self.task1, self.task2, self.task3, self.task4] {
        XCTAssertNil(
          try DependencyValidation.findCyclePath(
            db, targetId: TaskId(trusted: task), startId: TaskId(trusted: task)),
          "no live cycle may remain through \(task)")
      }
    }
  }

  func testTaskDependencyUpsertRejectsSelfDependency() throws {
    try withDB { db in
      try self.insertTask(db, self.task1)
      XCTAssertThrowsError(
        try ApplyEdge.applyTaskDependencyUpsert(
          db, entityId: "\(self.task1):\(self.task1)",
          payload: self.depPayload("2026-01-01T00:00:00Z"),
          version: self.vMid, tieBreak: .rejectEqual, applyTs: "")
      ) { error in
        guard case ApplyError.dependencyCycleRejected = error else {
          return XCTFail("expected dependencyCycleRejected, got \(error)")
        }
      }
    }
  }

  func testCycleBreakLogsLoserHlcAndDeviceSuffix() throws {
    let localVersion = "1711234560000_0000_dec01ca1dec01ca1"
    let incomingVersion = "1711234569999_0000_de007e1ede007e1e"
    try withDB { db in
      try self.insertTask(db, self.task1)
      try self.insertTask(db, self.task2)
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task1):\(self.task2)",
        payload: self.depPayload("2026-01-01T00:00:00Z"),
        version: localVersion, tieBreak: .rejectEqual, applyTs: "ts-local")
      try ApplyEdge.applyTaskDependencyUpsert(
        db, entityId: "\(self.task2):\(self.task1)",
        payload: self.depPayload("2026-01-02T00:00:00Z"),
        version: incomingVersion, tieBreak: .rejectEqual, applyTs: "ts-incoming")

      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT entity_id, winner_version, loser_version, loser_device_id, resolved_at
          FROM sync_conflict_log
          WHERE entity_type = 'task_dependency' AND resolution_type = 'cycle_break'
          """)
      let unwrapped = try XCTUnwrap(row, "cycle-break must record a conflict_log row")
      XCTAssertEqual(unwrapped["entity_id"] as String, "\(self.task1):\(self.task2)")
      XCTAssertEqual(unwrapped["winner_version"] as String, incomingVersion)
      XCTAssertEqual(unwrapped["loser_version"] as String, localVersion)
      let expectedSuffix = try Hlc.parse(localVersion).deviceSuffix
      XCTAssertEqual(unwrapped["loser_device_id"] as String, expectedSuffix)
      XCTAssertEqual(unwrapped["resolved_at"] as String, "ts-incoming")
    }
  }

  func testCycleBreakLoserIsDeterministicAcrossInsertOrders() throws {
    let vT2T3 = "1711234561000_0000_aabbccddaabbccdd"  // oldest forward edge
    let vT3T1 = "1711234562000_0000_aabbccddaabbccdd"
    let vClose = "1711234569999_0000_eeff0011eeff0011"

    func run(_ insertOrder: [(String, String, String)], closing: (String, String, String)) throws
      -> [String]
    {
      let store = try SyncTestSupport.freshStore()
      return try store.writer.write { db in
        for id in [self.task1, self.task2, self.task3] { try self.insertTask(db, id) }
        for (from, to, version) in insertOrder {
          try ApplyEdge.applyTaskDependencyUpsert(
            db, entityId: "\(from):\(to)", payload: self.depPayload("2026-01-01T00:00:00Z"),
            version: version, tieBreak: .rejectEqual, applyTs: "ts-seed")
        }
        // Closing edge fires the cycle-break helper (may throw if incoming loses;
        // ignore — we assert on the resulting edge set).
        _ = try? ApplyEdge.applyTaskDependencyUpsert(
          db, entityId: "\(closing.0):\(closing.1)",
          payload: self.depPayload("2026-01-02T00:00:00Z"), version: closing.2,
          tieBreak: .rejectEqual, applyTs: "ts-incoming")
        return try self.depEdges(db)
      }
    }

    let edgesA = try run(
      [(self.task2, self.task3, vT2T3), (self.task3, self.task1, vT3T1)],
      closing: (self.task1, self.task2, vClose))
    let edgesB = try run(
      [(self.task3, self.task1, vT3T1), (self.task2, self.task3, vT2T3)],
      closing: (self.task1, self.task2, vClose))
    XCTAssertEqual(
      edgesA, edgesB,
      "cycle-break loser must be deterministic across insert orders")
    XCTAssertFalse(
      edgesA.contains("\(self.task2):\(self.task3)"),
      "global-MIN(version) edge t2→t3 must be the elected loser")
  }
}
