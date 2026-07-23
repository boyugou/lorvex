import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class FutureRecordHoldTests: XCTestCase {
  private let taskID = "01966a3f-7c8b-7d4e-8f3a-00000000f001"
  private let v1 = "1711234567000_0000_1111111111111111"
  private let v2 = "1711234568000_0000_2222222222222222"
  private let v3 = "1711234569000_0000_3333333333333333"
  private let v4 = "1711234570000_0000_4444444444444444"
  private let v5 = "1711234571000_0000_5555555555555555"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func seedTask(
    _ db: Database, title: String, version: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks
            (id, list_id, title, status, defer_count,
             content_version, schedule_version, lifecycle_version, archive_version,
             version, created_at, updated_at)
        VALUES (?, 'inbox', ?, 'open', 0, ?, ?, ?, ?, ?,
                '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
        """,
      arguments: [taskID, title, version, version, version, version, version])
  }

  private func taskPayload(title: String, version: String) throws -> JSONValue {
    .object([
      "id": .string(taskID),
      "list_id": .string("inbox"),
      "title": .string(title),
      "status": .string("open"),
      "defer_count": .int(0),
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(version),
    ])
  }

  private func typedTask(title: String, version: String) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: taskID, operation: .upsert,
      version: try Hlc.parseCanonical(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        taskPayload(title: title, version: version)),
      deviceId: "future-hold-test-remote")
  }

  private func rawFuture(version: String) -> RawEnvelopeFields {
    RawEnvelopeFields(
      entityType: EntityName.task, entityId: taskID,
      operation: "future_upsert", version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: #"{"future_shape":true}"#, deviceId: "future-hold-test-remote")
  }

  private func enqueueCurrentTask(
    _ db: Database, version: String, registerIntent: TaskRegisterIntent
  ) throws {
    try db.execute(
      sql: """
        UPDATE tasks SET
          content_version = CASE WHEN :content THEN :version ELSE content_version END,
          schedule_version = CASE WHEN :schedule THEN :version ELSE schedule_version END,
          lifecycle_version = CASE WHEN :lifecycle THEN :version ELSE lifecycle_version END,
          archive_version = CASE WHEN :archive THEN :version ELSE archive_version END,
          version = :version
        WHERE id = :id
        """,
      arguments: [
        "content": registerIntent.contains(.content) ? 1 : 0,
        "schedule": registerIntent.contains(.schedule) ? 1 : 0,
        "lifecycle": registerIntent.contains(.lifecycle) ? 1 : 0,
        "archive": registerIntent.contains(.archive) ? 1 : 0,
        "version": version, "id": taskID,
      ])
    let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: EntityName.task, entityId: taskID)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: EntityName.task, entityId: taskID, payload: payload,
      context: OutboxWriteContext(
        version: version, deviceId: "future-hold-test-local",
        registerIntent: .task(registerIntent)))
  }

  private func operationalBoundaryVersion(offset: UInt64) throws -> String {
    try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs + offset,
      counter: 0, deviceSuffix: "eeeeeeeeeeeeeeee").description
  }

  func testOperationalBoundaryIsAcceptedButBoundaryPlusOneIsPermanentlyHeld() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "before", version: v1)
      let boundary = try operationalBoundaryVersion(offset: 0)
      let accepted = try typedTask(title: "at boundary", version: boundary)
      XCTAssertEqual(
        try Apply.applyEnvelope(db, registry: registry, envelope: accepted), .applied)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskID]),
        boundary)

      try enqueueCurrentTask(db, version: boundary, registerIntent: .all)
      let heldVersion = try operationalBoundaryVersion(offset: 1)
      let held = try typedTask(title: "must stay parked", version: heldVersion)
      let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: held)
      guard case .deferred(let reason) = outcome,
        case .operationallyUnusableHlc = reason
      else { return XCTFail("cap+1 must enter the typed clock hold") }
      try PendingInboxDrain.enqueueDeferred(db, envelope: held, reason: reason)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskID]),
        "at boundary")
      XCTAssertTrue(try Outbox.getPending(db).isEmpty)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 1)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT future_record_version FROM sync_outbox WHERE entity_id = ?",
          arguments: [taskID]),
        heldVersion)

      // A later drain applies the same static boundary and cannot mature merely
      // because time or retry count advanced.
      _ = try PendingInboxDrain.drainPendingInbox(db, registry: registry)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 1)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskID]),
        "at boundary")
    }
  }

  func testFutureHoldFencesExistingIntentAndRollsBackLaterLocalMutation() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "before", version: v1)
      try enqueueCurrentTask(db, version: v1, registerIntent: .all)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: rawFuture(version: v2))

      let fence = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT disposition, future_record_version
            FROM sync_outbox WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.task, taskID]))
      XCTAssertEqual(
        fence["disposition"] as String?,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(fence["future_record_version"] as String?, v2)
      XCTAssertTrue(try Outbox.getPending(db).isEmpty)
    }

    XCTAssertThrowsError(
      try store.writer.write { db in
        try db.execute(
          sql: "UPDATE tasks SET title = ? WHERE id = ?",
          arguments: ["must roll back", taskID])
        try enqueueCurrentTask(db, version: v3, registerIntent: .content)
      }
    ) { error in
      guard case EnqueueError.futureRecordRequiresNewerApp(
        let entityType, let entityId, let heldVersion) = error
      else { return XCTFail("unexpected error: \(error)") }
      XCTAssertEqual(entityType, EntityName.task)
      XCTAssertEqual(entityId, taskID)
      XCTAssertEqual(heldVersion, v2)
    }

    try store.writer.read { db in
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskID]),
        "before")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM sync_outbox WHERE entity_id = ?", arguments: [taskID]),
        v1)
    }
  }

  func testOrdinaryDependencyDeferralDoesNotBlockLocalWrite() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "before", version: v1)
      try PendingInboxDrain.enqueuePending(
        db, envelope: try typedTask(title: "waiting", version: v2),
        reason: "missing dependency", missingEntityType: EntityName.list,
        missingEntityID: "01966a3f-7c8b-7d4e-8f3a-00000000f099")
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?", arguments: ["allowed", taskID])
      try enqueueCurrentTask(db, version: v3, registerIntent: .content)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskID]),
        "allowed")
    }
  }

  func testPermanentFutureFenceSurvivesOrdinaryOutboxGcAndBacklogCap() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "local", version: v1)
      try enqueueCurrentTask(db, version: v1, registerIntent: .all)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: rawFuture(version: v2))
      try db.execute(
        sql: "UPDATE sync_outbox SET created_at = '2020-01-01T00:00:00.000Z' WHERE entity_id = ?",
        arguments: [taskID])

      XCTAssertEqual(try Outbox.gcSynced(db, retentionDays: 1), 0)
      XCTAssertEqual(try Outbox.gcUnsyncedBeyondCap(db, maxRows: 0), 0)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT disposition FROM sync_outbox WHERE entity_id = ?",
          arguments: [taskID]),
        Outbox.Disposition.futureRecordHold.rawValue)
    }
  }

  func testUnderstoodRemoteWinnerDiscardsOldIntentAndAllOlderProvenance() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "local", version: v1)
      try enqueueCurrentTask(db, version: v1, registerIntent: .all)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: rawFuture(version: v2))
      try PendingInboxDrain.enqueuePending(
        db, envelope: try typedTask(title: "remote", version: v3),
        reason: PendingInboxDrain.entityTypeTooNewReason,
        missingEntityType: nil, missingEntityID: nil, countsTowardRetryBudget: false)

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: registry)
      XCTAssertEqual(summary.replayed, 1)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 0)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskID]),
        "remote")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?", arguments: [taskID]),
        0)
    }
  }

  func testLocalWinnerIsRebuiltFromCanonicalRowAtCurrentSchema() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "canonical local", version: v4)
      try enqueueCurrentTask(db, version: v4, registerIntent: .all)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: rawFuture(version: v2))
      try PendingInboxDrain.enqueuePending(
        db, envelope: try typedTask(title: "older remote", version: v3),
        reason: PendingInboxDrain.entityTypeTooNewReason,
        missingEntityType: nil, missingEntityID: nil, countsTowardRetryBudget: false)

      let summary = try PendingInboxDrain.drainPendingInbox(db, registry: registry)
      XCTAssertEqual(summary.skipped, 1)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 0)
      let rebuilt = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, payload_schema_version, payload, disposition,
                   future_record_version
            FROM sync_outbox WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.task, taskID]))
      XCTAssertEqual(rebuilt["version"] as String, v4)
      XCTAssertEqual(rebuilt["payload_schema_version"] as Int64, Int64(LorvexVersion.payloadSchemaVersion))
      XCTAssertNil(rebuilt["disposition"] as String?)
      XCTAssertNil(rebuilt["future_record_version"] as String?)
      let payload = try XCTUnwrap(JSONValue.parse(rebuilt["payload"] as String))
      guard case .object(let object) = payload else { return XCTFail("payload is not an object") }
      XCTAssertEqual(object["title"], .string("canonical local"))
    }
  }

  func testLowerUnderstoodEnvelopeCannotClearHigherFutureHold() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "canonical local", version: v4)
      try enqueueCurrentTask(db, version: v4, registerIntent: .all)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: rawFuture(version: v5))
      try PendingInboxDrain.enqueuePending(
        db, envelope: try typedTask(title: "older remote", version: v3),
        reason: PendingInboxDrain.entityTypeTooNewReason,
        missingEntityType: nil, missingEntityID: nil, countsTowardRetryBudget: false)

      _ = try PendingInboxDrain.drainPendingInbox(db, registry: registry)
      XCTAssertEqual(try PendingInboxDrain.unresolvedFutureRecordCount(db), 1)
      let fence = try Row.fetchOne(
        db,
        sql: """
          SELECT disposition, future_record_version
          FROM sync_outbox WHERE entity_type = ? AND entity_id = ?
          """,
        arguments: [EntityName.task, taskID])
      XCTAssertEqual(
        fence?["disposition"] as String?,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(fence?["future_record_version"] as String?, v5)
    }
  }

  func testAuthoritativeUnknownStagingFencesPostSessionIntentAndPendingReadDefends() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let databaseID = "future-hold-authoritative-db"
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDatabaseInstanceId, value: databaseID)
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: "account-future-hold")
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "account-future-hold", zoneIdentifier: "LorvexZone"),
        databaseInstanceId: databaseID)
      try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)
      try AuthoritativeSnapshot.stagePage(
        db, records: [], deletedRecordNames: [], sessionToken: session.sessionToken)

      try seedTask(db, title: "post-session", version: v1)
      try enqueueCurrentTask(db, version: v1, registerIntent: .all)
      let raw = rawFuture(version: v2)
      try AuthoritativeSnapshot.stagePage(
        db,
        records: [
          AuthoritativeSnapshotRemoteRecord(
            recordName: SyncRecordName.opaque(
              entityType: raw.entityType, entityId: raw.entityId),
            state: .unknown, envelope: nil, rawEnvelope: raw)
        ],
        deletedRecordNames: [], sessionToken: session.sessionToken)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT disposition FROM sync_outbox WHERE entity_id = ?", arguments: [taskID]),
        Outbox.Disposition.futureRecordHold.rawValue)

      // Simulate a legacy/bypassing writer that accidentally reactivated the
      // row. The transport read must rediscover staged provenance and re-fence
      // it rather than returning bytes that overwrite the CloudKit slot.
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = 0, disposition = NULL,
              future_record_version = NULL, future_record_resolution = NULL,
              last_error = NULL
          WHERE entity_id = ?
          """,
        arguments: [taskID])
      XCTAssertTrue(try Outbox.getPending(db).isEmpty)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT disposition FROM sync_outbox WHERE entity_id = ?", arguments: [taskID]),
        Outbox.Disposition.futureRecordHold.rawValue)
    }
  }

  func testBeginningAuthoritativeSnapshotDoesNotCascadePermanentFutureFence() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "local", version: v1)
      try enqueueCurrentTask(db, version: v1, registerIntent: .all)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: rawFuture(version: v2))

      let databaseID = "future-hold-before-authoritative-db"
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyDatabaseInstanceId, value: databaseID)
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: "account-future-hold")
      _ = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "account-future-hold", zoneIdentifier: "LorvexZone"),
        databaseInstanceId: databaseID)

      let fence = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT disposition, future_record_version,
                   authoritative_session_token
            FROM sync_outbox WHERE entity_id = ?
            """,
          arguments: [taskID]))
      XCTAssertEqual(
        fence["disposition"] as String?,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(fence["future_record_version"] as String?, v2)
      XCTAssertNil(fence["authoritative_session_token"] as String?)
    }
  }
}
