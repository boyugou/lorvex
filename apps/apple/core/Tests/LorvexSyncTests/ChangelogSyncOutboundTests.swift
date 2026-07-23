import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// ACF-14 cross-device sync for the `ai_changelog` audit stream.
///
/// `ChangelogWrite.buildChangelogSyncPayload` emits exactly the keys the applier
/// reads, so a locally-written row round-trips through id-dedup apply on a peer;
/// the retention horizon in `ChangelogApplier.applyChangelogEntry` drops an
/// inbound row the receiver would immediately prune, so a lagging peer never
/// resurrects a GC'd entry.
final class ChangelogSyncOutboundTests: XCTestCase {
  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      _ = try CloudTraversalWitness.claimAccount(
        db, accountIdentifier: "account-a")
      let serverTime = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')"))
      try Tombstone.observeTrustedServerTime(
        db, accountIdentifier: "account-a", serverTime: serverTime)
      _ = try AuditRetentionFrontier.activateAccount(
        db, accountIdentifier: "account-a", zoneName: "LorvexZone-g1")
      try body(db)
    }
  }

  private func setRetention(_ db: Database, _ policy: ChangelogRetentionPolicy) throws {
    _ = try AuditRetentionFrontier.adoptPolicyForActiveAccount(
      db, accountIdentifier: "account-a", policy: policy,
      policyVersion: "6000000000000_0001_a1b2c3d4a1b2c3d4")
  }

  private func timestampDaysAgo(_ db: Database, _ daysAgo: Int) throws -> String {
    try XCTUnwrap(
      String.fetchOne(
        db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?)",
        arguments: ["-\(daysAgo) days"]))
  }

  private func applyPeer(_ db: Database, id: String, payload: JSONValue) throws {
    try ChangelogApplier.applyChangelogEntry(
      db, entityId: id, payload: try canonicalizeJSON(payload),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion)
  }

  private func peerPayload(id: String, timestamp: String, summary: String = "peer entry") throws
    -> JSONValue
  {
    let row = ChangelogWrite.ChangelogRow(
      id: id, timestamp: timestamp, operation: "create", entityType: "task",
      summary: summary, initiatedBy: "assistant", sourceDeviceId: "peer")
    return try ChangelogWrite.buildChangelogSyncPayload(row)
  }

  private func changelogCount(_ db: Database, id: String) throws -> Int {
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?", arguments: [id]) ?? -1
  }

  // MARK: - Payload builder round-trip

  func testBuiltPayloadRoundTripsThroughApply() throws {
    try withDB { db in
      let row = ChangelogWrite.ChangelogRow(
        id: "11111111-1111-7111-8111-111111111111",
        timestamp: "2026-03-23T12:00:00.000Z",
        operation: "update", entityType: "task", entityId: "task-1",
        entityIds: ["task-1", "task-2"],
        summary: "Renamed a task", initiatedBy: "assistant",
        mcpTool: "update_task", sourceDeviceId: "peer-device",
        beforeJson: #"{"title":"old"}"#, afterJson: #"{"title":"new"}"#)
      let payload = try ChangelogWrite.buildChangelogSyncPayload(row)
      try self.applyPeer(db, id: row.id, payload: payload)

      let stored = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT operation, entity_type, entity_id, summary, initiated_by, mcp_tool,
                   source_device_id, before_json, after_json
            FROM ai_changelog WHERE id = ?
            """,
          arguments: [row.id]))
      XCTAssertEqual(stored["operation"], "update")
      XCTAssertEqual(stored["entity_type"], "task")
      XCTAssertEqual(stored["entity_id"], "task-1")
      XCTAssertEqual(stored["summary"], "Renamed a task")
      XCTAssertEqual(stored["initiated_by"], "assistant")
      XCTAssertEqual(stored["mcp_tool"], "update_task")
      XCTAssertEqual(stored["source_device_id"], "peer-device")
      XCTAssertNotNil(stored["before_json"] as String?)
      XCTAssertNotNil(stored["after_json"] as String?)
      // The stringified `entity_ids` array reconstructs the join registry.
      let entityIds = try String.fetchAll(
        db,
        sql:
          "SELECT entity_id FROM ai_changelog_entities WHERE changelog_id = ? ORDER BY entity_id ASC",
        arguments: [row.id])
      XCTAssertEqual(entityIds, ["task-1", "task-2"])
    }
  }

  // MARK: - Inbound dedup

  func testPeerEntryInsertsOnceAndDedupesById() throws {
    try withDB { db in
      let id = "44444444-4444-7444-8444-444444444444"
      let payload = try self.peerPayload(id: id, timestamp: "2026-03-23T12:00:00.000Z")
      for _ in 0..<2 { try self.applyPeer(db, id: id, payload: payload) }
      XCTAssertEqual(try self.changelogCount(db, id: id), 1)
    }
  }

  // MARK: - Convergence horizon

  func testDaysHorizonDropsStaleButAppliesRecent() throws {
    try withDB { db in
      try self.setRetention(db, .days(30))
      // Older than the 30-day window: a lagging peer must not resurrect it.
      let staleId = "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa"
      try self.applyPeer(
        db, id: staleId,
        payload: try self.peerPayload(id: staleId, timestamp: try self.timestampDaysAgo(db, 45)))
      XCTAssertEqual(try self.changelogCount(db, id: staleId), 0)
      // Inside the window: applies.
      let freshId = "bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb"
      try self.applyPeer(
        db, id: freshId,
        payload: try self.peerPayload(id: freshId, timestamp: try self.timestampDaysAgo(db, 5)))
      XCTAssertEqual(try self.changelogCount(db, id: freshId), 1)
    }
  }

  func testOffPolicyDropsInboundEntry() throws {
    try withDB { db in
      try self.setRetention(db, .off)
      let id = "cccccccc-cccc-7ccc-8ccc-cccccccccccc"
      try self.applyPeer(
        db, id: id, payload: try self.peerPayload(id: id, timestamp: "2026-03-23T12:00:00.000Z"))
      XCTAssertEqual(try self.changelogCount(db, id: id), 0)
    }
  }

  func testMaximumPolicyAppliesAncientEntry() throws {
    try withDB { db in
      try self.setRetention(db, .maximum)
      let id = "dddddddd-dddd-7ddd-8ddd-dddddddddddd"
      try self.applyPeer(
        db, id: id,
        payload: try self.peerPayload(id: id, timestamp: try self.timestampDaysAgo(db, 4000)))
      XCTAssertEqual(try self.changelogCount(db, id: id), 1)
    }
  }

  func testInboundTimestampIsCanonicalizedBeforeRetentionStorage() throws {
    try withDB { db in
      try self.setRetention(db, .maximum)
      let id = "eeeeeeee-eeee-7eee-8eee-eeeeeeeeeeee"
      try self.applyPeer(
        db, id: id,
        payload: try self.peerPayload(id: id, timestamp: "2026-03-23T12:00:00+00:00"))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT timestamp FROM ai_changelog WHERE id = ?", arguments: [id]),
        "2026-03-23T12:00:00.000Z")
    }
  }

  func testInboundInvalidTimestampIsRejected() throws {
    try withDB { db in
      try self.setRetention(db, .maximum)
      let id = "ffffffff-ffff-7fff-8fff-ffffffffffff"
      XCTAssertThrowsError(
        try self.applyPeer(
          db, id: id, payload: try self.peerPayload(id: id, timestamp: "not-a-timestamp")))
      XCTAssertEqual(try self.changelogCount(db, id: id), 0)
    }
  }
}
