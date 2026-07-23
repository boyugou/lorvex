import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Contract tests for the durable, two-phase CloudKit truth-adoption path.
///
/// These tests deliberately exercise the core below the CloudKit coordinator:
/// the coordinator may advance its token only after these SQLite operations
/// have staged or atomically finalized the corresponding inventory.
final class AuthoritativeSnapshotTests: XCTestCase {
  private static let accountA = "account-a"
  private static let accountB = "account-b"
  private static let zoneA = "LorvexZone"
  private static let zoneB = "LorvexZone-v2"
  private static let deviceId = "snapshot-test-device"
  private static let databaseInstanceId = "snapshot-test-database"
  private static let remoteVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
  private static let newerLocalVersion = "9999913599999_0000_ffffffffffffffff"
  private static let ordinaryLocalVersion = "1711234567000_0000_bbbbbbbbbbbbbbbb"
  private static let postSessionVersion = "1711234568000_0000_bbbbbbbbbbbbbbbb"
  private static let futureSchemaVersion = "3000000000000_0000_dddddddddddddddd"
  private static let parentDeleteVersion = "1711234569000_0000_bbbbbbbbbbbbbbbb"
  private static let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000a001"
  private static let staleTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000a002"
  private static let listId = "01966a3f-7c8b-7d4e-8f3a-00000000a003"
  private static let redirectTargetId = "00000000-0000-7000-8000-000000000001"
  private static let redirectSourceId = "ffffffff-ffff-7fff-8fff-ffffffffffff"

  private final class LockedHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let state: HlcState

