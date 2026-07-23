import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// A complete CloudKit snapshot containing a crafted Delete for the permanent
/// inbox is recognized but self-healed. Rejecting it during preflight would
/// leave the same current CloudKit record poisoning every retry forever.
final class AuthoritativeSnapshotRequiredInboxRepairTests: XCTestCase {
  private final class LockedHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let state = try! HlcState(deviceSuffix: "cccccccccccccccc")

    func generate() -> Hlc {
      generate(dominating: nil)
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

  func testSnapshotInboxDeleteFinalizesWithDominatingRepairUpsert() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "snapshot-test-database")
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: "account-a")
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "account-a", zoneIdentifier: "LorvexZone"),
        databaseInstanceId: "snapshot-test-database")
      try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)

      let remoteDelete = try SyncTestSupport.completeEnvelope(
        entityType: .list, entityId: "inbox", operation: .delete,
        version: try Hlc.parse("9000000000000_0000_aaaaaaaaaaaaaaaa"),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "crafted-peer")
      let record = AuthoritativeSnapshotRemoteRecord(
        recordName: SyncRecordName.opaque(entityType: EntityName.list, entityId: "inbox"),
        state: .decoded, envelope: remoteDelete)
      try AuthoritativeSnapshot.stagePage(
        db, records: [record], deletedRecordNames: [],
        sessionToken: session.sessionToken)

      let report = try AuthoritativeSnapshot.finalize(
        db,
        registry: EntityApplierRegistry(
          appliers: EntityApplierRegistry.defaultEntityAppliers()),
        hlc: HlcSession(handle: LockedHlcHandle()), deviceId: "snapshot-test-device",
        sessionToken: session.sessionToken,
        databaseInstanceId: session.databaseInstanceId)

      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT operation, version, payload, disposition,
                 authoritative_session_token
          FROM sync_outbox
          WHERE entity_type = 'list' AND entity_id = 'inbox'
            AND synced_at IS NULL
          """)
      XCTAssertEqual(rows.count, 1)
      let repair = try XCTUnwrap(rows.first)
      XCTAssertEqual(repair["operation"] as String, SyncNaming.opUpsert)
      let repairVersion = try Hlc.parse(repair["version"] as String)
      XCTAssertGreaterThan(repairVersion, remoteDelete.version)
      let payload = try XCTUnwrap(JSONValue.parse(repair["payload"] as String))
      guard case .object(let fields) = payload else {
        return XCTFail("snapshot inbox repair payload must be an object")
      }
      XCTAssertEqual(fields["id"], .string("inbox"))
      XCTAssertEqual(fields["version"], .string(repairVersion.description))
      XCTAssertNil(repair["disposition"] as String?)
      XCTAssertNil(repair["authoritative_session_token"] as String?)

      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM lists WHERE id = 'inbox'"),
        repairVersion.description)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql:
            "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'list' AND entity_id = 'inbox'"),
        0)
      XCTAssertEqual(report.replayedRemoteRecords, 1)
      XCTAssertTrue(report.changedEntityTypes.contains(.list))
      XCTAssertNil(try AuthoritativeSnapshot.activeSession(db))
    }
  }
}
