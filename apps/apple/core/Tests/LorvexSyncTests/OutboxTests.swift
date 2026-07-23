import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Outbox query/mutation, retry, GC, and hardening coverage. Seeds via the
/// outbox writes + raw SQL, running inside `store.writer.write { ... }` so the
/// coalesce per-attempt SAVEPOINT contract (non-autocommit connection) holds.
final class OutboxTests: XCTestCase {

  // MARK: - Fixtures

  private func makeEnvelope(
    _ entityType: String, _ entityId: String, _ version: String,
    payload: String = #"{"title":"test"}"#
  ) -> SyncEnvelope {
    SyncEnvelope(
      entityType: EntityKind.parse(entityType)!,
      entityId: entityId,
      operation: .upsert,
      version: try! Hlc.parse(version),
      payloadSchemaVersion: 1,
      payload: payload,
      deviceId: "device-001")
  }

  private func makeDeleteEnvelope(
    _ entityType: String, _ entityId: String, _ version: String
  ) -> SyncEnvelope {
    SyncEnvelope(
      entityType: EntityKind.parse(entityType)!,
      entityId: entityId,
      operation: .delete,
      version: try! Hlc.parse(version),
      payloadSchemaVersion: 1,
      payload: "{}",
      deviceId: "device-001")
  }

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try body(db)
    }
  }

  private func beginAuthoritativeSession(_ db: Database) throws -> String {
    let databaseInstanceId = "outbox-test-database"
    try SyncCheckpoints.set(
      db, key: SyncCheckpoints.keyDatabaseInstanceId,
      value: databaseInstanceId)
    _ = try CloudTraversalWitness.claimAccount(
      db, accountIdentifier: "outbox-test-account")
    return try AuthoritativeSnapshot.begin(
      db,
      boundary: try SyncTestSupport.cloudTraversalBoundary(
        accountIdentifier: "outbox-test-account", zoneIdentifier: "LorvexZone"),
      databaseInstanceId: databaseInstanceId
    ).sessionToken
  }

  @discardableResult
  private func insertParkedAudit(
    _ db: Database, id: String, accountIdentifier: String,
    version: String, due: String
  ) throws -> Int64 {
    let row = ChangelogWrite.ChangelogRow(
      id: id, timestamp: "2026-01-01T00:00:00.000Z", operation: "update",
      entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000009999",
      summary: "retry-account isolation", initiatedBy: "assistant",
      sourceDeviceId: "device-001", retentionEpoch: 0,
      retentionAccountIdentifier: accountIdentifier)
    try ChangelogWrite.writeChangelogRow(db, row)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: EntityName.aiChangelog, entityId: id,
      payload: ChangelogWrite.buildChangelogSyncPayload(row),
      context: OutboxWriteContext(
        version: version, deviceId: "device-001"))
    let outboxId = try XCTUnwrap(
      Int64.fetchOne(
        db,
        sql: """
          SELECT id FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [EntityName.aiChangelog, id]))
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = ?, disposition = ?, next_retry_at = ?,
            recovery_round = 1
        WHERE id = ?
        """,
      arguments: [
        Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue,
        due, outboxId,
      ])
    return outboxId
  }

  // MARK: - query_and_mutation

  func testEnqueueAndGetPending() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].envelope.entityType, .task)
      XCTAssertEqual(pending[0].envelope.entityId, "01966a3f-7c8b-7d4e-8f3a-000000002163")
      XCTAssertEqual(pending[0].envelope.version.description, "1711234567890_0000_a1b2c3d4a1b2c3d4")
      XCTAssertNil(pending[0].syncedAt)
      XCTAssertEqual(pending[0].retryCount, 0)
    }
  }

  func testOperationalWireCeilingRejectsEveryOutboxEntryPointWithoutMutation() throws {
    try withDB { db in
      let version = try Hlc(
        physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
        deviceSuffix: "ffffffffffffffff").description
      let direct = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-000000002164", version)
      XCTAssertThrowsError(try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, direct)) { error in
        XCTAssertEqual(
          error as? Outbox.OutboxError,
          .operationalHlcCeilingExceeded(
            entityType: .task, entityId: direct.entityId, version: version))
      }
      XCTAssertThrowsError(try Outbox.enqueueCoalesced(db, direct)) { error in
        XCTAssertEqual(
          error as? Outbox.OutboxError,
          .operationalHlcCeilingExceeded(
            entityType: .task, entityId: direct.entityId, version: version))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testMultipleEnqueuesOrderedFifo() throws {
    try withDB { db in
      for i in 0..<5 {
        let env = makeEnvelope(
          "task", String(format: "01966a3f-7c8b-7d4e-8f3a-000000003%03d", i),
          "171123456789\(i)_0000_a1b2c3d4a1b2c3d4")
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      }
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 5)
      for (i, entry) in pending.enumerated() {
        XCTAssertEqual(entry.envelope.entityId, String(format: "01966a3f-7c8b-7d4e-8f3a-000000003%03d", i))
      }
    }
  }

  func testPendingCursorExcludesAttemptedPrefixAndReturnsNewerRows() throws {
    try withDB { db in
      for i in 0..<3 {
        let env = makeEnvelope(
          "task", String(format: "01966a3f-7c8b-7d4e-8f3a-000000004%03d", i),
          "171123456790\(i)_0000_a1b2c3d4a1b2c3d4")
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      }
      let first = try Outbox.getPending(db)
      XCTAssertEqual(first.count, 3)

      let tail = try Outbox.getPending(db, afterOutboxId: first[1].id)
      XCTAssertEqual(tail.map(\.id), [first[2].id])
    }
  }

  func testPendingCursorDoesNotRearmDueRowsBehindCursor() throws {
    try withDB { db in
      let pageSize = Int(Outbox.maxPendingFetch)
      var outboxIDs: [Int64] = []
      outboxIDs.reserveCapacity(pageSize * 2)
      for i in 0..<(pageSize * 2) {
        let env = makeEnvelope(
          "task", String(format: "01966a3f-7c8b-7d4e-8f3a-%012d", i),
          "1711234567999_0000_a1b2c3d4a1b2c3d4")
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
        outboxIDs.append(db.lastInsertedRowID)
      }

      let lowIDs = Array(outboxIDs[..<pageSize])
      let highIDs = Array(outboxIDs[pageSize...])
      let lowDue = "2026-08-01T01:00:00.000Z"
      let highDue = "2026-08-01T00:00:00.000Z"
      let now = "2026-08-01T02:00:00.000Z"
      for (ids, due) in [(lowIDs, lowDue), (highIDs, highDue)] {
        try db.execute(
          sql: """
            UPDATE sync_outbox
            SET retry_count = ?, disposition = ?, next_retry_at = ?,
                recovery_round = 1
            WHERE id BETWEEN ? AND ?
            """,
          arguments: [
            Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue,
            due, try XCTUnwrap(ids.first), try XCTUnwrap(ids.last),
          ])
      }

      let first = try Outbox.getPendingPage(db, now: now)
      XCTAssertEqual(first.entries.map(\.id), highIDs)
      XCTAssertEqual(first.lastScannedOutboxId, highIDs.last)

      let second = try Outbox.getPendingPage(
        db, now: now, afterOutboxId: first.lastScannedOutboxId)
      XCTAssertTrue(second.entries.isEmpty)
      XCTAssertNil(second.lastScannedOutboxId)

      let stillParked = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_outbox
          WHERE id BETWEEN ? AND ? AND disposition = ?
          """,
        arguments: [
          try XCTUnwrap(lowIDs.first), try XCTUnwrap(lowIDs.last),
          Outbox.Disposition.retryWait.rawValue,
        ])
      XCTAssertEqual(stillParked, pageSize)
      XCTAssertEqual(
        try Outbox.earliestRetryAt(db),
        try XCTUnwrap(SyncTimestamp.parse(lowDue)).date)

      let followUp = try Outbox.getPendingPage(db, now: now)
      XCTAssertEqual(followUp.entries.map(\.id), lowIDs)
    }
  }

  func testEarliestRetryAtReturnsTheDurableWakeDeadline() throws {
    try withDB { db in
      let env = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-000000004999",
        "1711234567999_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = db.lastInsertedRowID
      let due = "2026-08-01T01:02:03.000Z"
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, disposition = ?, next_retry_at = ?, recovery_round = 1
          WHERE id = ?
          """,
        arguments: [Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue, due, id])

      XCTAssertEqual(
        try Outbox.earliestRetryAt(db),
        try XCTUnwrap(SyncTimestamp.parse(due)).date)
    }
  }

  func testRetryRearmLeavesInactiveAccountAuditRowsParked() throws {
    try withDB { db in
      try db.execute(
        sql: """
          UPDATE audit_retention_binding
          SET ever_bound = 1, active_account_identifier = ?,
              active_zone_name = ?, updated_at = ?
          WHERE singleton = 1
          """,
        arguments: [
          "icloud-account-b", "LorvexZone",
          "2026-08-01T00:00:00.000Z",
        ])
      let inactiveId = try self.insertParkedAudit(
        db, id: "01966a3f-7c8b-7d4e-8f3a-000000004a01",
        accountIdentifier: "icloud-account-a",
        version: "1711234567999_0001_a1b2c3d4a1b2c3d4",
        due: "2026-08-01T01:00:00.000Z")
      let activeId = try self.insertParkedAudit(
        db, id: "01966a3f-7c8b-7d4e-8f3a-000000004b01",
        accountIdentifier: "icloud-account-b",
        version: "1711234567999_0002_a1b2c3d4a1b2c3d4",
        due: "2026-08-01T01:01:00.000Z")

      XCTAssertEqual(
        try Outbox.rearmRetryableFailuresDue(
          db, now: "2026-08-01T02:00:00.000Z"),
        1)
      let inactive = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT retry_count, disposition, next_retry_at
            FROM sync_outbox WHERE id = ?
            """,
          arguments: [inactiveId]))
      XCTAssertEqual(inactive["retry_count"] as Int64, Outbox.maxRetries)
      XCTAssertEqual(
        inactive["disposition"] as String?,
        Outbox.Disposition.retryWait.rawValue)
      XCTAssertEqual(
        inactive["next_retry_at"] as String?, "2026-08-01T01:00:00.000Z")

      let active = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT retry_count, disposition, next_retry_at
            FROM sync_outbox WHERE id = ?
            """,
          arguments: [activeId]))
      XCTAssertEqual(active["retry_count"] as Int64, 0)
      XCTAssertNil(active["disposition"] as String?)
      XCTAssertNil(active["next_retry_at"] as String?)
      XCTAssertEqual(
        try Outbox.getPending(
          db, now: "2026-08-01T02:00:00.000Z").map(\.id),
        [activeId])
    }
  }

  func testQuarantineAllPendingDropsEveryPendingRow() throws {
    try withDB { db in
      // Two pending rows plus one already synced. Quarantine must drop both
      // pending rows (pinning retry_count to maxRetries so getPending excludes
      // them and stamping last_error) while leaving the synced row untouched.
      let a = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-0000000000a1", "1711234567890_0001_a1b2c3d4a1b2c3d4")
      let b = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-0000000000a2", "1711234567890_0002_a1b2c3d4a1b2c3d4")
      let done = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-0000000000a3", "1711234567890_0003_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, a)
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, b)
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, done)
      let doneId = try Outbox.getPending(db).first { $0.envelope.entityId == done.entityId }!.id
      try Outbox.markManySynced(db, outboxIds: [doneId], syncedAt: "1711234567890_0004_a1b2c3d4a1b2c3d4")

      let sessionToken = try beginAuthoritativeSession(db)
      let count = try Outbox.quarantineAllPending(
        db, error: "over-window adopt",
        authoritativeSessionToken: sessionToken)
      XCTAssertEqual(
        count, 0,
        "beginning the authoritative session already fences its pre-session queue atomically")
      XCTAssertTrue(try Outbox.getPending(db).isEmpty, "no pending row survives quarantine")
      // Each quarantined row is pinned at maxRetries with the reason stamped; the
      // synced row keeps its NULL last_error.
      let retryA = try Int64.fetchOne(
        db, sql: "SELECT retry_count FROM sync_outbox WHERE entity_id = ?",
        arguments: [a.entityId])
      XCTAssertEqual(retryA, Outbox.maxRetries)
      let errA = try String.fetchOne(
        db, sql: "SELECT last_error FROM sync_outbox WHERE entity_id = ?", arguments: [a.entityId])
      XCTAssertEqual(
        errA,
        "authoritative snapshot adoption: pre-adoption outbound state is superseded by the complete iCloud snapshot")
      let dispositionA = try String.fetchOne(
        db, sql: "SELECT disposition FROM sync_outbox WHERE entity_id = ?",
        arguments: [a.entityId])
      XCTAssertEqual(dispositionA, Outbox.Disposition.authoritativeAdoption.rawValue)
      let retryDone = try Int64.fetchOne(
        db, sql: "SELECT retry_count FROM sync_outbox WHERE entity_id = ?",
        arguments: [done.entityId])
      XCTAssertEqual(retryDone, 0, "an already-synced row is untouched")
    }
  }

  func testQuarantineAllPendingOnEmptyOutboxIsNoop() throws {
    try withDB { db in
      let sessionToken = try beginAuthoritativeSession(db)
      let count = try Outbox.quarantineAllPending(
        db, error: "over-window adopt",
        authoritativeSessionToken: sessionToken)
      XCTAssertEqual(count, 0)
    }
  }

  func testDeletingAuthoritativeSessionCascadesItsOwnedFences() throws {
    try withDB { db in
      let envelope = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-0000000000a4",
        "1711234567890_0004_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, envelope)
      let sessionToken = try beginAuthoritativeSession(db)
      _ = try Outbox.quarantineAllPending(
        db, error: "snapshot adoption", authoritativeSessionToken: sessionToken)

      // Exercise the schema backstop directly, bypassing the explicit release
      // helper used by production cancel/finalize.
      try db.execute(
        sql: "DELETE FROM sync_authoritative_snapshot WHERE session_token = ?",
        arguments: [sessionToken])
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE authoritative_session_token = ?",
          arguments: [sessionToken]),
        0, "ON DELETE CASCADE prevents an orphan fence from occupying the unique slot")
    }
  }

  func testEnqueueDeleteOperation() throws {
    try withDB { db in
      let env = makeDeleteEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].envelope.operation, .delete)
    }
  }

  func testDecodeSyncOperationRejectsUnknownStrings() throws {
    XCTAssertEqual(try Outbox.decodeSyncOperation("upsert"), .upsert)
    XCTAssertEqual(try Outbox.decodeSyncOperation("delete"), .delete)
    XCTAssertThrowsError(try Outbox.decodeSyncOperation("merge")) { error in
      XCTAssertTrue("\(error)".contains("invalid sync_outbox operation"))
    }
  }

  /// A locally undecodable row is recoverable rather than permanently dropped:
  /// once a repaired build/data migration makes it decodable, the persisted due
  /// time automatically returns it to the outbound queue.
  func testDecodePoisonAutomaticallyRetriesAfterRepair() throws {
    try withDB { db in
      let entityId = "01966a3f-7c8b-7d4e-8f3a-0000000021c2"
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_outbox
              (entity_type, entity_id, operation, version, payload_schema_version,
               payload, device_id, created_at)
            VALUES ('task', ?, 'upsert', 'invalid-hlc', 1, '{"title":"repairable"}',
                    'device-001', '2026-03-23T12:00:00.000Z')
            """,
          arguments: [entityId])
      }

      XCTAssertTrue(
        try Outbox.getPending(db, now: "2026-03-23T12:00:00.000Z").isEmpty)
      let parked = try Row.fetchOne(
        db,
        sql: "SELECT id, disposition, next_retry_at FROM sync_outbox WHERE entity_id = ?",
        arguments: [entityId])!
      XCTAssertEqual(
        parked["disposition"] as String?,
        Outbox.Disposition.retryWait.rawValue)
      XCTAssertEqual(parked["next_retry_at"] as String?, "2026-03-23T13:00:00.000Z")

      try db.execute(
        sql: "UPDATE sync_outbox SET version = ? WHERE id = ?",
        arguments: ["1711234567890_0000_a1b2c3d4a1b2c3d4", parked["id"] as Int64])
      XCTAssertTrue(
        try Outbox.getPending(db, now: "2026-03-23T12:59:59.999Z").isEmpty)
      let recovered = try Outbox.getPending(db, now: "2026-03-23T13:00:00.000Z")
      XCTAssertEqual(recovered.map(\.envelope.entityId), [entityId])
    }
  }

  func testMarkManySyncedBatchMarksAllGivenIds() throws {
    try withDB { db in
      for i in 0..<5 {
        let env = makeEnvelope(
          "task", String(format: "01966a3f-7c8b-7d4e-8f3a-000000004%03d", i),
          "171123456789\(i)_0000_a1b2c3d4a1b2c3d4")
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      }
      let ids = try Outbox.getPending(db).map { $0.id }
      XCTAssertEqual(ids.count, 5)
      try Outbox.markManySynced(db, outboxIds: ids, syncedAt: "2026-03-23T12:00:00.000Z")
      XCTAssertTrue(try Outbox.getPending(db).isEmpty)
    }
  }

  func testMarkManySyncedPreservesExistingSyncedAt() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-00000000216f", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      try Outbox.markManySynced(db, outboxIds: [id], syncedAt: "2026-03-23T10:00:00.000Z")
      try Outbox.markManySynced(db, outboxIds: [id], syncedAt: "2026-03-23T12:00:00.000Z")
      let later = try String.fetchOne(db, sql: "SELECT synced_at FROM sync_outbox WHERE id = ?", arguments: [id])
      XCTAssertEqual(later, "2026-03-23T10:00:00.000Z")
    }
  }

  func testMarkManySyncedEmptySliceIsNoop() throws {
    try withDB { db in
      try Outbox.markManySynced(db, outboxIds: [], syncedAt: "2026-03-23T12:00:00.000Z")
    }
  }

  func testMarkManySyncedClearsLastError() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002195", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      try db.execute(
        sql: "UPDATE sync_outbox SET last_error = ?, retry_count = ? WHERE id = ?",
        arguments: ["Permission denied", 3, id])
      try Outbox.markManySynced(db, outboxIds: [id], syncedAt: "2026-03-23T12:00:00.000Z")
      let row = try Row.fetchOne(db, sql: "SELECT synced_at, last_error, retry_count FROM sync_outbox WHERE id = ?", arguments: [id])!
      XCTAssertEqual(row["synced_at"], "2026-03-23T12:00:00.000Z")
      XCTAssertNil(row["last_error"] as String?)
      XCTAssertEqual(row["retry_count"] as Int64, 3)
    }
  }

  // MARK: - retry

  func testRecordRetryIncrementsCount() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      _ = try Outbox.recordRetry(db, outboxId: id, retriedAt: "2026-03-23T12:00:00.000Z", error: nil)
      _ = try Outbox.recordRetry(db, outboxId: id, retriedAt: "2026-03-23T12:01:00.000Z", error: nil)
      let after = try Outbox.getPending(db)
      XCTAssertEqual(after[0].retryCount, 2)
      XCTAssertEqual(after[0].lastRetryAt, "2026-03-23T12:01:00.000Z")
    }
  }

  func testRecordRetrySameErrorThreeTimesEscalatesToMaxRetries() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002192", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      let err = "CloudKit rejected record: payload too large"
      let o1 = try Outbox.recordRetry(db, outboxId: id, retriedAt: "2026-03-23T12:00:00.000Z", error: err)
      XCTAssertEqual(o1.newRetryCount, 1); XCTAssertFalse(o1.exhaustedNow)
      let o2 = try Outbox.recordRetry(db, outboxId: id, retriedAt: "2026-03-23T12:01:00.000Z", error: err)
      XCTAssertEqual(o2.newRetryCount, 2); XCTAssertFalse(o2.exhaustedNow)
      let o3 = try Outbox.recordRetry(db, outboxId: id, retriedAt: "2026-03-23T12:02:00.000Z", error: err)
      XCTAssertEqual(o3.newRetryCount, Outbox.maxRetries); XCTAssertTrue(o3.exhaustedNow)
      XCTAssertEqual(o3.nextRetryAt, "2026-03-23T13:02:00.000Z")
      let state = try Row.fetchOne(
        db,
        sql: "SELECT disposition, next_retry_at, recovery_round, consecutive_error_count FROM sync_outbox WHERE id = ?",
        arguments: [id])!
      XCTAssertEqual(
        state["disposition"] as String?,
        Outbox.Disposition.retryWait.rawValue)
      XCTAssertEqual(state["next_retry_at"] as String?, "2026-03-23T13:02:00.000Z")
      XCTAssertEqual(state["recovery_round"] as Int64, 1)
      XCTAssertEqual(state["consecutive_error_count"] as Int64, 3)
    }
  }

  /// The fast-forward threshold is a true consecutive per-record streak, not
  /// merely total retry_count plus one matching predecessor. A, B, B contains
  /// only two consecutive B failures; the third B is the first point where the
  /// row may enter retry wait.
  func testRepeatedErrorEscalationCountsOnlyConsecutivePerRecordFailures() throws {
    try withDB { db in
      let env = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-0000000021c2",
        "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id

      for error in ["A", "B", "B"] {
        _ = try Outbox.recordRetry(
          db, outboxId: id, retriedAt: "2026-03-23T12:00:00.000Z", error: error)
      }
      let beforeThirdB = try Row.fetchOne(
        db,
        sql: "SELECT retry_count, consecutive_error_count, disposition FROM sync_outbox WHERE id = ?",
        arguments: [id])!
      XCTAssertEqual(beforeThirdB["retry_count"] as Int64, 3)
      XCTAssertEqual(beforeThirdB["consecutive_error_count"] as Int64, 2)
      XCTAssertNil(beforeThirdB["disposition"] as String?)

      let outcome = try Outbox.recordRetry(
        db, outboxId: id, retriedAt: "2026-03-23T12:01:00.000Z", error: "B")
      XCTAssertTrue(outcome.exhaustedNow)
      let afterThirdB = try Row.fetchOne(
        db,
        sql: "SELECT retry_count, consecutive_error_count, disposition FROM sync_outbox WHERE id = ?",
        arguments: [id])!
      XCTAssertEqual(afterThirdB["retry_count"] as Int64, Outbox.maxRetries)
      XCTAssertEqual(afterThirdB["consecutive_error_count"] as Int64, 3)
      XCTAssertEqual(
        afterThirdB["disposition"] as String?,
        Outbox.Disposition.retryWait.rawValue)
    }
  }

  /// An ordinary retry-wait row is dormant until its persisted due time, then the
  /// canonical pending read re-arms it exactly once. A second failed recovery
  /// round backs off further instead of spinning inside repeated drain calls.
  func testRetryWaitAutomaticallyRearmsWhenDueWithIncreasingBackoff() throws {
    try withDB { db in
      let env = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-0000000021c0",
        "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db, now: "2026-03-23T12:00:00.000Z")[0].id
      let error = "CloudKit rejected record: payload too large"
      for minute in 0..<3 {
        _ = try Outbox.recordRetry(
          db, outboxId: id, retriedAt: "2026-03-23T12:0\(minute):00.000Z", error: error)
      }

      XCTAssertTrue(
        try Outbox.getPending(db, now: "2026-03-23T13:01:59.999Z").isEmpty,
        "retry_wait must not re-arm before its due instant")
      let rearmed = try Outbox.getPending(db, now: "2026-03-23T13:02:00.000Z")
      XCTAssertEqual(rearmed.map(\.id), [id])
      XCTAssertEqual(rearmed[0].retryCount, 0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT consecutive_error_count FROM sync_outbox WHERE id = ?",
          arguments: [id]),
        0, "a due recovery round starts a fresh per-record error streak")

      for minute in 2..<5 {
        _ = try Outbox.recordRetry(
          db, outboxId: id, retriedAt: "2026-03-23T13:0\(minute):00.000Z", error: error)
      }
      let state = try Row.fetchOne(
        db,
        sql: "SELECT disposition, next_retry_at, recovery_round FROM sync_outbox WHERE id = ?",
        arguments: [id])!
      XCTAssertEqual(
        state["disposition"] as String?,
        Outbox.Disposition.retryWait.rawValue)
      XCTAssertEqual(state["next_retry_at"] as String?, "2026-03-23T19:04:00.000Z")
      XCTAssertEqual(state["recovery_round"] as Int64, 2)
      XCTAssertTrue(
        try Outbox.getPending(db, now: "2026-03-23T13:05:00.000Z").isEmpty,
        "a repeated pending read in the same cycle cannot tight-loop the row")
    }
  }

  func testRecordRetryWholesaleSameErrorDoesNotFastForward() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002195", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      // A wholesale chunk failure stamps the SAME error on every row each cycle,
      // so identical repeats are evidence of an outage shape, not a poisoned row.
      // With escalation reserved for per-record failures, five identical repeats
      // advance retry_count linearly and never fast-forward to maxRetries.
      let err = "push chunk failed: The operation couldn't be completed."
      // Seed a two-error per-record streak. The wholesale classification must
      // break it rather than becoming the apparent third per-record rejection.
      for _ in 0..<2 {
        _ = try Outbox.recordRetry(
          db, outboxId: id, retriedAt: "2026-03-23T12:00:00.000Z", error: err)
      }
      for i in 1...5 {
        let outcome = try Outbox.recordRetry(
          db, outboxId: id, retriedAt: "2026-03-23T12:0\(i):00.000Z", error: err,
          escalateOnRepeatedError: false)
        XCTAssertEqual(outcome.newRetryCount, Int64(i + 2))
        XCTAssertFalse(outcome.exhaustedNow)
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT consecutive_error_count FROM sync_outbox WHERE id = ?",
          arguments: [id]),
        0, "wholesale failures are not per-record streak evidence")
      XCTAssertEqual(try Outbox.getPending(db).count, 1, "the row stays pending, not quarantined")
    }
  }

  func testRecordRetryDifferentErrorsDoNotEscalateEarly() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002183", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      for (i, err) in ["net timeout", "conn reset", "net timeout", "TLS flap"].enumerated() {
        let outcome = try Outbox.recordRetry(db, outboxId: id, retriedAt: "2026-03-23T12:00:00.000Z", error: err)
        XCTAssertEqual(outcome.newRetryCount, Int64(i + 1))
        XCTAssertFalse(outcome.exhaustedNow)
      }
    }
  }

  func testRecordTransientFailureDoesNotAdvanceRetryCountOrEscalate() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-0000000021b0", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      // The identical transient error five times in a row — the exact shape that
      // would fast-forward a persistent error to maxRetries — must never spend
      // retry budget or escalate. The row stays pending (ships when online again).
      let err = "push chunk failed: The Internet connection appears to be offline."
      // Seed a two-error per-record streak; a transient event is a different
      // failure class and must break that streak without spending retry budget.
      for _ in 0..<2 {
        _ = try Outbox.recordRetry(
          db, outboxId: id, retriedAt: "2026-03-23T12:00:00.000Z", error: err)
      }
      for i in 0..<5 {
        try Outbox.recordTransientFailure(
          db, outboxId: id, retriedAt: "2026-03-23T12:0\(i):00.000Z", error: err)
      }
      let row = try Row.fetchOne(
        db,
        sql: "SELECT retry_count, last_error, last_retry_at, consecutive_error_count FROM sync_outbox WHERE id = ?",
        arguments: [id])!
      XCTAssertEqual(row["retry_count"] as Int64, 2, "a transient outage must not spend retry budget")
      XCTAssertEqual(row["consecutive_error_count"] as Int64, 0)
      XCTAssertEqual(row["last_retry_at"], "2026-03-23T12:04:00.000Z")
      XCTAssertTrue((row["last_error"] as String? ?? "").contains("offline"))
      XCTAssertEqual(try Outbox.getPending(db).count, 1, "the row stays pending, not quarantined")
    }
  }

  func testRecordTransientFailureSkipsSyncedRows() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-0000000021b1", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      try Outbox.markManySynced(db, outboxIds: [id], syncedAt: "2026-03-23T10:00:00.000Z")
      try Outbox.recordTransientFailure(db, outboxId: id, retriedAt: "2026-03-23T12:00:00.000Z", error: "offline")
      let row = try Row.fetchOne(db, sql: "SELECT last_error, last_retry_at FROM sync_outbox WHERE id = ?", arguments: [id])!
      XCTAssertNil(row["last_error"] as String?)
      XCTAssertNil(row["last_retry_at"] as String?)
    }
  }

  // MARK: - gc

  func testGcSyncedDeletesOldEntries() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let pending = try Outbox.getPending(db)
      try Outbox.markManySynced(db, outboxIds: [pending[0].id], syncedAt: "2020-01-01T00:00:00.000Z")
      let deleted = try Outbox.gcSynced(db, retentionDays: 1)
      XCTAssertEqual(deleted, 1)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testGcSyncedPreservesRecentEntries() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let pending = try Outbox.getPending(db)
      try Outbox.markManySynced(db, outboxIds: [pending[0].id], syncedAt: "2099-01-01T00:00:00.000Z")
      XCTAssertEqual(try Outbox.gcSynced(db, retentionDays: 1), 0)
    }
  }

  func testGcSyncedPreservesUnsyncedEntries() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      XCTAssertEqual(try Outbox.gcSynced(db, retentionDays: 0), 0)
    }
  }

  func testGcSyncedPreservesRetryWaitPastRetention() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      try db.execute(
        sql: "UPDATE sync_outbox SET retry_count = ?, last_error = 'permanent: schema mismatch', disposition = ?, next_retry_at = '2099-01-01T00:00:00.000Z', recovery_round = 1, created_at = '2020-01-01T00:00:00.000Z' WHERE id = ?",
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.retryWait.rawValue, id,
        ])
      XCTAssertEqual(try Outbox.gcSynced(db, retentionDays: 1), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 1)
    }
  }

  func testGcSyncedPreservesExhaustedRetryEntriesWithinRetention() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002163", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      try db.execute(
        sql: "UPDATE sync_outbox SET retry_count = ?, last_error = 'transient' WHERE id = ?",
        arguments: [Outbox.maxRetries, id])
      XCTAssertEqual(try Outbox.gcSynced(db, retentionDays: 1), 0)
    }
  }

  func testGcSyncedPreservesExhaustedEntriesWithNoLastError() throws {
    try withDB { db in
      let env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-00000000218b", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db)[0].id
      try db.execute(
        sql: "UPDATE sync_outbox SET retry_count = ?, created_at = '2020-01-01T00:00:00.000Z' WHERE id = ?",
        arguments: [Outbox.maxRetries, id])
      XCTAssertEqual(try Outbox.gcSynced(db, retentionDays: 1), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 1)
    }
  }

  func testGcSyncedReapsSyncedAndAuthoritativeFenceAndReturnsSummedCount() throws {
    try withDB { db in
      // A synced-history row past retention (deleted by the first DELETE) and a
      // deliberately-discarded authoritative fence (deleted by the second
      // DELETE), plus a
      // recent synced row and a live unsynced row that must both survive. The
      // returned count must be exactly the two-branch sum (2), proving the split
      // statements each contribute their own `changesCount`.
      let oldSynced = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002201", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, oldSynced)
      let oldSyncedId = try Outbox.getPending(db)[0].id
      try Outbox.markManySynced(db, outboxIds: [oldSyncedId], syncedAt: "2020-01-01T00:00:00.000Z")

      let recentSynced = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002202", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, recentSynced)
      let recentSyncedId = try Outbox.getPending(db)[0].id
      try Outbox.markManySynced(db, outboxIds: [recentSyncedId], syncedAt: "2099-01-01T00:00:00.000Z")

      let authoritativeFence = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002203", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, authoritativeFence)
      let authoritativeFenceID = try Outbox.getPending(db)[0].id
      let sessionToken = try beginAuthoritativeSession(db)
      try db.execute(
        sql: "UPDATE sync_outbox SET retry_count = ?, last_error = 'authoritative snapshot', disposition = ?, authoritative_session_token = ?, created_at = '2020-01-01T00:00:00.000Z' WHERE id = ?",
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.authoritativeAdoption.rawValue,
          sessionToken, authoritativeFenceID,
        ])

      let liveUnsynced = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002204", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, liveUnsynced)

      XCTAssertEqual(try Outbox.gcSynced(db, retentionDays: 1), 2)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 2)
      // Exactly the recent-synced and the live-unsynced rows remain.
      let survivors = try String.fetchAll(
        db, sql: "SELECT entity_id FROM sync_outbox ORDER BY entity_id")
      XCTAssertEqual(
        survivors,
        ["01966a3f-7c8b-7d4e-8f3a-000000002202", "01966a3f-7c8b-7d4e-8f3a-000000002204"])
    }
  }

  /// Snapshot adoption converts every unsynced row, including an already-dormant
  /// ordinary retry, into the non-recoverable authoritative fence. Generic due
  /// recovery must never make that pre-adoption write emit again.
  func testAuthoritativeAdoptionSupersedesRetryWaitAndNeverAutoRearms() throws {
    try withDB { db in
      let env = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-0000000021c1",
        "1711234567890_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      let id = try Outbox.getPending(db, now: "2026-03-23T12:00:00.000Z")[0].id
      let error = "CloudKit rejected record"
      for minute in 0..<3 {
        _ = try Outbox.recordRetry(
          db, outboxId: id, retriedAt: "2026-03-23T12:0\(minute):00.000Z", error: error)
      }

      let sessionToken = try beginAuthoritativeSession(db)
      XCTAssertEqual(
        try Outbox.quarantineAllPending(
          db, error: "snapshot adoption",
          authoritativeSessionToken: sessionToken),
        0,
        "the session begin transaction already supersedes retry-wait rows")
      let state = try Row.fetchOne(
        db,
        sql: "SELECT disposition, next_retry_at FROM sync_outbox WHERE id = ?",
        arguments: [id])!
      XCTAssertEqual(
        state["disposition"] as String?,
        Outbox.Disposition.authoritativeAdoption.rawValue)
      XCTAssertNil(state["next_retry_at"] as String?)
      XCTAssertTrue(
        try Outbox.getPending(db, now: "2099-01-01T00:00:00.000Z").isEmpty,
        "authoritative adoption is never a time-based retry")
    }
  }

  // MARK: - gc unsynced backlog cap (sync-off backstop)

  /// Past the cap, `gcUnsyncedBeyondCap` retains the newest `maxRows` unsynced
  /// rows and deletes the oldest beyond it — the never-pushed backlog the
  /// synced-row GC never touches. Age order is `id DESC`, so the highest ids
  /// (most recently enqueued) survive.
  func testGcUnsyncedBeyondCapKeepsNewestDropsOldest() throws {
    try withDB { db in
      var ids: [Int64] = []
      for i in 0..<6 {
        let env = makeEnvelope(
          "task", String(format: "01966a3f-7c8b-7d4e-8f3a-0000000042%02d", i),
          "171123456789\(i)_0000_a1b2c3d4a1b2c3d4")
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
        ids.append(
          try Int64.fetchOne(db, sql: "SELECT id FROM sync_outbox ORDER BY id DESC LIMIT 1")!)
      }

      let deleted = try Outbox.gcUnsyncedBeyondCap(db, maxRows: 2)
      XCTAssertEqual(deleted, 4, "the oldest 4 of 6 unsynced rows are shed")
      let survivors = try Int64.fetchAll(
        db, sql: "SELECT id FROM sync_outbox ORDER BY id ASC")
      XCTAssertEqual(survivors, Array(ids.suffix(2)), "the two newest ids survive the cap")
    }
  }

  /// A backlog within the cap is untouched — a later sign-in still delivers every
  /// queued row. Synced rows are excluded from the cap entirely (only the
  /// never-pushed subset is bounded).
  func testGcUnsyncedBeyondCapKeepsWithinCapAndIgnoresSynced() throws {
    try withDB { db in
      for i in 0..<3 {
        let env = makeEnvelope(
          "task", String(format: "01966a3f-7c8b-7d4e-8f3a-0000000043%02d", i),
          "171123456789\(i)_0000_a1b2c3d4a1b2c3d4")
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env)
      }
      // A synced row must never count against — or be deleted by — the unsynced
      // cap, even with maxRows: 0.
      let syncedEnv = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-000000004399", "1711234567899_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, syncedEnv)
      let syncedId = try Outbox.getPending(db).first { $0.envelope.entityId.hasSuffix("99") }!.id
      try Outbox.markManySynced(db, outboxIds: [syncedId], syncedAt: "2099-01-01T00:00:00.000Z")

      XCTAssertEqual(try Outbox.gcUnsyncedBeyondCap(db, maxRows: 100), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 4)

      // maxRows: 0 sheds all 3 unsynced rows but leaves the synced one.
      XCTAssertEqual(try Outbox.gcUnsyncedBeyondCap(db, maxRows: 0), 3)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NOT NULL"),
        1)
    }
  }

  /// A retention-prune delete is a durable privacy request, not disposable
  /// sync-off backlog. It may temporarily take the queue above its ordinary cap
  /// and must remain available to clear the shared CloudKit record later.
  func testGcUnsyncedBeyondCapNeverDropsChangelogDelete() throws {
    try withDB { db in
      let auditId = "01966a3f-7c8b-7d4e-8f3a-0000000000dd"
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(
        db,
        SyncEnvelope(
          entityType: .aiChangelog, entityId: auditId, operation: .delete,
          version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: #"{"retention_prune":true}"#, deviceId: "device-A"))
      for i in 1...2 {
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(
          db,
          makeEnvelope(
            "task", "01966a3f-7c8b-7d4e-8f3a-0000000000e\(i)",
            "171123456789\(i)_0000_a1b2c3d4a1b2c3d4"))
      }

      XCTAssertEqual(try Outbox.gcUnsyncedBeyondCap(db, maxRows: 1), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.aiChangelog, auditId]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL"),
        2, "one ordinary newest row plus the protected privacy delete remain")
    }
  }

  /// The sync-off backlog cap owns only active queued work. A retry-wait row is
  /// durable recovery state, while an authoritative-adoption fence is retained
  /// by its separate time-based policy; neither may be mistaken for disposable
  /// ordinary backlog even when the active cap is zero.
  func testGcUnsyncedBeyondCapDoesNotDeleteDispositionRows() throws {
    try withDB { db in
      // Establish an empty authoritative session first. Rows written after its
      // begin boundary are new local intent and are not auto-fenced.
      let sessionToken = try beginAuthoritativeSession(db)
      let retryEnvelope = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-0000000000f1",
        "1711234567891_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, retryEnvelope)
      let retryID = try Int64.fetchOne(
        db, sql: "SELECT id FROM sync_outbox WHERE entity_id = ?",
        arguments: [retryEnvelope.entityId])!
      for minute in 0..<3 {
        _ = try Outbox.recordRetry(
          db, outboxId: retryID,
          retriedAt: "2026-03-23T12:0\(minute):00.000Z",
          error: "persistent record rejection")
      }

      let fenceEnvelope = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-0000000000f2",
        "1711234567892_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, fenceEnvelope)
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, disposition = ?, authoritative_session_token = ?
          WHERE entity_id = ?
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.authoritativeAdoption.rawValue,
          sessionToken, fenceEnvelope.entityId,
        ])

      let activeEnvelope = makeEnvelope(
        "task", "01966a3f-7c8b-7d4e-8f3a-0000000000f3",
        "1711234567893_0000_a1b2c3d4a1b2c3d4")
      try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, activeEnvelope)

      XCTAssertEqual(try Outbox.gcUnsyncedBeyondCap(db, maxRows: 0), 1)
      let states = try Row.fetchAll(
        db,
        sql: "SELECT entity_id, disposition FROM sync_outbox ORDER BY entity_id")
      XCTAssertEqual(states.count, 2)
      XCTAssertEqual(states[0]["entity_id"] as String, retryEnvelope.entityId)
      XCTAssertEqual(
        states[0]["disposition"] as String?,
        Outbox.Disposition.retryWait.rawValue)
      XCTAssertEqual(states[1]["entity_id"] as String, fenceEnvelope.entityId)
      XCTAssertEqual(
        states[1]["disposition"] as String?,
        Outbox.Disposition.authoritativeAdoption.rawValue)
    }
  }

  // MARK: - hardening

  func testEnqueueRejectsEnvelopeWithPathTraversalEntityId() throws {
    try withDB { db in
      var env = makeEnvelope("task", "ok", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      env.entityId = "../etc/passwd"
      XCTAssertThrowsError(try SyncTestSupport.insertOutboxEnvelopeUnchecked(db, env))
    }
  }

  func testEnqueueCoalescedRejectsEnvelopeWithOversizedPayload() throws {
    try withDB { db in
      var env = makeEnvelope("task", "01966a3f-7c8b-7d4e-8f3a-000000002173", "1711234567890_0000_a1b2c3d4a1b2c3d4")
      env.payload = String(repeating: "x", count: SyncEnvelope.maxEnvelopePayloadBytes + 1)
      XCTAssertThrowsError(try Outbox.enqueueCoalesced(db, env))
      XCTAssertTrue(try Outbox.getPending(db).isEmpty)
    }
  }

  // MARK: - error wording parity (vs Rust `OutboxError` Display)

  func testOutboxErrorDescriptionMatchesRustDisplay() {
    XCTAssertEqual(
      Outbox.OutboxError.taintedVersion(entityType: .task, entityId: "t1", version: "seed").description,
      "outbox refused tainted incoming version for task/t1: version=\"seed\" failed Hlc::parse — caller must re-stamp")
    XCTAssertEqual(
      Outbox.OutboxError.contentionExhausted(entityType: .task, entityId: "t1", attempts: 4).description,
      "outbox coalesce retry budget exhausted for task/t1 after 4 attempts; the write was rolled back and must be retried")
  }

  // MARK: - dependency-edge wire-shape helpers

  func testDependencyEdgeEncodeEntityId() {
    XCTAssertEqual(DependencyEdge.encodeEntityId(taskId: "a", dependsOnTaskId: "b"), "a:b")
  }

  func testDependencyEdgeBuildDeletePayloadMatchesUpsertShape() {
    let payload = DependencyEdge.buildDeletePayload(
      taskId: "a", dependsOnTaskId: "b", version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
      createdAt: "2026-03-23T12:00:00.000Z")
    XCTAssertEqual(
      payload,
      .object([
        "task_id": .string("a"),
        "depends_on_task_id": .string("b"),
        "version": .string("1711234567890_0000_a1b2c3d4a1b2c3d4"),
        "created_at": .string("2026-03-23T12:00:00.000Z"),
      ]))
  }
}
