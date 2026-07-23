import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Sync round-trip for the additive `available_from` column: outbound emits it
/// via the generic pragma reader, and inbound apply honors the partial-update
/// present-flag (set / clear / preserve-on-absence), mirroring `planned_date`.
final class ApplyTaskAvailableFromTests: XCTestCase {
  private static let taskId = "00000000-0000-7000-8000-0000000000af"
  private static let v1 = "1711234567000_0000_dec0000100000001"
  private static let v2 = "1711234567001_0000_dec0000100000001"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func payload(_ overrides: [String: JSONValue]) -> String {
    var obj: [String: JSONValue] = [
      "title": .string("deferred task"),
      "status": .string("open"),
      "list_id": .string(inboxListId),
      "created_at": .string("2026-04-01T00:00:00.000Z"),
      "updated_at": .string("2026-04-01T00:00:00.000Z"),
    ]
    for (k, v) in overrides { obj[k] = v }
    return (try? SyncCanonicalize.canonicalizeJSON(.object(obj))) ?? "{}"
  }

  private func availableFrom(_ db: Database) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT available_from FROM tasks WHERE id = ?", arguments: [Self.taskId])
  }

  // MARK: - inbound

  func testInboundUpsertSetsAvailableFrom() throws {
    try withDB { db in
      try ApplyTask.applyTaskUpsert(
        db, entityId: Self.taskId,
        payload: self.payload(["available_from": .string("2026-06-20")]),
        version: Self.v1, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
      XCTAssertEqual(try self.availableFrom(db), "2026-06-20")
    }
  }

  func testInboundClearViaExplicitNullPresentFlag() throws {
    try withDB { db in
      try ApplyTask.applyTaskUpsert(
        db, entityId: Self.taskId,
        payload: self.payload(["available_from": .string("2026-06-20")]),
        version: Self.v1, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
      // A newer envelope carrying an explicit null clears it (present flag set).
      try ApplyTask.applyTaskUpsert(
        db, entityId: Self.taskId,
        payload: self.payload(["available_from": .null]),
        version: Self.v2, tieBreak: .rejectEqual, applyTs: "2026-04-02T00:00:00.000Z")
      XCTAssertNil(try self.availableFrom(db))
    }
  }

  func testInboundAbsencePreservesLocalValue() throws {
    try withDB { db in
      try ApplyTask.applyTaskUpsert(
        db, entityId: Self.taskId,
        payload: self.payload(["available_from": .string("2026-06-20")]),
        version: Self.v1, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
      // A newer envelope that omits the key must preserve the local value
      // (present flag 0 → CASE WHEN keeps tasks.available_from).
      try ApplyTask.applyTaskUpsert(
        db, entityId: Self.taskId,
        payload: self.payload(["title": .string("renamed")]),
        version: Self.v2, tieBreak: .rejectEqual, applyTs: "2026-04-02T00:00:00.000Z")
      XCTAssertEqual(try self.availableFrom(db), "2026-06-20", "omitted field preserves local")
    }
  }

  func testMalformedAvailableFromRejectedAtApplyBoundary() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try ApplyTask.buildTaskRow(
          db, taskId: Self.taskId,
          payload: self.payload(["available_from": .string("next friday")]),
          version: Self.v1)
      ) { error in
        guard case ApplyError.invalidPayload(let msg) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(msg.contains("available_from"), "got: \(msg)")
      }
    }
  }

  // MARK: - outbound

  func testOutboundPayloadEmitsAvailableFrom() throws {
    try withDB { db in
      try ApplyTask.applyTaskUpsert(
        db, entityId: Self.taskId,
        payload: self.payload(["available_from": .string("2026-06-20")]),
        version: Self.v1, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
      let snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: Self.taskId)
      guard case .object(let obj) = snapshot else {
        return XCTFail("expected object payload")
      }
      XCTAssertEqual(obj["available_from"], .string("2026-06-20"),
        "generic pragma reader must round-trip available_from outbound")
    }
  }

  func testOutboundPayloadEmitsNullWhenUnset() throws {
    try withDB { db in
      try ApplyTask.applyTaskUpsert(
        db, entityId: Self.taskId, payload: self.payload([:]),
        version: Self.v1, tieBreak: .rejectEqual, applyTs: "2026-04-01T00:00:00.000Z")
      let snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: Self.taskId)
      guard case .object(let obj) = snapshot else {
        return XCTFail("expected object payload")
      }
      XCTAssertEqual(obj["available_from"], .null)
    }
  }
}