    init() throws {
      state = try HlcState(deviceSuffix: "cccccccccccccccc")
    }

    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      // 2033-05-18: newer than ordinary fixtures, but below the HLC ceiling.
      return state.generate(withPhysicalMs: 2_000_000_000_000)
    }

    func generate(dominating floor: Hlc?) -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      if let floor {
        state.updateOnReceive(remote: floor, physicalMs: 2_000_000_000_000)
      }
      return state.generate(withPhysicalMs: 2_000_000_000_000)
    }
  }

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func hlcSession() throws -> HlcSession {
    HlcSession(handle: try LockedHlcHandle())
  }

  private func beginPulling(
    _ db: Database, account: String = accountA, zone: String = zoneA
  ) throws {
    try SyncCheckpoints.set(
      db, key: SyncCheckpoints.keyDatabaseInstanceId,
      value: Self.databaseInstanceId)
    _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: account)
    let session = try AuthoritativeSnapshot.begin(
      db,
      boundary: try SyncTestSupport.cloudTraversalBoundary(
        accountIdentifier: account, zoneIdentifier: zone),
      databaseInstanceId: Self.databaseInstanceId)
    try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)
    try AuthoritativeSnapshot.stagePage(
      db, records: [], deletedRecordNames: [], sessionToken: session.sessionToken)
  }

  private func listPayload(id: String, name: String = "Inbox") throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string(id),
        "name": .string(name),
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
        "version": .string(Self.remoteVersion),
      ]))
  }

  private func taskPayload(
    id: String, title: String, listId: String = "inbox",
    status: String = "open", version: String = remoteVersion
  ) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string(id),
        "list_id": .string(listId),
        "title": .string(title),
        "status": .string(status),
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
        "version": .string(version),
      ]))
  }

  private func tagPayload(displayName: String) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "display_name": .string(displayName),
        "lookup_key": .string(normalizeLookupKey(displayName)),
        "color": .null,
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
      ]))
  }

  private func redirectEnvelope(
    version: String = remoteVersion
  ) throws -> SyncEnvelope {
    try EntityRedirect.makeEnvelope(
      record: EntityRedirect.Record(
        sourceType: .tag, sourceId: Self.redirectSourceId,
        targetId: Self.redirectTargetId, version: version,
        createdAt: "2026-07-14T00:00:00.000Z"),
      deviceId: "remote-device")
  }

  private func deleteEnvelope(
    kind: EntityKind, id: String, version: String
  ) throws -> SyncEnvelope {
    SyncEnvelope(
      entityType: kind, entityId: id, operation: .delete,
      version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(version)])),
      deviceId: "remote-device")
  }

  private func seedTag(
    _ db: Database, id: String, displayName: String,
    version: String = ordinaryLocalVersion
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tags
            (id, display_name, lookup_key, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, '2026-07-14T00:00:00.000Z',
                '2026-07-14T00:00:00.000Z')
        """,
      arguments: [id, displayName, normalizeLookupKey(displayName), version])
  }

  private func envelope(
    kind: EntityKind, id: String, version: String = remoteVersion,
    payload: String
  ) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: kind, entityId: id, operation: .upsert,
      version: try Hlc.parse(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "remote-device")
  }

  private func staged(_ envelope: SyncEnvelope) -> AuthoritativeSnapshotRemoteRecord {
    AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: envelope.entityType.asString, entityId: envelope.entityId),
      state: .decoded, envelope: envelope)
  }

  private func stagedFuture(_ raw: RawEnvelopeFields) -> AuthoritativeSnapshotRemoteRecord {
    AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: raw.entityType, entityId: raw.entityId),
      state: .unknown, envelope: nil, rawEnvelope: raw)
  }

  private func futureTaskOperation(
    version: String = remoteVersion
  ) -> RawEnvelopeFields {
    RawEnvelopeFields(
      entityType: EntityName.task, entityId: Self.taskId,
      operation: "FutureTaskOperation", version: version,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: #"{"future_task_shape":true}"#, deviceId: "future-device")
  }

  private func stagePage(
    _ db: Database, records: [AuthoritativeSnapshotRemoteRecord],
    deletedRecordNames: [String]
  ) throws {
    let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
    try AuthoritativeSnapshot.stagePage(
      db, records: records, deletedRecordNames: deletedRecordNames,
      sessionToken: session.sessionToken)
  }

  private func inboxEnvelope() throws -> SyncEnvelope {
    try envelope(kind: .list, id: "inbox", payload: listPayload(id: "inbox"))
  }

  private func seedList(
    _ db: Database, id: String = listId, version: String = ordinaryLocalVersion
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, version, created_at, updated_at)
        VALUES (?, 'Local list', ?, '2026-07-14T00:00:00.000Z',
                '2026-07-14T00:00:00.000Z')
        """, arguments: [id, version])
  }

  private func seedTask(
    _ db: Database, id: String = taskId, listId: String = "inbox",
    title: String = "Local title", version: String = ordinaryLocalVersion
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks
            (id, list_id, title, status,
             content_version, schedule_version, lifecycle_version, archive_version,
             version, created_at, updated_at, defer_count)
        VALUES (?, ?, ?, 'open', ?, ?, ?, ?, ?, '2026-07-14T00:00:00.000Z',
                '2026-07-14T00:00:00.000Z', 0)
        """, arguments: [id, listId, title, version, version, version, version, version])
  }

  private func finalize(_ db: Database) throws -> AuthoritativeSnapshotReport {
    let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
    return try AuthoritativeSnapshot.finalize(
      db, registry: registry, hlc: hlcSession(), deviceId: Self.deviceId,
      sessionToken: session.sessionToken, databaseInstanceId: session.databaseInstanceId)
  }

  private func enqueueTaskSnapshot(
    _ db: Database, title: String, version: String,
    registerIntent: TaskRegisterIntent = .all
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
        "version": version, "id": Self.taskId,
      ])
    XCTAssertEqual(
      try String.fetchOne(
        db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
      title, "queued task fixture must match the canonical row")
    let payload = try SyncCanonicalize.canonicalizeJSON(
      OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: Self.taskId))
    let local = SyncEnvelope(
      entityType: .task, entityId: Self.taskId, operation: .upsert,
      version: try Hlc.parseCanonical(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: Self.deviceId)
    _ = try Outbox.enqueueCoalesced(
      db, local, registerIntent: .task(registerIntent))
  }

  private func deleteTaskAndEnqueueIntent(
    _ db: Database, id: String = taskId, version: String = postSessionVersion
  ) throws {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object(["version": .string(version)]))
    try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [id])
    try Tombstone.createTombstone(
      db, entityType: EntityName.task, entityId: id, version: version,
      deletedAt: "2026-07-14T00:00:00.000Z")
    _ = try Outbox.enqueueCoalesced(
      db,
      SyncEnvelope(
        entityType: .task, entityId: id, operation: .delete,
        version: try Hlc.parse(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: Self.deviceId))
  }

  // MARK: - Session lifecycle

  func testBeginIsIdempotentForSameBoundaryAndReplacesMismatchedZone() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      try stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])

      let same = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
        databaseInstanceId: Self.databaseInstanceId)
      XCTAssertEqual(same.phase, .pulling)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 1,
        "re-entering the same boundary preserves the durable page inventory")

      let newZone = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneB),
        databaseInstanceId: Self.databaseInstanceId)
      XCTAssertEqual(newZone.zoneName, Self.zoneB)
      XCTAssertEqual(newZone.phase, .preparing)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 0,
        "a zone mismatch must never reuse the old zone's inventory")
    }
  }

  func testRestartClearsInventoryAndCancelRemovesSession() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      try stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])

      let sessionToken = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db)).sessionToken

      _ = try AuthoritativeSnapshot.restart(
        db, databaseInstanceId: Self.databaseInstanceId)
      XCTAssertEqual(try AuthoritativeSnapshot.activeSession(db)?.phase, .preparing)
      XCTAssertEqual(
        try AuthoritativeSnapshot.activeSession(db)?.sessionToken, sessionToken,
        "restart resumes the same durable adoption and must keep fence ownership")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 0)

      try AuthoritativeSnapshot.markReady(db, sessionToken: sessionToken)
      try AuthoritativeSnapshot.stagePage(
        db, records: [], deletedRecordNames: [], sessionToken: sessionToken)
      try AuthoritativeSnapshot.stagePage(
        db, records: [], deletedRecordNames: [], sessionToken: sessionToken)
      XCTAssertEqual(try AuthoritativeSnapshot.activeSession(db)?.phase, .pulling)

      try AuthoritativeSnapshot.cancel(db)
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertThrowsError(
        try AuthoritativeSnapshot.restart(
          db, databaseInstanceId: Self.databaseInstanceId)
      ) { error in
        XCTAssertEqual(error as? AuthoritativeSnapshotError, .noActiveSession)
      }
    }
  }

  func testCancelPromotesStagedFutureRecordBeforeDroppingSession() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Before snapshot")
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Edit before cancel", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Edit before cancel", version: Self.postSessionVersion,
        registerIntent: .content)
      try stagePage(
        db,
        records: [stagedFuture(futureTaskOperation(version: Self.futureSchemaVersion))],
        deletedRecordNames: [])

      try AuthoritativeSnapshot.cancel(db)

      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_pending_inbox
            WHERE envelope_entity_type = 'task' AND envelope_entity_id = ?
              AND envelope_version = ?
            """,
          arguments: [Self.taskId, Self.futureSchemaVersion]),
        1, "cancel must not discard the only exact copy of the opaque remote record")
      let held = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, disposition, future_record_version,
                   future_record_resolution
            FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?
            """,
          arguments: [Self.taskId]))
      XCTAssertEqual(held["version"] as String, Self.postSessionVersion)
      XCTAssertEqual(
        held["disposition"] as String,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(held["future_record_version"] as String, Self.futureSchemaVersion)
      XCTAssertEqual(
        held["future_record_resolution"] as String,
        FutureRecordHold.Resolution.lww.rawValue)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Edit before cancel")
    }
  }

  func testRestartPromotesStagedFutureRecordAndPreservesDeleteIntent() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Delete before restart")
      try beginPulling(db)
      try deleteTaskAndEnqueueIntent(db)
      try stagePage(
        db,
        records: [stagedFuture(futureTaskOperation(version: Self.futureSchemaVersion))],
        deletedRecordNames: [])

      _ = try AuthoritativeSnapshot.restart(
        db, databaseInstanceId: Self.databaseInstanceId)

      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_pending_inbox
            WHERE envelope_entity_type = 'task' AND envelope_entity_id = ?
              AND envelope_version = ?
            """,
          arguments: [Self.taskId, Self.futureSchemaVersion]),
        1)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT operation FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ?
              AND disposition = ?
            """,
          arguments: [
            Self.taskId, Outbox.Disposition.futureRecordHold.rawValue,
          ]),
        SyncNaming.opDelete)
      XCTAssertEqual(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: Self.taskId)?.version,
        Self.postSessionVersion)
    }
  }

  func testCancelReleasesFenceWhenLaterPageDeletedFutureRecord() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Before snapshot")
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Safe to publish after delete", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Safe to publish after delete", version: Self.postSessionVersion,
        registerIntent: .content)
      let recordName = SyncRecordName.opaque(
        entityType: EntityName.task, entityId: Self.taskId)
      try stagePage(
        db,
        records: [stagedFuture(futureTaskOperation(version: Self.futureSchemaVersion))],
        deletedRecordNames: [])
      try stagePage(db, records: [], deletedRecordNames: [recordName])

      try AuthoritativeSnapshot.cancel(db)

      let active = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT disposition, future_record_version,
                   future_record_resolution
            FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?
            """,
          arguments: [Self.taskId]))
      XCTAssertNil(active["disposition"] as String?)
      XCTAssertNil(active["future_record_version"] as String?)
      XCTAssertNil(active["future_record_resolution"] as String?)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_id = ?",
          arguments: [Self.taskId]),
        0)
      XCTAssertNoThrow(
        try FutureRecordHold.requireWriteAllowed(
          db, entityType: EntityName.task, entityId: Self.taskId))
    }
  }

  func testSameAccountZoneAndGenerationWithDifferentDescriptorStartsFreshSession() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      try stagePage(db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])
      let first = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
      let changedBoundary = try CloudTraversalBoundary(
        accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA,
        generation: first.boundary.generation,
        generationIdentifier: "replacement-generation-identifier",
        readyWitness: "replacement-ready-witness")

      let replacement = try AuthoritativeSnapshot.begin(
        db, boundary: changedBoundary,
        databaseInstanceId: Self.databaseInstanceId)

      XCTAssertNotEqual(replacement.sessionToken, first.sessionToken)
      XCTAssertEqual(replacement.boundary, changedBoundary)
      XCTAssertEqual(replacement.phase, .preparing)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 0)
    }
  }

  func testStageAndFinalizeAreBoundToSessionTokenAndPhysicalDatabase() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Local content before terminal adoption")
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: Self.databaseInstanceId)
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: Self.accountA)
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
        databaseInstanceId: Self.databaseInstanceId)
      try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)

      XCTAssertThrowsError(
        try AuthoritativeSnapshot.stagePage(
          db, records: [staged(try inboxEnvelope())], deletedRecordNames: [],
          sessionToken: "different-session")
      ) { error in
        XCTAssertEqual(error as? AuthoritativeSnapshotError, .sessionTokenMismatch)
      }
      XCTAssertEqual(try AuthoritativeSnapshot.activeSession(db)?.phase, .ready)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 0)

      let remoteTask = try envelope(
        kind: .task, id: Self.taskId,
        payload: taskPayload(id: Self.taskId, title: "Remote terminal content"))
      try AuthoritativeSnapshot.stagePage(
        db, records: [staged(try inboxEnvelope()), staged(remoteTask)], deletedRecordNames: [],
        sessionToken: session.sessionToken)
      XCTAssertEqual(
        try Set(
          String.fetchAll(
            db, sql: "SELECT DISTINCT session_id FROM sync_authoritative_snapshot_records")),
        [session.sessionToken], "every staged page row must carry the real session FK")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Local content before terminal adoption", "staging must not mutate live rows")

      XCTAssertThrowsError(
        try AuthoritativeSnapshot.finalize(
          db, registry: registry, hlc: hlcSession(), deviceId: Self.deviceId,
          sessionToken: "different-session", databaseInstanceId: Self.databaseInstanceId)
      ) { error in
        XCTAssertEqual(error as? AuthoritativeSnapshotError, .sessionTokenMismatch)
      }
      XCTAssertThrowsError(
        try AuthoritativeSnapshot.finalize(
          db, registry: registry, hlc: hlcSession(), deviceId: Self.deviceId,
          sessionToken: session.sessionToken, databaseInstanceId: "different-database")
      ) { error in
        XCTAssertEqual(error as? AuthoritativeSnapshotError, .databaseInstanceMismatch)
      }
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Local content before terminal adoption")

      _ = try finalize(db)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Remote terminal content")
    }
  }

  func testMalformedPageCaughtInsideOuterTransactionRollsBackPhaseAndWholePage() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: Self.databaseInstanceId)
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: Self.accountA)
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
        databaseInstanceId: Self.databaseInstanceId)
      try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)

      let malformed = AuthoritativeSnapshotRemoteRecord(
        recordName: "malformed-record", state: .decoded, envelope: nil)
      XCTAssertThrowsError(
        try AuthoritativeSnapshot.stagePage(
          db, records: [staged(try inboxEnvelope()), malformed],
          deletedRecordNames: [], sessionToken: session.sessionToken)
      ) { error in
        XCTAssertEqual(
          error as? AuthoritativeSnapshotError,
          .malformedStagedEnvelope(recordName: "malformed-record"))
      }

      XCTAssertEqual(try AuthoritativeSnapshot.activeSession(db)?.phase, .ready)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 0,
        "a caller that catches a page error must not retain earlier records from that page")
    }
  }

  func testSameAccountAndZoneOnDifferentDatabaseInstanceFailsClosed() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      try stagePage(db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])
      let first = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))

      XCTAssertThrowsError(
        try AuthoritativeSnapshot.begin(
          db,
          boundary: try SyncTestSupport.cloudTraversalBoundary(
            accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
          databaseInstanceId: "replacement-database")
      ) { error in
        XCTAssertEqual(error as? AuthoritativeSnapshotError, .databaseInstanceMismatch)
      }
      XCTAssertEqual(try AuthoritativeSnapshot.activeSession(db), first)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 1)
    }
  }

  // MARK: - Page staging and authoritative replay

  func testAuthoritativeReplayOrdersRedirectAfterItsRemoteLiveTargetAndSource() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      let target = try envelope(
        kind: .tag, id: Self.redirectTargetId,
        payload: tagPayload(displayName: "Shared"))
      let source = try envelope(
        kind: .tag, id: Self.redirectSourceId,
        payload: tagPayload(displayName: "shared"))
      // Deliberately stage the alias before both ordinary upserts. Finalization
      // must establish the canonical rows first and apply aliases last.
      try stagePage(
        db,
        records: [
          staged(try redirectEnvelope()), staged(source), staged(target),
          staged(try inboxEnvelope()),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?",
          arguments: [Self.redirectTargetId]), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?",
          arguments: [Self.redirectSourceId]), 0)
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: Self.redirectSourceId)?.targetId,
        Self.redirectTargetId)
    }
  }

  func testAuthoritativeReplayAcceptsAliasWhoseTerminalTargetIsRemotelyDeleted() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      let sourceDelete = try deleteEnvelope(
        kind: .tag, id: Self.redirectSourceId,
        version: "1711234568000_0000_a1b2c3d4a1b2c3d4")
      let targetDelete = try deleteEnvelope(
        kind: .tag, id: Self.redirectTargetId,
        version: "1711234569000_0000_a1b2c3d4a1b2c3d4")
      try stagePage(
        db,
        records: [
          staged(try redirectEnvelope()), staged(sourceDelete), staged(targetDelete),
          staged(try inboxEnvelope()),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: Self.redirectSourceId)?.targetId,
        Self.redirectTargetId)
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.tag, entityId: Self.redirectTargetId))
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EntityName.tag, entityId: Self.redirectSourceId))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tags WHERE id IN (?, ?)",
          arguments: [Self.redirectTargetId, Self.redirectSourceId]), 0)
    }
  }

  func testPostSessionAliasPromotesItsRemoteAbsentTargetDependency() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      // The target predates the adoption and has no queue row of its own. A
      // post-session alias causally depends on it, so dependency closure must
      // preserve and replay the target before rebuilding the alias ledger.
      try seedTag(db, id: Self.redirectTargetId, displayName: "Canonical")
      try beginPulling(db)
      _ = try EntityRedirect.upsertAndEnqueue(
        db, sourceType: .tag, sourceId: Self.redirectSourceId,
        targetId: Self.redirectTargetId, version: Self.postSessionVersion,
        createdAt: "2026-07-14T00:00:00.000Z", deviceId: Self.deviceId)
      try stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT display_name FROM tags WHERE id = ?",
          arguments: [Self.redirectTargetId]), "Canonical")
      XCTAssertEqual(
        try EntityRedirect.get(
          db, sourceType: EntityName.tag, sourceId: Self.redirectSourceId)?.targetId,
        Self.redirectTargetId)
      let activeKinds = try String.fetchAll(
        db,
        sql: """
          SELECT entity_type FROM sync_outbox
          WHERE synced_at IS NULL AND disposition IS NULL
            AND ((entity_type = 'tag' AND entity_id = ?)
              OR entity_type = 'entity_redirect')
          ORDER BY entity_type
          """,
        arguments: [Self.redirectTargetId])
      XCTAssertEqual(activeKinds, [EntityName.entityRedirect, EntityName.tag])
    }
  }

  func testMultiplePagesAndPhysicalDeletionPruneWithoutSyntheticDeleteBarrier() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db)
      try beginPulling(db)

      let inbox = try inboxEnvelope()
      let remoteTask = try envelope(
        kind: .task, id: Self.taskId,
        payload: taskPayload(id: Self.taskId, title: "Remote page-one title"))
      try stagePage(
        db, records: [staged(inbox), staged(remoteTask)], deletedRecordNames: [])
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 2)

      // A later CloudKit page/change physically removed the record observed on
      // page one. The final inventory must no longer treat it as remote-live.
      try stagePage(
        db, records: [],
        deletedRecordNames: [
          SyncRecordName.opaque(entityType: EntityName.task, entityId: Self.taskId)
        ])
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_authoritative_snapshot_records"), 1)

      let report = try finalize(db)
      XCTAssertNil(
        try Row.fetchOne(db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [Self.taskId]))
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: Self.taskId))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [Self.taskId]), 0)
      XCTAssertGreaterThanOrEqual(report.removedLocalEntities, 1)
      XCTAssertTrue(report.changedEntityTypes.contains(.task))
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))

      // A peer can create this identity immediately after the terminal snapshot
      // token with an HLC below this device's wall clock. Authoritative absence
      // must not leave a synthetic local death barrier that erases that valid
      // post-terminal creation when the ordinary change arrives.
      let peerVersion = "1711234567500_0000_dddddddddddddddd"
      let peer = try envelope(
        kind: .task, id: Self.taskId, version: peerVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Created after terminal token", version: peerVersion))
      let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: peer)
      XCTAssertEqual(outcome, .applied)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Created after terminal token")
    }
  }

  func testRemoteSnapshotOverwritesSameIdentityWithLowerHlc() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Newer local content", version: Self.newerLocalVersion)
      try beginPulling(db)
      let remoteTask = try envelope(
        kind: .task, id: Self.taskId, version: Self.remoteVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Authoritative remote content",
          version: Self.remoteVersion))
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(remoteTask)], deletedRecordNames: [])

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Newer local content", "non-terminal staging must never touch live state")

      let report = try finalize(db)
      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT title, version FROM tasks WHERE id = ?", arguments: [Self.taskId]))
      XCTAssertEqual(row["title"] as String, "Authoritative remote content")
      XCTAssertEqual(row["version"] as String, Self.remoteVersion)
      XCTAssertEqual(report.replayedRemoteRecords, 2)
      XCTAssertTrue(report.changedEntityTypes.contains(.task))
    }
  }

  func testPostSessionCreateAbsentRemotelySurvivesAndIsReenqueued() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      try seedTask(
        db, title: "Created while snapshot pulls",
        version: Self.postSessionVersion)
      try enqueueTaskSnapshot(
        db, title: "Created while snapshot pulls",
        version: Self.postSessionVersion)
      try stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])

      _ = try finalize(db)

      let task = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT title, version FROM tasks WHERE id = ?",
          arguments: [Self.taskId]))
      XCTAssertEqual(task["title"] as String, "Created while snapshot pulls")
      XCTAssertGreaterThan(
        try Hlc.parse(task["version"] as String),
        try Hlc.parse(Self.postSessionVersion))
      let pending = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, disposition
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]))
      XCTAssertEqual(pending["operation"] as String, SyncNaming.opUpsert)
      XCTAssertNil(pending["disposition"] as String?)
      XCTAssertEqual(pending["version"] as String, task["version"] as String)
    }
  }

  func testPostSessionHabitCompletionPreservesRemoteAbsentHabitDependency() throws {
    let store = try SyncTestSupport.freshStore()
    let habitID = "01966a3f-7c8b-7d4e-8f3a-00000000a004"
    let completionDate = "2026-07-14"
    let completionID = "\(habitID):\(completionDate)"
    try store.writer.write { db in
      // The habit predates the adoption and has no fresh outbox row of its own.
      // The completion is authored after the initial fence and causally asserts
      // that this still-live parent must survive the remote-absence pass.
      try db.execute(
        sql: """
          INSERT INTO habits
              (id, name, frequency_type, target_count, archived, lookup_key,
               version, created_at, updated_at)
          VALUES (?, 'Read', 'daily', 1, 0, 'read', ?,
                  '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
          """,
        arguments: [habitID, Self.ordinaryLocalVersion])
      try beginPulling(db)
      try db.execute(
        sql: """
          INSERT INTO habit_completions
              (habit_id, completed_date, value, note, version, created_at, updated_at)
          VALUES (?, ?, 1, 'fresh intent', ?,
                  '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
          """,
        arguments: [habitID, completionDate, Self.postSessionVersion])
      let completionPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "habit_id": .string(habitID),
          "completed_date": .string(completionDate),
          "value": .int(1),
          "note": .string("fresh intent"),
          "version": .string(Self.postSessionVersion),
          "created_at": .string("2026-07-14T00:00:00.000Z"),
          "updated_at": .string("2026-07-14T00:00:00.000Z"),
        ]))
      _ = try Outbox.enqueueCoalesced(
        db,
        SyncEnvelope(
          entityType: .habitCompletion, entityId: completionID,
          operation: .upsert, version: try Hlc.parse(Self.postSessionVersion),
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: completionPayload, deviceId: Self.deviceId))
      try stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT name FROM habits WHERE id = ?", arguments: [habitID]),
        "Read")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT value FROM habit_completions
            WHERE habit_id = ? AND completed_date = ?
            """, arguments: [habitID, completionDate]),
        1)
      let activeKinds = try String.fetchAll(
        db,
        sql: """
          SELECT entity_type FROM sync_outbox
          WHERE synced_at IS NULL AND disposition IS NULL
            AND ((entity_type = 'habit' AND entity_id = ?)
              OR (entity_type = 'habit_completion' AND entity_id = ?))
          ORDER BY entity_type
          """, arguments: [habitID, completionID])
      XCTAssertEqual(activeKinds, [EntityName.habit, EdgeName.habitCompletion])
    }
  }

  func testParentDeleteWithResidualChildUpsertNormalizesToChildDeleteWithoutWedge() throws {
    let store = try SyncTestSupport.freshStore()
    let habitID = "01966a3f-7c8b-7d4e-8f3a-00000000a005"
    let completionDate = "2026-07-15"
    let completionID = "\(habitID):\(completionDate)"
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO habits
              (id, name, frequency_type, target_count, archived, lookup_key,
               version, created_at, updated_at)
          VALUES (?, 'Walk', 'daily', 1, 0, 'walk', ?,
                  '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
          """,
        arguments: [habitID, Self.ordinaryLocalVersion])
      try beginPulling(db)

      let completionPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "habit_id": .string(habitID),
          "completed_date": .string(completionDate),
          "value": .int(1),
          "note": .string("racing completion"),
          "version": .string(Self.postSessionVersion),
          "created_at": .string("2026-07-14T00:00:00.000Z"),
          "updated_at": .string("2026-07-14T00:00:00.000Z"),
        ]))
      try db.execute(
        sql: """
          INSERT INTO habit_completions
              (habit_id, completed_date, value, note, version, created_at, updated_at)
          VALUES (?, ?, 1, 'racing completion', ?,
                  '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
          """,
        arguments: [habitID, completionDate, Self.postSessionVersion])
      _ = try Outbox.enqueueCoalesced(
        db,
        SyncEnvelope(
          entityType: .habitCompletion, entityId: completionID,
          operation: .upsert, version: try Hlc.parse(Self.postSessionVersion),
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: completionPayload, deviceId: Self.deviceId))

      // Simulate a cross-surface interleaving that committed the canonical
      // cascading parent delete but left the earlier child upsert queue row.
      try db.execute(sql: "DELETE FROM habits WHERE id = ?", arguments: [habitID])
      let parentDeletePayload = try SyncCanonicalize.canonicalizeJSON(
        .object(["version": .string(Self.ordinaryLocalVersion)]))
      _ = try Outbox.enqueueCoalesced(
        db,
        SyncEnvelope(
          entityType: .habit, entityId: habitID, operation: .delete,
          version: try Hlc.parse(Self.parentDeleteVersion),
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: parentDeletePayload, deviceId: Self.deviceId))

      let remoteHabitPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "id": .string(habitID), "name": .string("Remote walk"),
          "frequency_type": .string("daily"), "weekdays": .array([]),
          "per_period_target": .int(1), "day_of_month": .null,
          "target_count": .int(1), "milestone_target": .null,
          "archived": .bool(false), "position": .int(0),
          "created_at": .string("2026-07-14T00:00:00.000Z"),
          "updated_at": .string("2026-07-14T00:00:00.000Z"),
          "version": .string(Self.remoteVersion),
        ]))
      let remoteHabit = try envelope(
        kind: .habit, id: habitID, payload: remoteHabitPayload)
      let remoteCompletion = try envelope(
        kind: .habitCompletion, id: completionID,
        payload: completionPayload)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()), staged(remoteHabit), staged(remoteCompletion),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM habits WHERE id = ?", arguments: [habitID]))
      XCTAssertNil(
        try String.fetchOne(
          db,
          sql: """
            SELECT habit_id FROM habit_completions
            WHERE habit_id = ? AND completed_date = ?
            """, arguments: [habitID, completionDate]))
      XCTAssertTrue(
        try Tombstone.isTombstoned(
          db, entityType: EdgeName.habitCompletion, entityId: completionID))
      let deleteKinds = try String.fetchAll(
        db,
        sql: """
          SELECT entity_type FROM sync_outbox
          WHERE synced_at IS NULL AND disposition IS NULL
            AND operation = 'delete'
            AND ((entity_type = 'habit' AND entity_id = ?)
              OR (entity_type = 'habit_completion' AND entity_id = ?))
          ORDER BY entity_type
          """, arguments: [habitID, completionID])
      XCTAssertEqual(deleteKinds, [EntityName.habit, EdgeName.habitCompletion])
    }
  }

  func testPostSessionUpdateDominatesFutureRemoteSnapshotValue() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Stale local", version: Self.ordinaryLocalVersion)
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Edited while snapshot pulls", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Edited while snapshot pulls",
        version: Self.postSessionVersion, registerIntent: .content)
      let futureRemote = try envelope(
        kind: .task, id: Self.taskId, version: Self.newerLocalVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Future-stamped remote",
          version: Self.newerLocalVersion))
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(futureRemote)],
        deletedRecordNames: [])

      _ = try finalize(db)

      let task = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT title, version FROM tasks WHERE id = ?",
          arguments: [Self.taskId]))
      XCTAssertEqual(task["title"] as String, "Edited while snapshot pulls")
      XCTAssertGreaterThan(
        try Hlc.parse(task["version"] as String),
        try Hlc.parse(Self.newerLocalVersion))
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT operation FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ?
              AND synced_at IS NULL AND disposition IS NULL
            """, arguments: [Self.taskId]),
        SyncNaming.opUpsert)
    }
  }

  func testPostSessionDeleteDominatesRemoteUpsertAndRebuildsDeathBarrier() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Delete me", version: Self.ordinaryLocalVersion)
      try beginPulling(db)
      try deleteTaskAndEnqueueIntent(db)
      let futureRemote = try envelope(
        kind: .task, id: Self.taskId, version: Self.newerLocalVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Remote resurrection attempt",
          version: Self.newerLocalVersion))
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(futureRemote)],
        deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertNil(
        try Row.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [Self.taskId]))
      let tombstone = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: Self.taskId))
      XCTAssertGreaterThan(
        try Hlc.parse(tombstone.version),
        try Hlc.parse(Self.newerLocalVersion))
      let pending = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, disposition
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]))
      XCTAssertEqual(pending["operation"] as String, SyncNaming.opDelete)
      XCTAssertNil(pending["disposition"] as String?)
      XCTAssertEqual(pending["version"] as String, tombstone.version)
    }
  }

  func testPostSessionDeleteHeldByFutureSnapshotIsPreservedThenReplayedAfterUpgrade() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Delete after snapshot begins")
      try beginPulling(db)
      try deleteTaskAndEnqueueIntent(db)
      let future = futureTaskOperation(version: Self.futureSchemaVersion)
      try stagePage(
        db, records: [staged(try inboxEnvelope()), stagedFuture(future)],
        deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertNil(
        try Row.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [Self.taskId]))
      let tombstone = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: Self.taskId))
      XCTAssertEqual(tombstone.version, Self.postSessionVersion)
      let held = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, payload, disposition,
                   future_record_version, future_record_resolution
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [Self.taskId]))
      XCTAssertEqual(held["operation"] as String, SyncNaming.opDelete)
      XCTAssertEqual(held["version"] as String, tombstone.version)
      XCTAssertEqual(
        held["disposition"] as String,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(held["future_record_version"] as String, Self.futureSchemaVersion)
      XCTAssertEqual(
        held["future_record_resolution"] as String,
        FutureRecordHold.Resolution.localAfterFuture.rawValue)
      guard case .object(let deletePayload)? = JSONValue.parse(held["payload"] as String) else {
        return XCTFail("restamped delete payload must be canonical JSON")
      }
      XCTAssertEqual(deletePayload["version"], .string(tombstone.version))

      // Model the first upgraded build that can decode the held record. It
      // consumes the remote value, then atomically re-authors the exact
      // post-session delete above that formerly opaque floor.
      let understood = try envelope(
        kind: .task, id: Self.taskId, version: Self.futureSchemaVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Future remote value",
          version: Self.futureSchemaVersion))
      let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: understood)
      guard case .applied = outcome else {
        return XCTFail("the newly-understood remote row must first become typed state")
      }
      let replay = try XCTUnwrap(
        try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: understood, outcome: outcome))
      let replayClock = try hlcSession()
      try FutureRecordHold.fulfillLocalIntentReplay(
        db, replay: replay, registry: registry,
        mintVersion: { floor in replayClock.nextVersionString(dominating: floor) },
        deviceId: Self.deviceId)
      let released = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, disposition
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [Self.taskId]))
      XCTAssertEqual(released["operation"] as String, SyncNaming.opDelete)
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(released["version"] as String),
        try Hlc.parseCanonical(Self.futureSchemaVersion))
      XCTAssertNil(released["disposition"] as String?)
    }
  }

  func testPostSessionUpdateHeldByFutureSnapshotRetainsUserValueWithoutPrematurePush() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Before snapshot")
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Edited after snapshot began", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Edited after snapshot began", version: Self.postSessionVersion,
        registerIntent: .content)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()),
          stagedFuture(futureTaskOperation(version: Self.futureSchemaVersion)),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      let task = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT title, version FROM tasks WHERE id = ?",
          arguments: [Self.taskId]))
      XCTAssertEqual(task["title"] as String, "Edited after snapshot began")
      XCTAssertEqual(task["version"] as String, Self.postSessionVersion)
      let held = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, disposition, future_record_version,
                   future_record_resolution
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [Self.taskId]))
      XCTAssertEqual(held["operation"] as String, SyncNaming.opUpsert)
      XCTAssertEqual(held["version"] as String, task["version"] as String)
      XCTAssertEqual(
        held["disposition"] as String,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(held["future_record_version"] as String, Self.futureSchemaVersion)
      XCTAssertEqual(
        held["future_record_resolution"] as String,
        FutureRecordHold.Resolution.localAfterFuture.rawValue)
    }
  }

  func testLaterSnapshotCannotDowngradeDurablePostSessionFutureIntent() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Before first snapshot")
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Intent survives every snapshot", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Intent survives every snapshot", version: Self.postSessionVersion,
        registerIntent: .content)
      let future = futureTaskOperation(version: Self.futureSchemaVersion)
      try stagePage(
        db,
        records: [staged(try inboxEnvelope()), stagedFuture(future)],
        deletedRecordNames: [])
      _ = try finalize(db)

      let firstHeldID = try XCTUnwrap(
        try Int64.fetchOne(
          db,
          sql: """
            SELECT id FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ?
              AND disposition = ?
            """,
          arguments: [
            Self.taskId, Outbox.Disposition.futureRecordHold.rawValue,
          ]))

      // A later session's numeric boundary includes the already-held row. The
      // durable local-after-future provenance, not that new boundary, remains
      // authoritative while the remote record is still opaque.
      try beginPulling(db)
      try stagePage(
        db,
        records: [staged(try inboxEnvelope()), stagedFuture(future)],
        deletedRecordNames: [])
      _ = try finalize(db)

      let held = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT id, version, disposition, future_record_version,
                   future_record_resolution
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ?
            """,
          arguments: [Self.taskId]))
      XCTAssertEqual(held["id"] as Int64, firstHeldID)
      XCTAssertEqual(held["version"] as String, Self.postSessionVersion)
      XCTAssertEqual(
        held["disposition"] as String,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(held["future_record_version"] as String, Self.futureSchemaVersion)
      XCTAssertEqual(
        held["future_record_resolution"] as String,
        FutureRecordHold.Resolution.localAfterFuture.rawValue)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Intent survives every snapshot")
    }
  }

  func testLaterUnderstoodSnapshotReplaysDurableFutureIntentAboveRemote() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Before first snapshot")
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Durable local intent", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Durable local intent", version: Self.postSessionVersion,
        registerIntent: .content)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()),
          stagedFuture(futureTaskOperation(version: Self.futureSchemaVersion)),
        ], deletedRecordNames: [])
      _ = try finalize(db)

      // The next build can understand the remote shape. The second snapshot
      // must adopt it, then re-author the durable local intent as a strict HLC
      // successor instead of treating the old queue id as pre-session state.
      try beginPulling(db)
      let understood = try envelope(
        kind: .task, id: Self.taskId, version: Self.futureSchemaVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Newly understood remote",
          version: Self.futureSchemaVersion))
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(understood)],
        deletedRecordNames: [])
      _ = try finalize(db)

      let task = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT title, version FROM tasks WHERE id = ?",
          arguments: [Self.taskId]))
      XCTAssertEqual(task["title"] as String, "Durable local intent")
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(task["version"] as String),
        try Hlc.parseCanonical(Self.futureSchemaVersion))
      let active = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, disposition
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [Self.taskId]))
      XCTAssertEqual(active["operation"] as String, SyncNaming.opUpsert)
      XCTAssertEqual(active["version"] as String, task["version"] as String)
      XCTAssertNil(active["disposition"] as String?)
    }
  }

  func testPostSessionFutureFenceAcceptsLocalHlcAboveOpaqueFloor() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Before snapshot")
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Higher local intent", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Higher local intent", version: Self.newerLocalVersion,
        registerIntent: .content)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()),
          stagedFuture(futureTaskOperation(version: Self.futureSchemaVersion)),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Higher local intent")
      let held = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, future_record_version, future_record_resolution
            FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?
          """,
          arguments: [Self.taskId]))
      XCTAssertEqual(held["version"] as String, Self.newerLocalVersion)
      XCTAssertEqual(held["future_record_version"] as String, Self.futureSchemaVersion)
      XCTAssertEqual(
        held["future_record_resolution"] as String,
        FutureRecordHold.Resolution.localAfterFuture.rawValue)
    }
  }

  func testPostSessionFutureHeldUpsertAboveOperationalCapDoesNotWedgeFinalization() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let overCap = try Hlc(
        physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
        deviceSuffix: "eeeeeeeeeeeeeeee").description
      try seedTask(db, title: "Before snapshot")
      try beginPulling(db)
      try db.execute(
        sql: "UPDATE tasks SET title = ? WHERE id = ?",
        arguments: ["Preserved over cap", Self.taskId])
      try enqueueTaskSnapshot(
        db, title: "Preserved over cap", version: Self.postSessionVersion,
        registerIntent: .content)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()), stagedFuture(futureTaskOperation(version: overCap)),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Preserved over cap")
      let held = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, future_record_version, future_record_resolution
            FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?
          """, arguments: [Self.taskId]))
      XCTAssertEqual(held["version"] as String, Self.postSessionVersion)
      XCTAssertEqual(held["future_record_version"] as String, overCap)
      XCTAssertEqual(
        held["future_record_resolution"] as String,
        FutureRecordHold.Resolution.localAfterFuture.rawValue)
    }
  }

  func testPostSessionFutureHeldDeleteAboveOperationalCapPreservesDeathBarrier() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let overCap = try Hlc(
        physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
        deviceSuffix: "ffffffffffffffff").description
      try seedTask(db, title: "Delete after begin")
      try beginPulling(db)
      try deleteTaskAndEnqueueIntent(db)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()), stagedFuture(futureTaskOperation(version: overCap)),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [Self.taskId]))
      let tombstone = try XCTUnwrap(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: Self.taskId))
      XCTAssertEqual(tombstone.version, Self.postSessionVersion)
      let held = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, future_record_version,
                   future_record_resolution
            FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?
          """, arguments: [Self.taskId]))
      XCTAssertEqual(held["operation"] as String, SyncNaming.opDelete)
      XCTAssertEqual(held["version"] as String, Self.postSessionVersion)
      XCTAssertEqual(held["future_record_version"] as String, overCap)
      XCTAssertEqual(
        held["future_record_resolution"] as String,
        FutureRecordHold.Resolution.localAfterFuture.rawValue)
    }
  }

  func testPreSessionFutureFenceAdoptsRemoteAuthoritativelyAfterUpgrade() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(
        db, title: "Stale high-HLC local", version: Self.newerLocalVersion)
      try enqueueTaskSnapshot(
        db, title: "Stale high-HLC local", version: Self.newerLocalVersion)
      try FutureRecordHold.fenceExistingLocalIntent(
        db, entityType: EntityName.task, entityId: Self.taskId,
        heldVersion: Self.futureSchemaVersion)
      try beginPulling(db)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()),
          stagedFuture(futureTaskOperation(version: Self.futureSchemaVersion)),
        ], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT future_record_resolution FROM sync_outbox WHERE entity_id = ?",
          arguments: [Self.taskId]),
        FutureRecordHold.Resolution.remoteAuthoritative.rawValue)

      let understood = try envelope(
        kind: .task, id: Self.taskId, version: Self.futureSchemaVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Authoritative future value",
          version: Self.futureSchemaVersion))
      let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: understood)
      XCTAssertEqual(outcome, .applied)
      XCTAssertNil(
        try FutureRecordHold.reconcileTerminalEnvelope(
          db, envelope: understood, outcome: outcome))
      let adopted = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT title, version FROM tasks WHERE id = ?",
          arguments: [Self.taskId]))
      XCTAssertEqual(adopted["title"] as String, "Authoritative future value")
      XCTAssertEqual(adopted["version"] as String, Self.futureSchemaVersion)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?",
          arguments: [Self.taskId]),
        0)
    }
  }

  func testCursorRestartDoesNotReclassifyPostSessionIntentAsStale() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try beginPulling(db)
      try seedTask(
        db, title: "Intent survives cursor restart",
        version: Self.postSessionVersion)
      try enqueueTaskSnapshot(
        db, title: "Intent survives cursor restart",
        version: Self.postSessionVersion)
      let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
      _ = try AuthoritativeSnapshot.restart(
        db, databaseInstanceId: session.databaseInstanceId)
      try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)
      try AuthoritativeSnapshot.stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [],
        sessionToken: session.sessionToken)

      _ = try finalize(db)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Intent survives cursor restart")
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT operation FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ?
              AND synced_at IS NULL AND disposition IS NULL
            """, arguments: [Self.taskId]),
        SyncNaming.opUpsert)
    }
  }

  func testRemoteAbsentStaleTombstoneIsRemovedFromAuthoritativeLedger() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: Self.staleTaskId,
        version: Self.newerLocalVersion,
        deletedAt: "2020-01-01T00:00:00.000Z")
      try beginPulling(db)
      try stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])

      _ = try finalize(db)

      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.task, entityId: Self.staleTaskId))
      let backfill = try Outbox.enqueueAllLiveForFullResync(db)
      XCTAssertFalse(
        try Outbox.getPending(db).contains {
          $0.envelope.entityType == .task
            && $0.envelope.entityId == Self.staleTaskId
        }, "a later full resync must not republish the superseded death barrier")
      XCTAssertGreaterThanOrEqual(backfill.emitted, 0)
    }
  }

  /// Regression: the pre-adoption high-HLC row used to remain as a permanent
  /// authoritative fence after successful finalization. The adopted lower-HLC
  /// row then could not re-enter the unique unsynced slot during a later local-
  /// authoritative rebuild, even though the backfill reported it as emitted.
  func testFinalizeReleasesFenceSoLowerHlcFullResyncActuallyEnqueues() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Newer stale local", version: Self.newerLocalVersion)
      try enqueueTaskSnapshot(
        db, title: "Newer stale local", version: Self.newerLocalVersion)
      try beginPulling(db)

      let fenced = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT disposition, authoritative_session_token
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]))
      XCTAssertEqual(
        fenced["disposition"] as String?,
        Outbox.Disposition.authoritativeAdoption.rawValue)
      XCTAssertNotNil(fenced["authoritative_session_token"] as String?)

      let remoteTask = try envelope(
        kind: .task, id: Self.taskId, version: Self.remoteVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Adopted lower-HLC remote",
          version: Self.remoteVersion))
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(remoteTask)],
        deletedRecordNames: [])

      _ = try finalize(db)
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        Self.remoteVersion)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]),
        0, "successful adoption permanently discards, rather than revives, the stale local write")

      let before =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL") ?? 0
      let backfill = try Outbox.enqueueAllLiveForFullResync(db)
      let after =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL") ?? 0
      XCTAssertEqual(backfill.emitted, after - before, "emitted must count actual fresh inserts")
      let rebuilt = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, disposition FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]))
      XCTAssertEqual(rebuilt["version"] as String, Self.remoteVersion)
      XCTAssertNil(rebuilt["disposition"] as String?)
    }
  }

  func testCancelDeletesFenceSoSameHlcFullResyncActuallyEnqueues() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Local authority", version: Self.newerLocalVersion)
      try enqueueTaskSnapshot(db, title: "Local authority", version: Self.newerLocalVersion)
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: Self.databaseInstanceId)
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: Self.accountA)
      _ = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
        databaseInstanceId: Self.databaseInstanceId)

      try AuthoritativeSnapshot.cancel(db)
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]),
        0, "cancel must discard the pre-adoption queue, not re-arm it")

      let report = try Outbox.enqueueAllLiveForFullResync(db)
      XCTAssertGreaterThan(report.emitted, 0)
      let rebuiltVersion = try String.fetchOne(
        db,
        sql: """
          SELECT version FROM sync_outbox
          WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
          """, arguments: [Self.taskId])
      XCTAssertEqual(rebuiltVersion, Self.newerLocalVersion)
    }
  }

  func testReplacementSessionTransfersOriginalFenceButPreservesInFlightIntent() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Stale before adoption", version: Self.ordinaryLocalVersion)
      try enqueueTaskSnapshot(
        db, title: "Stale before adoption", version: Self.ordinaryLocalVersion)
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: Self.databaseInstanceId)
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: Self.accountA)
      let first = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
        databaseInstanceId: Self.databaseInstanceId)

      try seedTask(
        db, id: Self.staleTaskId, title: "Authored during adoption",
        version: Self.postSessionVersion)
      let inFlight = try envelope(
        kind: .task, id: Self.staleTaskId, version: Self.postSessionVersion,
        payload: taskPayload(
          id: Self.staleTaskId, title: "Authored during adoption",
          version: Self.postSessionVersion))
      _ = try Outbox.enqueueCoalesced(db, inFlight)

      let replacement = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneB,
          generation: 2, generationIdentifier: "test-generation-2",
          readyWitness: "test-ready-witness-2"),
        databaseInstanceId: Self.databaseInstanceId)
      XCTAssertNotEqual(replacement.sessionToken, first.sessionToken)
      XCTAssertEqual(
        replacement.outboxBoundaryId, first.outboxBoundaryId,
        "replacement must preserve the original intent boundary")

      let staleFence = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT disposition, authoritative_session_token
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]))
      XCTAssertEqual(
        staleFence["disposition"] as String?,
        Outbox.Disposition.authoritativeAdoption.rawValue)
      XCTAssertEqual(
        staleFence["authoritative_session_token"] as String?, replacement.sessionToken)

      let activeIntent = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT disposition, authoritative_session_token
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.staleTaskId]))
      XCTAssertNil(activeIntent["disposition"] as String?)
      XCTAssertNil(activeIntent["authoritative_session_token"] as String?)

      try AuthoritativeSnapshot.cancel(db)
      XCTAssertNil(
        try Row.fetchOne(
          db,
          sql: """
            SELECT id FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]))
      XCTAssertNotNil(
        try Row.fetchOne(
          db,
          sql: """
            SELECT id FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.staleTaskId]))
    }
  }

  func testFutureFenceClassificationUsesDurableOutboxBoundaryNotTimestamp() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, title: "Pre-session future-held content")
      try enqueueTaskSnapshot(
        db, title: "Pre-session future-held content", version: Self.ordinaryLocalVersion)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: futureTaskOperation())
      let preSessionFenceId = try XCTUnwrap(
        try Int64.fetchOne(
          db, sql: "SELECT id FROM sync_outbox WHERE entity_id = ?",
          arguments: [Self.taskId]))

      try beginPulling(db)
      let session = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertEqual(session.outboxBoundaryId, preSessionFenceId)

      // Deliberately erase the wall-clock distinction. The pre-session row must
      // still be superseded because its durable id is at/below the boundary.
      try db.execute(
        sql: "UPDATE sync_outbox SET created_at = ? WHERE id = ?",
        arguments: [session.startedAt, preSessionFenceId])
      try stagePage(db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])
      _ = try finalize(db)

      XCTAssertNil(
        try Row.fetchOne(
          db, sql: "SELECT id FROM sync_outbox WHERE entity_id = ?",
          arguments: [Self.taskId]))
      XCTAssertNil(
        try Row.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [Self.taskId]))
    }
  }

  func testPostSessionFutureFenceSurvivesRestartAtSameTimestampAndReplaysIntent() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: Self.databaseInstanceId)
      _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: Self.accountA)
      let begun = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
        databaseInstanceId: Self.databaseInstanceId)

      try seedTask(
        db, title: "Authored after adoption began", version: Self.postSessionVersion)
      try enqueueTaskSnapshot(
        db, title: "Authored after adoption began", version: Self.postSessionVersion)
      try PendingInboxDrain.holdUnknownTypeRecord(db, raw: futureTaskOperation())
      let postSessionFenceId = try XCTUnwrap(
        try Int64.fetchOne(
          db, sql: "SELECT id FROM sync_outbox WHERE entity_id = ?",
          arguments: [Self.taskId]))
      XCTAssertGreaterThan(postSessionFenceId, begun.outboxBoundaryId)
      try db.execute(
        sql: "UPDATE sync_outbox SET created_at = ? WHERE id = ?",
        arguments: [begun.startedAt, postSessionFenceId])

      let restarted = try AuthoritativeSnapshot.restart(
        db, databaseInstanceId: Self.databaseInstanceId)
      XCTAssertEqual(restarted.outboxBoundaryId, begun.outboxBoundaryId)
      try AuthoritativeSnapshot.markReady(db, sessionToken: restarted.sessionToken)
      try AuthoritativeSnapshot.stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [],
        sessionToken: restarted.sessionToken)
      _ = try finalize(db)

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Authored after adoption began")
      let replayed = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT id, disposition, version FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [Self.taskId]))
      XCTAssertGreaterThan(replayed["id"] as Int64, begun.outboxBoundaryId)
      XCTAssertNil(replayed["disposition"] as String?)
      let replayedVersion = try Hlc.parseCanonical(replayed["version"] as String)
      XCTAssertGreaterThan(replayedVersion, try Hlc.parseCanonical(Self.postSessionVersion))
      XCTAssertTrue(Hlc.isOperationallyAcceptableWire(replayedVersion))
    }
  }

  func testRelaunchKeepsFenceOwnershipAndCancelStillReleasesIt() throws {
    let schema = try SyncTestSupport.loadSchemaSQL()
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "lorvex-authoritative-relaunch-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let databaseURL = directory.appendingPathComponent("lorvex.sqlite")
    var originalToken = ""

    do {
      let store = try LorvexStore.open(at: databaseURL, schemaSQL: schema)
      try store.writer.write { db in
        try seedTask(db, title: "Survives process restart", version: Self.newerLocalVersion)
        try enqueueTaskSnapshot(
          db, title: "Survives process restart", version: Self.newerLocalVersion)
        try SyncCheckpoints.set(
          db, key: SyncCheckpoints.keyDatabaseInstanceId,
          value: Self.databaseInstanceId)
        _ = try CloudTraversalWitness.claimAccount(db, accountIdentifier: Self.accountA)
        let session = try AuthoritativeSnapshot.begin(
          db,
          boundary: try SyncTestSupport.cloudTraversalBoundary(
            accountIdentifier: Self.accountA, zoneIdentifier: Self.zoneA),
          databaseInstanceId: Self.databaseInstanceId)
        originalToken = session.sessionToken
      }
    }

    let reopened = try LorvexStore.open(at: databaseURL, schemaSQL: schema)
    try reopened.writer.write { db in
      let resumed = try XCTUnwrap(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertEqual(resumed.sessionToken, originalToken)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT authoritative_session_token FROM sync_outbox
            WHERE disposition = 'authoritative_adoption'
            """),
        originalToken)

      try AuthoritativeSnapshot.cancel(db)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE synced_at IS NULL"), 0)
      let report = try Outbox.enqueueAllLiveForFullResync(db)
      XCTAssertGreaterThan(report.emitted, 0)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]),
        Self.newerLocalVersion)
    }
  }

  func testRowsAbsentFromRemoteArePrunedChildFirstWithoutDeathBarriers() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedList(db)
      try seedTask(db, listId: Self.listId)
      try beginPulling(db)
      try stagePage(
        db, records: [staged(try inboxEnvelope())], deletedRecordNames: [])

      let report = try finalize(db)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [Self.listId]),
        0)
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: Self.taskId))
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.list, entityId: Self.listId))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE synced_at IS NULL AND disposition IS NULL
              AND ((entity_type = 'task' AND entity_id = ?)
                OR (entity_type = 'list' AND entity_id = ?))
            """, arguments: [Self.taskId, Self.listId]), 0)
      XCTAssertGreaterThanOrEqual(report.removedLocalEntities, 2)
    }
  }

  func testRemoteTaskReferencingRemoteAbsentTombstonedListIsReemittedInInbox() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedList(db)
      try seedTask(db, listId: Self.listId)
      // A one-shot claim from the superseded pre-adoption history must not
      // suppress the repair required by the newly adopted snapshot.
      try db.execute(
        sql: """
          INSERT INTO sync_list_fallback_reemit_claims (task_id, payload_list_id)
          VALUES (?, ?)
          """, arguments: [Self.taskId, Self.listId])
      try beginPulling(db)
      let remoteTask = try envelope(
        kind: .task, id: Self.taskId,
        payload: taskPayload(
          id: Self.taskId, title: "Remote task", listId: Self.listId))
      // The task exists remotely but its list does not. Finalization first
      // tombstones the absent local list; typed task apply then takes the normal
      // inbox fallback, which must be re-emitted so CloudKit learns the repair.
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(remoteTask)],
        deletedRecordNames: [])

      let report = try finalize(db)
      XCTAssertTrue(report.changedEntityTypes.contains(.task))

      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "inbox")
      let reemit = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, payload, disposition
            FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
            """, arguments: [Self.taskId]))
      XCTAssertEqual(reemit["operation"] as String, "upsert")
      XCTAssertNil(reemit["disposition"] as String?)
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(reemit["version"] as String), remoteTask.version,
        "the inbox repair must be a strict successor of the remote task")
      let payload = try XCTUnwrap(JSONValue.parse(reemit["payload"] as String))
      guard case .object(let fields) = payload else {
        return XCTFail("task convergence re-emit must carry an object payload")
      }
      XCTAssertEqual(fields["list_id"], .string("inbox"))
    }
  }

  // MARK: - Fail-closed and transactionality

  func testMixedKnownAndFutureInventoryPreservesRawRecordWithoutApplyingIt() throws {
    let store = try SyncTestSupport.freshStore()
    let raw = futureTaskOperation()
    try store.writer.write { db in
      try seedTask(db)
      try beginPulling(db)
      try stagePage(
        db, records: [staged(try inboxEnvelope()), stagedFuture(raw)],
        deletedRecordNames: [])

      let report = try finalize(db)

      XCTAssertEqual(report.replayedRemoteRecords, 1)
      XCTAssertEqual(report.deferredUnknownTypeRecords, 1)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Local title",
        "a future operation participates in inventory but cannot mutate today's row")
      let storedJSON = try XCTUnwrap(
        try String.fetchOne(
          db,
          sql: """
            SELECT envelope FROM sync_pending_inbox
            WHERE envelope_entity_type = ? AND envelope_entity_id = ?
            """,
          arguments: [EntityName.task, Self.taskId]))
      let stored = try JSONDecoder().decode(
        RawEnvelopeFields.self, from: XCTUnwrap(storedJSON.data(using: .utf8)))
      XCTAssertEqual(stored, raw)
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
    }
  }

  func testAuthoritativeReservedHlcHeadroomIsParkedWithoutApplyingCanonicalState() throws {
    let store = try SyncTestSupport.freshStore()
    let heldVersion = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs + 1, counter: 0,
      deviceSuffix: "ffffffffffffffff").description
    try store.writer.write { db in
      try seedTask(db)
      try beginPulling(db)
      let heldTask = try envelope(
        kind: .task, id: Self.taskId, version: heldVersion,
        payload: taskPayload(
          id: Self.taskId, title: "Must remain parked", version: heldVersion))
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(heldTask)],
        deletedRecordNames: [])

      let report = try finalize(db)

      XCTAssertEqual(report.replayedRemoteRecords, 1)
      XCTAssertEqual(report.deferredUnknownTypeRecords, 1)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Local title")
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT envelope_version FROM sync_pending_inbox WHERE envelope_entity_id = ?",
          arguments: [Self.taskId]),
        heldVersion)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?",
          arguments: [Self.taskId]),
        0)
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertThrowsError(
        try FutureRecordHold.requireWriteAllowed(
          db, entityType: EntityName.task, entityId: Self.taskId))
    }
  }

  func testUnknownAndCorruptInventoryFailClosedWithoutMutatingLocalState() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db)
      try beginPulling(db)
      try stagePage(
        db,
        records: [
          staged(try inboxEnvelope()),
          stagedFuture(futureTaskOperation()),
          AuthoritativeSnapshotRemoteRecord(
            recordName: "corrupt-record", state: .corrupt, envelope: nil),
        ], deletedRecordNames: [])
    }

    XCTAssertThrowsError(
      try store.writer.write { db in _ = try finalize(db) }
    ) { error in
      XCTAssertEqual(
        error as? AuthoritativeSnapshotError,
        .unrecognizedRecords(unknown: 0, corrupt: 1))
    }

    try store.writer.read { db in
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Local title")
      XCTAssertEqual(try AuthoritativeSnapshot.activeSession(db)?.phase, .pulling)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0)
    }
  }

  func testMissingInboxFailsClosedAndKeepsSessionForRecovery() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db)
      try beginPulling(db)
      let task = try envelope(
        kind: .task, id: Self.taskId,
        payload: taskPayload(id: Self.taskId, title: "Remote"))
      try stagePage(db, records: [staged(task)], deletedRecordNames: [])
    }

    XCTAssertThrowsError(
      try store.writer.write { db in _ = try finalize(db) }
    ) { error in
      XCTAssertEqual(error as? AuthoritativeSnapshotError, .missingRequiredInbox)
    }
    try store.writer.read { db in
      XCTAssertNotNil(try AuthoritativeSnapshot.activeSession(db))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.taskId]),
        "Local title")
    }
  }

  func testApplyFailureAfterLocalDeletesRollsBackWholeFinalization() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      // This row is absent remotely, so finalization deletes it before replay.
      try seedTask(db, id: Self.staleTaskId, title: "Must survive rollback")
      try beginPulling(db)
      // This record is structurally decodable but fails typed task validation
      // only during replay, after the stale local row was already deleted.
      var invalidRemoteTask = try envelope(
        kind: .task, id: Self.taskId,
        payload: taskPayload(id: Self.taskId, title: "Cannot apply"))
      guard case .object(var invalidPayload)? = JSONValue.parse(invalidRemoteTask.payload) else {
        return XCTFail("complete task fixture must be an object")
      }
      invalidPayload["status"] = .string("future-status")
      invalidRemoteTask.payload = try SyncCanonicalize.canonicalizeJSON(.object(invalidPayload))
      try stagePage(
        db, records: [staged(try inboxEnvelope()), staged(invalidRemoteTask)],
        deletedRecordNames: [])
    }

    XCTAssertThrowsError(
      try store.writer.write { db in _ = try finalize(db) }
    ) { error in
      guard case .invalidPayload = error as? ApplyError else {
        return XCTFail("expected typed payload rejection, got \(error)")
      }
    }

    try store.writer.read { db in
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [Self.staleTaskId]),
        "Must survive rollback", "a late replay failure rolls back earlier missing-row deletes")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_tombstones"), 0,
        "delete tombstones from the aborted adoption must roll back")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0,
        "delete barriers from the aborted adoption must roll back")
      XCTAssertNotNil(try AuthoritativeSnapshot.activeSession(db))
    }
  }
}
