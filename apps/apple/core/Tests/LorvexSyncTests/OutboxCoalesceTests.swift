import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Outbox coalesce coverage — the coalescing, stale-LWW, SAVEPOINT-rollback,
/// and dropped-Delete-audit contract.
final class OutboxCoalesceTests: XCTestCase {

  private func env(
    _ entityType: String, _ entityId: String, _ version: String,
    payload: String = #"{"title":"test"}"#
  ) -> SyncEnvelope {
    try! SyncTestSupport.completeEnvelope(
      entityType: EntityKind.parse(entityType)!, entityId: entityId, operation: .upsert,
      version: try! Hlc.parse(version), payloadSchemaVersion: 1, payload: payload,
      deviceId: "device-001")
  }

  private func deleteEnv(_ entityType: String, _ entityId: String, _ version: String) -> SyncEnvelope {
    try! SyncTestSupport.completeEnvelope(
      entityType: EntityKind.parse(entityType)!, entityId: entityId, operation: .delete,
      version: try! Hlc.parse(version), payloadSchemaVersion: 1, payload: "{}",
      deviceId: "device-001")
  }

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  // MARK: - coalesce

  func testEnqueueCoalescedReplacesExisting() throws {
    try withDB { db in
      let env1 = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      let env2 = env(
        "task", "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567891_0000_a1b2c3d4a1b2c3d4", payload: #"{"title":"updated"}"#)
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env1)
      try Outbox.enqueueCoalesced(db, env2)
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].envelope.version.description, "1711234567891_0000_a1b2c3d4a1b2c3d4")
      XCTAssertEqual(
        JSONValue.parse(pending[0].envelope.payload).flatMap(ApplyJSON.object)?["title"],
        .string("updated"))
    }
  }

  func testEnqueueCoalescedRejectsStaleSnapshot() throws {
    try withDB { db in
      let newer = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567891_0000_a1b2c3d4a1b2c3d4")
      let stale = env(
        "task", "01966a3f-7c8b-7d4e-8f3a-000000002163",
        "1711234567890_0000_a1b2c3d4a1b2c3d4", payload: #"{"title":"stale"}"#)
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, newer)
      try Outbox.enqueueCoalesced(db, stale)
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].envelope.version.description, "1711234567891_0000_a1b2c3d4a1b2c3d4")
      XCTAssertNotEqual(pending[0].envelope.payload, #"{"title":"stale"}"#)
    }
  }

  func testEnqueueCoalescedIdenticalVersionIsNoop() throws {
    try withDB { db in
      let env1 = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      let env2 = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env1)
      try Outbox.enqueueCoalesced(db, env2)
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].envelope.version, env1.version)
    }
  }

  func testEnqueueCoalescedCanonicalReplacesTaintedExisting() throws {
    try withDB { db in
      let now = SyncTimestampFormat.syncTimestampNow()
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_outbox
                (entity_type, entity_id, operation, version,
                 payload_schema_version, payload, device_id, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            "task", "01966a3f-7c8b-7d4e-8f3a-0000000021a3", SyncNaming.opUpsert, "seed", 1,
            #"{"title":"test"}"#, "device-001", now,
          ])
      }
      let canonical = env("task", "01966a3f-7c8b-7d4e-8f3a-0000000021a3", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try Outbox.enqueueCoalesced(db, canonical)
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].envelope.version, canonical.version)
    }
  }

  func testEnqueueCoalescedDoesNotAffectDifferentEntity() throws {
    try withDB { db in
      let env1 = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      let env2 = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002164", "1711234567891_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env1)
      try Outbox.enqueueCoalesced(db, env2)
      XCTAssertEqual(try Outbox.getPending(db).count, 2)
    }
  }

  func testEnqueueCoalescedPreservesSyncedEntries() throws {
    try withDB { db in
      let env1 = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env1)
      let pending = try Outbox.getPending(db)
      try Outbox.markManySynced(db, outboxIds: [pending[0].id], syncedAt: "2026-03-23T12:00:00.000Z")
      let env2 = env("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567891_0000_a1b2c3d4a1b2c3d4")
      try Outbox.enqueueCoalesced(db, env2)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 2)
      let after = try Outbox.getPending(db)
      XCTAssertEqual(after.count, 1)
      XCTAssertEqual(after[0].envelope.version.description, "1711234567891_0000_a1b2c3d4a1b2c3d4")
    }
  }

  // MARK: - hardening

  func testCoalesceUsesTypedHlcCompareForLww() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-000000002186"
      let envNewer = env("task", entityId, "1711234567899_0000_a1b2c3d4a1b2c3d4")
      try Outbox.enqueueCoalesced(db, envNewer)
      let envOlder = env("task", entityId, "1711234567890_0000_ffffffffffffffff")
      try Outbox.enqueueCoalesced(db, envOlder)
      var stored = try String.fetchOne(db, sql: "SELECT version FROM sync_outbox WHERE entity_id = ? AND synced_at IS NULL", arguments: [entityId])
      XCTAssertEqual(stored, "1711234567899_0000_a1b2c3d4a1b2c3d4")
      let envNewest = env("task", entityId, "1711234567999_0000_0000000000000000")
      try Outbox.enqueueCoalesced(db, envNewest)
      stored = try String.fetchOne(db, sql: "SELECT version FROM sync_outbox WHERE entity_id = ? AND synced_at IS NULL", arguments: [entityId])
      XCTAssertEqual(stored, "1711234567999_0000_0000000000000000")
    }
  }

  func testCoalesceSavepointPreservesRacingRowOnUniqueConflict() throws {
    try withDB { db in
      let vOld = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      let vNew = "1711234567999_0000_a1b2c3d4a1b2c3d4"
      let entityId = "01966a3f-7c8b-7d4e-8f3a-000000002185"
      let envOld = env("task", entityId, vOld, payload: #"{"title":"racing"}"#)
      try Outbox.enqueueCoalesced(db, envOld)

      // AFTER-DELETE trigger re-injects a phantom row matching the partial
      // UNIQUE index, forcing the body's INSERT to collide on every attempt.
      try db.execute(sql: """
        CREATE TEMP TRIGGER h7_force_unique
        AFTER DELETE ON sync_outbox
        WHEN OLD.synced_at IS NULL
        BEGIN
           INSERT INTO sync_outbox
               (entity_type, entity_id, operation, version,
                payload_schema_version, payload, device_id, created_at)
           VALUES (OLD.entity_type, OLD.entity_id, OLD.operation, OLD.version,
                   OLD.payload_schema_version, OLD.payload, OLD.device_id, OLD.created_at);
        END;
        """)

      let envNew = env("task", entityId, vNew)
      XCTAssertThrowsError(try Outbox.enqueueCoalesced(db, envNew))

      try db.execute(sql: "DROP TRIGGER h7_force_unique")

      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT version, payload FROM sync_outbox \
          WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [entityId])
      XCTAssertEqual(rows.count, 1)
      XCTAssertEqual(rows[0]["version"], vOld)
      XCTAssertEqual(
        JSONValue.parse(rows[0]["payload"] as String).flatMap(ApplyJSON.object)?["title"],
        .string("racing"))
    }
  }

  func testCoalesceAuditLogsDroppedDeleteWhenUpsertOverwritesQueuedDelete() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-000000002184"
      try Outbox.enqueueCoalesced(db, env("task", entityId, "1711234567890_0000_a1b2c3d4a1b2c3d4"))
      try Outbox.enqueueCoalesced(db, deleteEnv("task", entityId, "1811234567890_0000_b1b2c3d4b1b2c3d4"))
      try Outbox.enqueueCoalesced(db, env("task", entityId, "1911234567890_0000_c1b2c3d4c1b2c3d4"))
      let droppedCount = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE operation = 'sync.outbox.coalesced_delete_dropped'") ?? 0
      XCTAssertGreaterThanOrEqual(droppedCount, 1)
    }
  }

  /// The dropped-Delete coalesce audit is device-local: written straight into
  /// `ai_changelog` and never enqueued to the sync outbox, with a summary worded
  /// as a local-only record. The intermediate Delete never left this device's
  /// outbox, so peers receive only the superseding Upsert and have nothing to
  /// reconstruct — the summary must not instruct them to.
  func testCoalesceDroppedDeleteAuditIsDeviceLocalAndWordedLocally() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-0000000021b7"
      try Outbox.enqueueCoalesced(db, env("task", entityId, "1711234567890_0000_a1b2c3d4a1b2c3d4"))
      try Outbox.enqueueCoalesced(db, deleteEnv("task", entityId, "1811234567890_0000_b1b2c3d4b1b2c3d4"))
      try Outbox.enqueueCoalesced(db, env("task", entityId, "1911234567890_0000_c1b2c3d4c1b2c3d4"))

      let summary = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql:
            "SELECT summary FROM ai_changelog WHERE operation = 'sync.outbox.coalesced_delete_dropped'"
        ))
      XCTAssertTrue(
        summary.contains("device-local"),
        "the audit summary must state it is a device-local record")
      XCTAssertFalse(
        summary.lowercased().contains("reconstruct"),
        "the audit summary must not instruct peers to reconstruct the dropped Delete")

      let changelogOutbox =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'ai_changelog'") ?? 0
      XCTAssertEqual(
        changelogOutbox, 0,
        "the dropped-Delete audit stays device-local, never enqueued to the sync zone")
    }
  }

  func testCoalesceDoesNotAuditLogWhenUpsertOverwritesQueuedUpsert() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-000000002193"
      try Outbox.enqueueCoalesced(db, env("task", entityId, "1711234567890_0000_a1b2c3d4a1b2c3d4"))
      try Outbox.enqueueCoalesced(db, env("task", entityId, "1811234567890_0000_b1b2c3d4b1b2c3d4"))
      let droppedCount = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE operation = 'sync.outbox.coalesced_delete_dropped'") ?? 0
      XCTAssertEqual(droppedCount, 0)
    }
  }

  // MARK: - Retry-wait re-arm (full-resync recovery of last resort)

  /// SY1 regression: an equal-version coalesce must revive a retry-wait row.
  ///
  /// When a transient outage burned an outbox row's retry budget to `maxRetries`
  /// (parking it), the full-resync backfill re-emits that entity at
  /// its EXISTING stored version to recover it. The equal-version enqueue hits the
  /// stale-coalesce branch, which otherwise preserves the existing row's
  /// `retry_count = maxRetries` — so the row stays excluded from `getPending`
  /// until its due time. Full resync is an explicit earlier recovery path, so an
  /// equal-version retry-wait row is replaced with fresh retry state.
  func testEqualVersionCoalesceReArmsRetryWaitRow() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-000000002199"
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db, env("task", entityId, version))

      // A persistent per-record failure moved the row into retry wait.
      try db.execute(
        sql: """
          UPDATE sync_outbox SET retry_count = ?, last_error = 'quotaExceeded', \
            disposition = ?, next_retry_at = '2099-01-01T00:00:00.000Z', \
            recovery_round = 1 \
          WHERE entity_id = ? AND synced_at IS NULL
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue, entityId,
        ])
      XCTAssertTrue(
        try Outbox.getPending(db).isEmpty, "the retry-wait row is excluded from getPending")

      // The full-resync backfill re-emits at the SAME stored version.
      try Outbox.enqueueCoalesced(db, env("task", entityId, version))

      // The row is re-armed: retry budget reset, last_error cleared, back in
      // getPending at the stored version.
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      let revived = try XCTUnwrap(pending.first)
      XCTAssertEqual(revived.envelope.entityId, entityId)
      XCTAssertEqual(revived.envelope.version.description, version)
      let (retry, lastError) = try retryState(db, entityId)
      XCTAssertEqual(retry, 0)
      XCTAssertNil(lastError)
    }
  }

  /// Retry wait relaxes only the EQUAL-version no-op needed by full-resync
  /// recovery. It must never let an older snapshot replace the newer queued
  /// envelope merely because the newer row is currently dormant.
  func testOlderVersionCannotReplaceRetryWaitRow() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000219c"
      let newer = "1811234567890_0000_b1b2c3d4b1b2c3d4"
      let older = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env("task", entityId, newer))
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, disposition = ?,
              next_retry_at = '2099-01-01T00:00:00.000Z', recovery_round = 1
          WHERE entity_id = ? AND synced_at IS NULL
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue, entityId,
        ])

      XCTAssertNil(try Outbox.enqueueCoalesced(db, env("task", entityId, older)))
      let queued = try String.fetchOne(
        db,
        sql: "SELECT version FROM sync_outbox WHERE entity_id = ? AND synced_at IS NULL",
        arguments: [entityId])
      XCTAssertEqual(queued, newer)
    }
  }

  /// Equal-version full-resync enqueue is generic recovery and must not revive a
  /// pre-adoption write that snapshot adoption intentionally fenced. A genuinely
  /// new user edit carries a newer HLC and may replace the fence normally.
  func testEqualVersionCoalesceNeverRearmsAuthoritativeAdoption() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000219b"
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env("task", entityId, version))
      let databaseInstanceId = "coalesce-test-database"
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: databaseInstanceId)
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: "coalesce-test-account")
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "coalesce-test-account", zoneIdentifier: "LorvexZone"),
        databaseInstanceId: databaseInstanceId)
      _ = try Outbox.quarantineAllPending(
        db, error: "authoritative snapshot adoption",
        authoritativeSessionToken: session.sessionToken)

      XCTAssertNil(try Outbox.enqueueCoalesced(db, env("task", entityId, version)))
      let (retry, _) = try retryState(db, entityId)
      XCTAssertEqual(retry, Outbox.maxRetries)
      let disposition = try String.fetchOne(
        db,
        sql: "SELECT disposition FROM sync_outbox WHERE entity_id = ? AND synced_at IS NULL",
        arguments: [entityId])
      XCTAssertEqual(disposition, Outbox.Disposition.authoritativeAdoption.rawValue)

      let newer = "1811234567890_0000_b1b2c3d4b1b2c3d4"
      XCTAssertNotNil(try Outbox.enqueueCoalesced(db, env("task", entityId, newer)))
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.map(\.envelope.version.description), [newer])
    }
  }

  /// A non-exhausted equal-version coalesce stays a no-op (the normal stale-LWW
  /// branch): only an explicit retry-wait row is revived.
  func testEqualVersionCoalesceIsStillNoopForHealthyRow() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-00000000219a"
      let version = "1711234567890_0000_a1b2c3d4a1b2c3d4"
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db, env("task", entityId, version))
      // A couple of transient failures, still well below the cap.
      try db.execute(
        sql: "UPDATE sync_outbox SET retry_count = 2 WHERE entity_id = ? AND synced_at IS NULL",
        arguments: [entityId])
      XCTAssertNil(try Outbox.enqueueCoalesced(db, env("task", entityId, version)))
      let (retry, _) = try retryState(db, entityId)
      XCTAssertEqual(retry, 2, "a healthy row's retry_count is untouched by an equal-version coalesce")
    }
  }

  private func retryState(_ db: Database, _ entityId: String) throws -> (Int64, String?) {
    let row = try Row.fetchOne(
      db,
      sql: "SELECT retry_count, last_error FROM sync_outbox WHERE entity_id = ? AND synced_at IS NULL",
      arguments: [entityId])!
    return (row["retry_count"], row["last_error"])
  }
}
