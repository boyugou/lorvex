import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// A canonical recurrence instance has one deterministic task identity.
/// A different id claiming the same natural key is rejected without mutating
/// the established row or manufacturing alias/death state.
final class RecurrenceContentConvergenceTests: XCTestCase {
  private let firstId = "00000000-0000-7000-8000-00000000000a"
  private let secondId = "00000000-0000-7000-8000-00000000000b"
  private let firstVersion = "1711234567000_0000_dec0000100000001"
  private let secondVersion = "1711234568000_0000_dec0000200000002"
  private let groupId = "00000000-0000-7000-8000-00000000d001"
  private let occurrenceDate = "2026-04-02"

  private var registry: EntityApplierRegistry {
    EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
  }

  private func envelope(id: String, version: String, title: String, body: String) throws
    -> SyncEnvelope
  {
    let key = "\(groupId):\(occurrenceDate)"
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "body": .string(body),
        "canonical_occurrence_date": .string(occurrenceDate),
        "created_at": .string("2026-04-01T00:00:00.000Z"),
        "list_id": .string(inboxListId),
        "recurrence_group_id": .string(groupId),
        "recurrence_instance_key": .string(key),
        "status": .string("open"),
        "title": .string(title),
        "updated_at": .string("2026-04-01T00:00:00.000Z"),
      ]))
    return try SyncTestSupport.completeEnvelope(
      entityType: .task, entityId: id, operation: .upsert,
      version: try Hlc.parseCanonical(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "device-remote")
  }

  func testDifferentIdClaimingCanonicalKeyFailsClosed() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertEqual(
        try Apply.applyEnvelope(
          db, registry: registry,
          envelope: try envelope(
            id: firstId, version: firstVersion, title: "Established", body: "keep")),
        .applied)

      XCTAssertThrowsError(
        try Apply.applyEnvelope(
          db, registry: registry,
          envelope: try envelope(
            id: secondId, version: secondVersion, title: "Conflicting", body: "discard"))
      ) { error in
        guard case .invalidPayload(let message) = error as? ApplyError else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("already claimed by task \(firstId)"))
      }

      let row = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT id, title, body, version FROM tasks WHERE id = ?",
          arguments: [firstId]))
      XCTAssertEqual(row["id"] as String, firstId)
      XCTAssertEqual(row["title"] as String, "Established")
      XCTAssertEqual(row["body"] as String?, "keep")
      XCTAssertEqual(row["version"] as String, firstVersion)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM tasks WHERE recurrence_instance_key = ?",
          arguments: ["\(groupId):\(occurrenceDate)"]), 1)
      XCTAssertNil(try TaskSyncRow.load(db, id: secondId))
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'task'"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_entity_redirects"), 0)
    }
  }
}
