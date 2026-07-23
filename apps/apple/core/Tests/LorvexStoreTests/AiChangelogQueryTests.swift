import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class AiChangelogQueryTests: XCTestCase {

  private struct TestEntry {
    let id: String
    let timestamp: String
    let operation: String
    let entityType: String
    let entityId: String?
    let entityIds: String?  // JSON array string, e.g. `["t-1","t-2"]`
    let initiatedBy: String
  }

  private func aiUpdate(
    id: String, timestamp: String, entityType: String, entityId: String, operation: String
  ) -> TestEntry {
    TestEntry(
      id: id, timestamp: timestamp, operation: operation,
      entityType: entityType, entityId: entityId,
      entityIds: nil, initiatedBy: "ai")
  }

  private func insertEntry(_ db: Database, _ entry: TestEntry) throws {
    try db.execute(
      sql: """
        INSERT INTO ai_changelog (
            id, timestamp, operation, entity_type, entity_id,
            summary, initiated_by, mcp_tool
        ) VALUES (?, ?, ?, ?, ?, 'summary', ?, 'test_tool')
        """,
      arguments: [
        entry.id, entry.timestamp, entry.operation, entry.entityType,
        entry.entityId, entry.initiatedBy,
      ])
    // The Rust harness routes through `replace_changelog_entities`, which is
    // outside the Phase-2 scope. Parse the bare JSON array here and INSERT
    // directly into `ai_changelog_entities`; the test fixtures only use
    // simple `["…","…"]` arrays of strings.
    if let raw = entry.entityIds {
      let ids = try Self.parseStringArray(raw)
      for eid in ids {
        try db.execute(
          sql: """
            INSERT INTO ai_changelog_entities (changelog_id, entity_id) \
            VALUES (?, ?)
            """,
          arguments: [entry.id, eid])
      }
    }
  }

  /// Minimal JSON-array-of-strings parser sufficient for fixtures like
  /// `["task-1","task-2"]`. Asserts on malformed input.
  private static func parseStringArray(_ raw: String) throws -> [String] {
    let data = raw.data(using: .utf8) ?? Data()
    let any = try JSONSerialization.jsonObject(with: data, options: [])
    guard let arr = any as? [String] else {
      throw NSError(
        domain: "AiChangelogQueryTests", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "expected JSON array of strings: \(raw)"])
    }
    return arr
  }

  // ---------------------------------------------------------------------

  func testExcludesManualRowsAndOrdersDesc() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "older", timestamp: "2026-01-01T00:00:00.000000Z",
          entityType: "task", entityId: "task-1", operation: "create"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "newer", timestamp: "2026-01-02T00:00:00.000000Z",
          entityType: "task", entityId: "task-1", operation: "update"))
      try self.insertEntry(
        db,
        TestEntry(
          id: "manual", timestamp: "2026-01-03T00:00:00.000000Z",
          operation: "update", entityType: "task", entityId: "task-1",
          entityIds: nil, initiatedBy: "manual"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(db, query: AiChangelogQuery(limit: 10))
    }
    XCTAssertEqual(entries.map(\.id), ["newer", "older"])
  }

  func testFiltersByExactEntityIdArrayMember() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        TestEntry(
          id: "match-array", timestamp: "2026-01-01T00:00:00.000000Z",
          operation: "batch_update", entityType: "task", entityId: nil,
          entityIds: "[\"task-1\",\"task-2\"]", initiatedBy: "ai"))
      try self.insertEntry(
        db,
        TestEntry(
          id: "no-substring-match", timestamp: "2026-01-02T00:00:00.000000Z",
          operation: "batch_update", entityType: "task", entityId: nil,
          entityIds: "[\"task-10\"]", initiatedBy: "ai"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(
        db, query: AiChangelogQuery(limit: 10, entityId: "task-1"))
    }
    XCTAssertEqual(entries.count, 1)
    XCTAssertEqual(entries[0].id, "match-array")
  }

  func testFiltersByEntityType() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "t1", timestamp: "2026-01-01T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "create"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "l1", timestamp: "2026-01-02T00:00:00.000000Z",
          entityType: "list", entityId: "l-1", operation: "create"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "t2", timestamp: "2026-01-03T00:00:00.000000Z",
          entityType: "task", entityId: "t-2", operation: "create"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(
        db, query: AiChangelogQuery(limit: 10, entityType: .task))
    }
    XCTAssertEqual(entries.map(\.id), ["t2", "t1"])
  }

  func testFiltersByOperation() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "c1", timestamp: "2026-01-01T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "create"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "u1", timestamp: "2026-01-02T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "update"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "u2", timestamp: "2026-01-03T00:00:00.000000Z",
          entityType: "task", entityId: "t-2", operation: "update"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "d1", timestamp: "2026-01-04T00:00:00.000000Z",
          entityType: "task", entityId: "t-2", operation: "delete"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(
        db, query: AiChangelogQuery(limit: 10, operation: "update"))
    }
    XCTAssertEqual(entries.map(\.id), ["u2", "u1"])
  }

  func testSinceFilterIsStrictlyAfter() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "a", timestamp: "2026-01-01T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "create"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "b", timestamp: "2026-01-02T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "update"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "c", timestamp: "2026-01-03T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "update"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(
        db,
        query: AiChangelogQuery(limit: 10, since: "2026-01-02T00:00:00.000000Z"))
    }
    XCTAssertEqual(entries.map(\.id), ["c"])
  }

  func testCombinesMultipleFilters() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "t-create-old", timestamp: "2026-01-01T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "create"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "t-update-new", timestamp: "2026-01-03T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "update"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "l-update-new", timestamp: "2026-01-04T00:00:00.000000Z",
          entityType: "list", entityId: "l-1", operation: "update"))
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "t-update-old", timestamp: "2026-01-01T12:00:00.000000Z",
          entityType: "task", entityId: "t-2", operation: "update"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(
        db,
        query: AiChangelogQuery(
          limit: 10, entityType: .task, operation: "update",
          since: "2026-01-02T00:00:00.000000Z"))
    }
    XCTAssertEqual(entries.map(\.id), ["t-update-new"])
  }

  func testRespectsLimit() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      for i in 0..<5 {
        try self.insertEntry(
          db,
          self.aiUpdate(
            id: "e-\(i)",
            timestamp: String(format: "2026-01-0%dT00:00:00.000000Z", i + 1),
            entityType: "task", entityId: "t-1", operation: "update"))
      }
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(db, query: AiChangelogQuery(limit: 2))
    }
    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries.map(\.id), ["e-4", "e-3"])
  }

  func testReturnsEmptyWhenNoMatch() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "t1", timestamp: "2026-01-01T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "create"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(
        db, query: AiChangelogQuery(limit: 10, entityId: "nonexistent"))
    }
    XCTAssertTrue(entries.isEmpty)
  }

  func testEntityIdMatchesBothScalarAndArrayMember() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.insertEntry(
        db,
        self.aiUpdate(
          id: "scalar-hit", timestamp: "2026-01-01T00:00:00.000000Z",
          entityType: "task", entityId: "t-1", operation: "create"))
      try self.insertEntry(
        db,
        TestEntry(
          id: "array-hit", timestamp: "2026-01-02T00:00:00.000000Z",
          operation: "batch_update", entityType: "task", entityId: nil,
          entityIds: "[\"t-1\",\"t-2\"]", initiatedBy: "ai"))
      try self.insertEntry(
        db,
        TestEntry(
          id: "miss", timestamp: "2026-01-03T00:00:00.000000Z",
          operation: "batch_update", entityType: "task", entityId: nil,
          entityIds: "[\"t-3\"]", initiatedBy: "ai"))
    }
    let entries = try store.writer.read { db in
      try AiChangelogQueryRepo.listAiChangelog(
        db, query: AiChangelogQuery(limit: 10, entityId: "t-1"))
    }
    XCTAssertEqual(entries.map(\.id), ["array-hit", "scalar-hit"])
  }

  // ai_changelog_actor_filter helper-level tests
  func testRendersBareTablePredicate() {
    XCTAssertEqual(
      AiChangelogActorFilter.assistantActorFilterSql(),
      "(initiated_by IS NULL OR initiated_by NOT IN ('human', 'system', 'user', 'manual'))")
  }

  func testRendersAliasedPredicate() {
    XCTAssertEqual(
      AiChangelogActorFilter.assistantActorFilterSql(forAlias: "ac"),
      "(ac.initiated_by IS NULL OR ac.initiated_by NOT IN ('human', 'system', 'user', 'manual'))")
  }
}
