import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// Service-level coverage for `deleteTag` / `mergeTags` on `SwiftLorvexCoreService`:
/// task-link removal, re-point + de-dupe, the `ai_changelog` row every MCP write
/// must log (Core Design Rule 2), and the `sync_outbox` tombstones — all against
/// a temp store seeded with the authoritative `schema/schema.sql`.
final class SwiftLorvexCoreServiceTagTests: XCTestCase {

  private func makeServiceAndStore() throws -> (SwiftLorvexCoreService, LorvexStore) {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return (SwiftLorvexCoreService(store: store), store)
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    try makeServiceAndStore().0
  }

  private func tagChangelogCount(_ service: SwiftLorvexCoreService, operation: String) throws -> Int {
    try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM ai_changelog WHERE operation = ? AND entity_type = 'tag'",
        arguments: [operation]) ?? -1
    }
  }

  private func outboxCount(
    _ service: SwiftLorvexCoreService, entityType: String, operation: String
  ) throws -> Int {
    try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND operation = ?",
        arguments: [entityType, operation]) ?? -1
    }
  }

  // MARK: - deleteTag

  func testDeleteTagRemovesLinksLogsChangelogAndTombstones() async throws {
    let service = try makeService()
    let a = try await service.createTask(TaskCreateDraft(title: "A", tags: ["work", "urgent"]))
    let b = try await service.createTask(TaskCreateDraft(title: "B", tags: ["work"]))

    let outcome = try await service.deleteTag(name: "work")
    XCTAssertEqual(outcome.tag, "work")
    XCTAssertEqual(outcome.tasksUpdated, 2)
    XCTAssertEqual(Set(outcome.taskIDs), Set([a.id, b.id]))

    // The tag drops out of the catalog; "urgent" survives on A.
    let tags = try await service.listAllTags()
    XCTAssertFalse(tags.contains("work"))
    XCTAssertTrue(tags.contains("urgent"))
    let removed = try await service.getTasksByTag(tag: "work")
    XCTAssertTrue(removed.isEmpty)
    let urgent = try await service.getTasksByTag(tag: "urgent")
    XCTAssertEqual(urgent.map(\.id), [a.id])

    // Exactly one tag-delete changelog row, plus the tag + both edge tombstones.
    XCTAssertEqual(try tagChangelogCount(service, operation: "delete"), 1)
    XCTAssertEqual(try outboxCount(service, entityType: "tag", operation: "delete"), 1)
    XCTAssertEqual(try outboxCount(service, entityType: "task_tag", operation: "delete"), 2)
  }

  func testDeleteTagRejectsUnknownName() async throws {
    let service = try makeService()
    do {
      _ = try await service.deleteTag(name: "ghost")
      XCTFail("deleteTag must reject an unknown tag name")
    } catch let LorvexCoreError.notFound(entity, id) {
      // A name-keyed lookup miss is a typed `.notFound` (MCP wire code
      // `not_found`), carrying the human tag name as `id`.
      XCTAssertEqual(entity, .tag)
      XCTAssertEqual(id, "ghost")
      XCTAssertEqual(
        LorvexCoreError.notFound(entity: entity, id: id).errorDescription,
        "Tag 'ghost' not found.")
    }
  }

  // MARK: - mergeTags

  func testMergeTagsRepointsDedupesLogsChangelogAndTombstones() async throws {
    let service = try makeService()
    let a = try await service.createTask(TaskCreateDraft(title: "A", tags: ["js"]))
    let b = try await service.createTask(TaskCreateDraft(title: "B", tags: ["js", "javascript"]))
    let c = try await service.createTask(TaskCreateDraft(title: "C", tags: ["javascript"]))

    let outcome = try await service.mergeTags(source: "js", target: "javascript")
    XCTAssertEqual(outcome.source, "js")
    XCTAssertEqual(outcome.target, "javascript")
    XCTAssertEqual(outcome.tasksUpdated, 2)
    XCTAssertEqual(outcome.tasksMoved, 1)
    XCTAssertEqual(outcome.tasksDeduped, 1)
    XCTAssertEqual(Set(outcome.taskIDs), Set([a.id, b.id]))

    let tags = try await service.listAllTags()
    XCTAssertFalse(tags.contains("js"))
    XCTAssertTrue(tags.contains("javascript"))
    let leftoverJS = try await service.getTasksByTag(tag: "js")
    XCTAssertTrue(leftoverJS.isEmpty)
    let merged = try await service.getTasksByTag(tag: "javascript")
    XCTAssertEqual(Set(merged.map(\.id)), Set([a.id, b.id, c.id]))

    // One tag-merge changelog row; the source tag + both source edges tombstoned.
    XCTAssertEqual(try tagChangelogCount(service, operation: "merge"), 1)
    XCTAssertEqual(try outboxCount(service, entityType: "tag", operation: "delete"), 1)
    XCTAssertEqual(try outboxCount(service, entityType: "task_tag", operation: "delete"), 2)
  }

  func testMergeTagsRetriesPastFutureSourceAndTargetEdgeVersions() async throws {
    let (service, store) = try makeServiceAndStore()
    let sourceOnly = try await service.createTask(
      TaskCreateDraft(title: "Source only", tags: ["js"]))
    let collision = try await service.createTask(
      TaskCreateDraft(title: "Collision", tags: ["js", "javascript"]))
    let sourceFuture = "9000000000001_0000_aaaaaaaaaaaaaaaa"
    let targetFuture = "9000000000002_0000_bbbbbbbbbbbbbbbb"
    let targetId = try await store.writer.write { db -> String in
      let sourceId = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT id FROM tags WHERE lookup_key = 'js'"))
      let targetId = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT id FROM tags WHERE lookup_key = 'javascript'"))
      try db.execute(
        sql: "UPDATE task_tags SET version = ? WHERE task_id = ? AND tag_id = ?",
        arguments: [sourceFuture, sourceOnly.id, sourceId])
      try db.execute(
        sql: "UPDATE task_tags SET version = ? WHERE task_id = ? AND tag_id = ?",
        arguments: [targetFuture, collision.id, targetId])
      return targetId
    }

    _ = try await service.mergeTags(source: "js", target: "javascript")

    try service.read { db in
      let movedVersion = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT version FROM task_tags WHERE task_id = ? AND tag_id = ?",
          arguments: [sourceOnly.id, targetId]))
      let collisionVersion = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT version FROM task_tags WHERE task_id = ? AND tag_id = ?",
          arguments: [collision.id, targetId]))
      XCTAssertGreaterThan(try Hlc.parse(movedVersion), try Hlc.parse(sourceFuture))
      XCTAssertGreaterThan(try Hlc.parse(collisionVersion), try Hlc.parse(targetFuture))
    }
  }

  func testMergeTagsRejectsUnknownTagsAndSelfMerge() async throws {
    let service = try makeService()
    _ = try await service.createTask(TaskCreateDraft(title: "A", tags: ["alpha"]))

    do {
      _ = try await service.mergeTags(source: "ghost", target: "alpha")
      XCTFail("merge must reject an unknown source tag")
    } catch {}
    do {
      _ = try await service.mergeTags(source: "alpha", target: "ghost")
      XCTFail("merge must reject an unknown target tag")
    } catch {}
    do {
      // Same normalized key (case-only difference) is a self-merge, not a merge.
      _ = try await service.mergeTags(source: "alpha", target: "ALPHA")
      XCTFail("merge must reject a self-merge")
    } catch {}
  }
}
