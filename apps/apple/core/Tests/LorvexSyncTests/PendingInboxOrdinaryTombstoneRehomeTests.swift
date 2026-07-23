import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// DEFECT 1 regression: a parked `.task` whose `list_id` points at a list that
/// later gets an ordinary tombstone must be re-homed to inbox on drain, NOT
/// discarded. `ApplyFk.checkFkDependencies` / `ApplyTask.resolveListId` treat a
/// deleted-list tombstone as a satisfied FK (re-home to inbox), so the two
/// arrival orders (delete-before-upsert vs upsert-parked-then-delete) must
/// converge. The pre-fix drain blind-discarded the parked task on the tombstone,
/// silently losing it on whichever peer parked the task first.
final class PendingInboxOrdinaryTombstoneRehomeTests: XCTestCase {
  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private let listL = "01966a3f-7c8b-7d4e-8f3a-00000000e001"
  private let taskT = "01966a3f-7c8b-7d4e-8f3a-00000000e002"

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

  private func ordinaryListTombstone(_ db: Database) throws {
    try Tombstone.createTombstone(
      db, entityType: EntityName.list, entityId: listL,
      version: "1711234567891_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-01-01T09:00:01.000Z")
  }

  private func taskListId(_ db: Database) throws -> String? {
    try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [taskT])
  }

  /// Arrival order A (the DEFECT 1 fix): the task is PARKED first (list L absent),
  /// then an ordinary tombstone for L arrives; the drain must re-home it, not
  /// discard it.
  func testDrainReHomesParkedTaskOnOrdinaryListTombstone() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let env = self.taskEnvelope(listId: self.listL)
      // Park it: the list is missing, so the apply defers on the FK.
      let deferred = try Apply.applyEnvelope(db, registry: self.registry, envelope: env)
      guard case .deferred = deferred else {
        return XCTFail("expected the task to defer on the missing list, got \(deferred)")
      }
      try PendingInboxDrain.enqueueDeferred(
        db, envelope: env, reason: .missingDependency(entityType: .list, entityId: self.listL))

      // The ordinary list-delete lands.
      try self.ordinaryListTombstone(db)

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)

      XCTAssertEqual(
        summary.discarded, 0, "the task must NOT be discarded on an ordinary list tombstone")
      XCTAssertEqual(summary.replayed, 1, "the task is applied (re-homed to inbox)")
      XCTAssertEqual(try self.taskListId(db), "inbox", "the task is re-homed to inbox")
    }
  }

  /// Arrival order B (already correct via the direct apply path): the tombstone
  /// exists BEFORE the task applies; it re-homes directly. Asserts the two orders
  /// converge to the same state.
  func testDirectApplyReHomesTaskOnOrdinaryListTombstone() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try self.ordinaryListTombstone(db)
      let result = try Apply.applyEnvelope(
        db, registry: self.registry, envelope: self.taskEnvelope(listId: self.listL))
      guard case .applied = result else {
        return XCTFail("expected the task to apply (re-home), got \(result)")
      }
      XCTAssertEqual(try self.taskListId(db), "inbox", "the task is re-homed to inbox")
    }
  }

  /// Guard: an EDGE-style child (task_reminder) whose FK parent (a task) is
  /// ordinarily tombstoned can never resolve — the parent is permanently
  /// gone — so it is still discarded, not resurrected into an infinite re-park.
  func testDrainStillDiscardsChildWhoseParentIsPermanentlyTombstoned() throws {
    let store = try SyncTestSupport.freshStore()
    let missingTask = "01966a3f-7c8b-7d4e-8f3a-00000000e003"
    try store.writer.write { db in
      let env = try SyncTestSupport.completeEnvelope(
        entityType: .taskReminder, entityId: "01966a3f-7c8b-7d4e-8f3a-00000000e004",
        operation: .upsert,
        version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: 1,
        payload: """
          {"task_id":"\(missingTask)","reminder_at":"2026-01-01T09:00:00Z",\
          "created_at":"2026-01-01T09:00:00Z"}
          """,
        deviceId: "device-001")
      try PendingInboxDrain.enqueueDeferred(
        db, envelope: env, reason: .missingDependency(entityType: .task, entityId: missingTask))
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: missingTask,
        version: "1711234567891_0000_a1b2c3d4a1b2c3d4", deletedAt: "2026-01-01T09:00:01.000Z")

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)

      XCTAssertEqual(summary.discarded, 1, "a child whose parent is permanently gone is discarded")
      XCTAssertEqual(try PendingInbox.countPending(db), 0)
    }
  }
}
