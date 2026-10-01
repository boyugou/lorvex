import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// The `ai_changelog` audit trail is device-local. Verified through the real
/// write surface:
/// - a canonical mutation writes exactly one audit row and never enqueues an
///   `ai_changelog` outbox row;
/// - the retention policy lives in this device's `device_state`, reads back
///   through the preferences surface as its wire value, and rejects invalid
///   values without changing the stored policy;
/// - tightening the policy prunes older rows locally, without sync delete
///   envelopes or tombstones, and `off` purges every row and stops recording;
/// - an inbound `ai_changelog` envelope is skipped and writes nothing.
final class SwiftLorvexCoreServiceAuditTrailTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(
        schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations()))
  }

  private func changelogRowIDs(_ service: SwiftLorvexCoreService) throws -> [String] {
    try service.read { db in try String.fetchAll(db, sql: "SELECT id FROM ai_changelog") }
  }

  /// Every outbox row for the audit entity, synced or not, of any operation.
  private func changelogOutboxCount(_ service: SwiftLorvexCoreService) throws -> Int {
    try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?",
        arguments: [EntityName.aiChangelog]) ?? -1
    }
  }

  private func storedPolicyRow(_ service: SwiftLorvexCoreService) throws -> String? {
    try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM device_state WHERE key = ?",
        arguments: [PreferenceKeys.prefAiChangelogRetentionPolicy])
    }
  }

  /// Insert audit rows backdated by the given number of days and return their ids.
  private func seedAuditRows(
    _ service: SwiftLorvexCoreService, daysAgo: [Int]
  ) throws -> [String] {
    let ids = daysAgo.map { _ in UUID().uuidString.lowercased() }
    try service.write { db in
      for (id, days) in zip(ids, daysAgo) {
        try db.execute(
          sql: """
            INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by)
            VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?), 'create', 'task', 'seed', 'ai')
            """,
          arguments: [id, "-\(days) days"])
      }
    }
    return ids
  }

  func testMutationWritesExactlyOneAuditRowAndEnqueuesNoAuditEnvelope() async throws {
    let service = try makeService()
    let task = try await service.createTask(TaskCreateDraft(title: "A"))

    XCTAssertEqual(
      try changelogRowIDs(service).count, 1, "one createTask should write exactly one audit row")
    XCTAssertEqual(try changelogOutboxCount(service), 0, "the audit row is never queued for sync")
    // The mutation itself still syncs: only the audit entity is device-local.
    XCTAssertTrue(
      try service.pendingOutbound().contains {
        $0.envelope.entityType == .task && $0.envelope.entityId == task.id
      })
  }

  func testEntityDeleteAuditsLocallyWithoutAuditEnvelopeOrTombstone() async throws {
    let service = try makeService()
    let list = try await service.createList(name: "Scratch", description: nil)
    try await service.deleteList(id: list.id)

    let rowIDs = try changelogRowIDs(service)
    XCTAssertGreaterThanOrEqual(rowIDs.count, 2, "the create and the delete are both audited")
    XCTAssertEqual(try changelogOutboxCount(service), 0)
    try service.read { db in
      for id in rowIDs {
        XCTAssertFalse(
          try Tombstone.isTombstoned(db, entityType: EntityName.aiChangelog, entityId: id))
      }
    }
  }

  func testOffPolicyWritesNoAuditRowAndPurgesExistingRows() async throws {
    let service = try makeService()
    _ = try await service.createTask(TaskCreateDraft(title: "before off"))
    XCTAssertEqual(try changelogRowIDs(service).count, 1)

    _ = try await service.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy,
      value: ChangelogRetentionPolicy.off.wireValue)
    XCTAssertEqual(
      try changelogRowIDs(service).count, 0,
      "switching to off purges the existing rows, including the audit of the switch itself")

    _ = try await service.createTask(TaskCreateDraft(title: "hidden"))

    XCTAssertEqual(
      try service.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks") ?? -1 }, 2,
      "the mutation commits even though it is not audited")
    XCTAssertEqual(try changelogRowIDs(service).count, 0)
    XCTAssertEqual(try changelogOutboxCount(service), 0)
  }

  func testInvalidRetentionPolicyWriteIsRejectedWithoutChangingThePolicy() async throws {
    let service = try makeService()
    let key = PreferenceKeys.prefAiChangelogRetentionPolicy

    let initialRead = try await service.getPreference(key: key)
    XCTAssertEqual(initialRead, "\"maximum\"", "an unset policy reads as maximum")

    _ = try await service.setPreference(
      key: key, value: ChangelogRetentionPolicy.days(30).wireValue)
    let rowsBefore = try changelogRowIDs(service).count

    for invalid in ["someday", "0", "-5", "1.5", ""] {
      do {
        _ = try await service.setPreference(key: key, value: invalid)
        XCTFail("expected '\(invalid)' to be rejected as a retention policy")
      } catch let StoreError.validation(message) {
        XCTAssertEqual(
          message,
          "preference '\(key)' must be 'maximum', 'off', or a positive integer day count")
      }
    }

    let storedRead = try await service.getPreference(key: key)
    XCTAssertEqual(storedRead, "30", "a rejected write leaves the stored policy untouched")
    XCTAssertEqual(try storedPolicyRow(service), "30")
    XCTAssertEqual(
      try changelogRowIDs(service).count, rowsBefore, "a rejected write records no audit row")
  }

  func testTighteningRetentionPrunesOlderRowsLocallyWithoutDeleteEnvelopes() async throws {
    let service = try makeService()
    let ids = try seedAuditRows(service, daysAgo: [90, 45, 1])
    let (oldA, oldB, recent) = (ids[0], ids[1], ids[2])

    _ = try await service.setPreference(
      key: PreferenceKeys.prefAiChangelogRetentionPolicy,
      value: ChangelogRetentionPolicy.days(7).wireValue)

    let surviving = Set(try changelogRowIDs(service))
    XCTAssertFalse(surviving.contains(oldA))
    XCTAssertFalse(surviving.contains(oldB))
    XCTAssertTrue(surviving.contains(recent), "a row inside the window is kept")
    XCTAssertEqual(try changelogOutboxCount(service), 0, "pruning queues no audit envelope")
    try service.read { db in
      for id in [oldA, oldB, recent] {
        XCTAssertFalse(
          try Tombstone.isTombstoned(db, entityType: EntityName.aiChangelog, entityId: id))
      }
    }
  }

  func testRetentionPreferenceReadsBackAsWireValueAndIsNeverAPreferenceRow() async throws {
    let service = try makeService()
    let key = PreferenceKeys.prefAiChangelogRetentionPolicy

    let policies: [(ChangelogRetentionPolicy, String)] = [
      (.off, "\"off\""), (.days(30), "30"), (.maximum, "\"maximum\""),
    ]
    for (policy, wire) in policies {
      _ = try await service.setPreference(key: key, value: policy.wireValue)
      let read = try await service.getPreference(key: key)
      let snapshot = try await service.getAllPreferences()
      XCTAssertEqual(read, wire)
      XCTAssertEqual(snapshot.values[key], wire)
    }

    // The policy is device-local state, never a synced `preferences` row.
    _ = try await service.setPreference(key: key, value: ChangelogRetentionPolicy.off.wireValue)
    XCTAssertEqual(try storedPolicyRow(service), "\"off\"")
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM preferences WHERE key = ?", arguments: [key]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.preference, key]),
        0)
    }

    // `maximum` is the absent-row default, so storing it removes the row.
    _ = try await service.setPreference(
      key: key, value: ChangelogRetentionPolicy.maximum.wireValue)
    XCTAssertNil(try storedPolicyRow(service))

    // Deleting the preference resets to `maximum` as well.
    _ = try await service.setPreference(key: key, value: ChangelogRetentionPolicy.days(7).wireValue)
    XCTAssertEqual(try storedPolicyRow(service), "7")
    try await service.deletePreference(key: key)
    XCTAssertNil(try storedPolicyRow(service))
    let afterDelete = try await service.getPreference(key: key)
    XCTAssertEqual(afterDelete, "\"maximum\"")
  }

  func testInboundAuditEnvelopeIsSkippedAndWritesNothing() async throws {
    let service = try makeService()
    let id = UUID().uuidString.lowercased()
    let version = try Hlc.parse("8000000000000_0000_b1b2c3d4b1b2c3d4")
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string(id),
        "timestamp": .string("2026-07-14T12:00:00.000Z"),
        "operation": .string("update"),
        "entity_type": .string("task"),
        "entity_id": .string(UUID().uuidString.lowercased()),
        "summary": .string("peer audit content"),
        "initiated_by": .string("assistant"),
        "source_device_id": .string("peer-device"),
        "version": .string(version.description),
      ]))
    let envelope = SyncEnvelope(
      entityType: .aiChangelog, entityId: id, operation: .upsert,
      version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "peer-device")

    let report = try service.applyInbound([envelope], undecodable: 0)

    XCTAssertEqual(report.applied, 0)
    XCTAssertEqual(report.skipped, 1)
    XCTAssertEqual(report.deferred, 0)
    XCTAssertTrue(try changelogRowIDs(service).isEmpty, "no audit row is written")
    XCTAssertEqual(try changelogOutboxCount(service), 0)
    try service.read { db in
      for table in ["sync_pending_inbox", "sync_conflict_log", "sync_tombstones"] {
        XCTAssertEqual(
          try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)"), 0,
          "a skipped audit envelope leaves nothing in \(table)")
      }
    }
  }
}
