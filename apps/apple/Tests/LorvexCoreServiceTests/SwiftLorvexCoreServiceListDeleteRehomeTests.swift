import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// A LOCAL `deleteList` re-homes a trashed task the same way the sync-apply path
/// re-homes a peer's list delete: the schema trigger `trg_lists_before_delete`
/// moves EVERY task still pointing at the list to inbox — including trashed
/// (`archived_at IS NOT NULL`) tasks the `assigned` guard doesn't count — with no
/// version bump and no outbox row. The local path must re-propagate that move as
/// a versioned edit (and log it), so local and remote authoring converge and are
/// audited identically.
final class SwiftLorvexCoreServiceListDeleteRehomeTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  func testLocalDeleteListPropagatesAndLogsTrashedTaskRehome() async throws {
    let listL = "01966a3f-7c8b-7d4e-8f3a-00000000e001"
    let trashedTask = "01966a3f-7c8b-7d4e-8f3a-00000000e002"
    let seedVersion = "0000000000000_0000_0000000000000000"
    let service = try makeService()

    try service.write { db in
      // A non-inbox list L (alongside the seeded inbox, so two lists exist) that
      // holds only a TRASHED task — the `assigned` guard, which ignores
      // `archived_at IS NOT NULL` rows, lets the delete proceed.
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at)
          VALUES (?, 'L', ?, '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
          """,
        arguments: [listL, seedVersion])
      try db.execute(
        sql: """
          INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at,
                             archived_at, defer_count)
          VALUES (?, ?, 'Trashed', 'open', ?, '2026-04-19T08:00:00.000Z',
                  '2026-04-19T08:00:00.000Z', '2026-04-19T09:00:00.000Z', 0)
          """,
        arguments: [trashedTask, listL, seedVersion])
    }

    try await service.deleteList(id: listL)

    // The list is gone and the trashed task was re-homed to inbox locally.
    let (listExists, taskListId, taskVersion, contentVersion) = try service.read { db in
      (
        try Bool.fetchOne(db, sql: "SELECT 1 FROM lists WHERE id = ?", arguments: [listL]) ?? false,
        try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [trashedTask]),
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [trashedTask]),
        try String.fetchOne(
          db, sql: "SELECT content_version FROM tasks WHERE id = ?", arguments: [trashedTask])
      )
    }
    XCTAssertFalse(listExists, "the list was deleted")
    XCTAssertEqual(taskListId, "inbox", "the trashed task was re-homed to inbox")
    XCTAssertNotEqual(
      taskVersion, seedVersion, "the re-home minted a fresh dominating HLC on the task")
    XCTAssertEqual(
      contentVersion, taskVersion,
      "list_id belongs to the content register, so the re-home must stamp that register")

    // The re-home was PROPAGATED: a task upsert carrying list_id=inbox is queued.
    let pending = try service.pendingOutbound()
    let rehomeUpsert = pending.first {
      $0.envelope.entityType == .task && $0.envelope.entityId == trashedTask
        && $0.envelope.operation == .upsert
    }
    let upsert = try XCTUnwrap(
      rehomeUpsert, "the local list-delete must enqueue a re-home upsert for the trashed task")
    XCTAssertTrue(
      upsert.envelope.payload.contains("\"list_id\":\"inbox\""),
      "the propagated upsert carries list_id=inbox; got \(upsert.envelope.payload)")
    let registerIntent = try service.read { db in
      try Int64.fetchOne(
        db,
        sql: """
          SELECT register_intent FROM sync_outbox
          WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [trashedTask])
    }
    XCTAssertEqual(registerIntent, TaskRegisterIntent.content.rawValue)

    // The re-home is AUDITED: a changelog row records the move.
    let rehomeChangelog = try service.read { db in
      try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE summary LIKE '%Re-homed%'") ?? 0
    }
    XCTAssertGreaterThanOrEqual(rehomeChangelog, 1, "the re-home wrote a changelog row")
  }

  /// Deleting the list that `default_list_id` points at must repoint the default
  /// to inbox (a synced preference upsert), so the deletion never leaves a
  /// dangling default pointer on this device or its peers.
  func testDeletingTheDefaultListRepointsTheDefaultToInbox() async throws {
    let listL = "01966a3f-7c8b-7d4e-8f3a-00000000e101"
    let seedVersion = "0000000000000_0000_0000000000000000"
    let service = try makeService()
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at)
          VALUES (?, 'L', ?, '2026-04-19T08:00:00.000Z', '2026-04-19T08:00:00.000Z')
          """,
        arguments: [listL, seedVersion])
    }
    _ = try await service.setPreference(key: PreferenceKeys.prefDefaultListId, value: listL)
    try await service.deleteList(id: listL)

    let defaultRaw = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?",
        arguments: [PreferenceKeys.prefDefaultListId])
    }
    XCTAssertEqual(
      defaultRaw, "\"inbox\"", "deleting the default list repoints default_list_id to inbox")

    let pending = try service.pendingOutbound()
    XCTAssertTrue(
      pending.contains {
        $0.envelope.entityType == .preference
          && $0.envelope.entityId == PreferenceKeys.prefDefaultListId
      },
      "the repoint enqueues a default_list_id preference upsert for peers")
  }

  /// Setting `default_list_id` to a list that does not exist is rejected up front
  /// rather than silently stored as a dangling pointer.
  func testSetDefaultListRejectsNonExistentList() async throws {
    let service = try makeService()
    let missingListID = "01966a3f-7c8b-7d4e-8f3a-0000000000ff"
    do {
      _ = try await service.setPreference(
        key: PreferenceKeys.prefDefaultListId, value: missingListID)
      XCTFail("expected a validation error for a default_list_id pointing at a missing list")
    } catch let StoreError.validation(message) {
      XCTAssertEqual(message, "list '\(missingListID)' does not exist")
    }
  }
}
