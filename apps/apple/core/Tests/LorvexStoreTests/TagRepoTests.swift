import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class TagRepoTests: XCTestCase {

  private let V = "0000000000000_0000_a0a0a0a0a0a0a0a0"
  private let T0 = "2026-04-01T00:00:00.000Z"

  private func tagid(_ id: String) -> TagId { TagId(trusted: id) }

  private func seedTask(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES ('list-default', 'L', ?1, ?2, ?2)
        """,
      arguments: [V, T0])
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, list_id, version, created_at, updated_at) \
        VALUES (?1, 'T', 'list-default', ?2, ?3, ?3)
        """,
      arguments: [id, V, T0])
  }

  private func seedTag(_ db: Database, id: String, name: String, lookupKey: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
        VALUES (?1, ?2, ?3, ?4, ?5, ?5)
        """,
      arguments: [id, name, lookupKey, V, T0])
  }

  private func link(_ db: Database, task: String, tag: String) throws {
    try db.execute(
      sql: "INSERT INTO task_tags (task_id, tag_id, version, created_at) VALUES (?1, ?2, ?3, ?4)",
      arguments: [task, tag, V, T0])
  }

  // -- resolveOrCreateTag --

  func testCreateTagGeneratesUuidAndComputesLookupKey() throws {
    let store = try TestSupport.freshStore()
    let (id, created) = try store.writer.write { db in
      try TagRepo.resolveOrCreateTag(
        db, displayName: "Work", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
    }
    XCTAssertTrue(created)
    XCTAssertEqual(id.count, 36)
    XCTAssertEqual(id.filter { $0 == "-" }.count, 4)

    let tag = try store.writer.read { db in
      try TagRepo.getTagByName(db, name: "work")
    }
    XCTAssertEqual(tag?.displayName, "Work")
    XCTAssertEqual(tag?.lookupKey, "work")
    XCTAssertEqual(tag?.version, "0000000000001_0000_0000000000000001")
  }

  func testResolveOrCreateFindsExisting() throws {
    let store = try TestSupport.freshStore()
    let (id1, c1, id2, c2) = try store.writer.write { db -> (String, Bool, String, Bool) in
      let a = try TagRepo.resolveOrCreateTag(
        db, displayName: "Home", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      let b = try TagRepo.resolveOrCreateTag(
        db, displayName: "home", version: "0000000000002_0000_0000000000000002", now: "2026-01-01T00:00:00.000Z")
      return (a.id, a.wasCreated, b.id, b.wasCreated)
    }
    XCTAssertTrue(c1)
    XCTAssertFalse(c2)
    XCTAssertEqual(id1, id2)
  }

  func testResolveOrCreateDifferentNamesCreateDifferentTags() throws {
    let store = try TestSupport.freshStore()
    let (a, b) = try store.writer.write { db -> (String, String) in
      let x = try TagRepo.resolveOrCreateTag(
        db, displayName: "Work", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      let y = try TagRepo.resolveOrCreateTag(
        db, displayName: "Home", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      return (x.id, y.id)
    }
    XCTAssertNotEqual(a, b)
  }

  // -- getTagByName --

  func testGetTagByNameIsCaseInsensitive() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try TagRepo.resolveOrCreateTag(
        db, displayName: "Urgent", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
    }
    try store.writer.read { db in
      XCTAssertNotNil(try TagRepo.getTagByName(db, name: "urgent"))
      XCTAssertNotNil(try TagRepo.getTagByName(db, name: "URGENT"))
      XCTAssertNotNil(try TagRepo.getTagByName(db, name: "Urgent"))
      XCTAssertNotNil(try TagRepo.getTagByName(db, name: "uRgEnT"))
    }
  }

  func testGetTagByNameReturnsNilWhenAbsent() throws {
    let store = try TestSupport.freshStore()
    let tag = try store.writer.read { db in
      try TagRepo.getTagByName(db, name: "nonexistent")
    }
    XCTAssertNil(tag)
  }

  // -- renameTag --

  func testRenameUpdatesDisplayNameAndLookupKey() throws {
    let store = try TestSupport.freshStore()
    let id = try store.writer.write { db -> String in
      let r = try TagRepo.resolveOrCreateTag(
        db, displayName: "Groceries", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      try TagRepo.renameTag(
        db, tagId: self.tagid(r.id), newDisplayName: "Shopping",
        version: "0000000000002_0000_0000000000000002", now: "2026-01-01T00:00:00.000Z")
      return r.id
    }
    let (oldT, newT) = try store.writer.read { db -> (TagRow?, TagRow?) in
      (try TagRepo.getTagByName(db, name: "Groceries"),
       try TagRepo.getTagByName(db, name: "Shopping"))
    }
    XCTAssertNil(oldT)
    XCTAssertEqual(newT?.displayName, "Shopping")
    XCTAssertEqual(newT?.lookupKey, "shopping")
    XCTAssertEqual(newT?.version, "0000000000002_0000_0000000000000002")
    XCTAssertEqual(newT?.id, id)
  }

  func testRenameSameNormalizedKeyUpdatesDisplayOnly() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let r = try TagRepo.resolveOrCreateTag(
        db, displayName: "work", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      try TagRepo.renameTag(
        db, tagId: self.tagid(r.id), newDisplayName: "Work",
        version: "0000000000002_0000_0000000000000002", now: "2026-01-01T00:00:00.000Z")
    }
    let tag = try store.writer.read { db in
      try TagRepo.getTagByName(db, name: "work")
    }
    XCTAssertEqual(tag?.displayName, "Work")
  }

  func testRenameNonexistentReturnsNotFound() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TagRepo.renameTag(
          db, tagId: self.tagid("nonexistent-id"),
          newDisplayName: "NewName", version: "0000000000001_0000_0000000000000001",
          now: "2026-01-01T00:00:00.000Z")
      }
    ) { err in
      guard case StoreError.notFound(let entity, _) = err else {
        return XCTFail("expected .notFound, got \(err)")
      }
      XCTAssertEqual(entity, EntityName.tag)
    }
  }

  func testRenameWithStaleVersionReturnsStaleVersionError() throws {
    let store = try TestSupport.freshStore()
    let id = try store.writer.write { db -> String in
      let r = try TagRepo.resolveOrCreateTag(
        db, displayName: "Original", version: "0000000000009_0000_0000000000000009", now: "2026-01-01T00:00:00.000Z")
      return r.id
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try TagRepo.renameTag(
          db, tagId: self.tagid(id), newDisplayName: "Stale",
          version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      }
    ) { err in
      guard case StoreError.staleVersion(let entity, let rid) = err else {
        return XCTFail("expected .staleVersion, got \(err)")
      }
      XCTAssertEqual(entity, EntityName.tag)
      XCTAssertEqual(rid, id)
    }
    let canonical = try store.writer.read { db in
      try TagRepo.getTagByName(db, name: "Original")
    }
    XCTAssertEqual(canonical?.version, "0000000000009_0000_0000000000000009")
  }

  // -- CJK / emoji --

  func testCreateCjkTag() throws {
    let store = try TestSupport.freshStore()
    let id = try store.writer.write { db -> String in
      let r = try TagRepo.resolveOrCreateTag(
        db, displayName: "工作", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      XCTAssertTrue(r.wasCreated)
      return r.id
    }
    let tag = try store.writer.read { db in
      try TagRepo.getTagByName(db, name: "工作")
    }
    XCTAssertEqual(tag?.id, id)
    XCTAssertEqual(tag?.displayName, "工作")
    XCTAssertEqual(tag?.lookupKey, "工作")
  }

  func testCreateEmojiTag() throws {
    let store = try TestSupport.freshStore()
    let id = try store.writer.write { db -> String in
      let r = try TagRepo.resolveOrCreateTag(
        db, displayName: "🏠 Home", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      return r.id
    }
    let tag = try store.writer.read { db in
      try TagRepo.getTagByName(db, name: "🏠 home")
    }
    XCTAssertEqual(tag?.id, id)
    XCTAssertEqual(tag?.displayName, "🏠 Home")
  }

  func testRenameChainPreservesIdentity() throws {
    let store = try TestSupport.freshStore()
    let id = try store.writer.write { db -> String in
      let r = try TagRepo.resolveOrCreateTag(
        db, displayName: "Alpha", version: "0000000000001_0000_0000000000000001", now: "2026-01-01T00:00:00.000Z")
      try TagRepo.renameTag(
        db, tagId: self.tagid(r.id), newDisplayName: "Beta",
        version: "0000000000002_0000_0000000000000002", now: "2026-01-01T00:00:00.000Z")
      try TagRepo.renameTag(
        db, tagId: self.tagid(r.id), newDisplayName: "Gamma",
        version: "0000000000003_0000_0000000000000003", now: "2026-01-01T00:00:00.000Z")
      return r.id
    }
    let tag = try store.writer.read { db in
      try TagRepo.getTagByName(db, name: "Gamma")
    }
    XCTAssertEqual(tag?.id, id)
  }

  // -- deleteTag --

  func testDeleteTagRemovesTagRowAndCascadesEdges() throws {
    let store = try TestSupport.freshStore()
    let edges = try store.writer.write { db -> [TaskTagEdge] in
      try self.seedTask(db, "task-1")
      try self.seedTask(db, "task-2")
      try self.seedTag(db, id: "tag-1", name: "Work", lookupKey: "work")
      try self.link(db, task: "task-1", tag: "tag-1")
      try self.link(db, task: "task-2", tag: "tag-1")
      let edges = try TagRepo.taskTagEdges(db, tagId: self.tagid("tag-1"))
      let deleted = try TagRepo.deleteTag(db, tagId: self.tagid("tag-1"))
      XCTAssertEqual(deleted, 1)
      return edges
    }
    XCTAssertEqual(edges.map { $0.taskId }, ["task-1", "task-2"])
    try store.writer.read { db in
      XCTAssertNil(try TagRepo.getTagByName(db, name: "work"))
      // The FK ON DELETE CASCADE drops the tag's task_tags links.
      let edgeCount = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_tags WHERE tag_id = ?", arguments: ["tag-1"])
      XCTAssertEqual(edgeCount, 0)
      // The tasks themselves survive.
      let taskCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks")
      XCTAssertEqual(taskCount, 2)
    }
  }

  func testDeleteTagReturnsZeroWhenAbsent() throws {
    let store = try TestSupport.freshStore()
    let deleted = try store.writer.write { db in
      try TagRepo.deleteTag(db, tagId: self.tagid("missing-id"))
    }
    XCTAssertEqual(deleted, 0)
  }

  // -- mergeTag --

  func testMergeTagRepointsDedupesAndDeletesSource() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> TagMergeRepoResult in
      try self.seedTask(db, "task-1")  // source only
      try self.seedTask(db, "task-2")  // source + target (de-dupes)
      try self.seedTask(db, "task-3")  // target only (untouched)
      try self.seedTag(db, id: "src", name: "JS", lookupKey: "js")
      try self.seedTag(db, id: "tgt", name: "JavaScript", lookupKey: "javascript")
      try self.link(db, task: "task-1", tag: "src")
      try self.link(db, task: "task-2", tag: "src")
      try self.link(db, task: "task-2", tag: "tgt")
      try self.link(db, task: "task-3", tag: "tgt")
      return try TagRepo.mergeTag(
        db, sourceId: self.tagid("src"), targetId: self.tagid("tgt"),
        version: "0000000000003_0000_0e0e000000000001", now: "2026-04-03T00:00:00.000Z")
    }
    XCTAssertEqual(result.sourceEdges.map { $0.taskId }, ["task-1", "task-2"])
    XCTAssertEqual(result.dedupedTaskIds, ["task-2"])
    try store.writer.read { db in
      // Source tag and its edges are gone.
      XCTAssertNil(try TagRepo.getTagByName(db, name: "js"))
      let srcEdges = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM task_tags WHERE tag_id = 'src'")
      XCTAssertEqual(srcEdges, 0)
      // Target now carries all three tasks, de-duplicated (task-2 only once).
      let targetTasks = try String.fetchAll(
        db, sql: "SELECT task_id FROM task_tags WHERE tag_id = 'tgt' ORDER BY task_id ASC")
      XCTAssertEqual(targetTasks, ["task-1", "task-2", "task-3"])
      // Re-pointed edges carry the merge version.
      let v1 = try String.fetchOne(
        db, sql: "SELECT version FROM task_tags WHERE tag_id = 'tgt' AND task_id = 'task-1'")
      XCTAssertEqual(v1, "0000000000003_0000_0e0e000000000001")
      let v2 = try String.fetchOne(
        db, sql: "SELECT version FROM task_tags WHERE tag_id = 'tgt' AND task_id = 'task-2'")
      XCTAssertEqual(v2, "0000000000003_0000_0e0e000000000001")
      // Target tag row survives.
      XCTAssertNotNil(try TagRepo.getTagByName(db, name: "javascript"))
    }
  }

  func testMergeTagNeverLowersFutureSourceOrTargetEdgeVersions() throws {
    let store = try TestSupport.freshStore()
    let sourceFuture = "9000000000001_0000_aaaaaaaaaaaaaaaa"
    let targetFuture = "9000000000002_0000_bbbbbbbbbbbbbbbb"
    try store.writer.write { db in
      try self.seedTask(db, "source-only")
      try self.seedTask(db, "collision")
      try self.seedTag(db, id: "src", name: "Source", lookupKey: "source")
      try self.seedTag(db, id: "tgt", name: "Target", lookupKey: "target")
      try self.link(db, task: "source-only", tag: "src")
      try self.link(db, task: "collision", tag: "src")
      try self.link(db, task: "collision", tag: "tgt")
      try db.execute(
        sql: "UPDATE task_tags SET version = ? WHERE task_id = 'source-only' AND tag_id = 'src'",
        arguments: [sourceFuture])
      try db.execute(
        sql: "UPDATE task_tags SET version = ? WHERE task_id = 'collision' AND tag_id = 'tgt'",
        arguments: [targetFuture])

      _ = try TagRepo.mergeTag(
        db, sourceId: self.tagid("src"), targetId: self.tagid("tgt"),
        version: "1711234569000_0000_dec0000100000001",
        now: "2026-04-03T00:00:00.000Z")

      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: "SELECT version FROM task_tags WHERE task_id = 'source-only' AND tag_id = 'tgt'"),
        sourceFuture)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT version FROM task_tags WHERE task_id = 'collision' AND tag_id = 'tgt'"),
        targetFuture)
    }
  }
}
