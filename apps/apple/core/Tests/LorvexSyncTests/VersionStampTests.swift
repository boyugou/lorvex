import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports `lorvex-sync/src/version_stamp/tests.rs`. Covers the simple-PK /
/// composite-PK dispatch table, the LWW gate (`? > version`), and the typed
/// outcomes — entityNotFound, superseded (typed-HLC and byte-fallback), benign
/// equal-version no-op, and the ai_changelog exemption.
final class VersionStampTests: XCTestCase {
  private func seedTask(_ db: Database, id: String, version: String) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES ('inbox', 'Inbox', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """)
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, list_id, version, created_at, updated_at) \
        VALUES (?, 'T', 'inbox', ?, '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')
        """,
      arguments: [id, version])
  }

  func testCoversAllSimplePkEntityTypes() {
    let simpleTypes = [
      "task", "list", "habit", "tag", "calendar_event", "task_reminder",
      "habit_reminder_policy", "preference", "memory",
      "daily_review", "current_focus", "focus_schedule",
    ]
    for et in simpleTypes {
      XCTAssertTrue(VersionStamp.simplePkSupported(et), "simplePkSql should return Some for \(et)")
    }
  }

  func testReturnsNoneForCompositePkTypes() {
    for et in ["task_calendar_event_link", "habit_completion", "task_tag", "task_dependency"] {
      XCTAssertFalse(VersionStamp.simplePkSupported(et), "should return None for composite \(et)")
    }
  }

  func testTaskChecklistItemIsCoveredInSimplePkDispatch() {
    XCTAssertTrue(VersionStamp.simplePkSupported("task_checklist_item"))
  }

  func testStampEntityVersionAllowsKnownNoVersionEntities() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertNoThrow(
        try VersionStamp.stampEntityVersion(
          db, entityType: EntityName.aiChangelog, entityId: "chg-1", version: "0000000000001_0000_0000000000000001"))
    }
  }

  func testStampEntityVersionRejectsMalformedCompositeEntityIds() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try VersionStamp.stampEntityVersion(
          db, entityType: EdgeName.taskTag, entityId: "not-a-composite-id", version: "0000000000001_0000_0000000000000001")
      ) { error in
        guard case VersionStamp.VersionStampError.invalidCompositeEntityId = error else {
          return XCTFail("expected invalidCompositeEntityId, got \(error)")
        }
      }
    }
  }

  func testStampEntityVersionReturnsEntityNotFoundForMissingSimplePkRow() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try VersionStamp.stampEntityVersion(
          db, entityType: EntityName.task, entityId: "no-such-task", version: "0000000000001_0000_0000000000000001")
      ) { error in
        guard case VersionStamp.VersionStampError.entityNotFound(let t, let id) = error else {
          return XCTFail("expected entityNotFound, got \(error)")
        }
        XCTAssertEqual(t, "task")
        XCTAssertEqual(id, "no-such-task")
      }
    }
  }

  func testStampEntityVersionReturnsEntityNotFoundForMissingCompositeEdge() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertThrowsError(
        try VersionStamp.stampEntityVersion(
          db, entityType: EdgeName.taskTag, entityId: "task-missing:tag-missing", version: "0000000000001_0000_0000000000000001")
      ) { error in
        guard case VersionStamp.VersionStampError.entityNotFound(let t, _) = error else {
          return XCTFail("expected entityNotFound, got \(error)")
        }
        XCTAssertEqual(t, "task_tag")
      }
    }
  }

  func testStampEntityVersionDoesNotRegressNewerVersion() throws {
    let store = try SyncTestSupport.freshStore()
    let newer = "1711234567200_0000_dec0000200000002"
    let older = "1711234567000_0000_dec0000100000001"
    try store.writer.write { db in
      try seedTask(db, id: "t-regress", version: newer)
      XCTAssertThrowsError(
        try VersionStamp.stampEntityVersion(
          db, entityType: EntityName.task, entityId: "t-regress", version: older)
      ) { error in
        guard case VersionStamp.VersionStampError.superseded(let t, let id, let existing) = error
        else {
          return XCTFail("expected superseded, got \(error)")
        }
        XCTAssertEqual(t, EntityName.task)
        XCTAssertEqual(id, "t-regress")
        XCTAssertEqual(existing, newer)
      }
      let observed = try String.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id='t-regress'")
      XCTAssertEqual(observed, newer)
    }
  }

  func testStampEntityVersionSurfacesSupersededForUnparseableExistingThatBeatsStampBytewise() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let corruptVersion = "zzz-corrupt"
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try seedTask(db, id: "t-corrupt", version: corruptVersion)
      }
      XCTAssertThrowsError(
        try VersionStamp.stampEntityVersion(
          db, entityType: EntityName.task, entityId: "t-corrupt",
          version: "1711234567000_0000_dec0000100000001")
      ) { error in
        guard case VersionStamp.VersionStampError.superseded(_, _, let existing) = error else {
          return XCTFail("expected superseded, got \(error)")
        }
        XCTAssertEqual(existing, corruptVersion)
      }
    }
  }

  func testStampEntityVersionReturnsSupersededForCompositeEdge() throws {
    let store = try SyncTestSupport.freshStore()
    let parentV = "0000000000000_0000_a0a0a0a0a0a0a0a0"
    let edgeNewer = "1711234567300_0000_dec0000300000003"
    let staleStamp = "1711234567200_0000_dec0000200000002"
    try store.writer.write { db in
      try seedTask(db, id: "t-edge", version: parentV)
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) \
          VALUES ('tag-edge', 'X', 'x', ?, '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')
          """,
        arguments: [parentV])
      try db.execute(
        sql: """
          INSERT INTO task_tags (task_id, tag_id, created_at, version) \
          VALUES ('t-edge', 'tag-edge', '2026-03-01T00:00:00Z', ?)
          """,
        arguments: [edgeNewer])

      XCTAssertThrowsError(
        try VersionStamp.stampEntityVersion(
          db, entityType: EdgeName.taskTag, entityId: "t-edge:tag-edge", version: staleStamp)
      ) { error in
        guard case VersionStamp.VersionStampError.superseded(let t, let id, let existing) = error
        else {
          return XCTFail("expected superseded, got \(error)")
        }
        XCTAssertEqual(t, EdgeName.taskTag)
        XCTAssertEqual(id, "t-edge:tag-edge")
        XCTAssertEqual(existing, edgeNewer)
      }
    }
  }

  func testStampEntityVersionUpdatesWhenNewVersionIsStrictlyGreater() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try seedTask(db, id: "t-forward", version: "0000000000001_0000_0000000000000001")
      XCTAssertNoThrow(
        try VersionStamp.stampEntityVersion(
          db, entityType: EntityName.task, entityId: "t-forward", version: "0000000000002_0000_0000000000000002"))
      let observed = try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id='t-forward'")
      XCTAssertEqual(observed, "0000000000002_0000_0000000000000002")
    }
  }
}
