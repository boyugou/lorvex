import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Wiring coverage for ``SyncRetention``: the best-effort post-apply GC sweep and
/// the apply-independent maintenance sweep. Tombstone permanence is pinned here at
/// the sweep level — ``SyncRetention/runPostApplyGC(_:syncedAt:)`` never reaps
/// a tombstone (the death-ledger is permanent) while it still prunes every other
/// bookkeeping table.
final class SyncRetentionTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  func testSyncOffOutboxCapArmsRecoverableFullReseed() throws {
    try withDB { db in
      for i in 0..<3 {
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(
          db,
          envelope(
            entityId: String(format: "01966a3f-7c8b-7d4e-8f3a-0000000099%02d", i),
            version: "171123456789\(i)_0000_a1b2c3d4a1b2c3d4",
            deviceId: "device-A"))
      }

      XCTAssertEqual(
        try SyncRetention.gcActiveOutboxAndFlagReseed(
          db, maxRows: 2, syncedAt: "2026-04-01T00:00:00.000Z"),
        1)
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey),
        "true")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = ?",
          arguments: [ResolutionName.reseedRequired]),
        1)
    }
  }

  private func envelope(
    entityId: String, version: String, deviceId: String, operation: SyncOperation = .upsert
  ) -> SyncEnvelope {
    SyncEnvelope(
      entityType: .task,
      entityId: entityId,
      operation: operation,
      version: try! Hlc.parse(version),
      payloadSchemaVersion: 1,
      payload: #"{"title":"test"}"#,
      deviceId: deviceId)
  }

  // MARK: - Anti-resurrection

  /// The ordinary death ledger and permanent alias ledger both survive GC.
  func testGcRetainsEntityRedirectAndPlainTombstone() throws {
    try withDB { db in
      // Deleted past the full-resync horizon, at a low version — the configuration
      // a version-domain reap would have collected.
      let recentDelete = try String.fetchOne(
        db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-120 days')")!
      let lowVersion = "1000000000000_0000_a1b2c3d4a1b2c3d4"
      let loser = "ffffffff-ffff-7fff-8fff-ffffffffffff"
      let winner = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: loser, targetId: winner,
        version: lowVersion, createdAt: recentDelete)
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-plain",
        version: lowVersion, deletedAt: recentDelete)

      XCTAssertEqual(try Tombstone.gcTombstonesWatermark(db), 0)
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-plain"),
        "ordinary maintenance cannot reclaim a plain tombstone")
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.tag, entityId: loser),
        "the merge loser's ordinary death barrier survives")
      XCTAssertNotNil(
        try EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: loser),
        "the independent permanent alias survives")
    }
  }

  // MARK: - Post-apply GC sweep

  /// The post-apply sweep reaps synced outbox rows past the retention window but
  /// keeps unsynced rows.
  func testPostApplyGcReapsSyncedOutboxKeepsUnsynced() throws {
    try withDB { db in
      let syncedId = "01966a3f-7c8b-7d4e-8f3a-000000000001"
      let unsyncedId = "01966a3f-7c8b-7d4e-8f3a-000000000002"
      let synced = envelope(
        entityId: syncedId, version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deviceId: "device-A")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, synced)
      let syncedRowId = try Outbox.getPending(db).first { $0.envelope.entityId == syncedId }!.id
      try Outbox.markManySynced(db, outboxIds: [syncedRowId], syncedAt: "2020-01-01T00:00:00.000Z")

      let unsynced = envelope(
        entityId: unsyncedId, version: "1711234567891_0000_a1b2c3d4a1b2c3d4", deviceId: "device-A")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, unsynced)

      SyncRetention.runPostApplyGC(db, syncedAt: "2026-04-01T00:00:00.000Z")

      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?", arguments: [syncedId]),
        0, "synced outbox row past the window must be reaped")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?", arguments: [unsyncedId]),
        1, "unsynced outbox row must be retained")
    }
  }

  /// The post-apply sweep also reaps pending-inbox orphans whose FK parent never
  /// arrived within the full-resync horizon, and keeps recent ones — the GC was
  /// previously defined and unit-tested but never wired into the sweep.
  func testPostApplyGcReapsExpiredPendingInbox() throws {
    try withDB { db in
      func seedPending(entityId: String, firstAttemptedAt: String) throws {
        try db.execute(
          sql: """
            INSERT INTO sync_pending_inbox
              (envelope, reason, missing_entity_type, missing_entity_id,
               envelope_entity_type, envelope_entity_id, envelope_version,
               first_attempted_at, last_attempted_at, attempt_count)
            VALUES (?, 'fk_unresolved', 'task', ?, 'task_reminder', ?,
                    '1711234567890_0000_a1b2c3d4a1b2c3d4', ?, ?, 1)
            """,
          arguments: [
            "{\"entity_id\":\"\(entityId)\"}", entityId, entityId,
            firstAttemptedAt, firstAttemptedAt,
          ])
      }
      try seedPending(entityId: "orphan-old", firstAttemptedAt: "2020-01-01T00:00:00.000Z")
      let recent = try String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")!
      try seedPending(entityId: "orphan-recent", firstAttemptedAt: recent)

      SyncRetention.runPostApplyGC(db, syncedAt: "2026-04-01T00:00:00.000Z")

      XCTAssertEqual(
        try PendingInbox.countPending(db), UInt64(1),
        "expired orphan reaped, recent kept")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_id = ?",
          arguments: ["orphan-old"]),
        0, "orphan past the full-resync horizon must be reaped")
    }
  }

  /// The post-apply retention sweep leaves generation-managed tombstones intact
  /// while still pruning the other bookkeeping tables. An ancient tombstone survives
  /// ``SyncRetention/runPostApplyGC(_:syncedAt:)``, while the synced outbox
  /// row, the stale conflict-log row, and the expired pending-inbox orphan are all
  /// reaped as before.
  func testPostApplyGcRetainsTombstoneWhilePruningOtherTables() throws {
    try withDB { db in
      // An ancient (>365 days) plain tombstone.
      let ancient = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-400 days')"))
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "task-permanent",
        version: "1000000000000_0000_a1b2c3d4a1b2c3d4", deletedAt: ancient)

      // A synced outbox row well past the 7-day outbox retention window.
      let syncedId = "01966a3f-7c8b-7d4e-8f3a-0000000055aa"
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db,
        envelope(
          entityId: syncedId, version: "1711234567890_0000_a1b2c3d4a1b2c3d4", deviceId: "device-A"))
      let syncedRowId = try Outbox.getPending(db).first { $0.envelope.entityId == syncedId }!.id
      try Outbox.markManySynced(db, outboxIds: [syncedRowId], syncedAt: "2020-01-01T00:00:00.000Z")

      // A stale conflict-log row past the 30-day conflict retention window.
      try ConflictLog.logConflict(
        db,
        ConflictLog.Entry(
          entityType: "task", entityId: "conflict-old",
          winnerVersion: "9000000000000_0000_a1b2c3d4a1b2c3d4",
          loserVersion: "1000000000000_0000_a1b2c3d4a1b2c3d4", loserDeviceId: "device-B",
          loserPayload: nil, resolvedAt: "2020-01-01T00:00:00.000Z",
          resolutionType: ResolutionName.lww))

      // The list-fallback claim is operational convergence state, not a
      // diagnostic. It must survive the 30-day conflict-log GC indefinitely.
      let claimedTaskId = "claim-task"
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, list_id, version, created_at, updated_at)
          VALUES (?, 'Claim owner', 'inbox',
                  '0000000000000_0000_0000000000000000',
                  '2020-01-01T00:00:00.000Z', '2020-01-01T00:00:00.000Z')
          """, arguments: [claimedTaskId])
      try db.execute(
        sql: """
          INSERT INTO sync_list_fallback_reemit_claims (task_id, payload_list_id)
          VALUES (?, 'absent-list')
          """, arguments: [claimedTaskId])

      // A pending-inbox orphan whose FK parent never arrived within the horizon.
      try db.execute(
        sql: """
          INSERT INTO sync_pending_inbox
            (envelope, reason, missing_entity_type, missing_entity_id,
             envelope_entity_type, envelope_entity_id, envelope_version,
             first_attempted_at, last_attempted_at, attempt_count)
          VALUES (?, 'fk_unresolved', 'task', 'orphan-parent', 'task_reminder', 'orphan-old',
                  '1711234567890_0000_a1b2c3d4a1b2c3d4', '2020-01-01T00:00:00.000Z',
                  '2020-01-01T00:00:00.000Z', 1)
          """,
        arguments: ["{\"entity_id\":\"orphan-old\"}"])

      SyncRetention.runPostApplyGC(db, syncedAt: "2026-04-01T00:00:00.000Z")

      // Generation publication, not ordinary maintenance, owns reclamation.
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: "task-permanent"),
        "the post-apply sweep must not reap a tombstone without generation authority")
      // The other retention steps still prune.
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?", arguments: [syncedId]),
        0, "the synced outbox row past the window is still reaped")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE entity_id = ?",
          arguments: ["conflict-old"]),
        0, "the stale conflict-log row is still reaped")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_list_fallback_reemit_claims WHERE task_id = ?",
          arguments: [claimedTaskId]),
        1, "durable list-fallback claims must survive generic diagnostic retention")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_id = ?",
          arguments: ["orphan-old"]),
        0, "the expired pending-inbox orphan is still reaped")
    }
  }

  // MARK: - Sync-off maintenance sweep (apply-independent)

  /// The apply-independent maintenance sweep enforces the retention caps with NO
  /// `applyInbound`: under a days-retention policy it prunes expired audit rows
  /// and their full-content outbox copies, age-caps `error_logs`, and keeps an
  /// unrelated unsynced row that is within the generous backlog cap.
  func testLocalMaintenanceGcEnforcesCapsWithoutApply() throws {
    try withDB { db in
      try AuditRetentionFrontier.adoptPolicyForCurrentScope(
        db, policy: .days(30),
        policyVersion: "0000000000000_0000_0000000000000000")

      // An old error_logs row (reaped) and a recent one (kept).
      try db.execute(
        sql: """
          INSERT INTO error_logs (id, source, level, message, created_at)
          VALUES ('old', 's', 'warn', 'm', '2020-01-01T00:00:00.000Z')
          """)
      let recent = try String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")!
      try db.execute(
        sql: """
          INSERT INTO error_logs (id, source, level, message, created_at)
          VALUES ('recent', 's', 'warn', 'm', ?)
          """,
        arguments: [recent])

      // Two expired audit rows: one still pending and one already acknowledged.
      // Neither full-content upsert may survive the local prune. In particular,
      // the pending one must not upload if the user enables sync later.
      let pendingAuditId = "01966a3f-7c8b-7d4e-8f3a-0000000044ab"
      let syncedAuditId = "01966a3f-7c8b-7d4e-8f3a-0000000044ac"
      for id in [pendingAuditId, syncedAuditId] {
        try db.execute(
          sql: """
            INSERT INTO ai_changelog
              (id, timestamp, operation, entity_type, summary, initiated_by)
            VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-100 days'),
                    'create', 'task', 'private audit payload', 'ai')
            """,
          arguments: [id])
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(
          db,
          SyncEnvelope(
            entityType: .aiChangelog, entityId: id, operation: .upsert,
            version: try Hlc.parse(
              id == pendingAuditId
                ? "1711234567891_0000_a1b2c3d4a1b2c3d4"
                : "1711234567892_0000_a1b2c3d4a1b2c3d4"),
            payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
            payload: #"{"summary":"private audit payload"}"#, deviceId: "device-A"))
      }
      let syncedAuditOutboxId = try XCTUnwrap(
        Outbox.getPending(db).first { $0.envelope.entityId == syncedAuditId }?.id)
      try Outbox.markManySynced(
        db, outboxIds: [syncedAuditOutboxId], syncedAt: recent)

      // One unsynced outbox row — well within the generous cap.
      let outboxEntityId = "01966a3f-7c8b-7d4e-8f3a-0000000044aa"
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db,
        envelope(
          entityId: outboxEntityId, version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
          deviceId: "device-A"))

      try AuditRetentionFrontier.adoptPolicyForCurrentScope(
        db, policy: .days(30),
        policyVersion: "6000000000000_0000_a1b2c3d4a1b2c3d4")
      SyncRetention.runLocalMaintenanceGC(
        db, syncedAt: "2026-04-01T00:00:00.000Z",
        includeActiveOutboxCap: true)

      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'old'"), 0,
        "an aged error_logs row is reaped by the sweep")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'recent'"), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?",
          arguments: [outboxEntityId]),
        1, "a within-cap unsynced outbox row is retained for a later sign-in")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id IN (?, ?)",
          arguments: [pendingAuditId, syncedAuditId]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id IN (?, ?) AND operation = ?
            """,
          arguments: [
            EntityName.aiChangelog, pendingAuditId, syncedAuditId, SyncNaming.opUpsert,
          ]),
        0, "expired audit content is removed from both pending and synced outbox states")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id IN (?, ?) AND operation = ?
            """,
          arguments: [
            EntityName.aiChangelog, pendingAuditId, syncedAuditId, SyncNaming.opDelete,
          ]),
        0, "retention never creates audit tombstone envelopes")
    }
  }

  /// The post-apply sweep age-trims `error_logs`, and the row cap keeps only the
  /// most-recent rows so a persistent error can't grow the table without limit.
  func testPostApplyGcBoundsErrorLogs() throws {
    try withDB { db in
      func seedLog(id: String, createdAt: String) throws {
        try db.execute(
          sql: """
            INSERT INTO error_logs (id, source, level, message, created_at)
            VALUES (?, 's', 'warn', 'm', ?)
            """,
          arguments: [id, createdAt])
      }
      // Age-trim via the sweep: an old row is reaped, a recent one survives.
      try seedLog(id: "old", createdAt: "2020-01-01T00:00:00.000Z")
      let recent = try String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')")!
      try seedLog(id: "recent", createdAt: recent)
      SyncRetention.runPostApplyGC(db, syncedAt: "2026-04-01T00:00:00.000Z")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'old'"), 0)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM error_logs WHERE id = 'recent'"), 1)

      // Row cap: 4 in-window rows, cap to 2 → the two most-recent survive.
      try db.execute(sql: "DELETE FROM error_logs")
      for i in 1...4 { try seedLog(id: "cap-\(i)", createdAt: "2026-03-0\(i)T00:00:00.000Z") }
      _ = try ErrorLog.gc(db, retentionDays: 3650, maxRows: 2)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM error_logs"), 2)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE id IN ('cap-3','cap-4')"),
        2, "the two most-recent rows survive the cap")
    }
  }
}
