import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports `lorvex-sync::pending_inbox::tests/{attempt_cap, drain_fairness,
/// validation_quarantine, quarantine_blocklist, error_dedup_busy, redirect_remap}.rs`.
/// Drives the drain through the real default applier registry + apply pipeline.
final class PendingInboxDrainTests: XCTestCase {
  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  // MARK: - fixtures (mirror Rust support.rs)

  private func makeEnvelope(_ entityType: String, _ entityId: String) -> SyncEnvelope {
    if SyncEntityId.isCanonicalUuid(entityId) {
      return try! SyncTestSupport.completeEnvelope(
        entityType: EntityKind.parse(entityType)!, entityId: entityId, operation: .upsert,
        version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: 1, payload: #"{"title":"test"}"#, deviceId: "device-001")
    }
    return SyncEnvelope(
      entityType: EntityKind.parse(entityType)!, entityId: entityId, operation: .upsert,
      version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: 1, payload: #"{"title":"test"}"#, deviceId: "device-001")
  }

  private func makeReminderEnvelopeWithMissingTask(_ reminderId: String, _ taskId: String)
    -> SyncEnvelope
  {
    let canonicalID = SyncEntityId.isCanonicalUuid(reminderId)
      ? reminderId : fixtureUUID(seed: reminderId)
    return try! SyncTestSupport.completeEnvelope(
      entityType: .taskReminder, entityId: canonicalID, operation: .upsert,
      version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
      payloadSchemaVersion: 1,
      payload:
        #"{"task_id":"\#(taskId)","reminder_at":"2026-01-01T09:00:00Z","created_at":"2026-01-01T09:00:00Z"}"#,
      deviceId: "device-001")
  }

  private func fixtureUUID(seed: String) -> String {
    let hash = seed.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
      ($0 ^ UInt64($1)) &* 1_099_511_628_211
    }
    return String(format: "00000000-0000-7000-8000-%012llx", hash & 0xffff_ffff_ffff)
  }

  private func insertUnparseablePendingRow(
    _ db: Database, _ envelopeEntityType: String, _ envelopeEntityId: String, _ attemptCount: Int64
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (
            ?, ?, ?, ?, ?, ?, ?,
            '2026-03-27T09:00:00.000Z', '2026-03-27T09:00:00.000Z', ?
         )
        """,
      arguments: [
        #"{"entity_type":"task_reminder","entity_id":"broken""#, ResolutionName.fkUnresolved,
        EntityName.task, "01966a3f-7c8b-7d4e-8f3a-000000002189",
        envelopeEntityType, envelopeEntityId, "1711234567890_0000_a1b2c3d4a1b2c3d4", attemptCount,
      ])
  }

  private func countPending(_ db: Database) throws -> UInt64 {
    try PendingInbox.countPending(db)
  }

  private func exhaustedConflictCount(_ db: Database) throws -> Int64 {
    try Int64.fetchOne(
      db, sql: "SELECT COUNT(*) FROM sync_conflict_log WHERE resolution_type = ?",
      arguments: [ResolutionName.pendingInboxExhausted]) ?? 0
  }

  // MARK: - attempt_cap.rs

  func testDrainDiscardsEntryThatExceededAttemptCap() throws {
    try withDB { db in
      let env = self.makeReminderEnvelopeWithMissingTask(
        "reminder-stuck", "01966a3f-7c8b-7d4e-8f3a-000000002191")
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: EntityName.task, missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002191")
      try db.execute(
        sql: """
          UPDATE sync_pending_inbox
          SET attempt_count = ?, last_attempted_at = '2020-01-01T00:00:00.000Z'
          """,
        arguments: [PendingInbox.maxAttempts - 1])

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(summary.discarded, 1)
      XCTAssertEqual(try self.countPending(db), 0)
      XCTAssertEqual(try self.exhaustedConflictCount(db), 1)
    }
  }

  func testSchemaTooNewDeferralDoesNotConsumeRetryBudget() throws {
    try withDB { db in
      var env = self.makeEnvelope(EntityName.task, "01966a3f-7c8b-7d4e-8f3a-0000000021f0")
      env.payloadSchemaVersion = LorvexVersion.payloadSchemaVersion + 2
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: "schema_too_new",
        missingEntityType: nil, missingEntityID: nil)
      let before = try PendingInbox.getAllPending(db).first?.attemptCount

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)

      XCTAssertEqual(summary.replayed, 0)
      XCTAssertEqual(summary.discarded, 0)
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending.first?.attemptCount, before)
      XCTAssertTrue(pending.first?.reason.contains("schema") == true)
    }
  }

  func testSchemaTooNewDuplicateEnqueueDoesNotConsumeRetryBudget() throws {
    try withDB { db in
      var env = self.makeEnvelope(EntityName.task, "01966a3f-7c8b-7d4e-8f3a-0000000021f1")
      env.payloadSchemaVersion = LorvexVersion.payloadSchemaVersion + 2
      for _ in 0..<5 {
        try PendingInboxDrain.enqueueDeferred(
          db,
          envelope: env,
          reason: .schemaTooNew(
            remoteVersion: env.payloadSchemaVersion,
            localVersion: LorvexVersion.payloadSchemaVersion))
      }

      let pending = try PendingInbox.getAllPending(db)

      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending.first?.attemptCount, 1)
      XCTAssertTrue(pending.first?.reason.contains("payload_schema_version") == true)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 1)
    }
  }

  func testSchemaTooNewDuplicateEnqueueAtAttemptCapIsStillHeld() throws {
    try withDB { db in
      var env = self.makeEnvelope(EntityName.task, "01966a3f-7c8b-7d4e-8f3a-0000000021f2")
      env.payloadSchemaVersion = LorvexVersion.payloadSchemaVersion + 2
      try PendingInboxDrain.enqueueDeferred(
        db,
        envelope: env,
        reason: .schemaTooNew(
          remoteVersion: env.payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))
      try db.execute(
        sql: "UPDATE sync_pending_inbox SET attempt_count = ?",
        arguments: [PendingInbox.maxAttempts])

      try PendingInboxDrain.enqueueDeferred(
        db,
        envelope: env,
        reason: .schemaTooNew(
          remoteVersion: env.payloadSchemaVersion,
          localVersion: LorvexVersion.payloadSchemaVersion))

      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending.first?.attemptCount, PendingInbox.maxAttempts)
      XCTAssertEqual(try self.exhaustedConflictCount(db), 0)
      let blocklisted = try PendingInboxDrain.isQuarantined(
        db,
        entityType: env.entityType.asString,
        entityID: env.entityId,
        version: env.version.description)
      XCTAssertFalse(blocklisted)
    }
  }

  /// An `aggregateInvariantBlocked` deferral is a by-design HOLD, not a failing
  /// retry. A duplicate enqueue must NOT bump `attempt_count` toward
  /// the cap, or a task-holding peer would raise a false `pending_inbox_exhausted`
  /// / `reseed_required` for a correct standing refusal.
  func testAggregateInvariantBlockedDuplicateEnqueueDoesNotConsumeRetryBudget() throws {
    try withDB { db in
      let env = SyncEnvelope(
        entityType: .list, entityId: "protected-list", operation: .delete,
        version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: 1, payload: "{}", deviceId: "device-001")
      for _ in 0..<5 {
        try PendingInboxDrain.enqueueDeferred(
          db, envelope: env,
          reason: .aggregateInvariantBlocked(
            entityType: .list, entityId: "protected-list", invariant: "at_least_one_list"))
      }
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(
        pending.first?.attemptCount, 1, "an invariant-blocked hold must not burn the retry budget")
      XCTAssertEqual(
        try PendingInboxDrain.unresolvedFutureRecordCount(db), 0,
        "a current-schema standing refusal remains representable in a candidate snapshot")
    }
  }

  /// A legacy/future pending copy of `delete(inbox)` is not allowed to sit in a
  /// permanent retry loop. Drain removes it and surfaces the same typed repair
  /// obligation as direct inbound apply; the host fulfills that obligation in
  /// the surrounding transaction before acknowledging progress.
  func testPendingInboxDeleteDrainSurfacesAndFulfillsTypedRepair() throws {
    try withDB { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at)
          VALUES (?, 't', 'open', 'inbox', ?, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """,
        arguments: [
          "01966a3f-7c8b-7d4e-8f3a-000000003001", "1711234567890_0000_a1b2c3d4a1b2c3d4",
        ])
      let env = try SyncTestSupport.completeEnvelope(
        entityType: .list, entityId: "inbox", operation: .delete,
        version: try Hlc.parse("1711234599999_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: 1, payload: "{}", deviceId: "device-001")
      try PendingInboxDrain.enqueueDeferred(
        db, envelope: env,
        reason: .aggregateInvariantBlocked(
          entityType: .list, entityId: "inbox", invariant: "at_least_one_list"))

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(
        summary.repairObligations,
        [.reassertRequiredInbox(remoteDeleteVersion: env.version)])
      XCTAssertTrue(try PendingInbox.getAllPending(db).isEmpty)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql:
            "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'list' AND entity_id = 'inbox'"),
        0)

      let clock = try HlcState(deviceSuffix: "cccccccccccccccc")
      try ApplyRepair.fulfill(
        db, obligation: try XCTUnwrap(summary.repairObligations.first),
        mintVersion: { floor in
          if let floor {
            clock.updateOnReceive(remote: floor, physicalMs: 2_000_000_000_000)
          }
          return clock.generate(withPhysicalMs: 2_000_000_000_000).description
        }, deviceId: "device-local")
      let repair = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version FROM sync_outbox
            WHERE entity_type = 'list' AND entity_id = 'inbox' AND synced_at IS NULL
            """))
      XCTAssertEqual(repair["operation"] as String, SyncNaming.opUpsert)
      XCTAssertGreaterThan(try Hlc.parse(repair["version"] as String), env.version)
    }
  }

  /// A parked future-OPERATION record (known entity_type, an operation this build
  /// does not know, on a forward-compat schema) must be HELD by the drain like a
  /// future entity_type — never quarantined — so a future build that adds the
  /// operation still applies it instead of losing it.
  func testHeldFutureOperationRecordNotQuarantinedByDrain() throws {
    try withDB { db in
      let raw = RawEnvelopeFields(
        entityType: EntityName.task, entityId: "01966a3f-7c8b-7d4e-8f3a-000000004001",
        operation: "archive",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
        payload: #"{"title":"t"}"#, deviceId: "device-001")
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: raw)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 1)
      let before = try PendingInbox.getAllPending(db).first?.attemptCount

      for _ in 0..<3 {
        _ = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      }

      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1, "a future-operation record must be HELD, not quarantined")
      XCTAssertEqual(pending.first?.attemptCount, before, "the hold must not bump attempt_count")
      XCTAssertEqual(
        try self.exhaustedConflictCount(db), 0, "a held future record is never quarantined")
    }
  }

  func testEnqueuePendingCoalescesDuplicateEnvelopes() throws {
    try withDB { db in
      let env = self.makeEnvelope(EntityName.taskReminder, "reminder-coalesce")
      for _ in 0..<5 {
        try PendingInboxDrain.enqueuePending(
          db, envelope: env, reason: ResolutionName.fkUnresolved,
          missingEntityType: EntityName.task,
          missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002189")
      }
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].attemptCount, 5)
    }
  }

  func testEnqueuePendingDistinguishesEnvelopesByVersion() throws {
    try withDB { db in
      var env = self.makeEnvelope(EntityName.taskReminder, "reminder-multi")
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: nil, missingEntityID: nil)
      env.version = try Hlc.parse("1711234999999_0001_deadbeefdeadbeef")
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: nil, missingEntityID: nil)
      XCTAssertEqual(try self.countPending(db), 2)
    }
  }

  func testDrainKeepsEntryBelowAttemptCap() throws {
    try withDB { db in
      let env = self.makeReminderEnvelopeWithMissingTask(
        "reminder-still-trying", "01966a3f-7c8b-7d4e-8f3a-000000002189")
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: EntityName.task, missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002189")
      try db.execute(
        sql:
          "UPDATE sync_pending_inbox SET last_attempted_at = '2020-01-01T00:00:00.000Z'")

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(summary.discarded, 0)
      XCTAssertEqual(try self.countPending(db), 1)
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending[0].attemptCount, 2)
    }
  }

  // MARK: - drain_fairness.rs

  func testDrainReachesOldParentAfterFirstCappedChildBatch() throws {
    try withDB { db in
      let parentTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000218d"
      for idx in 0..<500 {
        let env = self.makeReminderEnvelopeWithMissingTask(
          String(format: "reminder-capped-prefix-%03d", idx), parentTaskId)
        try PendingInboxDrain.enqueuePending(
          db, envelope: env, reason: ResolutionName.fkUnresolved,
          missingEntityType: EntityName.task, missingEntityID: parentTaskId)
      }
      let parent = try SyncTestSupport.completeEnvelope(
        entityType: .task, entityId: parentTaskId, operation: .upsert,
        version: try Hlc.parse("1711234569999_0000_b1b2c3d4b1b2c3d4"), payloadSchemaVersion: 1,
        payload:
          #"{"title":"Recovered parent","status":"open","defer_count":0,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}"#,
        deviceId: "device-001")
      try PendingInboxDrain.enqueuePending(
        db, envelope: parent, reason: "queued_parent", missingEntityType: nil, missingEntityID: nil)
      try db.execute(
        sql: """
          UPDATE sync_pending_inbox
          SET first_attempted_at = '2026-01-01T00:00:00.000Z',
              last_attempted_at = '2026-01-01T00:00:00.000Z'
          """)

      let first = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(first.replayed, 0)
      let second = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertGreaterThanOrEqual(second.replayed, 1)
      let parentCount =
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [parentTaskId])
        ?? 0
      XCTAssertEqual(parentCount, 1)
    }
  }

  // MARK: - validation_quarantine.rs

  func testDrainQuarantinesUnparseableEnvelopeAndContinues() throws {
    try withDB { db in
      try self.insertUnparseablePendingRow(db, EntityName.taskReminder, "broken", 1)
      let env = self.makeReminderEnvelopeWithMissingTask(
        "reminder-after-poison", "01966a3f-7c8b-7d4e-8f3a-0000000021a2")
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: EntityName.task, missingEntityID: "01966a3f-7c8b-7d4e-8f3a-0000000021a2")
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: "01966a3f-7c8b-7d4e-8f3a-0000000021a2",
        version: "1711234999999_0000_deadbeefdeadbeef", deletedAt: "2026-03-27T11:00:00.000Z")

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(summary.discarded, 1)
      XCTAssertGreaterThanOrEqual(summary.errors, 1)

      let unparseableLogs =
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = ?",
          arguments: ["sync.pending_inbox.unparseable_envelope"]) ?? 0
      XCTAssertGreaterThanOrEqual(unparseableLogs, 1)

      let poisonAttempt =
        try Int64.fetchOne(
          db, sql: "SELECT attempt_count FROM sync_pending_inbox WHERE envelope_entity_id = 'broken'")
        ?? 0
      XCTAssertEqual(poisonAttempt, PendingInbox.maxAttempts)
    }
  }

  func testDrainQuarantinesAtCapUnparseableEnvelopeToConflictLog() throws {
    try withDB { db in
      try self.insertUnparseablePendingRow(
        db, EntityName.taskReminder, "broken-at-cap", PendingInbox.maxAttempts)
      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(summary.discarded, 1)
      XCTAssertEqual(try self.countPending(db), 0)
      XCTAssertEqual(try self.exhaustedConflictCount(db), 1)
    }
  }

  func testEnqueuePendingRejectsMalformedPayloadJson() throws {
    try withDB { db in
      let env = SyncEnvelope(
        entityType: .taskReminder, entityId: "01966a3f-7c8b-7d4e-8f3a-00000000214d",
        operation: .upsert, version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: 1, payload: #"{"task_id":"01966a3f-7c8b-7d4e-8f3a-000000002188""#,
        deviceId: "device-001")
      XCTAssertThrowsError(
        try PendingInboxDrain.enqueuePending(
          db, envelope: env, reason: ResolutionName.fkUnresolved,
          missingEntityType: EntityName.task, missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002188")
      ) { error in
        // A structural JSON parse failure must classify as `.malformedPayload`,
        // not be mislabeled as an over-deep-but-valid `.canonicalization` payload.
        guard case EnqueueError.malformedPayload = error else {
          XCTFail("expected malformedPayload, got \(error)")
          return
        }
      }
      XCTAssertEqual(try self.countPending(db), 0)
    }
  }

  func testEnqueuePendingRejectsOverlyNestedPayload() throws {
    try withDB { db in
      let depth = SyncCanonicalize.maxJSONDepth + 2
      var deep = ""
      for _ in 0..<depth { deep += #"{"x":"# }
      deep += "1"
      for _ in 0..<depth { deep += "}" }
      let env = SyncEnvelope(
        entityType: .task, entityId: "01966a3f-7c8b-7d4e-8f3a-00000000217b", operation: .upsert,
        version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"), payloadSchemaVersion: 1,
        payload: deep, deviceId: "device-001")
      XCTAssertThrowsError(
        try PendingInboxDrain.enqueuePending(
          db, envelope: env, reason: ResolutionName.fkUnresolved,
          missingEntityType: nil, missingEntityID: nil)
      ) { error in
        // `JSONValue.parse` enforces the same depth cap as the canonicalizer, so
        // a payload nested beyond the cap is rejected at the parse boundary as
        // `.malformedPayload` and never reaches canonicalization.
        guard case EnqueueError.malformedPayload = error else {
          XCTFail("expected malformedPayload, got \(error)")
          return
        }
      }
      XCTAssertEqual(try self.countPending(db), 0)
    }
  }

  // MARK: - quarantine_blocklist.rs

  func testEnqueuePendingShortCircuitsQuarantinedIdentity() throws {
    try withDB { db in
      let env = self.makeEnvelope(EntityName.taskReminder, "reminder-poison")
      try PendingInboxDrain.recordQuarantine(
        db, entityType: env.entityType.asString, entityID: env.entityId,
        version: env.version.description)
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: EntityName.task, missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002189")
      XCTAssertTrue(try PendingInbox.getAllPending(db).isEmpty)
    }
  }

  func testEnqueuePendingRecordsBlocklistWhenCapPromotes() throws {
    try withDB { db in
      let env = self.makeEnvelope(EntityName.taskReminder, "reminder-cap")
      for _ in 0..<Int(PendingInbox.maxAttempts) {
        try PendingInboxDrain.enqueuePending(
          db, envelope: env, reason: ResolutionName.fkUnresolved,
          missingEntityType: EntityName.task,
          missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002189")
      }
      XCTAssertTrue(try PendingInbox.getAllPending(db).isEmpty)
      let blocklisted = try PendingInboxDrain.isQuarantined(
        db, entityType: env.entityType.asString, entityID: env.entityId,
        version: env.version.description)
      XCTAssertTrue(blocklisted)

      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: EntityName.task, missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002189")
      XCTAssertTrue(try PendingInbox.getAllPending(db).isEmpty)
    }
  }

  func testRecordQuarantinePreservesFirstObservedRow() throws {
    try withDB { db in
      try PendingInboxDrain.recordQuarantine(
        db, entityType: EntityName.task, entityID: "01966a3f-7c8b-7d4e-8f3a-000000002192",
        version: "0000000000001_0000_0000000000000001")
      let first = try Row.fetchOne(
        db,
        sql: """
          SELECT quarantined_at FROM sync_quarantine_blocklist
          WHERE entity_type = ? AND entity_id = ? AND version = ?
          """,
        arguments: [EntityName.task, "01966a3f-7c8b-7d4e-8f3a-000000002192", "0000000000001_0000_0000000000000001"])!
      let firstAt: String = first["quarantined_at"]

      Thread.sleep(forTimeInterval: 0.005)
      try PendingInboxDrain.recordQuarantine(
        db, entityType: EntityName.task, entityID: "01966a3f-7c8b-7d4e-8f3a-000000002192",
        version: "0000000000001_0000_0000000000000001")
      let second = try Row.fetchOne(
        db,
        sql: """
          SELECT quarantined_at FROM sync_quarantine_blocklist
          WHERE entity_type = ? AND entity_id = ? AND version = ?
          """,
        arguments: [EntityName.task, "01966a3f-7c8b-7d4e-8f3a-000000002192", "0000000000001_0000_0000000000000001"])!
      let secondAt: String = second["quarantined_at"]

      XCTAssertEqual(firstAt, secondAt)
    }
  }

  // MARK: - error_dedup_busy.rs

  func testBusyOrLockedApplyFailureClassification() throws {
    let busy = ApplyError.dbBusyOrLocked("database is locked")
    let locked = ApplyError.dbBusyOrLocked("database table is locked")
    let permanent = ApplyError.invalidPayload("bad")
    XCTAssertTrue(PendingInboxDrain.isTransientBusyOrLocked(busy))
    XCTAssertTrue(PendingInboxDrain.isTransientBusyOrLocked(locked))
    XCTAssertFalse(PendingInboxDrain.isTransientBusyOrLocked(permanent))

    try withDB { db in
      let env = self.makeEnvelope(EntityName.taskReminder, "reminder-busy")
      try PendingInboxDrain.enqueuePending(
        db, envelope: env, reason: ResolutionName.fkUnresolved,
        missingEntityType: EntityName.task, missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002189")
      let initial =
        try Int64.fetchOne(db, sql: "SELECT attempt_count FROM sync_pending_inbox LIMIT 1") ?? 0
      let initialTs =
        try String.fetchOne(db, sql: "SELECT last_attempted_at FROM sync_pending_inbox LIMIT 1") ?? ""
      Thread.sleep(forTimeInterval: 0.025)
      let entryId = try Int64.fetchOne(db, sql: "SELECT id FROM sync_pending_inbox LIMIT 1")!
      try PendingInbox.recordReattemptBusy(db, id: entryId)
      let after =
        try Int64.fetchOne(
          db, sql: "SELECT attempt_count FROM sync_pending_inbox WHERE id = ?", arguments: [entryId])
        ?? 0
      let afterTs =
        try String.fetchOne(
          db, sql: "SELECT last_attempted_at FROM sync_pending_inbox WHERE id = ?",
          arguments: [entryId]) ?? ""
      XCTAssertEqual(after, initial)
      XCTAssertGreaterThan(afterTs, initialTs)
    }
  }

  // MARK: - redirect_remap.rs

  private func taskTagEnvelope(_ taskId: String, _ tagId: String) -> SyncEnvelope {
    try! SyncTestSupport.completeEnvelope(
      entityType: .taskTag, entityId: "\(taskId):\(tagId)", operation: .upsert,
      version: try! Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"), payloadSchemaVersion: 1,
      payload: #"{"created_at":"2026-03-27T09:00:00Z"}"#, deviceId: "device-001")
  }

  func testDrainRemapsCompositeRedirectViaEntityIdWhenPayloadLacksFkFields() throws {
    try withDB { db in
      try PendingInboxDrain.enqueuePending(
        db,
        envelope: SyncEnvelope(
          entityType: .taskTag,
          entityId:
            "01966a3f-7c8b-7d4e-8f3a-000000002163:01966a3f-7c8b-7d4e-8f3a-000000002161",
          operation: .upsert, version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
          payloadSchemaVersion: 1, payload: #"{"created_at":"2026-03-27T09:00:00Z"}"#,
          deviceId: "device-001"),
        reason: ResolutionName.fkUnresolved, missingEntityType: EntityName.tag,
        missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002161")
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag,
        sourceId: "01966a3f-7c8b-7d4e-8f3a-000000002161",
        targetId: "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        version: "1711234569000_0000_deadbeefdeadbeef")

      XCTAssertNoThrow(try PendingInboxDrain.drainPendingInbox(db, registry: self.registry))
    }
  }

  func testDrainCoalescesIdentityCollisionAfterRedirectRemap() throws {
    let redirectTaskId = "01966a3f-7c8b-7d4e-8f3a-000000002163"
    let redirectOldTagId = "01966a3f-7c8b-7d4e-8f3a-000000002161"
    let redirectNewTagId = "01966a3f-7c8b-7d4e-8f3a-00000000215f"
    let redirectEdgeVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
    try withDB { db in
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Merged tag', 'merged tag', ?, '2026-03-27T09:00:00Z', '2026-03-27T09:00:00Z')
          """,
        arguments: [redirectNewTagId, "1711234569000_0000_deadbeefdeadbeef"])

