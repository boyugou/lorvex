import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceCloudTransportDebtTests: XCTestCase {
  private struct TransportDebt: Equatable {
    let pending: Int
    let quarantined: Int
    let corruptFences: Int
    let futureRecordHolds: Int
  }

  private let accountA = "account-a"
  private let accountB = "account-b"
  private let zoneA = "LorvexZone-g7"
  private let zoneB = "LorvexZone-g8"

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func boundary(
    account: String? = nil, zone: String? = nil, generation: Int = 7
  ) throws -> CloudTraversalBoundary {
    try CloudTraversalBoundary(
      accountIdentifier: account ?? accountA, zoneIdentifier: zone ?? zoneA,
      generation: generation,
      generationIdentifier: "generation-\(generation)",
      readyWitness: "ready-\(generation)")
  }

  private func seedTransportDebt(
    _ service: SwiftLorvexCoreService, traversalIdentifier: String,
    boundary suppliedBoundary: CloudTraversalBoundary? = nil
  ) async throws -> String {
    let localTask = try await service.createTask(
      title: "Preserved local intent", notes: "")
    let boundary: CloudTraversalBoundary
    if let suppliedBoundary {
      boundary = suppliedBoundary
    } else {
      boundary = try self.boundary()
    }
    _ = try service.claimCloudTraversalAccount(
      accountIdentifier: boundary.accountIdentifier)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: traversalIdentifier, start: .baseline)
    let futureVersion = "1711234567892_0000_b1c2d3e4b1c2d3e4"
    let future = RawEnvelopeFields(
      entityType: EntityName.task, entityId: localTask.id,
      operation: "future_operation", version: futureVersion,
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
      payload: #"{"future":true}"#, deviceId: "future-device")
    _ = try service.applyInboundTraversalPage(
      [], deferredUnknownTypeRecords: [future], cloudReceipts: [], undecodable: 1,
      boundary: boundary, traversalIdentifier: traversalIdentifier,
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x71]), moreComing: true,
        observation: CloudTraversalPageObservation(
          generationRootIdentifier: boundary.generationIdentifier)),
      inboundObservation: CloudInboundPageObservation(
        corruptRecordNames: ["corrupt-record-\(traversalIdentifier)"]))
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO sync_quarantine_blocklist
              (entity_type, entity_id, version, quarantined_at)
          VALUES (?, ?, ?, '2026-07-14T00:00:00.000Z')
        """,
        arguments: [EntityName.task, localTask.id, futureVersion])
      // A complete authoritative snapshot can classify the local payload as a
      // fallback that should disappear only if CloudKit later reports a real
      // physical delete. Explicit account/reupload reset is not that signal.
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET future_record_resolution = ?
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [
          FutureRecordHold.Resolution.remoteAuthoritative.rawValue,
          EntityName.task, localTask.id,
        ])
    }
    return localTask.id
  }

  private func transportDebt(
    _ service: SwiftLorvexCoreService
  ) throws -> TransportDebt {
    try service.read { db in
      TransportDebt(
        pending: try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_pending_inbox") ?? -1,
        quarantined: try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_quarantine_blocklist") ?? -1,
        corruptFences: try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_cloudkit_corrupt_record_fences") ?? -1,
        futureRecordHolds: try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE synced_at IS NULL AND disposition = ?
            """,
          arguments: [Outbox.Disposition.futureRecordHold.rawValue]) ?? -1)
    }
  }

  private func assertCanonicalIntentCanBeReenumerated(
    _ service: SwiftLorvexCoreService, taskID: String,
    file: StaticString = #filePath, line: UInt = #line
  ) async throws {
    XCTAssertEqual(
      try transportDebt(service),
      TransportDebt(pending: 0, quarantined: 0, corruptFences: 0, futureRecordHolds: 0),
      file: file, line: line)
    let task = try await service.loadTask(id: taskID)
    XCTAssertEqual(
      task.title, "Preserved local intent",
      file: file, line: line)
    let oldLineageSlotExists = try service.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [EntityName.task, taskID]) ?? -1
    }
    XCTAssertEqual(oldLineageSlotExists, 0, file: file, line: line)

    let backfill = try service.enqueueFullResyncBackfill()
    XCTAssertGreaterThanOrEqual(backfill.emitted, 1, file: file, line: line)
    let outboxState = try service.read { db -> (exists: Bool, disposition: String?) in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT disposition FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.task, taskID])
      else { return (false, nil) }
      let disposition: String? = row["disposition"]
      return (true, disposition)
    }
    XCTAssertTrue(outboxState.exists, file: file, line: line)
    XCTAssertNil(outboxState.disposition, file: file, line: line)
  }

  func testAccountSwitchClearsTransportDebtAndRearmsLocalIntent() async throws {
    let service = try makeService()
    let taskID = try await seedTransportDebt(
      service, traversalIdentifier: "account-switch")
    XCTAssertEqual(
      try transportDebt(service),
      TransportDebt(pending: 1, quarantined: 1, corruptFences: 1, futureRecordHolds: 1))

    let binding = try service.prepareCloudTraversalForAccountAdoption(
      newAccountIdentifier: accountB, mode: .accountSwitchOrRetry)

    XCTAssertEqual(binding.accountIdentifier, accountB)
    try await assertCanonicalIntentCanBeReenumerated(service, taskID: taskID)
  }

  func testSameAccountZoneReenableClearsTransportDebtAndRearmsLocalIntent() async throws {
    let service = try makeService()
    let taskID = try await seedTransportDebt(
      service, traversalIdentifier: "same-account-zone-reenable")
    XCTAssertEqual(
      try transportDebt(service),
      TransportDebt(pending: 1, quarantined: 1, corruptFences: 1, futureRecordHolds: 1))

    let binding = try service.prepareCloudTraversalForAccountAdoption(
      newAccountIdentifier: accountA, mode: .sameAccountDeletedZoneReupload)

    XCTAssertEqual(binding.accountIdentifier, accountA)
    try await assertCanonicalIntentCanBeReenumerated(service, taskID: taskID)
  }

  func testSameAccountOrdinaryRetryPreservesNewTransportLineage() async throws {
    let service = try makeService()
    _ = try await seedTransportDebt(
      service, traversalIdentifier: "old-account-lineage")
    _ = try service.prepareCloudTraversalForAccountAdoption(
      newAccountIdentifier: accountB, mode: .accountSwitchOrRetry)

    let newBoundary = try boundary(account: accountB, zone: zoneB, generation: 8)
    let taskID = try await seedTransportDebt(
      service, traversalIdentifier: "new-account-lineage", boundary: newBoundary)
    let debtBefore = try transportDebt(service)
    let traversalBefore = try service.cloudTraversalState(
      accountIdentifier: accountB, zoneIdentifier: zoneB)
    XCTAssertNotNil(traversalBefore.progress)
    try service.write { db in
      try SyncCheckpoints.set(
        db, key: SyncCheckpoints.keyReseedRequired, value: "true")
    }

    let binding = try service.prepareCloudTraversalForAccountAdoption(
      newAccountIdentifier: accountB, mode: .accountSwitchOrRetry)

    XCTAssertEqual(binding.accountIdentifier, accountB)
    XCTAssertEqual(try transportDebt(service), debtBefore)
    XCTAssertEqual(
      try service.cloudTraversalState(
        accountIdentifier: accountB, zoneIdentifier: zoneB),
      traversalBefore)
    XCTAssertTrue(try service.isReseedRequired())
    let task = try await service.loadTask(id: taskID)
    XCTAssertEqual(task.title, "Preserved local intent")
  }

  func testExplicitReuploadPreservesTombstoneForCandidateEnumeration() async throws {
    let service = try makeService()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: accountA)
    let task = try await service.createTask(title: "Deleted local intent", notes: "")
    try await service.permanentlyDeleteTask(id: task.id)
    let tombstoneVersion = try service.read { db in
      try String.fetchOne(
        db,
        sql: """
          SELECT version FROM sync_tombstones
          WHERE entity_type = ? AND entity_id = ?
          """,
        arguments: [EntityName.task, task.id])
    }
    XCTAssertNotNil(tombstoneVersion)
    let futureVersion = "1711234567892_0000_b1c2d3e4b1c2d3e4"
    try service.deferUnknownTypeRecords([
      RawEnvelopeFields(
        entityType: EntityName.task, entityId: task.id,
        operation: "future_operation", version: futureVersion,
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion + 1,
        payload: #"{"future":true}"#, deviceId: "future-device")
    ])
    let fencedCount = try service.write { db in
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET future_record_resolution = ?
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [
          FutureRecordHold.Resolution.remoteAuthoritative.rawValue,
          EntityName.task, task.id,
        ])
      return db.changesCount
    }
    XCTAssertEqual(fencedCount, 1)

    _ = try service.prepareCloudTraversalForAccountAdoption(
      newAccountIdentifier: accountA, mode: .sameAccountDeletedZoneReupload)

    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM sync_tombstones
            WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.task, task.id])
      },
      tombstoneVersion)
    let remainingTaskOutbox = try service.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT operation, disposition FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [EntityName.task, task.id]
      ).map { row in
        let operation: String = row["operation"]
        let disposition: String? = row["disposition"]
        return "\(operation)|\(disposition ?? "active")"
      }
    }
    XCTAssertTrue(remainingTaskOutbox.isEmpty, "remaining outbox: \(remainingTaskOutbox)")

    _ = try service.enqueueFullResyncBackfill()
    let delete = try XCTUnwrap(
      try service.pendingOutbound().map(\.envelope).first {
        $0.entityType == .task && $0.entityId == task.id
      })
    XCTAssertEqual(delete.operation, .delete)
    XCTAssertEqual(delete.version.description, tombstoneVersion)
  }

  func testZoneDeletionClearsOnlyExactAccountZoneCorruptFences() throws {
    let service = try makeService()
    let accountA = accountA
    let accountB = accountB
    let zoneA = zoneA
    let zoneB = zoneB
    try service.write { db in
      let observedAt = "2026-07-14T00:00:00.000Z"
      let rows = [
        (accountA, zoneA, 7, "generation-7", "ready-7", "a-zone-a-7"),
        (accountA, zoneA, 8, "generation-8", "ready-8", "a-zone-a-8"),
        (accountA, zoneB, 8, "generation-8", "ready-8", "a-zone-b-8"),
        (accountB, zoneA, 7, "generation-7", "ready-7", "b-zone-a-7"),
      ]
      for row in rows {
        try db.execute(
          sql: """
            INSERT INTO sync_cloudkit_corrupt_record_fences (
              account_identifier, zone_identifier, generation,
              generation_identifier, ready_witness, record_name,
              first_observed_at, last_observed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            row.0, row.1, row.2, row.3, row.4, row.5, observedAt, observedAt,
          ])
      }
    }

    try service.acknowledgeAuditRetentionZoneDeletion(
      forAccountIdentifier: accountA, zoneName: zoneA)

    let remaining = try service.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT account_identifier, zone_identifier, record_name
          FROM sync_cloudkit_corrupt_record_fences
          ORDER BY account_identifier, zone_identifier, record_name
          """
      ).map { row in
        let account: String = row["account_identifier"]
        let zone: String = row["zone_identifier"]
        let record: String = row["record_name"]
        return "\(account)|\(zone)|\(record)"
      }
    }
    XCTAssertEqual(
      remaining,
      [
        "account-a|LorvexZone-g8|a-zone-b-8",
        "account-b|LorvexZone-g7|b-zone-a-7",
      ])
  }
}
