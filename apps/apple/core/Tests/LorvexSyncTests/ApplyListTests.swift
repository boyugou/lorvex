import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity `#[test]` cases for the `list` aggregate delete handler: the
/// re-home-via-trigger path for non-inbox lists (active + archived tasks), the
/// permanent required-inbox rejection, and the clean no-reference delete.
final class ApplyListTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func seedList(_ db: Database, id: String, version: String) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, version, created_at, updated_at)
        VALUES (?, 'list-name', ?, '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z')
        """,
      arguments: [id, version])
  }

  private func seedTask(_ db: Database, id: String, listId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at, defer_count)
        VALUES (?, ?, 'task', 'open', '0000000000000_0000_a0a0a0a0a0a0a0a0',
                '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z', 0)
        """,
      arguments: [id, listId])
  }

  private func seedArchivedTask(_ db: Database, id: String, listId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, list_id, title, status, version, created_at, updated_at,
                           archived_at, defer_count)
        VALUES (?, ?, 'trashed task', 'open', '0000000000000_0000_a0a0a0a0a0a0a0a0',
                '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z', '2026-04-19T07:30:00Z', 0)
        """,
      arguments: [id, listId])
  }

  private func countConflicts(_ db: Database, entityId: String, resolution: String) throws -> Int64
  {
    try Int64.fetchOne(
      db,
      sql: """
        SELECT COUNT(*) FROM sync_conflict_log
        WHERE entity_type = ? AND entity_id = ? AND resolution_type = ?
        """,
      arguments: [EntityName.list, entityId, resolution]) ?? -1
  }

  func testApplyListDeleteProceedsWhenActiveTasksReferenceNonInboxList() throws {
    try withDB { db in
      try self.seedList(db, id: "l-target", version: "1711234560000_0000_aaaaaaaaaaaaaaaa")
      try self.seedTask(db, id: "t-1", listId: "l-target")

      let result = try ApplyList.applyListDelete(
        db, entityId: "l-target", version: "1711234569999_0000_aaaaaaaaaaaaaaaa",
        applyTs: "2026-04-19T08:05:00.000Z")
      XCTAssertEqual(result, .applied, "delete must apply (trigger re-homes tasks to inbox)")

      let gone = try Int64.fetchOne(
        db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'l-target'")
      XCTAssertEqual(gone, 0)

      let rehomed = try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = 't-1'")
      XCTAssertEqual(rehomed, "inbox", "task must be re-homed to inbox")

      XCTAssertEqual(
        try self.countConflicts(db, entityId: "l-target", resolution: ResolutionName.fkStalled), 0)
    }
  }

  func testApplyListDeleteProceedsWhenOnlyArchivedTasksReferenceList() throws {
    try withDB { db in
      try self.seedList(db, id: "l-trash", version: "1711234560000_0000_aaaaaaaaaaaaaaaa")
      try self.seedArchivedTask(db, id: "t-trashed", listId: "l-trash")

      let result = try ApplyList.applyListDelete(
        db, entityId: "l-trash", version: "1711234569999_0000_aaaaaaaaaaaaaaaa",
        applyTs: "2026-04-19T08:05:00.000Z")
      XCTAssertEqual(result, .applied)

      let gone = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'l-trash'")
      XCTAssertEqual(gone, 0)

      let rehomed = try String.fetchOne(
        db, sql: "SELECT list_id FROM tasks WHERE id = 't-trashed'")
      XCTAssertEqual(rehomed, "inbox", "archived task must be re-homed to inbox")
    }
  }

  func testApplyListDeletePermanentlyRejectsInboxEvenWhenTasksReferenceIt() throws {
    try withDB { db in
      try self.seedList(db, id: "l-other", version: "1711234560000_0000_bbbbbbbbbbbbbbbb")
      try self.seedTask(db, id: "t-on-inbox", listId: "inbox")

      let result = try ApplyList.applyListDelete(
        db, entityId: "inbox", version: "1711234569999_0000_aaaaaaaaaaaaaaaa",
        applyTs: "2026-04-19T08:05:00.000Z")
      XCTAssertEqual(result, .requiredInbox)

      let stillThere = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'inbox'")
      XCTAssertEqual(stillThere, 1, "inbox row must remain")

      XCTAssertEqual(
        try self.countConflicts(db, entityId: "inbox", resolution: ResolutionName.fkStalled), 0,
        "the permanent schema invariant is not a retryable FK conflict")
    }
  }

  func testInboundInboxDeleteFailsClosedWithoutTombstoneOrPendingHold() throws {
    try withDB { db in
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .list, entityId: "inbox", operation: .delete,
        version: try Hlc.parse("1711234569999_0000_aaaaaaaaaaaaaaaa"),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion, payload: "{}",
        deviceId: "peer-device")
      let result = try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(
          appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: envelope)

      guard
        case .repairRequired(
          .reassertRequiredInbox(let remoteDeleteVersion)) = result
      else {
        return XCTFail("required inbox delete must surface its typed repair, got \(result)")
      }
      XCTAssertEqual(remoteDeleteVersion, envelope.version)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'inbox'"), 1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'list' AND entity_id = 'inbox'"),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_pending_inbox WHERE envelope_entity_type = 'list' AND envelope_entity_id = 'inbox'"),
        0)
    }
  }

  /// Cross-device archive sync: a peer archiving — then later unarchiving — a
  /// whole list rides the LWW-gated list upsert, so `archived_at` converges
  /// locally in both directions.
  func testApplyListUpsertSyncsArchivedAt() throws {
    try withDB { db in
      try self.seedList(db, id: "l-arch", version: "1711234560000_0000_aaaaaaaaaaaaaaaa")

      let archived = """
        {"id":"l-arch","name":"list-name","color":null,"icon":null,"description":null,\
        "ai_notes":null,"archived_at":"2026-04-20T09:00:00.000Z",\
        "created_at":"2026-04-19T08:00:00Z","updated_at":"2026-04-20T09:00:00Z"}
        """
      try ApplyList.applyListUpsert(
        db, entityId: "l-arch", payload: archived,
        version: "1711234569999_0000_aaaaaaaaaaaaaaaa", tieBreak: .rejectEqual)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT archived_at FROM lists WHERE id = 'l-arch'"),
        "2026-04-20T09:00:00.000Z", "peer archive must converge locally")

      let unarchived = """
        {"id":"l-arch","name":"list-name","color":null,"icon":null,"description":null,\
        "ai_notes":null,"archived_at":null,\
        "created_at":"2026-04-19T08:00:00Z","updated_at":"2026-04-21T09:00:00Z"}
        """
      try ApplyList.applyListUpsert(
        db, entityId: "l-arch", payload: unarchived,
        version: "1711234579999_0000_aaaaaaaaaaaaaaaa", tieBreak: .rejectEqual)
      XCTAssertNil(
        try String.fetchOne(db, sql: "SELECT archived_at FROM lists WHERE id = 'l-arch'"),
        "peer unarchive must converge locally")
    }
  }

  /// Cross-device reorder sync: a peer's list upsert carrying a new `position`
  /// converges locally, so a drag on one device reorders the catalog on another.
  func testApplyListUpsertSyncsPosition() throws {
    try withDB { db in
      try self.seedList(db, id: "l-pos", version: "1711234560000_0000_aaaaaaaaaaaaaaaa")
      let payload = """
        {"id":"l-pos","name":"list-name","color":null,"icon":null,"description":null,\
        "ai_notes":null,"archived_at":null,"position":7,\
        "created_at":"2026-04-19T08:00:00Z","updated_at":"2026-04-20T09:00:00Z"}
        """
      try ApplyList.applyListUpsert(
        db, entityId: "l-pos", payload: payload,
        version: "1711234569999_0000_aaaaaaaaaaaaaaaa", tieBreak: .rejectEqual)
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT position FROM lists WHERE id = 'l-pos'"), 7,
        "peer position must converge locally")
    }
  }

  /// BH-5: a peer upsert that predates the `position` column (omits the key) must
  /// PRESERVE this device's current manual order, not reset it to 0. A bare
  /// `?? 0` would let a position-less envelope from a staggered-rollout peer
  /// clobber an order already set here; the other fields still converge (the
  /// envelope is never dropped). The habit applier uses byte-identical logic.
  func testApplyListUpsertPreservesExistingPositionWhenAbsent() throws {
    try withDB { db in
      try self.seedList(db, id: "l-nopos", version: "1711234560000_0000_aaaaaaaaaaaaaaaa")
      try db.execute(sql: "UPDATE lists SET position = 5 WHERE id = 'l-nopos'")
      let payload = """
        {"id":"l-nopos","name":"renamed","color":null,"icon":null,"description":null,\
        "ai_notes":null,"archived_at":null,\
        "created_at":"2026-04-19T08:00:00Z","updated_at":"2026-04-20T09:00:00Z"}
        """
      try ApplyList.applyListUpsert(
        db, entityId: "l-nopos", payload: payload,
        version: "1711234569999_0000_aaaaaaaaaaaaaaaa", tieBreak: .rejectEqual)
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT position FROM lists WHERE id = 'l-nopos'"), 5,
        "an absent position must preserve the existing order, not reset to 0")
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT name FROM lists WHERE id = 'l-nopos'"), "renamed",
        "the rest of the position-less envelope still applies (never dropped)")
    }
  }

  func testApplyListDeleteProceedsWhenNoTasksReferenceTheList() throws {
    try withDB { db in
      try self.seedList(db, id: "l-empty", version: "1711234560000_0000_aaaaaaaaaaaaaaaa")

      let result = try ApplyList.applyListDelete(
        db, entityId: "l-empty", version: "1711234569999_0000_aaaaaaaaaaaaaaaa",
        applyTs: "2026-04-19T08:05:00.000Z")
      XCTAssertEqual(result, .applied)

      let gone = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM lists WHERE id = 'l-empty'")
      XCTAssertEqual(gone, 0)

      XCTAssertEqual(
        try self.countConflicts(db, entityId: "l-empty", resolution: ResolutionName.fkStalled), 0)
    }
  }

  /// SYNC-MED-3: a delete for a `list` this device never materialized must be an
  /// idempotent `.applied` no-op, NOT a deferral. In fleet steady state a device
  /// holding only `inbox` (totalLists == 1) receives the delete record for a list
  /// it never had; evaluating `at_least_one_list` before checking row existence
  /// used to return `.skippedByInvariant`, parking a never-held list's delete
  /// forever as a budget-exempt hold.
  func testApplyListDeleteForAbsentRowAppliesInsteadOfDeferring() throws {
    try withDB { db in
      // Fresh store holds only the seeded `inbox`, so totalLists == 1 and the old
      // ordering would trip the at_least_one_list guard for the absent list.
      let result = try ApplyList.applyListDelete(
        db, entityId: "01966a3f-7c8b-7d4e-8f3a-00000000ff01",
        version: "1711234569999_0000_aaaaaaaaaaaaaaaa", applyTs: "2026-04-19T08:05:00.000Z")
      XCTAssertEqual(
        result, .applied,
        "a delete for a list this device never had must apply as a no-op, not defer")
    }
  }

  /// Full-pipeline companion: the absent-list delete advances the delete frontier
  /// (writes a tombstone) and never parks in `sync_pending_inbox`.
  func testApplyEnvelopeAbsentListDeleteTombstonesAndDoesNotDefer() throws {
    try withDB { db in
      let ghost = "01966a3f-7c8b-7d4e-8f3a-00000000ff02"
      let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .list, entityId: ghost, operation: .delete,
        version: try Hlc.parse("1711234569999_0000_aaaaaaaaaaaaaaaa"),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: "{}", deviceId: "remote-device")

      let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)

      XCTAssertEqual(result, .applied, "absent-row list delete applies (idempotent no-op)")
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.list, entityId: ghost),
        "the delete frontier advances via a tombstone")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_pending_inbox") ?? -1, 0,
        "the delete must not park in the pending inbox")
    }
  }

  func testTaskUpsertReferencingOrdinaryTombstonedListLandsInInbox() throws {
    try withDB { db in
      let deletedList = "01966a3f-7c8b-7d4e-8f3a-00000000a301"
      let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000a302"
      try Tombstone.createTombstone(
        db,
        entityType: EntityName.list,
        entityId: deletedList,
        version: "1711234567890_0000_a1b2c3d4a1b2c3d4",
        deletedAt: "2026-04-19T08:00:00.000Z")
      let payload = try SyncCanonicalize.canonicalizeJSON(.object([
        "title": .string("Remote task"),
        "status": .string("open"),
        "list_id": .string(deletedList),
        "created_at": .string("2026-04-19T08:01:00.000Z"),
        "updated_at": .string("2026-04-19T08:01:00.000Z"),
      ]))
      let envelope = try SyncTestSupport.completeEnvelope(
        entityType: .task,
        entityId: taskId,
        operation: .upsert,
        version: try Hlc.parse("1711234568890_0000_a1b2c3d4a1b2c3d4"),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload,
        deviceId: "remote-device")
      let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())

      let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)

      XCTAssertEqual(result, .applied)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [taskId]),
        inboxListId)
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_pending_inbox") ?? -1,
        0)
    }
  }

  // MARK: - Applier registration + dispatch

  func testDefaultRegistryDispatchesTaskAndListUpserts() throws {
    try withDB { db in
      let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
      XCTAssertNotNil(registry.lookup(EntityKind.task.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.list.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.habit.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.tag.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.taskTag.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.taskDependency.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.taskCalendarEventLink.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.habitCompletion.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.taskReminder.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.taskChecklistItem.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.habitReminderPolicy.asString))
      // The remaining per-entity appliers are now all landed — the apply
      // pipeline dispatches every syncable entity type to a real applier.
      XCTAssertNotNil(registry.lookup(EntityKind.calendarEvent.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.currentFocus.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.focusSchedule.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.dailyReview.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.memory.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.preference.asString))
      XCTAssertNotNil(registry.lookup(EntityKind.aiChangelog.asString))
      // Local-only / non-synced types still resolve to nil → unknownEntityType.
      XCTAssertNil(registry.lookup(EntityKind.deviceState.asString))
    }
  }
}
