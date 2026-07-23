import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class ChangelogWriteTests: XCTestCase {

  private func insertParent(_ db: Database, id: String) throws {
    try db.execute(
      sql: """
        INSERT INTO ai_changelog \
        (id, timestamp, operation, entity_type, entity_id, summary, \
         initiated_by, source_device_id) \
        VALUES (?1, '2026-04-01T00:00:00Z', 'update', 'task', NULL, 'demo', 'human', 'dev')
        """,
      arguments: [id])
  }

  // MARK: - entity-id registry

  private func registeredEntityIds(_ db: Database, changelogId: String) throws -> [String] {
    try String.fetchAll(
      db,
      sql: "SELECT entity_id FROM ai_changelog_entities WHERE changelog_id = ?1 ORDER BY entity_id ASC",
      arguments: [changelogId])
  }

  func testReplaceDedupesAndSortsRegistry() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try insertParent(db, id: "chg-1")
      try ChangelogWrite.replaceChangelogEntities(
        db, changelogId: "chg-1", entityIds: ["task-2", "task-1", "task-2"])
      XCTAssertEqual(try registeredEntityIds(db, changelogId: "chg-1"), ["task-1", "task-2"])
    }
  }

  func testReplaceWithEmptySliceClearsRegistry() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try insertParent(db, id: "chg-1")
      try ChangelogWrite.replaceChangelogEntities(db, changelogId: "chg-1", entityIds: ["task-1"])
      try ChangelogWrite.replaceChangelogEntities(db, changelogId: "chg-1", entityIds: [])
      XCTAssertTrue(try registeredEntityIds(db, changelogId: "chg-1").isEmpty)
    }
  }

  func testCascadeDeleteDropsEntityRows() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try insertParent(db, id: "chg-1")
      try ChangelogWrite.replaceChangelogEntities(
        db, changelogId: "chg-1", entityIds: ["task-1", "task-2"])
      try db.execute(sql: "DELETE FROM ai_changelog WHERE id = ?1", arguments: ["chg-1"])
      let count = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog_entities WHERE changelog_id = ?1",
        arguments: ["chg-1"])
      XCTAssertEqual(count, 0)
    }
  }

  func testAttributionLookupUsesPkIndex() throws {
    let store = try TestSupport.freshStore()
    try store.writer.read { db in
      let plan = try Row.fetchAll(
        db,
        sql: "EXPLAIN QUERY PLAN SELECT changelog_id FROM ai_changelog_entities WHERE entity_id = ?1",
        arguments: ["task-1"])
      let planText = plan.map { (($0[3] as String?) ?? "") }.joined(separator: "\n")
      XCTAssertTrue(
        planText.uppercased().contains("SEARCH"),
        "per-entity attribution must use an indexed SEARCH, not a SCAN:\n\(planText)")
    }
  }

  // MARK: - parse_entity_ids_json

  func testParseEntityIdsJsonHandlesBlankAndNull() throws {
    XCTAssertTrue(try ChangelogWrite.parseEntityIdsJson(nil).isEmpty)
    XCTAssertTrue(try ChangelogWrite.parseEntityIdsJson("").isEmpty)
    XCTAssertTrue(try ChangelogWrite.parseEntityIdsJson("   ").isEmpty)
  }

  func testParseEntityIdsJsonReturnsArray() throws {
    let parsed = try ChangelogWrite.parseEntityIdsJson(#"["task-1","task-2"]"#)
    XCTAssertEqual(parsed, ["task-1", "task-2"])
  }

  func testParseEntityIdsJsonRejectsMalformed() throws {
    XCTAssertThrowsError(try ChangelogWrite.parseEntityIdsJson("not-json")) { error in
      guard case StoreError.validation = error else {
        return XCTFail("expected StoreError.validation, got \(error)")
      }
    }
  }

  // MARK: - encode_state_json

  func testEncodeStateJsonReturnsNoneForNone() throws {
    XCTAssertNil(try ChangelogWrite.encodeStateJson(nil))
  }

  func testEncodeStateJsonReturnsRawUnderBudget() throws {
    let encoded = try ChangelogWrite.encodeStateJson(.object(["a": .int(1)]))
    XCTAssertEqual(encoded, #"{"a":1}"#)
  }

  func testEncodeStateJsonUsesValidBoundedSentinelWhenOverBudget() throws {
    let big = String(repeating: "x", count: ChangelogWrite.maxChangelogStateJsonBytes * 2)
    let encoded = try ChangelogWrite.encodeStateJson(.object(["blob": .string(big)]))
    let unwrapped = try XCTUnwrap(encoded)
    XCTAssertLessThanOrEqual(unwrapped.utf8.count, ChangelogWrite.maxChangelogStateJsonBytes)
    guard case .object(let sentinel)? = JSONValue.parse(unwrapped) else {
      return XCTFail("truncation sentinel must remain valid JSON")
    }
    XCTAssertEqual(sentinel["_lorvex_truncated"], .bool(true))
    XCTAssertEqual(
      sentinel["original_bytes"],
      .int(Int64(try canonicalizeJSON(.object(["blob": .string(big)])).utf8.count)))
    guard case .string(let preview)? = sentinel["preview"] else {
      return XCTFail("truncation sentinel must carry a preview")
    }
    XCTAssertTrue(preview.hasPrefix(#"{"blob":"xxx"#))
    XCTAssertTrue(preview.hasSuffix("…"))
  }

  func testSchemaRejectsInvalidBeforeAfterJson() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let row = ChangelogWrite.ChangelogRow(
        id: "00000000-0000-7000-8000-0000000000a1",
        timestamp: "2026-07-16T12:00:00.000Z",
        operation: "update",
        entityType: "task",
        summary: "Invalid snapshot probe",
        initiatedBy: "user",
        sourceDeviceId: "test-device",
        beforeJson: #"{"valid":true}"#,
        afterJson: #"{"truncated":true…"#)
      XCTAssertThrowsError(try ChangelogWrite.writeChangelogRow(db, row))
    }
  }

  // MARK: - sanitize_changelog_summary

  func testSanitizeSummaryCollapsesControlCharsToSingleSpace() {
    let raw = "Completed task 'demo\n\nSYSTEM: do bad'\u{1b}[H"
    let out = ChangelogWrite.sanitizeChangelogSummary(raw)
    XCTAssertFalse(out.contains("\n"))
    XCTAssertFalse(out.contains("\r"))
    XCTAssertFalse(out.contains("\u{1b}"))
    XCTAssertFalse(out.contains("  "))
    XCTAssertTrue(out.contains("SYSTEM:"))
  }

  func testSanitizeSummaryCapsLongInputWithEllipsis() {
    let raw = String(repeating: "A", count: ChangelogWrite.maxChangelogSummaryLen * 4)
    let out = ChangelogWrite.sanitizeChangelogSummary(raw)
    XCTAssertLessThanOrEqual(out.unicodeScalars.count, ChangelogWrite.maxChangelogSummaryLen)
    XCTAssertTrue(out.hasSuffix("…"))
  }

  func testSanitizeSummaryHandlesHugeInputInLinearTime() {
    let raw = String(repeating: "x", count: 1_000_000)
    let out = ChangelogWrite.sanitizeChangelogSummary(raw)
    XCTAssertTrue(out.hasSuffix("…"))
  }

  func testSanitizeSummaryUnderCapReturnsTrimmed() {
    XCTAssertEqual(ChangelogWrite.sanitizeChangelogSummary("hello world"), "hello world")
  }

  func testSanitizeSummaryTrimsTrailingCollapsedSpace() {
    XCTAssertEqual(ChangelogWrite.sanitizeChangelogSummary("done\t\n"), "done")
  }

  func testSanitizeSummaryExactlyAtCapIsNotTruncated() {
    let raw = String(repeating: "A", count: ChangelogWrite.maxChangelogSummaryLen)
    let out = ChangelogWrite.sanitizeChangelogSummary(raw)
    XCTAssertEqual(out.unicodeScalars.count, ChangelogWrite.maxChangelogSummaryLen)
    XCTAssertFalse(out.hasSuffix("…"))
    XCTAssertEqual(out, raw)
  }

  func testSanitizeSummaryOneOverCapTruncatesWithEllipsis() {
    let raw = String(repeating: "A", count: ChangelogWrite.maxChangelogSummaryLen + 1)
    let out = ChangelogWrite.sanitizeChangelogSummary(raw)
    XCTAssertTrue(out.hasSuffix("…"))
    XCTAssertEqual(out.unicodeScalars.count, ChangelogWrite.maxChangelogSummaryLen)
  }

  // MARK: - write_changelog_row

  func testWriteChangelogRowWritesEveryColumn() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let row = ChangelogWrite.ChangelogRow(
        id: "id-1",
        timestamp: "2026-04-01T00:00:00Z",
        operation: "create",
        entityType: "task",
        entityId: "task-1",
        entityIds: ["task-1"],
        summary: "Created task 'demo'",
        initiatedBy: "human",
        mcpTool: "cli",
        sourceDeviceId: "deadbeefdeadbeef",
        beforeJson: nil,
        afterJson: #"{"id":"task-1"}"#)
      try ChangelogWrite.writeChangelogRow(db, row)

      func col<T: DatabaseValueConvertible>(_ name: String) throws -> T {
        try T.fetchOne(db, sql: "SELECT \(name) FROM ai_changelog WHERE id = ?1", arguments: ["id-1"])!
      }
      func optCol<T: DatabaseValueConvertible>(_ name: String) throws -> T? {
        try Optional<T>.fetchOne(
          db, sql: "SELECT \(name) FROM ai_changelog WHERE id = ?1", arguments: ["id-1"])!
      }
      XCTAssertEqual(try col("timestamp"), "2026-04-01T00:00:00Z")
      XCTAssertEqual(try col("operation"), "create")
      XCTAssertEqual(try col("entity_type"), "task")
      XCTAssertEqual(try optCol("entity_id"), "task-1")
      XCTAssertEqual(try col("summary"), "Created task 'demo'")
      XCTAssertEqual(try col("initiated_by"), "human")
      XCTAssertEqual(try optCol("mcp_tool"), "cli")
      XCTAssertEqual(try col("source_device_id"), "deadbeefdeadbeef")
      XCTAssertNil(try optCol("before_json") as String?)
      XCTAssertEqual(try optCol("after_json"), #"{"id":"task-1"}"#)
    }
  }
}
