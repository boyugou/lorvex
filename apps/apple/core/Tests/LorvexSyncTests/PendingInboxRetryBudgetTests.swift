import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// DEFECT 5 regression:
///
/// (a) The pending-inbox retry budget must be consumed on WALL-CLOCK cadence, not
///     per-drain (chunk) cadence. One large initial pull runs the full drain per
///     50-envelope chunk; a set of rows whose FK parent arrives thousands of
///     records later in the SAME sync must not have its 50-attempt budget burned
///     across those chunks and be quarantined mid-sync.
///
/// (b) The full-resync backfill must enqueue rows in topological order (lists
///     before tasks) so a backfill-repopulated zone does not deliver tasks before
///     their list.
final class PendingInboxRetryBudgetTests: XCTestCase {
  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private let listL = "01966a3f-7c8b-7d4e-8f3a-00000000a001"
  private let taskT = "01966a3f-7c8b-7d4e-8f3a-00000000a002"

  private func taskEnvelope(listId: String) -> SyncEnvelope {
    try! SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: taskT, operation: .upsert,
      version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: 1,
      payload: """
        {"list_id":"\(listId)","title":"T","status":"open",\
        "created_at":"2026-01-01T09:00:00.000Z","updated_at":"2026-01-01T09:00:00.000Z",\
        "defer_count":0}
        """,
      deviceId: "device-001")
  }

  /// (a) Many drains in quick succession (a multi-chunk pull) must NOT burn the
  /// retry budget of a legitimately-waiting entry. After far more drains than the
  /// 50-attempt cap, the entry's FK parent finally arrives and it applies — it was
  /// never quarantined.
  func testRapidMultiChunkDrainsDoNotQuarantineWaitingEntry() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let env = self.taskEnvelope(listId: self.listL)
      try PendingInboxDrain.enqueueDeferred(
        db, envelope: env, reason: .missingDependency(entityType: .list, entityId: self.listL))

      // A single large pull runs the drain per chunk — here 60 drains, all within
      // the same wall-clock instant, well past the 50-attempt cap.
      for _ in 0..<60 {
        _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      }

      // Still parked, NOT quarantined, budget not burned.
      XCTAssertEqual(try PendingInbox.countPending(db), 1, "the waiting entry survives the pull")
      XCTAssertFalse(
        try PendingInboxDrain.isQuarantined(
          db, entityType: EntityName.task, entityID: self.taskT,
          version: "1711234567890_0000_a1b2c3d4a1b2c3d4"),
        "the waiting entry was not quarantined mid-sync")
      let attempt = try PendingInbox.getAllPending(db).first?.attemptCount ?? -1
      XCTAssertLessThan(attempt, PendingInbox.maxAttempts, "the retry budget was not burned by chunk count")

      // The FK parent finally arrives (later in the same sync); the entry applies.
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at)
          VALUES (?, 'L', '0000000000000_0000_0000000000000000',
                  '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
          """,
        arguments: [self.listL])
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)

      let applied =
        (try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [self.taskT]) ?? 0) > 0
      XCTAssertTrue(applied, "the legitimately-waiting entry applied once its parent arrived")
    }
  }

  /// (b) The full-resync backfill enqueues lists before tasks.
  func testFullResyncBackfillEnqueuesListsBeforeTasks() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at)
          VALUES (?, 'L', '0000000000000_0000_0000000000000000',
                  '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
          """,
        arguments: [self.listL])
      try db.execute(
        sql: """
          INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at,
                             defer_count)
          VALUES (?, ?, 'T', 'open', '0000000000000_0000_0000000000000000',
                  '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 0)
          """,
        arguments: [self.taskT, self.listL])

      _ = try Outbox.enqueueAllLiveForFullResync(db)

      let kinds = try Outbox.getPending(db).map { $0.envelope.entityType }
      let firstList = kinds.firstIndex(of: .list)
      let firstTask = kinds.firstIndex(of: .task)
      let listIdx = try XCTUnwrap(firstList, "backfill enqueued at least one list")
      let taskIdx = try XCTUnwrap(firstTask, "backfill enqueued the task")
      XCTAssertLessThan(
        listIdx, taskIdx, "lists must be enqueued before tasks (topological order)")
    }
  }
}
