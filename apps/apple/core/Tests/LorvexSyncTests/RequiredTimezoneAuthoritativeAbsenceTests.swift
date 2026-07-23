import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class RequiredTimezoneAuthoritativeAbsenceTests: XCTestCase {
  private static let timezoneKey = PreferenceKeys.prefTimezone
  private static let timezoneValue = #""America/Los_Angeles""#
  private static let localVersion = "1711234567000_0000_bbbbbbbbbbbbbbbb"
  private static let remoteVersion = "1711234567890_0000_a1b2c3d4a1b2c3d4"
  private static let repairVersion = "2000000000000_0000_cccccccccccccccc"
  private static let databaseInstanceID = "required-timezone-test-database"
  private static let accountID = "required-timezone-test-account"
  private static let zoneID = "LorvexZone"
  private static let deviceID = "required-timezone-test-device"

  private final class FixedHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
    private let lock = NSLock()
    private let state: HlcState

    init() throws {
      state = try HlcState(deviceSuffix: "cccccccccccccccc")
    }

    func generate() -> Hlc {
      lock.lock()
      defer { lock.unlock() }
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

  func testIncrementalPhysicalDeletionPreservesAndReassertsTimezoneOnly() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedPreference(
        db, key: Self.timezoneKey, value: Self.timezoneValue,
        version: Self.localVersion)
      try seedPreference(
        db, key: PreferenceKeys.prefWorkingHours,
        value: #"{"end":"17:00","start":"09:00"}"#,
        version: Self.localVersion)

      let timezoneRecordName = SyncRecordName.opaque(
        entityType: EntityName.preference, entityId: Self.timezoneKey)
      let workingHoursRecordName = SyncRecordName.opaque(
        entityType: EntityName.preference, entityId: PreferenceKeys.prefWorkingHours)
      let result = try CloudInboundCompleteness.reconcilePhysicalDeletions(
        db, deletedRecordNames: [timezoneRecordName, workingHoursRecordName])

      XCTAssertEqual(
        result.requiredReassertions,
        [
          CloudPhysicalDeletionReassertion(
            entityType: .preference, entityId: Self.timezoneKey)
        ])
      XCTAssertEqual(result.removedEntityTypes, [.preference])
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT value FROM preferences WHERE key = ?",
          arguments: [Self.timezoneKey]),
        Self.timezoneValue)
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT value FROM preferences WHERE key = ?",
          arguments: [PreferenceKeys.prefWorkingHours]))

      let outcome = try ConvergenceEmitter.enqueueCurrentCanonicalState(
        db, entityType: EntityName.preference, entityId: Self.timezoneKey,
        mintVersion: { _ in Self.repairVersion }, deviceId: Self.deviceID)
      XCTAssertEqual(outcome, .enqueuedUpsert)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM preferences WHERE key = ?",
          arguments: [Self.timezoneKey]),
        Self.repairVersion)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'
              AND synced_at IS NULL
            """,
          arguments: [EntityName.preference, Self.timezoneKey]),
        Self.repairVersion)
    }
  }

  func testCompleteAuthoritativeSnapshotPreservesAbsentTimezoneWithDominatingReemit() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedPreference(
        db, key: Self.timezoneKey, value: Self.timezoneValue,
        version: Self.localVersion)
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: Self.databaseInstanceID)
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: Self.accountID)
      let boundary = try SyncTestSupport.cloudTraversalBoundary(
        accountIdentifier: Self.accountID, zoneIdentifier: Self.zoneID)
      let session = try AuthoritativeSnapshot.begin(
        db, boundary: boundary, databaseInstanceId: Self.databaseInstanceID)
      try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)
      try AuthoritativeSnapshot.stagePage(
        db, records: [try inboxRecord()], deletedRecordNames: [],
        sessionToken: session.sessionToken)

      let report = try AuthoritativeSnapshot.finalize(
        db,
        registry: EntityApplierRegistry(
          appliers: EntityApplierRegistry.defaultEntityAppliers()),
        hlc: HlcSession(handle: try FixedHlcHandle()), deviceId: Self.deviceID,
        sessionToken: session.sessionToken,
        databaseInstanceId: Self.databaseInstanceID)

      XCTAssertTrue(report.changedEntityTypes.contains(.preference))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT value FROM preferences WHERE key = ?",
          arguments: [Self.timezoneKey]),
        Self.timezoneValue)
      let repairedVersion = try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM preferences WHERE key = ?",
          arguments: [Self.timezoneKey]))
      XCTAssertGreaterThan(
        try Hlc.parseCanonical(repairedVersion),
        try Hlc.parseCanonical(Self.localVersion))
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'
              AND synced_at IS NULL
            """,
          arguments: [EntityName.preference, Self.timezoneKey]),
        repairedVersion)
    }
  }

  private func seedPreference(
    _ db: Database, key: String, value: String, version: String
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO preferences (key, value, version, updated_at)
        VALUES (?, ?, ?, '2026-07-21T00:00:00.000Z')
        ON CONFLICT(key) DO UPDATE SET
          value = excluded.value,
          version = excluded.version,
          updated_at = excluded.updated_at
        """,
      arguments: [key, value, version])
  }

  private func inboxRecord() throws -> AuthoritativeSnapshotRemoteRecord {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string("inbox"),
        "name": .string("Inbox"),
        "created_at": .string("2026-07-21T00:00:00.000Z"),
        "updated_at": .string("2026-07-21T00:00:00.000Z"),
        "version": .string(Self.remoteVersion),
      ]))
    let envelope = try SyncTestSupport.completeEnvelope(
      entityType: .list, entityId: "inbox", operation: .upsert,
      version: try Hlc.parseCanonical(Self.remoteVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "remote-device")
    return AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: EntityName.list, entityId: "inbox"),
      state: .decoded, envelope: envelope)
  }
}
