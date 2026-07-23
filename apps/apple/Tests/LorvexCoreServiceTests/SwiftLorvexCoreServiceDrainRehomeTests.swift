import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// DEFECT 4 regression: the SA1 list-delete task re-home must PROPAGATE when the
/// list-delete replays via the pending-inbox drain, not just when it flows
/// through the direct `applyInbound` loop.
///
/// The schema trigger `trg_lists_before_delete` re-homes a deleted non-inbox
/// list's tasks to inbox with no version bump and no outbox row. The direct
/// apply loop captures those tasks and re-enqueues them (`ListDeleteRehome`); the
/// drain-replay path used to apply the delete bare, so a deferred list-delete
/// that later replayed re-homed tasks LOCALLY only — peers diverged on those
/// tasks' `list_id`.
final class SwiftLorvexCoreServiceDrainRehomeTests: XCTestCase {

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

  func testDrainReplayedListDeletePropagatesReHome() throws {
    let listL = "01966a3f-7c8b-7d4e-8f3a-00000000f001"
    let taskT = "01966a3f-7c8b-7d4e-8f3a-00000000f002"
    let service = try makeService()

    try service.write { db in
      // A converged non-inbox list L holding task T.
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at)
          VALUES (?, 'L', '0000000000000_0000_0000000000000000',
                  '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
          """,
        arguments: [listL])
      try db.execute(
        sql: """
          INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at,
                             defer_count)
          VALUES (?, ?, 'T', 'open', '0000000000000_0000_0000000000000000',
                  '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 0)
          """,
        arguments: [taskT, listL])

      // Park a list-delete for L in the pending inbox — the state left by a
      // prior deferral (e.g. a schema/invariant hold). Draining it replays the
      // delete; the trigger re-homes T to inbox.
      let listDelete = SyncEnvelope(
        entityType: .list, entityId: listL, operation: .delete,
        version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: #"{"version":"1711234567890_0000_a1b2c3d4a1b2c3d4"}"#,
        deviceId: "device-remote")
      try PendingInboxDrain.enqueuePending(
        db, envelope: listDelete, reason: "list_delete_deferred",
        missingEntityType: nil, missingEntityID: nil)
    }

    // An empty inbound batch still drives the drain, which replays the parked
    // list-delete and (with the fix) propagates the re-home.
    let report = try service.applyInbound([], undecodable: 0)
    XCTAssertGreaterThanOrEqual(report.drainReplayed, 1, "the parked list-delete replayed")

    // Local re-home landed.
    let listId = try service.read { db in
      try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [taskT])
    }
    XCTAssertEqual(listId, "inbox", "T re-homed to inbox locally")

    // The re-home was PROPAGATED: a fresh task upsert (list_id=inbox) is queued
    // and T's row version advanced past its seed version.
    let pending = try service.pendingOutbound()
    let rehomeUpsert = pending.first {
      $0.envelope.entityType == .task && $0.envelope.entityId == taskT
        && $0.envelope.operation == .upsert
    }
    let upsert = try XCTUnwrap(
      rehomeUpsert, "the drain-replayed list-delete must enqueue a re-home upsert for T")
    XCTAssertTrue(
      upsert.envelope.payload.contains("\"list_id\":\"inbox\""),
      "the propagated upsert carries list_id=inbox; got \(upsert.envelope.payload)")

    let version = try service.read { db in
      try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskT])
    }
    XCTAssertNotEqual(
      version, "0000000000000_0000_0000000000000000",
      "the re-home minted a fresh dominating HLC on T")
  }
}
