import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Ports `repositories/task/write/tests.rs`.
final class TaskRepoWriteTests: XCTestCase {

  private func tid(_ id: String) -> TaskId { TaskId(trusted: id) }

  private func storeErrorMessage(_ e: Error) -> String {
    switch e as? StoreError {
    case .validation(let m), .invariant(let m), .serialization(let m): return m
    case .staleVersion(let entity, let id): return "stale version: \(entity)/\(id)"
    case .versionSuperseded(let entity, let id, let attempted, let existing):
      return "superseded version: \(entity)/\(id) \(attempted)/\(existing)"
    case .notFound(let entity, let id): return "not found: \(entity)/\(id)"
    case nil: return String(describing: e)
    }
  }

  // MARK: - Create

  func testCreateMinimalTask() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let params = TaskCreateParams(
        id: "t1", title: "Buy milk", status: "open", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T00:00:00Z")
      let row = try TaskRepo.Write.createTask(db, params: params)
      XCTAssertEqual(row.core.id, "t1")
      XCTAssertEqual(row.core.title, "Buy milk")
      XCTAssertEqual(row.core.createdAt, row.core.updatedAt)
      XCTAssertEqual(row.core.version, "0000000000001_0000_0000000000000001")
      XCTAssertEqual(row.core.contentVersion, row.core.version)
      XCTAssertEqual(row.scheduling.scheduleVersion, row.core.version)
      XCTAssertEqual(row.lifecycle.lifecycleVersion, row.core.version)
      XCTAssertEqual(row.lifecycle.archiveVersion, row.core.version)
      XCTAssertEqual(row.lifecycle.recurrenceRolloverState, .none)

      let title = try String.fetchOne(
        db, sql: "SELECT title FROM tasks WHERE id = 't1'")
      XCTAssertEqual(title, "Buy milk")
    }
  }

  func testCreateFullTask() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      var params = TaskCreateParams(
        id: "t2", title: "Full task", status: "open", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T00:00:00Z")
      params.body = "body text"
      params.rawInput = "raw"
      params.aiNotes = "notes"
      params.priority = 2
      params.dueDate = "2026-04-01"
      params.estimatedMinutes = 30
      params.recurrence = "weekly"
      params.recurrenceGroupId = "rg1"
      params.canonicalOccurrenceDate = "2026-04-01"
      params.plannedDate = "2026-04-01"
      try TaskRepo.Write.createTask(db, params: params)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT body, priority, estimated_minutes FROM tasks WHERE id = 't2'"))
      XCTAssertEqual(row["body"] as String?, "body text")
      XCTAssertEqual(row["priority"] as Int64?, 2)
      XCTAssertEqual(row["estimated_minutes"] as Int64?, 30)
    }
  }


  // MARK: - Update

  func testUpdateTitleOnly() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try TaskRepo.Write.createTask(
        db,
        params: TaskCreateParams(
          id: "t3", title: "Original", status: "open", version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T00:00:00Z"))

      var patch = TaskUpdatePatch(
        taskId: "t3", version: "0000000000002_0000_0000000000000002", now: "2026-03-27T01:00:00Z")
      patch.title = "Updated"
      patch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: patch)

      let row = try XCTUnwrap(try Row.fetchOne(
        db,
        sql:
          "SELECT title, content_version, schedule_version, lifecycle_version, archive_version "
          + "FROM tasks WHERE id = 't3'"))
      XCTAssertEqual(row[0] as String, "Updated")
      XCTAssertEqual(row[1] as String, "0000000000002_0000_0000000000000002")
      XCTAssertEqual(row[2] as String, "0000000000001_0000_0000000000000001")
      XCTAssertEqual(row[3] as String, "0000000000001_0000_0000000000000001")
      XCTAssertEqual(row[4] as String, "0000000000001_0000_0000000000000001")
    }
  }

  func testUpdateStatusSetsTransitionMetadata() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try TaskRepo.Write.createTask(
        db,
        params: TaskCreateParams(
          id: "t4", title: "Complete me", status: "open", version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T00:00:00Z"))

      var patch = TaskUpdatePatch(
        taskId: "t4", version: "0000000000002_0000_0000000000000002", now: "2026-03-27T10:00:00Z")
      patch.status = .completed
      patch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: patch)

      let row = try XCTUnwrap(try Row.fetchOne(
        db,
        sql:
          "SELECT completed_at, content_version, schedule_version, lifecycle_version, archive_version "
          + "FROM tasks WHERE id = 't4'"))
      XCTAssertEqual(row[0] as String?, "2026-03-27T10:00:00Z")
      XCTAssertEqual(row[1] as String, "0000000000001_0000_0000000000000001")
      XCTAssertEqual(row[2] as String, "0000000000002_0000_0000000000000002")
      XCTAssertEqual(row[3] as String, "0000000000002_0000_0000000000000002")
      XCTAssertEqual(row[4] as String, "0000000000001_0000_0000000000000001")
    }
  }

  func testUpdateStatusTransitionDoesNotDuplicateExplicitPlannedDate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try TaskRepo.Write.createTask(
        db,
        params: TaskCreateParams(
          id: "reopen-planned", title: "Reopen with a plan", status: "cancelled",
          version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z"))

      var patch = TaskUpdatePatch(
        taskId: "reopen-planned", version: "0000000000002_0000_0000000000000002", now: "2026-03-27T10:00:00Z")
      patch.status = .open
      patch.plannedDate = .set("2026-03-28")
      patch.beforeStatus = .cancelled
      try TaskRepo.Write.applyTaskUpdate(db, patch: patch)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT status, planned_date FROM tasks WHERE id = 'reopen-planned'"))
      XCTAssertEqual(row["status"] as String?, "open")
      XCTAssertEqual(row["planned_date"] as String?, "2026-03-28")
    }
  }

  func testUpdateStatusRequiresTypedBeforeStatus() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try TaskRepo.Write.createTask(
        db,
        params: TaskCreateParams(
          id: "missing-before-status", title: "Complete me", status: "open",
          version: "0000000000001_0000_0000000000000001", now: "2026-03-27T00:00:00Z"))

      var patch = TaskUpdatePatch(
        taskId: "missing-before-status", version: "0000000000002_0000_0000000000000002", now: "2026-03-27T10:00:00Z")
      patch.status = .completed
      // beforeStatus deliberately omitted.

      XCTAssertThrowsError(try TaskRepo.Write.applyTaskUpdate(db, patch: patch)) {
        error in
        guard case .invariant(let message) = error as? StoreError else {
          XCTFail("expected invariant error, got \(error)")
          return
        }
        XCTAssertTrue(message.contains("missing typed before_status"))
        XCTAssertTrue(message.contains("missing-before-status"))
      }

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: "SELECT status, completed_at FROM tasks WHERE id = 'missing-before-status'"))
      XCTAssertEqual(row["status"] as String?, "open")
      XCTAssertNil(row["completed_at"] as String?)
    }
  }

  func testUpdateClearNullableField() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      var create = TaskCreateParams(
        id: "t5", title: "Has body", status: "open", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T00:00:00Z")
      create.body = "body content"
      try TaskRepo.Write.createTask(db, params: create)

      var patch = TaskUpdatePatch(
        taskId: "t5", version: "0000000000002_0000_0000000000000002", now: "2026-03-27T01:00:00Z")
      patch.body = .clear
      patch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: patch)

      let body = try String.fetchOne(db, sql: "SELECT body FROM tasks WHERE id = 't5'")
      XCTAssertNil(body)
    }
  }

  func testUpdateRejectsClearingListId() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try db.execute(
          sql: """
            INSERT INTO lists (id, name, version, created_at, updated_at)
            VALUES ('l1', 'Inbox', '0000000000000_0000_a0a0a0a0a0a0a0a0',
                    '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')
            """)
        var create = TaskCreateParams(
          id: "t6", title: "Keep classified", status: "open", version: "0000000000001_0000_0000000000000001",
          now: "2026-03-27T00:00:00Z")
        create.listId = "l1"
        try TaskRepo.Write.createTask(db, params: create)

        var patch = TaskUpdatePatch(
          taskId: "t6", version: "0000000000002_0000_0000000000000002", now: "2026-03-27T01:00:00Z")
        patch.listId = .clear
        patch.beforeStatus = .open
        try TaskRepo.Write.applyTaskUpdate(db, patch: patch)
      }
    ) { error in
      XCTAssertTrue(
        storeErrorMessage(error).contains("tasks must belong to a real list"),
        "got: \(storeErrorMessage(error))")
    }
  }

  // MARK: - ai_notes set / clear

  func testUpdateSetsAiNotes() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try TaskRepo.Write.createTask(
        db,
        params: TaskCreateParams(
          id: "t-attr", title: "Attribution", status: "open", version: "0000000000001_0000_0000000000000001",
          now: "2026-04-18T00:00:00Z"))

      var patch = TaskUpdatePatch(
        taskId: "t-attr", version: "0000000000002_0000_0000000000000002", now: "2026-04-18T01:00:00Z")
      patch.aiNotes = .set("AI-authored note")
      patch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: patch)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT ai_notes FROM tasks WHERE id = 't-attr'"))
      XCTAssertEqual(row["ai_notes"] as String?, "AI-authored note")
    }
  }

  func testUpdateClearsAiNotes() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      var create = TaskCreateParams(
        id: "t-clear", title: "Clear", status: "open", version: "0000000000001_0000_0000000000000001",
        now: "2026-04-18T00:00:00Z")
      create.aiNotes = "Old note"
      try TaskRepo.Write.createTask(db, params: create)

      var patch = TaskUpdatePatch(
        taskId: "t-clear", version: "0000000000002_0000_0000000000000002", now: "2026-04-18T01:00:00Z")
      patch.aiNotes = .clear
      patch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: patch)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db, sql: "SELECT ai_notes FROM tasks WHERE id = 't-clear'"))
      XCTAssertNil(row["ai_notes"] as String?)
    }
  }

  // MARK: - archived_at round-trip

  func testUpdateArchivedAtRoundTripsThroughPatch() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try TaskRepo.Write.createTask(
        db,
        params: TaskCreateParams(
          id: "t-trash", title: "Trash me", status: "open", version: "0000000000001_0000_0000000000000001",
          now: "2026-04-26T00:00:00Z"))

      // (a) Set archived_at.
      var setPatch = TaskUpdatePatch(
        taskId: "t-trash", version: "0000000000002_0000_0000000000000002", now: "2026-04-26T01:00:00Z")
      setPatch.archivedAt = .set("2026-04-26T01:00:00Z")
      setPatch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: setPatch)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT archived_at FROM tasks WHERE id = 't-trash'"),
        "2026-04-26T01:00:00Z")

      // (c) Unrelated patch leaves archived_at alone.
      var renamePatch = TaskUpdatePatch(
        taskId: "t-trash", version: "0000000000003_0000_0000000000000003", now: "2026-04-26T02:00:00Z")
      renamePatch.title = "Renamed in Trash"
      renamePatch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: renamePatch)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT archived_at FROM tasks WHERE id = 't-trash'"),
        "2026-04-26T01:00:00Z")

      // (b) Clear archived_at.
      var clearPatch = TaskUpdatePatch(
        taskId: "t-trash", version: "0000000000004_0000_0000000000000004", now: "2026-04-26T03:00:00Z")
      clearPatch.archivedAt = .clear
      clearPatch.beforeStatus = .open
      try TaskRepo.Write.applyTaskUpdate(db, patch: clearPatch)
      XCTAssertNil(
        try String.fetchOne(db, sql: "SELECT archived_at FROM tasks WHERE id = 't-trash'"))
    }
  }

  // MARK: - Duplicate

  func testDuplicateCopiesFieldsAndResets() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      var create = TaskCreateParams(
        id: "src", title: "Source task", status: "completed", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T00:00:00Z")
      create.body = "body"
      create.aiNotes = "ai notes"
      create.priority = 3
      create.dueDate = "2026-04-01"
      create.estimatedMinutes = 60
      create.recurrence = "daily"
      create.recurrenceGroupId = "rg1"
      create.canonicalOccurrenceDate = "2026-04-01"
      try TaskRepo.Write.createTask(db, params: create)

      try db.execute(
        sql: "UPDATE tasks SET completed_at = '2026-03-27T05:00:00Z' WHERE id = 'src'")

      let source = try XCTUnwrap(try TaskRepo.Read.getTask(db, taskId: self.tid("src")))

      try TaskRepo.Write.duplicateTask(
        db, source: source, newId: "dup", newTitle: "Source task (copy)",
        recurrenceGroupId: "rg1", canonicalOccurrenceDate: "2026-04-01",
        version: "0000000000002_0000_0000000000000002", now: "2026-03-27T06:00:00Z")

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT status, completed_at, raw_input, defer_count, \
                   title, body, priority FROM tasks WHERE id = 'dup'
            """))
      XCTAssertEqual(row["status"] as String?, "open")
      XCTAssertNil(row["completed_at"] as String?)
      XCTAssertNil(row["raw_input"] as String?)
      XCTAssertEqual(row["defer_count"] as Int64?, 0)
      XCTAssertEqual(row["title"] as String?, "Source task (copy)")
      XCTAssertEqual(row["body"] as String?, "body")
      XCTAssertEqual(row["priority"] as Int64?, 3)
    }
  }
}
