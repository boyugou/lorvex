import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// The reminder wall-clock anchor is one semantic value split across two wire
/// fields. The executable manifest validates each field, while this cross-field
/// probe proves a malformed pair is rejected before FK parking or mutation.
final class SyncPayloadReminderAnchorContractTests: XCTestCase {
  private func goldenReminder() throws -> SyncEnvelope {
    try XCTUnwrap(
      SyncPayloadContractFixture.goldenEnvelopes().first {
        $0.entityType == .taskReminder
      })
  }

  private func replacingPayload(
    _ envelope: SyncEnvelope, mutate: (inout [String: JSONValue]) -> Void
  ) throws -> SyncEnvelope {
    guard case .object(var object)? = JSONValue.parse(envelope.payload) else {
      throw XCTSkip("golden task-reminder payload is not an object")
    }
    mutate(&object)
    return SyncEnvelope(
      entityType: envelope.entityType, entityId: envelope.entityId,
      operation: envelope.operation, version: envelope.version,
      payloadSchemaVersion: envelope.payloadSchemaVersion,
      payload: try SyncCanonicalize.canonicalizeJSON(.object(object)),
      deviceId: envelope.deviceId)
  }

  func testManifestAcceptsAbsentOrCompleteAnchor() throws {
    let golden = try goldenReminder()
    let absent = try replacingPayload(golden) {
      $0["original_local_time"] = .null
      $0["original_tz"] = .null
    }
    let complete = try replacingPayload(golden) {
      $0["original_local_time"] = .string("09:05")
      $0["original_tz"] = .string("America/Los_Angeles")
    }

    XCTAssertNoThrow(try SyncPayloadContractRegistry.validate(absent))
    XCTAssertNoThrow(try SyncPayloadContractRegistry.validate(complete))
  }

  func testManifestRejectsPartialAndMalformedAnchor() throws {
    let golden = try goldenReminder()
    let partial = try replacingPayload(golden) {
      $0["original_local_time"] = .string("09:05")
      $0["original_tz"] = .null
    }
    let badTime = try replacingPayload(golden) {
      $0["original_local_time"] = .string("24:00")
      $0["original_tz"] = .string("America/Los_Angeles")
    }
    let badZone = try replacingPayload(golden) {
      $0["original_local_time"] = .string("09:05")
      $0["original_tz"] = .string("Not/A_Real_Zone")
    }

    for envelope in [partial, badTime, badZone] {
      XCTAssertThrowsError(try SyncPayloadContractRegistry.validate(envelope)) { error in
        guard case SyncPayloadContractError.violations = error else {
          return XCTFail("expected deterministic contract violation, got \(error)")
        }
      }
    }
  }

  func testInboundPartialAnchorRejectsBeforePendingOrMutation() throws {
    let partial = try replacingPayload(try goldenReminder()) {
      $0["original_local_time"] = .string("09:05")
      $0["original_tz"] = .null
    }
    let store = try SyncTestSupport.freshStore()
    let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())

    try store.writer.write { db in
      XCTAssertThrowsError(try Apply.applyEnvelope(db, registry: registry, envelope: partial)) {
        error in
        guard case ApplyError.invalidPayload(let detail) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(detail.contains("must both be null or both be present"))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_pending_inbox"), 0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task_reminders"), 0)
    }
  }

  func testOutboundPartialAnchorRejectsWithoutOutboxRow() throws {
    let partial = try replacingPayload(try goldenReminder()) {
      $0["original_local_time"] = .string("09:05")
      $0["original_tz"] = .null
    }
    let store = try SyncTestSupport.freshStore()

    try store.writer.write { db in
      XCTAssertThrowsError(try Outbox.enqueueCoalesced(db, partial)) { error in
        guard case Outbox.OutboxError.invalidPayloadContract(let detail) = error else {
          return XCTFail("expected invalidPayloadContract, got \(error)")
        }
        XCTAssertTrue(detail.contains("must both be null or both be present"))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }
}
