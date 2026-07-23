import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// S-2 full-resync backfill: `Outbox.enqueueAllLiveForFullResync` must re-enqueue
/// every live (non-tombstoned) entity into `sync_outbox` at its EXISTING stored
/// version (HLC) — never a fresh one — through the coalesced outbox path, so a
/// freshly (re-)created CloudKit zone is repopulated without LWW-inflating any
/// row or clobbering a concurrent peer edit. The backfill must be idempotent.
final class FullResyncBackfillTests: XCTestCase {

  /// A stored HLC distinct from any freshly-minted one. A fresh HLC carries a
  /// ~1.7e12 `physical_ms`; this seeds `physical_ms = 1234`, so a test that
  /// asserts the re-enqueued envelope equals this string fails loudly if the
  /// implementation minted a new version instead of preserving the stored one.
  private static let storedVersion = "0000000001234_0007_00000000feedface"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  // MARK: - Seed helpers (raw SQL at a fixed stored version)

  private func seedTask(_ db: Database, _ id: String, _ title: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, defer_count, version, created_at, updated_at)
        VALUES (?, ?, 'open', 0, ?, '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, title, Self.storedVersion])
  }

  private func seedList(_ db: Database, _ id: String, _ name: String) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, version, created_at, updated_at)
        VALUES (?, ?, ?, '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, name, Self.storedVersion])
  }

  private func seedTag(_ db: Database, _ id: String, _ name: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
        VALUES (?, ?, ?, ?, '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, name, name, Self.storedVersion])
  }

  private func seedTaskTag(_ db: Database, _ taskId: String, _ tagId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO task_tags (task_id, tag_id, version, created_at)
        VALUES (?, ?, ?, '2026-03-20T00:00:00.000Z')
        """,
      arguments: [taskId, tagId, Self.storedVersion])
  }

  private func seedCurrentFocus(_ db: Database, date: String, taskId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
        VALUES (?, 'Plan', 'UTC', ?, '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [date, Self.storedVersion])
    try db.execute(
      sql: "INSERT INTO current_focus_items (date, position, task_id) VALUES (?, 0, ?)",
      arguments: [date, taskId])
  }

  private func seedWeeklyHabit(_ db: Database, _ id: String, weekdays: [Int64]) throws {
    try db.execute(
      sql: """
        INSERT INTO habits (id, name, frequency_type, target_count, archived, lookup_key,
                            version, created_at, updated_at)
        VALUES (?, 'Workout', 'weekly', 1, 0, 'workout', ?,
                '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, Self.storedVersion])
    for wd in weekdays {
      try db.execute(
        sql: "INSERT INTO habit_weekdays (habit_id, weekday) VALUES (?, ?)",
        arguments: [id, wd])
    }
  }

  private func seedChangelog(_ db: Database, _ id: String) throws {
    try db.execute(
      sql: """
        INSERT INTO ai_changelog (id, timestamp, operation, entity_type, summary, initiated_by)
        VALUES (?, '2026-03-20T00:00:00.000Z', 'create', 'task', 'made a task', 'ai')
        """,
      arguments: [id])
  }

  private func pendingByKey(_ db: Database) throws -> [String: Outbox.OutboxEntry] {
    var map: [String: Outbox.OutboxEntry] = [:]
    for entry in try Outbox.getPending(db) {
      map["\(entry.envelope.entityType.asString)/\(entry.envelope.entityId)"] = entry
    }
    return map
  }

  private func storedVersionOf(
    _ db: Database, table: String, pkColumn: String, pk: String
  ) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT version FROM \(table) WHERE \(pkColumn) = ?", arguments: [pk])
  }

  private func unsyncedRowCount(_ db: Database, type: String, id: String) throws -> Int {
    try Int.fetchOne(
      db,
      sql:
        "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL",
      arguments: [type, id]) ?? -1
  }

  // MARK: - Tests

  /// Every zero-HLC singleton seed must also have byte-identical semantic
  /// content. A wall-clock timestamp paired with the shared zero version makes
  /// two fresh devices look like different writes at the same HLC, forcing the
  /// equal-version collision path to mint needless repair successors forever.
  func testFreshDeviceSeedsAreCanonicalExactReplays() throws {
    let deviceA = try SyncTestSupport.freshStore()
    let deviceB = try SyncTestSupport.freshStore()
    let epoch = "1970-01-01T00:00:00.000Z"

    let envelopesA = try deviceA.writer.write { db -> [SyncEnvelope] in
      let inbox = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT created_at, updated_at FROM lists WHERE id = 'inbox'"))
      XCTAssertEqual(inbox["created_at"] as String, epoch)
      XCTAssertEqual(inbox["updated_at"] as String, epoch)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT updated_at FROM preferences WHERE key = 'default_list_id'"),
        epoch)

      _ = try Outbox.enqueueAllLiveForFullResync(db)
      return try Outbox.getPending(db)
        .map(\.envelope)
        .filter {
          ($0.entityType == .list && $0.entityId == "inbox")
            || ($0.entityType == .preference && $0.entityId == "default_list_id")
        }
    }
    XCTAssertEqual(envelopesA.count, 2)

    try deviceB.writer.write { db in
      let registry = EntityApplierRegistry(
        appliers: EntityApplierRegistry.defaultEntityAppliers())
      for envelope in envelopesA {
        let result = try Apply.applyEnvelope(db, registry: registry, envelope: envelope)
        guard case .skipped = result else {
          return XCTFail(
            "fresh canonical seed must be an exact semantic replay, got \(result)")
        }
      }

      _ = try Outbox.enqueueAllLiveForFullResync(db)
      let envelopesB = try Outbox.getPending(db)
        .map(\.envelope)
        .filter {
          ($0.entityType == .list && $0.entityId == "inbox")
            || ($0.entityType == .preference && $0.entityId == "default_list_id")
        }
      let semanticA = Dictionary(
        uniqueKeysWithValues: envelopesA.map {
          ("\($0.entityType.asString)/\($0.entityId)", "\($0.version)|\($0.payload)")
        })
      let semanticB = Dictionary(
        uniqueKeysWithValues: envelopesB.map {
          ("\($0.entityType.asString)/\($0.entityId)", "\($0.version)|\($0.payload)")
        })
      XCTAssertEqual(semanticB, semanticA)
    }
  }

  func testBackfillExcludesVirtualControlPlanePreferenceRowAndTombstone() throws {
    try withDB { db in
      let key = PreferenceKeys.prefAiChangelogRetentionPolicy
      try db.execute(
        sql: """
          INSERT INTO preferences (key, value, version, updated_at)
          VALUES (?, '"off"', ?, '2026-03-20T00:00:00.000Z')
          """,
        arguments: [key, Self.storedVersion])
      try Tombstone.createTombstone(
        db, entityType: EntityName.preference, entityId: key,
        version: Self.storedVersion, deletedAt: "2026-03-20T00:00:00.000Z")

      let report = try Outbox.enqueueAllLiveForFullResync(db)
      XCTAssertEqual(report.skipped, 0)
      XCTAssertEqual(
        try self.unsyncedRowCount(db, type: EntityName.preference, id: key), 0)
    }
  }

  /// Every re-enqueued envelope carries the SAME version string the row stores,
  /// across the generic reader (list/tag), the task reader, the aggregate reader
  /// (current_focus + embedded children), and the composite-edge path (task_tag).
  /// The stored `version` column is never advanced.
  func testBackfillReenqueuesAtExistingStoredVersion() throws {
    try withDB { db in
      let taskId = "01966a3f-7c8b-7d4e-8f3a-000000000a01"
      let listId = "01966a3f-7c8b-7d4e-8f3a-000000000b01"
      let tagId = "01966a3f-7c8b-7d4e-8f3a-000000000c01"
      try seedTask(db, taskId, "Write tests")
      try seedList(db, listId, "Inbox")
      try seedTag(db, tagId, "urgent")
      try seedTaskTag(db, taskId, tagId)
      try seedCurrentFocus(db, date: "2026-03-20", taskId: taskId)
      try seedChangelog(db, "01966a3f-7c8b-7d4e-8f3a-000000000d01")

      let report = try Outbox.enqueueAllLiveForFullResync(db)

      // Internal consistency: every entity the backfill reported is a distinct
      // pending outbox row (no phantom / double counting), and a healthy pass
      // skips nothing. A fresh store also
      // ships a default Inbox `list` + `default_list_id` preference, which the
      // backfill correctly re-pushes alongside the seeded entities — so assert
      // against the live outbox rather than a hard-coded seed cardinality.
      let pendingEntries = try Outbox.getPending(db)
      XCTAssertEqual(report.emitted, pendingEntries.count)
      XCTAssertEqual(report.skipped, 0)
      XCTAssertTrue(report.errors.isEmpty)
      let pending = try pendingByKey(db)
      XCTAssertEqual(pending.count, pendingEntries.count, "no duplicate (type, id) enqueued")

      let edgeId = "\(taskId):\(tagId)"
      let expected: [(String, String)] = [
        ("task", taskId),
        ("list", listId),
        ("tag", tagId),
        ("task_tag", edgeId),
        ("current_focus", "2026-03-20"),
      ]
      for (type, id) in expected {
        let entry = try XCTUnwrap(pending["\(type)/\(id)"], "missing re-enqueued \(type)/\(id)")
        XCTAssertEqual(
          entry.envelope.version.description, Self.storedVersion,
          "\(type)/\(id) must re-enqueue at its stored version, not a fresh HLC")
        XCTAssertEqual(entry.envelope.operation, .upsert)
        // The canonical payload also carries the stored version (the engine
        // injects context.version), proving no fresh-HLC inflation.
        let payload = try XCTUnwrap(JSONValue.parse(entry.envelope.payload))
        guard case .object(let obj) = payload else { return XCTFail("payload not object") }
        XCTAssertEqual(obj["version"], .string(Self.storedVersion), "\(type) payload version")
      }

      // The aggregate envelope embeds its materialized children.
      let focus = try XCTUnwrap(pending["current_focus/2026-03-20"])
      let focusPayload = try XCTUnwrap(JSONValue.parse(focus.envelope.payload))
      guard case .object(let focusObj) = focusPayload else { return XCTFail("focus payload") }
      XCTAssertEqual(focusObj["task_ids"], .array([.string(taskId)]))

      // ai_changelog is append-only (no version column, version-stamp-exempt) and
      // is never emitted through the payload-upsert path, so the backfill skips it.
      XCTAssertNil(pending["ai_changelog/01966a3f-7c8b-7d4e-8f3a-000000000d01"])

      // The stored `version` columns are unchanged — re-enqueue must not LWW-bump.
      XCTAssertEqual(
        try storedVersionOf(db, table: "tasks", pkColumn: "id", pk: taskId), Self.storedVersion)
      XCTAssertEqual(
        try storedVersionOf(db, table: "lists", pkColumn: "id", pk: listId), Self.storedVersion)
      XCTAssertEqual(
        try storedVersionOf(db, table: "tags", pkColumn: "id", pk: tagId), Self.storedVersion)
      XCTAssertEqual(
        try storedVersionOf(db, table: "current_focus", pkColumn: "date", pk: "2026-03-20"),
        Self.storedVersion)
      let edgeVersion = try String.fetchOne(
        db, sql: "SELECT version FROM task_tags WHERE task_id = ? AND tag_id = ?",
        arguments: [taskId, tagId])
      XCTAssertEqual(edgeVersion, Self.storedVersion)
    }
  }

  /// Calling the backfill twice must not create a second divergent unsynced
  /// outbox row for any entity, and must not change any stored or enqueued
  /// version. The coalesced path's LWW gate treats the equal-version second
  /// enqueue as stale and preserves the queued row.
  func testBackfillIsIdempotent() throws {
    try withDB { db in
      let taskId = "01966a3f-7c8b-7d4e-8f3a-000000000a02"
      let tagId = "01966a3f-7c8b-7d4e-8f3a-000000000c02"
      try seedTask(db, taskId, "Idempotent")
      try seedTag(db, tagId, "later")
      try seedTaskTag(db, taskId, tagId)

      let first = try Outbox.enqueueAllLiveForFullResync(db)
      let firstPending = try Outbox.getPending(db)
      let secondReturn = try Outbox.enqueueAllLiveForFullResync(db)
      let secondPending = try Outbox.getPending(db)

      XCTAssertGreaterThanOrEqual(first.emitted, 3, "task + tag + task_tag at least")
      XCTAssertEqual(
        secondReturn.emitted, 0,
        "equal-version coalesced rows already pending are successful no-ops, not fresh emissions")
      XCTAssertEqual(secondReturn.skipped, 0)
      XCTAssertTrue(secondReturn.errors.isEmpty)
      XCTAssertEqual(
        firstPending.count, secondPending.count,
        "double-call must not add divergent outbox rows")

      // Exactly one unsynced row per (type, id) — the partial UNIQUE invariant.
      XCTAssertEqual(try unsyncedRowCount(db, type: "task", id: taskId), 1)
      XCTAssertEqual(try unsyncedRowCount(db, type: "task_tag", id: "\(taskId):\(tagId)"), 1)

      // Versions (stored + enqueued) are still the original stored version.
      XCTAssertEqual(
        try storedVersionOf(db, table: "tasks", pkColumn: "id", pk: taskId), Self.storedVersion)
      let pending = try pendingByKey(db)
      XCTAssertEqual(
        try XCTUnwrap(pending["task/\(taskId)"]).envelope.version.description, Self.storedVersion)
    }
  }

  func testSyncOffOutboxCapLossIsRecoveredByRequiredBackfill() throws {
    try withDB { db in
      let ids = (1...3).map {
        String(format: "01966a3f-7c8b-7d4e-8f3a-00000000ee%02d", $0)
      }
      for (offset, id) in ids.enumerated() {
        try seedTask(db, id, "Capped \(offset)")
        try SyncTestSupport.insertOutboxEnvelopeUnchecked(
          db,
          SyncEnvelope(
            entityType: .task, entityId: id, operation: .upsert,
            version: try Hlc.parse(Self.storedVersion),
            payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
            payload: #"{"version":"0000000001234_0007_00000000feedface"}"#,
            deviceId: "device-A"))
      }

      XCTAssertEqual(
        try SyncRetention.gcActiveOutboxAndFlagReseed(
          db, maxRows: 2, syncedAt: "2026-07-14T12:00:00.000Z"),
        1)
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey), "true")

      let report = try Outbox.enqueueAllLiveForFullResync(db)
      XCTAssertEqual(report.skipped, 0)
      let pendingTaskIDs = Set(
        try Outbox.getPending(db).compactMap {
          $0.envelope.entityType == .task ? $0.envelope.entityId : nil
        })
      XCTAssertTrue(Set(ids).isSubset(of: pendingTaskIDs))
      XCTAssertNil(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey),
        "only a complete backfill may clear the recoverable-loss marker")
    }
  }

  /// D1: the full-resync backfill routes `habit` through the same snapshot
  /// reader the incremental enqueue uses, so a weekly habit's `weekdays` set
  /// rides the re-pushed envelope (and `lookup_key` stays off the wire).
  func testBackfillHabitCarriesWeekdays() throws {
    try withDB { db in
      let habitId = "01966a3f-7c8b-7d4e-8f3a-000000000f01"
      try seedWeeklyHabit(db, habitId, weekdays: [0, 2])

      _ = try Outbox.enqueueAllLiveForFullResync(db)

      let pending = try pendingByKey(db)
      let entry = try XCTUnwrap(pending["habit/\(habitId)"], "missing re-enqueued habit")
      XCTAssertEqual(
        entry.envelope.version.description, Self.storedVersion,
        "habit must re-enqueue at its stored version, not a fresh HLC")
      let payload = try XCTUnwrap(JSONValue.parse(entry.envelope.payload))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(
        obj["weekdays"], .array([.int(0), .int(2)]),
        "full-resync habit envelope must carry the weekly weekday set")
      XCTAssertNil(obj["lookup_key"], "habit wire shape omits lookup_key")
    }
  }

  // MARK: - Tombstone re-enqueue

  /// A death version strictly newer than ``storedVersion`` (physical 1234), so a
  /// re-pushed `delete` at this version out-votes a peer's live row.
  private static let deathVersion = "0000000009999_0007_00000000feedface"

  /// The backfill re-pushes the alias independently, plus both ordinary death
  /// barriers at their stored versions.
  func testBackfillReenqueuesTombstonesAsDeleteEnvelopes() throws {
    try withDB { db in
      let now = SyncTimestampFormat.syncTimestampNow()

      let deadTaskId = "01966a3f-7c8b-7d4e-8f3a-0000000000d1"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: deadTaskId, version: Self.deathVersion,
        deletedAt: now)

      let loserTagId = "01966a3f-7c8b-7d4e-8f3a-0000000000d2"
      let winnerTagId = "01966a3f-7c8b-7d4e-8f3a-0000000000d0"
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: loserTagId, targetId: winnerTagId,
        version: Self.deathVersion, createdAt: now)

      _ = try Outbox.enqueueAllLiveForFullResync(db)
      let pending = try pendingByKey(db)

      let deadTask = try XCTUnwrap(
        pending["task/\(deadTaskId)"], "a plain tombstone must be re-enqueued as a delete")
      XCTAssertEqual(deadTask.envelope.operation, .delete)
      XCTAssertEqual(deadTask.envelope.version.description, Self.deathVersion)

      let loserTag = try XCTUnwrap(
        pending["tag/\(loserTagId)"], "a redirect (merge-loser) tombstone must be re-enqueued")
      XCTAssertEqual(loserTag.envelope.operation, .delete)
      XCTAssertEqual(loserTag.envelope.version.description, Self.deathVersion)

      let alias = try XCTUnwrap(
        try EntityRedirect.get(db, sourceType: EntityName.tag, sourceId: loserTagId))
      XCTAssertEqual(alias.targetId, winnerTagId)
      let aliasKey =
        "entity_redirect/"
        + EntityRedirect.wireEntityId(sourceType: .tag, sourceId: loserTagId)
      XCTAssertEqual(pending[aliasKey]?.envelope.operation, .upsert)
    }
  }

  func testTransitionBackfillSkipsOnlyConfirmedDeletesCoveredByGenerationCutoff() throws {
    try withDB { db in
      let oldID = "01966a3f-7c8b-7d4e-8f3a-0000000000e1"
      let recentID = "01966a3f-7c8b-7d4e-8f3a-0000000000e2"
      let unconfirmedID = "01966a3f-7c8b-7d4e-8f3a-0000000000e3"
      for id in [oldID, recentID, unconfirmedID] {
        try Tombstone.createTombstone(
          db, entityType: EntityName.task, entityId: id,
          version: Self.deathVersion, deletedAt: "2020-01-01T00:00:00.000Z")
      }
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: oldID,
          version: Self.deathVersion,
          confirmedAt: "2024-01-01T00:00:00.000Z"))
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.task, entityId: recentID,
          version: Self.deathVersion,
          confirmedAt: "2026-01-01T00:00:00.000Z"))

      _ = try Outbox.enqueueAllLiveForFullResync(
        db, tombstoneCompactionCutoff: "2025-01-01T00:00:00.000Z")
      let pending = try pendingByKey(db)
      XCTAssertNil(pending["task/\(oldID)"])
      XCTAssertEqual(pending["task/\(recentID)"]?.envelope.operation, .delete)
      XCTAssertEqual(pending["task/\(unconfirmedID)"]?.envelope.operation, .delete)
    }
  }

  func testTransitionBackfillRetainsPermanentRedirectTargetDeath() throws {
    try withDB { db in
      let targetID = "01966a3f-7c8b-7d4e-8f3a-0000000000a0"
      let sourceID = "01966a3f-7c8b-7d4e-8f3a-0000000000a1"
      try Tombstone.createTombstone(
        db, entityType: EntityName.tag, entityId: targetID,
        version: Self.deathVersion, deletedAt: "2020-01-01T00:00:00.000Z")
      _ = try Tombstone.confirmCloudPresence(
        db,
        confirmation: .init(
          entityType: EntityName.tag, entityId: targetID,
          version: Self.deathVersion,
          confirmedAt: "2024-01-01T00:00:00.000Z"))
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: sourceID, targetId: targetID,
        version: Self.deathVersion, createdAt: "2024-01-01T00:00:00.000Z")
      try db.execute(sql: "DELETE FROM sync_outbox")

      _ = try Outbox.enqueueAllLiveForFullResync(
        db, tombstoneCompactionCutoff: "2025-01-01T00:00:00.000Z")
      let pending = try pendingByKey(db)
      XCTAssertEqual(pending["tag/\(targetID)"]?.envelope.operation, .delete)
      XCTAssertEqual(
        pending[
          "entity_redirect/"
            + EntityRedirect.wireEntityId(sourceType: .tag, sourceId: sourceID)
        ]?.envelope.operation,
        .upsert)
    }
  }

  /// H7 delete-resurrection guard: `sync_tombstones` retains death knowledge well
  /// past `fullResyncHorizonDays` — a plain tombstone an active peer has not yet
  /// acknowledged survives the watermark GC's version gate. A merge loser has
  /// both an ordinary tombstone and an independent permanent alias. A backfill
  /// that re-pushes only tombstones younger than the
  /// horizon leaves a zone recreated after >horizon days with NO record of those
  /// deletes, so a returning offline peer's stale live upsert resurrects the
  /// entity. Every tombstone still present locally must ride the backfill.
  func testBackfillReenqueuesTombstonesOlderThanFullResyncHorizon() throws {
    try withDB { db in
      // Aged past the 90-day full-resync horizon but within local retention.
      let agedPlainDeletedAt = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-120 days')"))
      // A merge-loser ordinary tombstone and its permanent alias at the same age.
      let agedRedirectDeletedAt = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-300 days')"))

      let agedTaskId = "01966a3f-7c8b-7d4e-8f3a-0000000000d4"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: agedTaskId, version: Self.deathVersion,
        deletedAt: agedPlainDeletedAt)

      let agedLoserTagId = "01966a3f-7c8b-7d4e-8f3a-0000000000d5"
      let winnerTagId = "01966a3f-7c8b-7d4e-8f3a-0000000000d4"
      try SyncTestSupport.seedEntityRedirect(
        db, sourceType: .tag, sourceId: agedLoserTagId, targetId: winnerTagId,
        version: Self.deathVersion, createdAt: agedRedirectDeletedAt)

      _ = try Outbox.enqueueAllLiveForFullResync(db)
      let pending = try pendingByKey(db)

      let agedTask = try XCTUnwrap(
        pending["task/\(agedTaskId)"],
        "a plain tombstone older than fullResyncHorizonDays still exists locally "
          + "and must be re-pushed, or a >horizon zone recreation resurrects the entity")
      XCTAssertEqual(agedTask.envelope.operation, .delete)
      XCTAssertEqual(agedTask.envelope.version.description, Self.deathVersion)

      let agedLoser = try XCTUnwrap(
        pending["tag/\(agedLoserTagId)"],
        "a merge loser's ordinary death barrier must be re-pushed past the horizon")
      XCTAssertEqual(agedLoser.envelope.operation, .delete)
      XCTAssertEqual(agedLoser.envelope.version.description, Self.deathVersion)

      let redirectID = EntityRedirect.wireEntityId(
        sourceType: .tag, sourceId: agedLoserTagId)
      let alias = try XCTUnwrap(
        pending["entity_redirect/\(redirectID)"],
        "the permanent alias must be reconstructed independently of its death barrier")
      XCTAssertEqual(alias.envelope.operation, .upsert)
      XCTAssertEqual(alias.envelope.version.description, Self.deathVersion)
    }
  }

  /// End-to-end no-resurrection: device B deleted a task (only the tombstone
  /// survives) and re-pushes the delete on backfill. An offline peer (device A)
  /// that still holds the task LIVE at an older version applies that delete and
  /// converges on the deletion instead of resurrecting it.
  func testBackfillTombstoneDeletePreventsPeerResurrection() throws {
    let deadTaskId = "01966a3f-7c8b-7d4e-8f3a-0000000000e1"

    // Device B: the row is gone; the backfill re-pushes the delete.
    var deleteEnvelope: SyncEnvelope?
    try withDB { db in
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: deadTaskId, version: Self.deathVersion,
        deletedAt: SyncTimestampFormat.syncTimestampNow())
      _ = try Outbox.enqueueAllLiveForFullResync(db)
      let entry = try XCTUnwrap(try pendingByKey(db)["task/\(deadTaskId)"])
      XCTAssertEqual(entry.envelope.operation, .delete)
      deleteEnvelope = entry.envelope
    }
    let envelope = try XCTUnwrap(deleteEnvelope)

    // Device A: the task is still live at the older stored version.
    try withDB { db in
      try seedTask(db, deadTaskId, "Still live on the offline peer")
      XCTAssertEqual(
        try storedVersionOf(db, table: "tasks", pkColumn: "id", pk: deadTaskId), Self.storedVersion)

      _ = try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: envelope)

      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [deadTaskId]),
        0, "the backfilled delete must remove the peer's live row — no resurrection")
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: deadTaskId),
        "the peer records the death tombstone from the applied delete")
    }
  }

  /// The generation-managed death-ledger fix, end to end. Device B holds only a tombstone
  /// for a deleted task whose `deleted_at` is ancient (400 days).
  /// `gcTombstonesWatermark` retains it, so the full-resync backfill still
  /// re-pushes the `delete` barrier into the rebuilt zone, and an over-window peer
  /// (device A) still holding the task live converges on the deletion instead of
  /// resurrecting it.
  func testGcNoLongerDropsTombstoneSoRebuiltZoneStillBuriesEntity() throws {
    let deadTaskId = "01966a3f-7c8b-7d4e-8f3a-0000000000e2"

    // Device B: the row is gone; only the ancient, below-watermark tombstone remains.
    var deleteEnvelope: SyncEnvelope?
    try withDB { db in
      let ancientDeath = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-400 days')"))
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: deadTaskId, version: Self.deathVersion,
        deletedAt: ancientDeath)

      XCTAssertEqual(try Tombstone.gcTombstonesWatermark(db), 0)
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: deadTaskId),
        "ordinary GC retains the tombstone the backfill needs")

      _ = try Outbox.enqueueAllLiveForFullResync(db)
      let entry = try XCTUnwrap(
        try pendingByKey(db)["task/\(deadTaskId)"],
        "the retained tombstone re-pushes its delete barrier into the rebuilt zone")
      XCTAssertEqual(entry.envelope.operation, .delete)
      XCTAssertEqual(entry.envelope.version.description, Self.deathVersion)
      deleteEnvelope = entry.envelope
    }
    let envelope = try XCTUnwrap(deleteEnvelope)

    // Device A: the over-window peer still holds the task live at the older version.
    try withDB { db in
      try seedTask(db, deadTaskId, "Zombie still live on the over-window peer")
      XCTAssertEqual(
        try storedVersionOf(db, table: "tasks", pkColumn: "id", pk: deadTaskId), Self.storedVersion)

      _ = try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: envelope)

      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [deadTaskId]),
        0, "the re-pushed delete buries the entity — no resurrection")
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: deadTaskId))
    }
  }

  /// The bug this fix closes, kept as a live guard. Device B's tombstone was
  /// reaped by an old watermark GC, so its backfill re-pushes NO delete barrier
  /// into the rebuilt zone. The over-window peer (device A) still holds the task
  /// live, edits it into a fresh dominating HLC, and ships the upsert; with no
  /// surviving tombstone on device B, nothing blocks it and the deleted entity
  /// RESURRECTS. Fails loudly if watermark tombstone GC is ever reintroduced.
  func testResurrectionReproWhenTombstoneMissing() throws {
    let deadTaskId = "01966a3f-7c8b-7d4e-8f3a-0000000000e3"
    // A fresh dominating HLC modelling device A's later edit of the zombie row.
    let resurrectVersion = "9999913599999_0000_00000000feedface"

    // Device A: the over-window peer still holds the task live and edits it into a
    // fresh dominating HLC, producing the upsert it would re-push into a rebuilt zone.
    var resurrectUpsert: SyncEnvelope?
    try withDB { db in
      try seedTask(db, deadTaskId, "Zombie still live on the over-window peer")
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?", arguments: [resurrectVersion, deadTaskId])
      _ = try Outbox.enqueueAllLiveForFullResync(db)
      let entry = try XCTUnwrap(try pendingByKey(db)["task/\(deadTaskId)"])
      XCTAssertEqual(entry.envelope.operation, .upsert)
      XCTAssertEqual(entry.envelope.version.description, resurrectVersion)
      resurrectUpsert = entry.envelope
    }
    let upsert = try XCTUnwrap(resurrectUpsert)

    // Device B: it deleted the task, but an old watermark GC reaped the tombstone.
    // Its backfill re-pushes no delete barrier, so device A's stale upsert is not
    // blocked and the deleted entity RESURRECTS.
    try withDB { db in
      let ancientDeath = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-400 days')"))
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: deadTaskId, version: Self.deathVersion,
        deletedAt: ancientDeath)
      // Simulate the removed watermark GC dropping the death knowledge.
      XCTAssertTrue(
        try Tombstone.removeTombstone(db, entityType: EntityName.task, entityId: deadTaskId))

      _ = try Outbox.enqueueAllLiveForFullResync(db)
      XCTAssertNil(
        try pendingByKey(db)["task/\(deadTaskId)"],
        "with the tombstone reaped, the backfill carries no delete barrier for the entity")

      _ = try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: upsert)

      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks WHERE id = ?", arguments: [deadTaskId]),
        1,
        "with no surviving tombstone, the stale upsert resurrects the deleted entity — "
          + "the tail the generation-managed death ledger closes")
    }
  }

  /// A second backfill pass must not create a divergent delete outbox row for a
  /// tombstone — the coalesce LWW gate treats the equal-version re-enqueue as
  /// stale and preserves the single queued row.
  func testBackfillTombstoneReenqueueIsIdempotent() throws {
    try withDB { db in
      let deadTaskId = "01966a3f-7c8b-7d4e-8f3a-0000000000f1"
      try Tombstone.createTombstone(
        db, entityType: EntityName.task, entityId: deadTaskId, version: Self.deathVersion,
        deletedAt: SyncTimestampFormat.syncTimestampNow())

      _ = try Outbox.enqueueAllLiveForFullResync(db)
      _ = try Outbox.enqueueAllLiveForFullResync(db)

      XCTAssertEqual(
        try unsyncedRowCount(db, type: "task", id: deadTaskId), 1,
        "double backfill must not add a divergent delete outbox row")
    }
  }

  /// DEFECT 8 follow-up: the `reseed_required` marker `SyncRetention` sets before a
  /// horizon GC is never cleared on its own. A completed full-resync backfill is
  /// the reseed of last resort — the point at which the missing data has been
  /// re-pushed/re-pulled — so it must auto-clear the marker; otherwise a one-time
  /// loss keeps the host prompting a reseed forever.
  func testFullResyncBackfillClearsReseedRequiredMarker() throws {
    try withDB { db in
      // A device flagged reseed_required by the retention sweep.
      try SyncCheckpoints.set(db, key: SyncNaming.reseedRequiredCheckpointKey, value: "true")
      try seedList(db, "01966a3f-7c8b-7d4e-8f3a-000000000abc", "Groceries")

      _ = try Outbox.enqueueAllLiveForFullResync(db)

      let marker = try String.fetchOne(
        db, sql: "SELECT value FROM sync_checkpoints WHERE key = ?",
        arguments: [SyncNaming.reseedRequiredCheckpointKey])
      XCTAssertNil(marker, "a successful full-resync backfill clears the reseed_required marker")
    }
  }

  // MARK: - Partial backfill (poison row) must not report a completed reseed

  /// M2: a poison row (here a tombstone whose stored version fails `Hlc.parse`,
  /// which the enqueue pipeline refuses as `taintedVersion`) is isolated and
  /// skipped — but a pass that skipped anything did NOT re-assert this device's
  /// full state, so it must NOT clear the `reseed_required` marker, and must
  /// leave a persistent `error_logs` diagnostic. A later pass retries the same
  /// row; once every row emits, the marker clears.
  func testBackfillPoisonRowRetainsReseedMarkerUntilCleanPass() throws {
    try withDB { db in
      let listId = "01966a3f-7c8b-7d4e-8f3a-000000000abd"
      let poisonTaskId = "01966a3f-7c8b-7d4e-8f3a-000000000abe"
      try SyncCheckpoints.set(db, key: SyncNaming.reseedRequiredCheckpointKey, value: "true")
      try seedList(db, listId, "Groceries")
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES ('task', ?, 'tainted-version', ?)
            """,
          arguments: [poisonTaskId, SyncTimestampFormat.syncTimestampNow()])
      }

      let partial = try Outbox.enqueueAllLiveForFullResync(db)

      // The result is structured: the poison row is counted, not absorbed.
      XCTAssertEqual(partial.skipped, 1)
      XCTAssertEqual(partial.errors.count, 1)
      XCTAssertGreaterThanOrEqual(partial.emitted, 1)
      // The healthy rows still rode the pass (poison isolation preserved) …
      XCTAssertNotNil(try pendingByKey(db)["list/\(listId)"])
      // … but the marker survives: the reseed is not complete.
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey), "true",
        "a backfill that skipped a row must not clear reseed_required")
      // A persistent diagnostic points at the partial pass.
      let diagnostics = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM error_logs WHERE source = 'sync.full_resync_backfill'") ?? 0
      XCTAssertGreaterThanOrEqual(
        diagnostics, 1, "a partial backfill must leave an error_logs diagnostic")

      // Heal the poison (re-stamp a canonical death version); the retry pass
      // emits everything and only then clears the marker.
      try db.execute(
        sql: "UPDATE sync_tombstones SET version = ? WHERE entity_id = ?",
        arguments: [Self.deathVersion, poisonTaskId])
      let clean = try Outbox.enqueueAllLiveForFullResync(db)

      XCTAssertEqual(clean.skipped, 0)
      XCTAssertNotNil(
        try pendingByKey(db)["task/\(poisonTaskId)"],
        "the second pass retries (and now emits) the previously-skipped row")
      XCTAssertNil(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey),
        "a clean pass (nothing skipped) completes the reseed and clears the marker")
    }
  }

  /// H3: the recovery paths that reach a backfill WITHOUT `SyncRetention` having
  /// pre-set `reseed_required` (DB replacement, `zoneNotFound` zone recreate,
  /// account first-run, explicit account adoption) commit their recovery — clear
  /// the checkpoint / lift the pause — once the enqueue returns. If a poison row
  /// skips silently and the marker was never set, that data is dropped from the
  /// (re-)created zone with no retry trigger. So a partial pass must SET the
  /// marker even when it was NOT already present, leaving a durable, identity-
  /// gated retry trigger the `reseed_required` recovery arm re-runs each cycle.
  func testBackfillPoisonRowSetsReseedMarkerWhenNotPreset() throws {
    try withDB { db in
      let listId = "01966a3f-7c8b-7d4e-8f3a-000000000ac0"
      let poisonTaskId = "01966a3f-7c8b-7d4e-8f3a-000000000ac1"
      // No reseed_required pre-set: this models a recovery path (e.g. zone
      // recreate / account adopt) that never flagged it, unlike the horizon-GC
      // retention sweep.
      XCTAssertNil(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey),
        "precondition: the marker starts absent on these recovery paths")
      try seedList(db, listId, "Groceries")
      try SyncTestSupport.seedIgnoringCheckConstraints(db) {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
            VALUES ('task', ?, 'tainted-version', ?)
            """,
          arguments: [poisonTaskId, SyncTimestampFormat.syncTimestampNow()])
      }

      let partial = try Outbox.enqueueAllLiveForFullResync(db)

      // The poison row is isolated and counted; the healthy rows still rode.
      XCTAssertEqual(partial.skipped, 1)
      XCTAssertGreaterThanOrEqual(partial.emitted, 1)
      XCTAssertNotNil(try pendingByKey(db)["list/\(listId)"])
      // The fix: the partial pass SETS the marker even though nothing pre-set it,
      // so the recovery path that clears its checkpoint / lifts its pause still
      // leaves a durable retry trigger for the dropped row.
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey), "true",
        "a partial pass on a path that never pre-set the marker must SET it so the next cycle retries")

      // Heal the poison; the retry pass emits everything and only then clears.
      try db.execute(
        sql: "UPDATE sync_tombstones SET version = ? WHERE entity_id = ?",
        arguments: [Self.deathVersion, poisonTaskId])
      let clean = try Outbox.enqueueAllLiveForFullResync(db)

      XCTAssertEqual(clean.skipped, 0)
      XCTAssertNil(
        try SyncCheckpoints.get(db, key: SyncNaming.reseedRequiredCheckpointKey),
        "a clean retry pass completes the reseed and clears the marker it set")
    }
  }
}
