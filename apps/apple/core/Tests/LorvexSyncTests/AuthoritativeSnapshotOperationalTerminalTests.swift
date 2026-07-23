import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class AuthoritativeSnapshotOperationalTerminalTests: XCTestCase {
  private final class LockedHlcHandle: HlcDominatingStateHandle, @unchecked Sendable {
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

  private let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000e201"
  private let localVersion = "1800000000100_0000_1111222233334444"
  private let inboxVersion = "1800000000200_0000_2222333344445555"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func envelope(
    kind: EntityKind, id: String, version: Hlc, payload: String
  ) throws -> SyncEnvelope {
    try SyncTestSupport.completeEnvelope(
      entityType: kind, entityId: id, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "remote-device")
  }

  func testAuthoritativeSnapshotParksExactOperationalTerminalWithoutReplacingLocalRow() throws {
    let store = try SyncTestSupport.freshStore()
    let terminal = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs,
      counter: Hlc.maxCounter, deviceSuffix: "ffffffffffffffff")

    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks
              (id, list_id, title, status, version, created_at, updated_at, defer_count)
          VALUES (?, 'inbox', 'Local title', 'open', ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z', 0)
          """,
        arguments: [taskId, localVersion])
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyDatabaseInstanceId,
        value: "snapshot-terminal-database")
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: "snapshot-terminal-account")
      let session = try AuthoritativeSnapshot.begin(
        db,
        boundary: try SyncTestSupport.cloudTraversalBoundary(
          accountIdentifier: "snapshot-terminal-account",
          zoneIdentifier: "LorvexZone-terminal"),
        databaseInstanceId: "snapshot-terminal-database")
      try AuthoritativeSnapshot.markReady(db, sessionToken: session.sessionToken)

      let inboxHlc = try Hlc.parseCanonical(inboxVersion)
      let inboxPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "created_at": .string("2026-07-15T00:00:00.000Z"),
          "name": .string("Inbox"),
          "updated_at": .string("2026-07-15T00:00:00.000Z"),
          "version": .string(inboxVersion),
        ]))
      let terminalPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "created_at": .string("2026-07-15T00:00:00.000Z"),
          "defer_count": .int(0),
          "list_id": .string("inbox"),
          "status": .string("open"),
          "title": .string("Uneditable remote value"),
          "updated_at": .string("2026-07-15T00:00:00.000Z"),
          "version": .string(terminal.description),
        ]))
      let inbox = try envelope(
        kind: .list, id: "inbox", version: inboxHlc, payload: inboxPayload)
      let task = try envelope(
        kind: .task, id: taskId, version: terminal, payload: terminalPayload)
      try AuthoritativeSnapshot.stagePage(
        db,
        records: [inbox, task].map {
          AuthoritativeSnapshotRemoteRecord(
            recordName: SyncRecordName.opaque(
              entityType: $0.entityType.asString, entityId: $0.entityId),
            state: .decoded, envelope: $0)
        },
        deletedRecordNames: [], sessionToken: session.sessionToken)

      let report = try AuthoritativeSnapshot.finalize(
        db, registry: registry,
        hlc: HlcSession(handle: try LockedHlcHandle()),
        deviceId: "snapshot-terminal-device",
        sessionToken: session.sessionToken,
        databaseInstanceId: "snapshot-terminal-database")

      XCTAssertEqual(report.replayedRemoteRecords, 1)
      XCTAssertEqual(report.deferredUnknownTypeRecords, 1)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [taskId]),
        "Local title")
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT envelope_version FROM sync_pending_inbox
            WHERE envelope_entity_type = ? AND envelope_entity_id = ?
              AND reason LIKE ?
            """,
          arguments: [
            EntityName.task, taskId,
            "\(DeferralReason.operationallyUnusableHlcReasonMarker)%",
          ]),
        terminal.description)
      XCTAssertThrowsError(
        try FutureRecordHold.requireWriteAllowed(
          db, entityType: EntityName.task, entityId: taskId))
    }
  }
}
