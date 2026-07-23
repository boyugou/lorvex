import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Audit-stream coverage for remote-authoritative snapshot adoption. The audit
/// table has no LWW `version` column, so it requires explicit inventory and
/// retention assertions separate from the ordinary aggregate tests.
final class AuthoritativeSnapshotAuditTests: XCTestCase {
  private static let account = "account-a"
  private static let zone = "LorvexZone"
  private static let deviceId = "snapshot-test-device"
  private static let databaseInstanceId = "snapshot-test-database"
  private static let remoteVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
  private static let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000a001"
  private static let auditId = "01966a3f-7c8b-7d4e-8f3a-00000000a004"

  private final class LockedHlcHandle: HlcStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let state = try! HlcState(deviceSuffix: "cccccccccccccccc")

    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
      return state.generate(withPhysicalMs: 2_000_000_000_000)
    }
  }

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func envelope(kind: EntityKind, id: String, payload: String) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: kind, entityId: id, operation: .upsert,
      version: try Hlc.parse(Self.remoteVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "remote-device")
  }

  private func staged(_ envelope: SyncEnvelope) -> AuthoritativeSnapshotRemoteRecord {
    AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: envelope.entityType.asString, entityId: envelope.entityId),
      state: .decoded, envelope: envelope)
  }

  private func listPayload() throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string("inbox"), "name": .string("Inbox"),
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
        "version": .string(Self.remoteVersion),
      ]))
  }

  private func changelogPayload(timestamp: String) throws -> String {
    let row = ChangelogWrite.ChangelogRow(
      id: Self.auditId, timestamp: timestamp, operation: "update",
      entityType: EntityName.task, entityId: Self.taskId,
      summary: "Remote audit entry", initiatedBy: "assistant",
      sourceDeviceId: "remote-device")
    return try SyncCanonicalize.canonicalizeJSON(
      ChangelogWrite.buildChangelogSyncPayload(row))
  }

  private func beginReady(_ db: Database) throws -> AuthoritativeSnapshotSession {
    try SyncCheckpoints.set(
      db, key: SyncCheckpoints.keyDatabaseInstanceId,
      value: Self.databaseInstanceId)
    _ = try CloudTraversalWitness.claimAccount(
      db, accountIdentifier: Self.account)
    try Tombstone.observeTrustedServerTime(
      db, accountIdentifier: Self.account,
      serverTime: "2026-07-15T12:00:00.000Z")
    _ = try AuditRetentionFrontier.activateAccount(
      db, accountIdentifier: Self.account, zoneName: Self.zone)
    let session = try AuthoritativeSnapshot.begin(
      db,
      boundary: try SyncTestSupport.cloudTraversalBoundary(
        accountIdentifier: Self.account, zoneIdentifier: Self.zone),
      databaseInstanceId: Self.databaseInstanceId)
    try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)
    return session
  }

  private func finalize(_ db: Database, session: AuthoritativeSnapshotSession) throws
    -> AuthoritativeSnapshotReport
  {
    try AuthoritativeSnapshot.finalize(
      db, registry: registry, hlc: HlcSession(handle: LockedHlcHandle()),
      deviceId: Self.deviceId, sessionToken: session.sessionToken,
      databaseInstanceId: session.databaseInstanceId)
  }

  private func seedChangelog(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO ai_changelog
            (id, timestamp, operation, entity_type, entity_id, summary, initiated_by)
        VALUES (?, '2026-07-13T00:00:00.000Z', 'update', 'task', ?,
                'Local audit entry', 'assistant')
        """, arguments: [Self.auditId, Self.taskId])
    try db.execute(
      sql: "INSERT INTO ai_changelog_entities (changelog_id, entity_id) VALUES (?, ?)",
      arguments: [Self.auditId, Self.taskId])
  }

  private func setRetentionPolicy(
    _ db: Database, policy: ChangelogRetentionPolicy
  ) throws {
    _ = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
      db, accountIdentifier: Self.account, policy: policy,
      policyVersion: Self.remoteVersion)
  }

  func testRemoteAbsentLocalChangelogIsRemovedWithoutInventingBarrier() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedChangelog(db)
      let session = try beginReady(db)
      let inbox = try envelope(kind: .list, id: "inbox", payload: listPayload())
      try AuthoritativeSnapshot.stagePage(
        db, records: [staged(inbox)], deletedRecordNames: [],
        sessionToken: session.sessionToken)

      let report = try finalize(db, session: session)

      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [Self.auditId]), 0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog_entities WHERE changelog_id = ?",
          arguments: [Self.auditId]), 0, "normalized attribution rows must cascade-delete")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.aiChangelog, Self.auditId]),
        0, "remote absence already is authoritative; do not invent a delete")
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.aiChangelog, entityId: Self.auditId))
      XCTAssertGreaterThanOrEqual(report.removedLocalEntities, 1)
      XCTAssertTrue(report.changedEntityTypes.contains(.aiChangelog))
    }
  }

  func testAuthoritativeInventoryRepairsForeignAccountAuditRows() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedChangelog(db)
      let inactiveID = "01966a3f-7c8b-7d4e-8f3a-00000000b004"
      try db.execute(
        sql: """
          INSERT INTO ai_changelog
              (id, timestamp, operation, entity_type, entity_id, summary,
               initiated_by, retention_epoch, retention_account_identifier)
          VALUES (?, '2026-07-13T00:00:00.000Z', 'update', 'task', ?,
                  'Inactive account audit entry', 'assistant', 0, 'account-b')
        """,
        arguments: [inactiveID, Self.taskId])
      let session = try beginReady(db)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [inactiveID]),
        0, "activation repairs any foreign-account canonical audit content")
      let inbox = try envelope(kind: .list, id: "inbox", payload: listPayload())
      try AuthoritativeSnapshot.stagePage(
        db, records: [staged(inbox)], deletedRecordNames: [],
        sessionToken: session.sessionToken)

      _ = try finalize(db, session: session)

      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [Self.auditId]),
        0, "the active account's remote-absent audit row is superseded")
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [inactiveID]),
        0, "only the active account may remain in the queryable audit working set")
    }
  }

  func testRemoteOldChangelogUnderOffRetentionQueuesPhysicalDelete() throws {
    try assertRemoteAuditRejectedByRetention(
      policy: .off, timestamp: "2026-07-14T00:00:00.000Z",
      expectedReason: .belowFrontier)
  }

  func testRemoteOldChangelogUnderDaysRetentionQueuesPhysicalDelete() throws {
    try assertRemoteAuditRejectedByRetention(
      policy: .days(30), timestamp: "2020-01-01T00:00:00.000Z",
      expectedReason: .policyHorizon)
  }

  private func assertRemoteAuditRejectedByRetention(
    policy: ChangelogRetentionPolicy, timestamp: String,
    expectedReason: AuditRetentionPurgeReason,
    file: StaticString = #filePath, line: UInt = #line
  ) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let session = try beginReady(db)
      try setRetentionPolicy(db, policy: policy)

      let inbox = try envelope(kind: .list, id: "inbox", payload: listPayload())
      let audit = try envelope(
        kind: .aiChangelog, id: Self.auditId,
        payload: changelogPayload(timestamp: timestamp))
      try AuthoritativeSnapshot.stagePage(
        db, records: [staged(inbox), staged(audit)],
        deletedRecordNames: [], sessionToken: session.sessionToken)

      let report = try finalize(db, session: session)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [Self.auditId]),
        0, "out-of-window authoritative audit content must not be retained", file: file, line: line)
      XCTAssertNil(
        try Tombstone.getTombstone(
          db, entityType: EntityName.aiChangelog, entityId: Self.auditId),
        "retention no longer leaves an audit death ledger", file: file, line: line)
      let outboxCount = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [EntityName.aiChangelog, Self.auditId])
      XCTAssertEqual(outboxCount, 0, "retention never emits audit deletes", file: file, line: line)
      let purge = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT account_identifier, zone_name, reason
            FROM audit_retention_purge_queue WHERE entity_id = ?
            """,
          arguments: [Self.auditId]),
        file: file, line: line)
      XCTAssertEqual(purge["account_identifier"] as String, Self.account, file: file, line: line)
      XCTAssertEqual(purge["zone_name"] as String, Self.zone, file: file, line: line)
      XCTAssertEqual(
        purge["reason"] as String, expectedReason.rawValue,
        file: file, line: line)
      XCTAssertEqual(report.replayedRemoteRecords, 2, file: file, line: line)
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db), file: file, line: line)
    }
  }
}
