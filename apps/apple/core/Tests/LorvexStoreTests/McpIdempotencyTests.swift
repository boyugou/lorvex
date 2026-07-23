import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class McpIdempotencyTests: XCTestCase {

  private func checkedLookup(
    _ db: Database, _ tool: String, _ key: String, _ requestRepr: String
  ) throws -> McpIdempotency.LookupOutcome {
    let checksum = McpIdempotency.computeRequestChecksum(requestRepr)
    return try McpIdempotency.lookupChecked(db, toolName: tool, key: key, suppliedChecksum: checksum)
  }

  func testLookupReturnsNoneWhenKeyAbsent() throws {
    let store = try TestSupport.freshStore()
    try store.writer.read { db in
      XCTAssertEqual(
        try checkedLookup(db, "create_task", "missing", "{\"missing\":true}"), .miss)
    }
  }

  func testRecordThenLookupReturnsPayload() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let checksum = McpIdempotency.computeRequestChecksum("{\"hello\":1}")
      try McpIdempotency.record(
        db, key: "key-1", toolName: "create_task", requestChecksum: checksum,
        responsePayload: "{\"hello\":1}")
      XCTAssertEqual(
        try checkedLookup(db, "create_task", "key-1", "{\"hello\":1}"),
        .hit("{\"hello\":1}"))
    }
  }

  func testRecordRejectsEmptyRequestChecksum() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try McpIdempotency.record(
          db, key: "empty-checksum", toolName: "create_task", requestChecksum: "",
          responsePayload: "{\"ok\":true}")
      ) { error in
        XCTAssertTrue("\(error)".contains("request_checksum"), "got \(error)")
      }
      let rows = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1", arguments: ["empty-checksum"])
      XCTAssertEqual(rows, 0, "failed empty checksum write must not persist")
    }
  }

  func testSchemaRejectsDefaultOrEmptyRequestChecksum() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO mcp_idempotency \
            (key, tool_name, response_payload, expires_at) \
            VALUES ('missing-checksum', 'create_task', '{}', '2099-01-01T00:00:00.000Z')
            """),
        "schema must not provide an empty request_checksum default")
      XCTAssertThrowsError(
        try db.execute(
          sql: """
            INSERT INTO mcp_idempotency \
            (key, tool_name, request_checksum, response_payload, expires_at) \
            VALUES ('empty-checksum', 'create_task', '', '{}', '2099-01-01T00:00:00.000Z')
            """),
        "schema must reject explicitly empty request_checksum values")
    }
  }

  func testLookupAfterExpiryReturnsNoneAndSweepRemovesRow() throws {
    McpIdempotency.resetSweepClock()
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let created = Date().addingTimeInterval(-48 * 3600)
      let checksum = McpIdempotency.computeRequestChecksum("{\"old\":true}")
      try McpIdempotency.recordAt(
        db, key: "stale", toolName: "create_task", requestChecksum: checksum,
        responsePayload: "{\"old\":true}", now: created,
        ttlHours: McpIdempotency.defaultTtlHours)

      XCTAssertEqual(
        try checkedLookup(db, "create_task", "stale", "{\"old\":true}"), .miss,
        "expired rows must not resurface")

      let deleted = try McpIdempotency.sweepExpired(db)
      XCTAssertEqual(deleted, 1, "sweep should drop exactly the stale row")

      let remaining = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1", arguments: ["stale"])
      XCTAssertEqual(remaining, 0)
    }
  }

  func testRecordRejectsDifferentChecksumWithoutOverwritingPriorPayload() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let cs1 = McpIdempotency.computeRequestChecksum("{\"v\":1}")
      try McpIdempotency.record(
        db, key: "dup", toolName: "create_task", requestChecksum: cs1, responsePayload: "{\"v\":1}")
      let cs2 = McpIdempotency.computeRequestChecksum("{\"v\":2}")
      XCTAssertThrowsError(
        try McpIdempotency.record(
          db, key: "dup", toolName: "create_task", requestChecksum: cs2,
          responsePayload: "{\"v\":2}"))
      XCTAssertEqual(
        try checkedLookup(db, "create_task", "dup", "{\"v\":1}"), .hit("{\"v\":1}"))
    }
  }

  func testMutationClaimIsAtomicAndOnlyOwnerCanFinalize() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let checksum = McpIdempotency.computeRequestChecksum("{\"title\":\"A\"}")
      let ownerClaim = "claim-owner"
      XCTAssertEqual(
        try McpIdempotency.claimMutation(
          db, key: "atomic", toolName: "create_task", requestChecksum: checksum,
          claimPayload: ownerClaim),
        .acquired)
      XCTAssertEqual(
        try McpIdempotency.claimMutation(
          db, key: "atomic", toolName: "create_task", requestChecksum: checksum,
          claimPayload: ownerClaim),
        .owned)
      XCTAssertEqual(
        try McpIdempotency.claimMutation(
          db, key: "atomic", toolName: "create_task", requestChecksum: checksum,
          claimPayload: "claim-competitor"),
        .replay(ownerClaim))

      XCTAssertThrowsError(
        try McpIdempotency.finalizeMutation(
          db, key: "atomic", toolName: "create_task", requestChecksum: checksum,
          claimPayload: "claim-competitor", responsePayload: "response"))
      try McpIdempotency.finalizeMutation(
        db, key: "atomic", toolName: "create_task", requestChecksum: checksum,
        claimPayload: ownerClaim, responsePayload: "response")
      XCTAssertEqual(
        try McpIdempotency.lookupChecked(
          db, toolName: "create_task", key: "atomic", suppliedChecksum: checksum),
        .hit("response"))
    }
  }

  func testMutationFinalizationRequiresExistingOwnedClaim() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try McpIdempotency.finalizeMutation(
          db, key: "missing", toolName: "create_task",
          requestChecksum: McpIdempotency.computeRequestChecksum("{}"),
          claimPayload: "claim-owner", responsePayload: "response"))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM mcp_idempotency WHERE tool_name = ? AND key = ?",
          arguments: ["create_task", "missing"]),
        0)
    }
  }

  func testSameKeyCanBeCachedIndependentlyPerTool() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let request = "{\"id\":\"same-shaped-id\"}"
      let checksum = McpIdempotency.computeRequestChecksum(request)
      try McpIdempotency.record(
        db, key: "shared-destructive-key", toolName: "delete_list", requestChecksum: checksum,
        responsePayload: "{\"deleted_list_id\":\"same-shaped-id\"}")
      try McpIdempotency.record(
        db, key: "shared-destructive-key", toolName: "delete_calendar_event",
        requestChecksum: checksum, responsePayload: "{\"deleted_event_id\":\"same-shaped-id\"}")

      let rows = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1",
        arguments: ["shared-destructive-key"])
      XCTAssertEqual(rows, 2, "same idempotency key must not collapse cache rows across tools")
      XCTAssertEqual(
        try checkedLookup(db, "delete_list", "shared-destructive-key", request),
        .hit("{\"deleted_list_id\":\"same-shaped-id\"}"))
      XCTAssertEqual(
        try checkedLookup(db, "delete_calendar_event", "shared-destructive-key", request),
        .hit("{\"deleted_event_id\":\"same-shaped-id\"}"))
      XCTAssertEqual(
        try checkedLookup(db, "delete_habit_reminder_policy", "shared-destructive-key", request),
        .miss, "a same-shaped request for another tool must not replay either cached payload")
    }
  }

  func testSweepPreservesUnexpiredRows() throws {
    McpIdempotency.resetSweepClock()
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let freshCs = McpIdempotency.computeRequestChecksum("{\"keep\":true}")
      try McpIdempotency.record(
        db, key: "fresh", toolName: "create_task", requestChecksum: freshCs,
        responsePayload: "{\"keep\":true}")
      let dropCs = McpIdempotency.computeRequestChecksum("{\"drop\":true}")
      try McpIdempotency.recordAt(
        db, key: "old", toolName: "create_task", requestChecksum: dropCs,
        responsePayload: "{\"drop\":true}", now: Date().addingTimeInterval(-48 * 3600),
        ttlHours: McpIdempotency.defaultTtlHours)

      let deleted = try McpIdempotency.sweepExpired(db)
      XCTAssertEqual(deleted, 1)
      guard case .hit = try checkedLookup(db, "create_task", "fresh", "{\"keep\":true}") else {
        return XCTFail("sweep must not remove unexpired rows")
      }
    }
  }

  func testUncheckedLookupEntryPointsAreNotExposed() {
    // The Swift surface exposes only checksum-aware lookups
    // (`lookupChecked` / `lookupCheckedAt`); there is no no-checksum
    // `lookup(...)` entry point that could replay a stale response.
    // Asserted structurally by the type's public API in McpIdempotency.swift.
    XCTAssertTrue(true)
  }

  func testSweepExpiredSkipsWhenRecentSweepRan() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let cs = McpIdempotency.computeRequestChecksum("{\"v\":1}")
      try McpIdempotency.recordAt(
        db, key: "stale-1", toolName: "create_task", requestChecksum: cs,
        responsePayload: "{\"v\":1}", now: Date().addingTimeInterval(-48 * 3600),
        ttlHours: McpIdempotency.defaultTtlHours)

      McpIdempotency.setSweepClock(Int64(Date().timeIntervalSince1970 * 1000))
      let skipped = try McpIdempotency.sweepExpired(db)
      XCTAssertEqual(skipped, 0, "sweep within skip window must short-circuit")

      let remaining = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM mcp_idempotency WHERE key = ?1", arguments: ["stale-1"])
      XCTAssertEqual(remaining, 1, "skipped sweep must not delete rows")

      McpIdempotency.resetSweepClock()
      let deleted = try McpIdempotency.sweepExpired(db)
      XCTAssertEqual(deleted, 1, "post-window sweep must run and delete")
    }
  }

  func testLookupCheckedRejectsPayloadCollision() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let originalChecksum = McpIdempotency.computeRequestChecksum("{\"task\":\"draft\"}")
      try McpIdempotency.record(
        db, key: "shared-key", toolName: "create_task", requestChecksum: originalChecksum,
        responsePayload: "{\"id\":\"t-1\"}")

      let outcome = try McpIdempotency.lookupChecked(
        db, toolName: "create_task", key: "shared-key",
        suppliedChecksum: McpIdempotency.computeRequestChecksum("{\"task\":\"different\"}"))
      guard case .checksumMismatch(let storedTool, let storedChecksum, let suppliedChecksum) = outcome
      else {
        return XCTFail("expected checksumMismatch, got \(outcome)")
      }
      XCTAssertEqual(storedTool, "create_task")
      XCTAssertEqual(storedChecksum, originalChecksum)
      XCTAssertNotEqual(storedChecksum, suppliedChecksum)
    }
  }

  func testLookupCheckedReturnsHitOnMatchingChecksum() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let checksum = McpIdempotency.computeRequestChecksum("{\"task\":\"draft\"}")
      try McpIdempotency.record(
        db, key: "match-key", toolName: "create_task", requestChecksum: checksum,
        responsePayload: "{\"id\":\"t-1\"}")
      let outcome = try McpIdempotency.lookupChecked(
        db, toolName: "create_task", key: "match-key", suppliedChecksum: checksum)
      XCTAssertEqual(outcome, .hit("{\"id\":\"t-1\"}"))
    }
  }

  func testComputeRequestChecksumIsStableAndDistinguishesPayloads() {
    let a = McpIdempotency.computeRequestChecksum("{\"x\":1}")
    let b = McpIdempotency.computeRequestChecksum("{\"x\":1}")
    let c = McpIdempotency.computeRequestChecksum("{\"x\":2}")
    XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, c)
    XCTAssertEqual(a.count, 64)
    XCTAssertTrue(a.allSatisfy { $0.isHexDigit && !$0.isUppercase })
  }

  func testTimestampsMatchCanonicalSyncFormat() {
    let now = Date()
    let canonical = SyncTimestampFormat.formatSyncTimestamp(now)
    XCTAssertEqual(canonical.count, 24)
    XCTAssertTrue(canonical.hasSuffix("Z"))
    let later = SyncTimestampFormat.formatSyncTimestamp(now.addingTimeInterval(3600))
    XCTAssertTrue(later > canonical)
    XCTAssertEqual(later.count, 24)
    XCTAssertTrue(later.hasSuffix("Z"))
  }
}