      try PendingInboxDrain.enqueuePending(
        db, envelope: self.taskTagEnvelope(redirectTaskId, redirectNewTagId),
        reason: ResolutionName.fkUnresolved, missingEntityType: EntityName.task,
        missingEntityID: redirectTaskId)
      try PendingInboxDrain.enqueuePending(
        db, envelope: self.taskTagEnvelope(redirectTaskId, redirectOldTagId),
        reason: ResolutionName.fkUnresolved, missingEntityType: EntityName.tag,
        missingEntityID: redirectOldTagId)
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: redirectOldTagId, targetId: redirectNewTagId,
        version: "1711234569000_0000_deadbeefdeadbeef")

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(summary.errors, 0)
      XCTAssertEqual(summary.remapped, 1)
      XCTAssertEqual(try self.countPending(db), 1)

      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT envelope_entity_type, envelope_entity_id, envelope_version,
                 missing_entity_type, missing_entity_id, attempt_count
          FROM sync_pending_inbox
          """)!
      XCTAssertEqual(row["envelope_entity_type"] as String, EdgeName.taskTag)
      XCTAssertEqual(row["envelope_entity_id"] as String, "\(redirectTaskId):\(redirectNewTagId)")
      XCTAssertEqual(row["envelope_version"] as String, redirectEdgeVersion)
      XCTAssertEqual(row["missing_entity_type"] as String?, EntityName.task)
      XCTAssertEqual(row["missing_entity_id"] as String?, redirectTaskId)
      // The two source rows each start at attempt_count 1 and the collision fold
      // keeps MAX(1, 1) = 1; the still-deferred re-attempt bump is time-gated
      // (``PendingInboxDrain/attemptBumpMinInterval``) and does not fire within
      // the same drain instant, so the merged row stays at 1.
      XCTAssertEqual(row["attempt_count"] as Int64, 1)
    }
  }

  func testDrainDiscardsMalformedCompositeRedirectEntityId() throws {
    try withDB { db in
      try PendingInboxDrain.enqueuePending(
        db,
        envelope: SyncEnvelope(
          entityType: .taskTag,
          entityId:
            "01966a3f-7c8b-7d4e-8f3a-000000002163:01966a3f-7c8b-7d4e-8f3a-000000002161:extra",
          operation: .upsert, version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"),
          payloadSchemaVersion: 1, payload: #"{"created_at":"2026-03-27T09:00:00Z"}"#,
          deviceId: "device-001"),
        reason: ResolutionName.fkUnresolved, missingEntityType: EntityName.tag,
        missingEntityID: "01966a3f-7c8b-7d4e-8f3a-000000002161")
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag,
        sourceId: "01966a3f-7c8b-7d4e-8f3a-000000002161",
        targetId: "01966a3f-7c8b-7d4e-8f3a-00000000215f",
        version: "1711234569000_0000_deadbeefdeadbeef")

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(summary.discarded, 1)
      XCTAssertEqual(try self.countPending(db), 0)
    }
  }

  // MARK: - entity_type_too_new (S-4 forward-compat HOLD)

  /// A well-formed envelope carrying a FUTURE entity_type the build cannot parse
  /// is HELD by the drain, never quarantined: `attempt_count` stays put (so the
  /// per-row cap can't shed it), the row survives, and nothing lands in the
  /// poison blocklist. It can only leave via the horizon GC.
  func testDrainHoldsUnknownEntityTypeRowWithoutQuarantine() throws {
    try withDB { db in
      let raw = RawEnvelopeFields(
        entityType: "quantum_widget",
        entityId: "01966a3f-7c8b-7d4e-8f3a-000000003001",
        operation: "upsert",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
        payloadSchemaVersion: 1,
        payload: #"{"q":1}"#,
        deviceId: "device-001")
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: raw)

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(summary.discarded, 0)
      XCTAssertEqual(summary.replayed, 0)

      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      // Retry budget untouched — the unknown-type lane never bumps attempt_count.
      XCTAssertEqual(pending.first?.attemptCount, 1)
      XCTAssertEqual(pending.first?.reason, "entity_type_too_new")

      // Not treated as poison: no unparseable-envelope log, not blocklisted.
      let unparseableLogs =
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM error_logs WHERE source = ?",
          arguments: ["sync.pending_inbox.unparseable_envelope"]) ?? 0
      XCTAssertEqual(unparseableLogs, 0)
      let blocklisted = try PendingInboxDrain.isQuarantined(
        db, entityType: "quantum_widget", entityID: "01966a3f-7c8b-7d4e-8f3a-000000003001",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4")
      XCTAssertFalse(blocklisted)
    }
  }

  /// Re-delivering the same unknown-type record keeps a single HELD row whose
  /// `attempt_count` never climbs (HOLD semantics, mirrors schema_too_new).
  func testHoldUnknownTypeCoalescesRedeliveryWithoutBumpingAttempts() throws {
    try withDB { db in
      let raw = RawEnvelopeFields(
        entityType: "quantum_widget",
        entityId: "01966a3f-7c8b-7d4e-8f3a-000000003005",
        operation: "upsert",
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
        payloadSchemaVersion: 1,
        payload: #"{"q":1}"#,
        deviceId: "device-001")
      for _ in 0..<5 {
        try PendingInboxDrain.holdUnknownTypeRecord(db, raw: raw)
      }
      let pending = try PendingInbox.getAllPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending.first?.attemptCount, 1)
    }
  }

  /// On a later build whose `EntityKind` includes the type, the SAME parked row
  /// (reason `entity_type_too_new`) now deserializes and the apply path runs —
  /// the deferred data is recovered, not lost. Simulated by parking a row whose
  /// stored type is one this build already understands.
  func testDrainAppliesHeldUnknownTypeRowOnceTypeBecomesKnown() throws {
    let taskId = "01966a3f-7c8b-7d4e-8f3a-000000003002"
    try withDB { db in
      let envelopeJSON = try PendingInboxDrain.serializeEnvelope(
        try SyncTestSupport.completeEnvelope(
          entityType: .task, entityId: taskId, operation: .upsert,
          version: try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4"), payloadSchemaVersion: 1,
          payload:
            #"{"title":"unfrozen","status":"open","defer_count":0,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"}"#,
          deviceId: "device-001"))
      try db.execute(
        sql: """
          INSERT INTO sync_pending_inbox (
              envelope, reason, missing_entity_type, missing_entity_id,
              envelope_entity_type, envelope_entity_id, envelope_version,
              first_attempted_at, last_attempted_at, attempt_count
           ) VALUES (
              ?, 'entity_type_too_new', NULL, NULL,
              'task', ?, '1711234567890_0000_a1b2c3d4a1b2c3d4',
              '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z', 1
           )
          """,
        arguments: [envelopeJSON, taskId])

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertGreaterThanOrEqual(summary.replayed, 1)
      XCTAssertEqual(try self.countPending(db), 0)
      let taskCount =
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [taskId])
        ?? 0
      XCTAssertEqual(taskCount, 1)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 0)
    }
  }

  func testNewlyUnderstoodFutureRecordKeepsProvenanceUntilDependencyArrives() throws {
    let taskId = "01966a3f-7c8b-7d4e-8f3a-000000003010"
    let reminderId = "01966a3f-7c8b-7d4e-8f3a-000000003011"
    try withDB { db in
      let envelope = self.makeReminderEnvelopeWithMissingTask(reminderId, taskId)
      try PendingInboxDrain.enqueuePending(
        db, envelope: envelope, reason: PendingInboxDrain.entityTypeTooNewReason,
        missingEntityType: nil, missingEntityID: nil)

      let waiting = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(waiting.replayed, 0)
      let held = try XCTUnwrap(PendingInbox.getAllPending(db).first)
      XCTAssertEqual(held.reason, PendingInboxDrain.entityTypeTooNewReason)
      XCTAssertEqual(held.missingEntityType, EntityName.task)
      XCTAssertEqual(held.missingEntityID, taskId)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 1)

      try db.execute(
        sql: """
          INSERT INTO tasks
              (id, list_id, title, status, version, created_at, updated_at)
          VALUES (?, 'inbox', 'dependency', 'open', ?,
                  '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')
          """,
        arguments: [taskId, "1711234567000_0000_b1c2d3e4b1c2d3e4"])
      let replayed = try PendingInboxDrain.drainPendingInbox(db, registry: self.registry)
      XCTAssertEqual(replayed.replayed, 1)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 0)
    }
  }
}
