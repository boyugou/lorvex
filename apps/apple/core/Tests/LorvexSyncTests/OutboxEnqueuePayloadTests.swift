import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the Rust `lorvex-sync::outbox_enqueue` payload-pipeline test suite
/// (`tests/{payload_writes,entity_upserts,aggregates,delete_cascade,
/// pending_drain}.rs`) plus the tombstone shadow side-effect.
///
/// Seeds via raw SQL against the authoritative schema. The pending-drain cases
/// cover both the no-match gate and the real replay path through
/// `drain_pending_inbox`. The `upsert_after_delete_clears_stale_tombstone` test
/// pins the row-state contract: a fresh Upsert clears the stale local tombstone.
final class OutboxEnqueuePayloadTests: XCTestCase {

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  private func setupHlc() throws -> HlcState {
    try HlcState(deviceSuffix: "decafdec00000001")
  }

  /// Test-local twin of the production write-surface pattern
  /// (`SwiftLorvexCoreService.enqueueUpsert`): mint a fresh HLC, stamp any
  /// authored task registers, read the entity snapshot, and route through
  /// `enqueuePayloadUpsert`.
  private func enqueueEntityUpsert(
    _ db: Database, entityType: String, entityId: String, hlcState: HlcState, deviceId: String,
    taskRegisterIntent: TaskRegisterIntent? = nil
  ) throws {
    let version = hlcState.generate().description
    let registerIntent: EntityRegisterIntent
    if entityType == EntityName.task {
      let taskIntent = taskRegisterIntent ?? .all
      try db.execute(
        sql: """
          UPDATE tasks
          SET content_version = CASE WHEN ? THEN ? ELSE content_version END,
              schedule_version = CASE WHEN ? THEN ? ELSE schedule_version END,
              lifecycle_version = CASE WHEN ? THEN ? ELSE lifecycle_version END,
              archive_version = CASE WHEN ? THEN ? ELSE archive_version END,
              version = ?
          WHERE id = ?
          """,
        arguments: [
          taskIntent.contains(.content), version,
          taskIntent.contains(.schedule), version,
          taskIntent.contains(.lifecycle), version,
          taskIntent.contains(.archive), version,
          version,
          entityId,
        ])
      registerIntent = .task(taskIntent)
    } else {
      registerIntent = .none
    }
    let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: entityType, entityId: entityId)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: entityType, entityId: entityId, payload: payload,
      context: OutboxWriteContext(
        version: version, deviceId: deviceId, registerIntent: registerIntent))
  }

  private func enqueueSnapshotUpsert(
    _ db: Database, entityType: String, entityId: String, version: String,
    deviceId: String = "dev-001", taskRegisterIntent: TaskRegisterIntent? = nil
  ) throws {
    let registerIntent: EntityRegisterIntent
    if entityType == EntityName.task {
      let taskIntent = taskRegisterIntent ?? .all
      try db.execute(
        sql: """
          UPDATE tasks
          SET content_version = CASE WHEN ? THEN ? ELSE content_version END,
              schedule_version = CASE WHEN ? THEN ? ELSE schedule_version END,
              lifecycle_version = CASE WHEN ? THEN ? ELSE lifecycle_version END,
              archive_version = CASE WHEN ? THEN ? ELSE archive_version END,
              version = ?
          WHERE id = ?
          """,
        arguments: [
          taskIntent.contains(.content), version,
          taskIntent.contains(.schedule), version,
          taskIntent.contains(.lifecycle), version,
          taskIntent.contains(.archive), version,
          version,
          entityId,
        ])
      registerIntent = .task(taskIntent)
    } else {
      registerIntent = .none
    }
    let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: entityType, entityId: entityId)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: entityType, entityId: entityId, payload: payload,
      context: OutboxWriteContext(
        version: version, deviceId: deviceId, registerIntent: registerIntent))
  }

  // MARK: - seed helpers (raw SQL, mirroring tests/support.rs)

  private func insertTask(_ db: Database, _ id: String, _ title: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, status, defer_count, version, created_at, updated_at)
        VALUES (?, ?, 'open', 0, '0000000000000_0000_0000000000000000',
                '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, title])
  }

  private func insertList(_ db: Database, _ id: String, _ name: String) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, version, created_at, updated_at)
        VALUES (?, ?, '0000000000000_0000_0000000000000000',
                '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, name])
  }

  private func insertTag(_ db: Database, _ id: String, _ name: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
        VALUES (?, ?, ?, '0000000000000_0000_0000000000000000',
                '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, name, name])
  }

  private func insertCalendarEvent(_ db: Database, _ id: String, allDay: Int64) throws {
    try db.execute(
      sql: """
        INSERT INTO calendar_events (id, title, start_date, start_time, all_day, event_type,
                                     content_version, recurrence_topology_version, version,
                                     created_at, updated_at)
        VALUES (?, 'Planning', '2026-03-20', ?, ?, 'event',
                '0000000000000_0000_0000000000000000',
                '0000000000000_0000_0000000000000000',
                '0000000000000_0000_0000000000000000',
                '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id, allDay == 0 ? "09:00" : nil, allDay])
  }

  private func insertPreference(_ db: Database, _ key: String, _ value: String) throws {
    try db.execute(
      sql: """
        INSERT INTO preferences (key, value, version, updated_at)
        VALUES (?, ?, '0000000000000_0000_0000000000000000', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [key, value])
  }

  private func insertTaskTag(_ db: Database, _ taskId: String, _ tagId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO task_tags (task_id, tag_id, created_at, version)
        VALUES (?, ?, '2026-03-20T00:00:00.000Z', '0000000000000_0000_0000000000000000')
        """,
      arguments: [taskId, tagId])
  }

  private func seedDefaultListAndTasks(_ db: Database, _ taskIds: [String]) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at)
        VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002136', 'Default',
                '0000000000000_0000_0000000000000000',
                '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
        """)
    for id in taskIds {
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, defer_count, version,
                             created_at, updated_at)
          VALUES (?, 'T', 'open', '01966a3f-7c8b-7d4e-8f3a-000000002136', 0,
                  '0000000000000_0000_0000000000000000',
                  '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [id])
    }
  }

  private func parseOutboxPayload(
    _ db: Database, _ entityType: String, _ entityId: String
  ) throws -> JSONValue {
    let raw = try XCTUnwrap(
      try String.fetchOne(
        db, sql: "SELECT payload FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [entityType, entityId]))
    return try XCTUnwrap(JSONValue.parse(raw))
  }

  // MARK: - payload_writes.rs

  func testEnqueuePayloadUpsertStampsVersionAndWritesHoldColumnsNull() throws {
    try withDB { db in
      try insertTask(db, "01966a3f-7c8b-7d4e-8f3a-000000002163", "Stamped task")
      let version = "1743280000000_0001_deadbeefdeadbeef"
      try self.enqueueSnapshotUpsert(
        db, entityType: EntityName.task,
        entityId: "01966a3f-7c8b-7d4e-8f3a-000000002163", version: version)

      let stamped = try String.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002163'")
      XCTAssertEqual(stamped, version)

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, payload FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002163'
            """))
      XCTAssertEqual(row["version"] as String, version)
      let payload = try XCTUnwrap(JSONValue.parse(row["payload"] as String))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["version"], .string(version))
    }
  }

  func testEnqueuePayloadDeletePreservesPreDeletePayloadVersion() throws {
    try withDB { db in
      let deleteVersion = "1743280000000_0001_deadbeefdeadbeef"
      let rowVersion = "1743279999999_0000_feedfacefeedface"
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: EntityName.task, entityId: "01966a3f-7c8b-7d4e-8f3a-000000002163",
        payload: .object([
          "id": .string("01966a3f-7c8b-7d4e-8f3a-000000002163"),
          "title": .string("Deleted task"),
          "version": .string(rowVersion),
        ]),
        context: OutboxWriteContext(
          version: deleteVersion, deviceId: "dev-001"))

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT version, payload FROM sync_outbox
            WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000002163'
            """))
      XCTAssertEqual(row["version"] as String, deleteVersion)
      let payload = try XCTUnwrap(JSONValue.parse(row["payload"] as String))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["version"], .string(rowVersion))
    }
  }

  func testEnqueuePayloadUpsertSurfacesEntityVersionStampFailures() throws {
    try withDB { db in
      try db.execute(sql: "DROP TABLE tasks")
      var thrown: Error?
      do {
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: EntityName.task, entityId: "01966a3f-7c8b-7d4e-8f3a-000000002163",
          payload: .object([
            "id": .string("01966a3f-7c8b-7d4e-8f3a-000000002163"),
            "title": .string("Stamped task"),
            "status": .string("open"),
          ]),
          context: OutboxWriteContext(
            version: "1743280000000_0001_deadbeefdeadbeef", deviceId: "dev-001"))
      } catch { thrown = error }

      let err = try XCTUnwrap(thrown as? EnqueueError)
      guard case .sqlite(let inner) = err else {
        return XCTFail("expected sqlite error, got \(err)")
      }
      let message = "\(inner)"
      XCTAssertTrue(
        message.contains("no such table") || message.contains("tasks"),
        "unexpected error: \(message)")

      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? -1
      XCTAssertEqual(count, 0, "enqueue should not persist an outbox row")
    }
  }

  func testEnqueuePayloadDeleteCreatesTombstoneForCompositeEdge() throws {
    try withDB { db in
      try insertTask(db, "01966a3f-7c8b-7d4e-8f3a-000000002165", "Task")
      try insertTag(db, "01966a3f-7c8b-7d4e-8f3a-000000002159", "Tag")
      try insertTaskTag(
        db, "01966a3f-7c8b-7d4e-8f3a-000000002165", "01966a3f-7c8b-7d4e-8f3a-000000002159")

      let version = "1743280000000_0001_deadbeefdeadbeef"
      let entityId = "01966a3f-7c8b-7d4e-8f3a-000000002165:01966a3f-7c8b-7d4e-8f3a-000000002159"
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: EdgeName.taskTag, entityId: entityId,
        payload: .object([
          "task_id": .string("01966a3f-7c8b-7d4e-8f3a-000000002165"),
          "tag_id": .string("01966a3f-7c8b-7d4e-8f3a-000000002159"),
        ]),
        context: OutboxWriteContext(
          version: version, deviceId: "dev-001"))

      let count =
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_tombstones
            WHERE entity_type = ? AND entity_id = ? AND version = ?
            """,
          arguments: [EdgeName.taskTag, entityId, version]) ?? -1
      XCTAssertEqual(count, 1, "delete enqueue must record a tombstone")
    }
  }

  /// Seeds the forward-compat shadow row directly and verifies the Upsert merge
  /// re-emits the unknown `future_field` alongside the locally-edited known
  /// column.
  func testEnqueueEntityUpsertPreservesForwardCompatShadowFieldsOnLocalRewrite() throws {
    try withDB { db in
      let id = "01966a3f-7c8b-7d4e-8f3a-00000000219d"
      let futureVersion = "1711234567000_0000_a1b2c3d4a1b2c3d4"
      try insertTask(db, id, "Shadow title")
      let shadowPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "id": .string(id),
          "title": .string("Shadow title"),
          "status": .string("open"),
          "defer_count": .int(0),
          "created_at": .string("2026-04-19T10:00:00.000Z"),
          "updated_at": .string("2026-04-19T10:00:00.000Z"),
          "future_field": .string("preserve-me"),
        ]))
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow
              (entity_type, entity_id, base_version, payload_schema_version,
               raw_payload_json, source_device_id, updated_at)
          VALUES (?, ?, ?, ?, ?, 'future-peer', '2026-04-19T10:00:00.000Z')
          """,
        arguments: [
          EntityName.task, id, futureVersion,
          LorvexVersion.payloadSchemaVersion + 1, shadowPayload,
        ])

      try db.execute(
        sql: """
          UPDATE tasks SET title = 'Locally edited title',
                           updated_at = '2026-04-19T10:05:00.000Z'
          WHERE id = ?
          """,
        arguments: [id])

      let hlc = try setupHlc()
      try enqueueEntityUpsert(
        db, entityType: EntityName.task, entityId: id, hlcState: hlc,
        deviceId: "dev-001", taskRegisterIntent: .content)

      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      let payload = try XCTUnwrap(JSONValue.parse(pending[0].envelope.payload))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["title"], .string("Locally edited title"))
      XCTAssertEqual(
        obj["future_field"], .string("preserve-me"),
        "re-enqueue must merge unknown fields back from payload shadow")
    }
  }

  /// A-7: a local rewrite that merges a forward-compat shadow must stamp the
  /// re-emitted envelope at the shadow's HIGHER schema version, so a same-schema
  /// peer takes the parse-forward-compat path and RE-STASHES the unknown field
  /// rather than parsing fully and reaping its own shadow (dropping the field).
  func testForwardCompatReEmitStampsShadowSchemaSoPeerReStashes() throws {
    let id = "01966a3f-7c8b-7d4e-8f3a-0000000021a7"
    let futureVersion = "1711234567000_0000_a1b2c3d4a1b2c3d4"
    let futureSchema = LorvexVersion.payloadSchemaVersion + 1
    var wirePayload = ""
    var wireSchema: UInt32 = 0
    var wireVersion = ""

    try withDB { db in
      try insertTask(db, id, "Shadow title")
      let shadowPayload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "id": .string(id), "title": .string("Shadow title"), "status": .string("open"),
          "defer_count": .int(0),
          "created_at": .string("2026-04-19T10:00:00.000Z"),
          "updated_at": .string("2026-04-19T10:00:00.000Z"),
          "fc": .string("preserve-me"),
        ]))
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow
              (entity_type, entity_id, base_version, payload_schema_version,
               raw_payload_json, source_device_id, updated_at)
          VALUES (?, ?, ?, ?, ?, 'future-peer', '2026-04-19T10:00:00.000Z')
          """,
        arguments: [EntityName.task, id, futureVersion, futureSchema, shadowPayload])

      try db.execute(
        sql:
          "UPDATE tasks SET title = 'Locally edited', updated_at = '2026-04-19T10:05:00.000Z' "
          + "WHERE id = ?",
        arguments: [id])

      let hlc = try setupHlc()
      try enqueueEntityUpsert(
        db, entityType: EntityName.task, entityId: id, hlcState: hlc,
        deviceId: "dev-001", taskRegisterIntent: .content)

      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(
        pending[0].envelope.payloadSchemaVersion, futureSchema,
        "re-emit must stamp the shadow's higher schema so N peers re-stash the unknown field")
      wirePayload = pending[0].envelope.payload
      wireSchema = pending[0].envelope.payloadSchemaVersion
      wireVersion = pending[0].envelope.version.description
    }

    // A peer at the local (lower) schema receives the re-emit. Because the
    // envelope is stamped one ahead, it lands parse-forward-compat and re-stashes
    // `fc` instead of applying fully and reaping its own shadow.
    let peer = try SyncTestSupport.freshStore()
    try peer.writer.write { db in
      let env = SyncEnvelope(
        entityType: .task, entityId: id, operation: .upsert,
        version: try Hlc.parse(wireVersion),
        payloadSchemaVersion: wireSchema, payload: wirePayload, deviceId: "dev-001")
      let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
      let result = try Apply.applyEnvelope(db, registry: registry, envelope: env)
      guard case .applied = result else {
        return XCTFail("forward-compat envelope must apply known fields, got \(result)")
      }
      let shadow = try XCTUnwrap(
        PayloadShadow.getShadow(db, entityType: EntityName.task, entityID: id),
        "peer must re-stash the unknown field rather than drop it")
      let obj = try XCTUnwrap(JSONValue.parse(shadow.rawPayloadJSON))
      guard case .object(let map) = obj else { return XCTFail("shadow payload not object") }
      XCTAssertEqual(map["fc"], .string("preserve-me"))
    }
  }

  /// A-8: a local edit that merges a forward-compat shadow must bump the shadow's
  /// base_version to the new row version. Otherwise promotion at the next schema
  /// upgrade sees `live > base`, reaps the shadow as obsolete, and the editing
  /// device permanently loses the forward-compat field. With the bump, promotion
  /// takes the equal-version fill branch and restores it.
  func testLocalEditBumpsShadowBaseSoPromotionRestoresForwardCompatField() throws {
    try withDB { db in
      let id = "01966a3f-7c8b-7d4e-8f3a-0000000021a8"
      let v1 = "1711234567890_0201_deadbeefdeadbeef"
      // Live row truncated to a NULL body (an older parser landed it); the shadow
      // carries the value at the same V1. `body` stands in for a field that
      // becomes known after the schema upgrade this promotion simulates.
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, status, list_id,
            content_version, schedule_version, lifecycle_version, archive_version, version,
            created_at, updated_at
          )
          VALUES (?, 'Shadow task', 'open', 'inbox', ?, ?, ?, ?, ?,
                  '2026-03-27T09:00:00.000Z',
                  '2026-03-27T09:00:00.000Z')
          """,
        arguments: [id, v1, v1, v1, v1, v1])
      let shadowPayload = """
        {"id":"\(id)","title":"Shadow task","status":"open","list_id":"inbox",\
        "body":"Recovered from shadow","created_at":"2026-03-27T09:00:00.000Z",\
        "updated_at":"2026-03-27T09:00:00.000Z"}
        """
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow
            (entity_type, entity_id, base_version, payload_schema_version,
             raw_payload_json, source_device_id, updated_at)
          VALUES ('task', ?, ?, 1, ?, 'device-remote', '2026-03-27T09:00:00.000Z')
          """,
        arguments: [id, v1, shadowPayload])

      // Local edit → re-enqueue at a fresh (newer) version, merging the shadow.
      try db.execute(
        sql: "UPDATE tasks SET title = 'Locally edited' WHERE id = ?", arguments: [id])
      let hlc = try setupHlc()
      try enqueueEntityUpsert(
        db, entityType: EntityName.task, entityId: id, hlcState: hlc,
        deviceId: "dev-001", taskRegisterIntent: .content)

      // The shadow's base_version now tracks the row's new version.
      let rowVersion = try XCTUnwrap(
        String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [id]))
      let shadowBase = try XCTUnwrap(
        PayloadShadow.getShadow(db, entityType: EntityName.task, entityID: id)
      ).baseVersion
      XCTAssertEqual(
        shadowBase, rowVersion, "local edit must advance the shadow base to the row version")

      // Promotion (schema now understands the field) restores the value via the
      // equal-version fill branch instead of reaping the shadow as obsolete.
      let registry = EntityApplierRegistry(appliers: EntityApplierRegistry.defaultEntityAppliers())
      XCTAssertEqual(try ApplyPromote.promotePayloadShadows(db, registry: registry), 1)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT body FROM tasks WHERE id = ?", arguments: [id]),
        "Recovered from shadow")
    }
  }

  func testEnqueueRejectsParseableButNoncanonicalContextVersionAtomically() throws {
    try withDB { db in
      let id = "01966a3f-7c8b-7d4e-8f3a-000000002164"
      try insertTask(db, id, "Canonical version boundary")
      let storedBefore = try String.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [id])
      let noncanonical = "1743280000000_1_DEADBEEFDEADBEEF"
      XCTAssertNoThrow(try Hlc.parse(noncanonical), "fixture must remain parseable")

      XCTAssertThrowsError(
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: EntityName.task, entityId: id,
          payload: try OutboxEnqueue.readEntityPayloadSnapshot(
            db, entityType: EntityName.task, entityId: id),
          context: OutboxWriteContext(version: noncanonical, deviceId: "dev-001"))
      ) { error in
        guard case .taintedVersion(let kind, let entityID, let version) = error as? EnqueueError
        else { return XCTFail("expected taintedVersion, got \(error)") }
        XCTAssertEqual(kind, .task)
        XCTAssertEqual(entityID, id)
        XCTAssertEqual(version, noncanonical)
      }
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [id]),
        storedBefore,
        "version stamping must roll back when the wire HLC is noncanonical")
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  // MARK: - entity_upserts.rs

  func testEnqueueUpsertReadsSnapshotAndWritesToOutbox() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try insertTask(db, "01966a3f-7c8b-7d4e-8f3a-000000002163", "Buy milk")
      try enqueueEntityUpsert(
        db, entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000002163",
        hlcState: hlc, deviceId: "dev-001", taskRegisterIntent: .content)

      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      XCTAssertEqual(pending[0].envelope.entityType, .task)
      XCTAssertEqual(pending[0].envelope.entityId, "01966a3f-7c8b-7d4e-8f3a-000000002163")
      XCTAssertEqual(pending[0].envelope.operation, .upsert)
      XCTAssertEqual(pending[0].envelope.deviceId, "dev-001")
      XCTAssertEqual(pending[0].envelope.payloadSchemaVersion, LorvexVersion.payloadSchemaVersion)
      let payload = try XCTUnwrap(JSONValue.parse(pending[0].envelope.payload))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["title"], .string("Buy milk"))
      XCTAssertEqual(obj["status"], .string("open"))
    }
  }

  func testTaskUpsertSnapshotCarriesRecurrenceExceptions() throws {
    try withDB { db in
      let hlc = try setupHlc()
      let id = "01966a3f-7c8b-7d4e-8f3a-000000002199"
      try insertTask(db, id, "Recurring task")
      try db.execute(
        sql: """
          INSERT INTO task_recurrence_exceptions (task_id, exception_date)
          VALUES (?, '2026-04-10'), (?, '2026-04-17')
          """,
        arguments: [id, id])

      try enqueueEntityUpsert(
        db, entityType: EntityName.task, entityId: id, hlcState: hlc,
        deviceId: "dev-001")

      let payload = try parseOutboxPayload(db, EntityName.task, id)
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(
        obj["recurrence_exceptions"],
        .string("[\"2026-04-10\",\"2026-04-17\"]"))
    }
  }

  func testEnqueueUpsertSerializesSqliteBoolColumnsAsJsonBool() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try insertCalendarEvent(db, "01966a3f-7c8b-7d4e-8f3a-000000002114", allDay: 1)
      try enqueueEntityUpsert(
        db, entityType: EntityName.calendarEvent,
        entityId: "01966a3f-7c8b-7d4e-8f3a-000000002114",
        hlcState: hlc, deviceId: "dev-001")

      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      let payload = try XCTUnwrap(JSONValue.parse(pending[0].envelope.payload))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["all_day"], .bool(true))
    }
  }

  func testEnqueuePreferenceUpsertUsesCanonicalJsonValuePayload() throws {
    try withDB { db in
      let hlc = try setupHlc()
      // The outbox enqueue path validates a `preference` entity_id against
      // `PreferenceKeys.isKnownPreferenceKey` / `isLocalOnlyPreference`
      // (`SyncEntityId.validateForKind`), so every case here must use a real
      // synced, non-local-only key. The double- and array-shaped cases below
      // borrow keys whose production value is a different shape purely to
      // exercise canonical JSON value-type encoding; they are not asserting
      // those keys hold that shape in practice.
      let cases: [(String, String, JSONValue)] = [
        (PreferenceKeys.prefSetupCompleted, "true", .bool(true)),
        (PreferenceKeys.prefTimezone, "1.25", .double(1.25)),
        (PreferenceKeys.prefSetupState, "\"dark\"", .string("dark")),
        (
          PreferenceKeys.prefWorkingHours, "{\"start\":\"09:00\",\"end\":\"17:00\"}",
          .object(["end": .string("17:00"), "start": .string("09:00")])
        ),
        (
          PreferenceKeys.prefRecordRawInput, "[\"today\",\"calendar\"]",
          .array([.string("today"), .string("calendar")])
        ),
        (PreferenceKeys.prefSetupSummary, "null", .null),
      ]
      for (key, storedJSON, expected) in cases {
        try insertPreference(db, key, storedJSON)
        try enqueueEntityUpsert(
          db, entityType: EntityName.preference, entityId: key, hlcState: hlc,
          deviceId: "dev-001")

        let payload = try parseOutboxPayload(db, EntityName.preference, key)
        guard case .object(let obj) = payload else { return XCTFail("payload not object") }
        XCTAssertEqual(obj["key"], .string(key))
        XCTAssertEqual(obj["value"], expected, "value mismatch for \(key)")
        XCTAssertEqual(obj["updated_at"], .string("2026-03-20T00:00:00.000Z"))
      }
    }
  }

  // MARK: - habit (D1 weekdays omission)

  private func insertWeeklyHabit(
    _ db: Database, _ id: String, weekdays: [Int64]
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO habits (id, name, frequency_type, target_count, archived,
                            lookup_key, version, created_at, updated_at)
        VALUES (?, 'Workout', 'weekly', 1, 0, 'workout',
                '0000000000000_0000_0000000000000000',
                '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')
        """,
      arguments: [id])
    for wd in weekdays {
      try db.execute(
        sql: "INSERT INTO habit_weekdays (habit_id, weekday) VALUES (?, ?)",
        arguments: [id, wd])
    }
  }

  /// D1: the outbound habit envelope must carry the `weekly` weekday set (which
  /// lives in the `habit_weekdays` child, not a `habits` column) and must NOT
  /// leak `lookup_key` (peers re-derive it from the validated name on apply).
  func testEnqueueHabitUpsertCarriesWeekdaysAndOmitsLookupKey() throws {
    try withDB { db in
      let hlc = try setupHlc()
      let id = "01966a3f-7c8b-7d4e-8f3a-000000005001"
      try insertWeeklyHabit(db, id, weekdays: [0, 2])
      try enqueueEntityUpsert(
        db, entityType: EntityName.habit, entityId: id, hlcState: hlc,
        deviceId: "dev-001")

      let payload = try parseOutboxPayload(db, EntityName.habit, id)
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(
        obj["weekdays"], .array([.int(0), .int(2)]),
        "outbound habit envelope must carry the weekly weekday set")
      XCTAssertNil(
        obj["lookup_key"], "habit wire shape omits lookup_key (peers re-derive on apply)")
      XCTAssertEqual(obj["frequency_type"], .string("weekly"))
    }
  }

  /// D1: full enqueue → `ApplyHabit` round-trip on a fresh peer store rebuilds
  /// `habit_weekdays` to the origin's set. A `weekdays:[]` envelope would let the
  /// peer treat the weekly habit as "every day".
  func testHabitEnqueueApplyRoundTripRebuildsWeekdaysOnPeer() throws {
    let id = "01966a3f-7c8b-7d4e-8f3a-000000005002"
    var wirePayload = ""
    try withDB { db in
      let hlc = try setupHlc()
      try insertWeeklyHabit(db, id, weekdays: [0, 2])
      try enqueueEntityUpsert(
        db, entityType: EntityName.habit, entityId: id, hlcState: hlc,
        deviceId: "dev-001")
      wirePayload = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT payload FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.habit, id]))
    }

    let peer = try SyncTestSupport.freshStore()
    try peer.writer.write { db in
      try ApplyHabit.applyHabitUpsert(
        db, entityId: id, payload: wirePayload,
        version: "1711234560000_0000_dec0000100000001", tieBreak: .rejectEqual,
        applyTs: "2026-04-01T00:00:00.000Z")
      let weekdays = try Int64.fetchAll(
        db, sql: "SELECT weekday FROM habit_weekdays WHERE habit_id = ? ORDER BY weekday ASC",
        arguments: [id])
      XCTAssertEqual(
        weekdays, [0, 2], "peer must rebuild habit_weekdays from the synced weekday set")
    }
  }

  func testEnqueueUpsertProducesCanonicalJson() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try insertList(db, "01966a3f-7c8b-7d4e-8f3a-00000000212f", "Work")
      try enqueueEntityUpsert(
        db, entityType: "list", entityId: "01966a3f-7c8b-7d4e-8f3a-00000000212f",
        hlcState: hlc, deviceId: "dev-001")

      let pending = try Outbox.getPending(db)
      let payloadStr = pending[0].envelope.payload
      let val = try XCTUnwrap(JSONValue.parse(payloadStr))
      let reCanonical = try SyncCanonicalize.canonicalizeJSON(val)
      XCTAssertEqual(payloadStr, reCanonical)
    }
  }

  func testCoalescingReplacesFirstUpsert() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try insertTask(db, "01966a3f-7c8b-7d4e-8f3a-000000002163", "Original title")
      try enqueueEntityUpsert(
        db, entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000002163",
        hlcState: hlc, deviceId: "dev-001")
      try db.execute(
        sql: """
          UPDATE tasks SET title = 'Updated title', updated_at = '2026-03-21T00:00:00.000Z'
          WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000002163'
          """)
      try enqueueEntityUpsert(
        db, entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000002163",
        hlcState: hlc, deviceId: "dev-001")

      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1, "second upsert should coalesce with first")
      let payload = try XCTUnwrap(JSONValue.parse(pending[0].envelope.payload))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["title"], .string("Updated title"))
    }
  }

  func testEntityNotFoundReturnsError() throws {
    try withDB { db in
      let hlc = try setupHlc()
      var thrown: Error?
      do {
        try enqueueEntityUpsert(
          db, entityType: "task", entityId: "nonexistent", hlcState: hlc,
          deviceId: "dev-001")
      } catch { thrown = error }
      let err = try XCTUnwrap(thrown as? EnqueueError)
      guard case .entityNotFound(let et, let id) = err else {
        return XCTFail("expected entityNotFound, got \(err)")
      }
      XCTAssertEqual(et, "task")
      XCTAssertEqual(id, "nonexistent")
    }
  }

  func testUnknownEntityTypeReturnsError() throws {
    try withDB { db in
      let hlc = try setupHlc()
      var thrown: Error?
      do {
        try enqueueEntityUpsert(
          db, entityType: "nonexistent_type", entityId: "id-1", hlcState: hlc,
          deviceId: "dev-001")
      } catch { thrown = error }
      let err = try XCTUnwrap(thrown as? EnqueueError)
      guard case .unknownEntityType = err else {
        return XCTFail("expected unknownEntityType, got \(err)")
      }
    }
  }

  func testEnqueueUpsertForList() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try insertList(db, "01966a3f-7c8b-7d4e-8f3a-00000000212f", "Personal")
      try enqueueEntityUpsert(
        db, entityType: "list", entityId: "01966a3f-7c8b-7d4e-8f3a-00000000212f",
        hlcState: hlc, deviceId: "dev-001")
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      let payload = try XCTUnwrap(JSONValue.parse(pending[0].envelope.payload))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["name"], .string("Personal"))
    }
  }

  func testEnqueueUpsertForTag() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try insertTag(db, "01966a3f-7c8b-7d4e-8f3a-000000002157", "urgent")
      try enqueueEntityUpsert(
        db, entityType: "tag", entityId: "01966a3f-7c8b-7d4e-8f3a-000000002157",
        hlcState: hlc, deviceId: "dev-001")
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 1)
      let payload = try XCTUnwrap(JSONValue.parse(pending[0].envelope.payload))
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(obj["display_name"], .string("urgent"))
    }
  }

  func testEntityTypeToTableCoversAllSinglePkSyncableTypes() throws {
    let edges = [
      EdgeName.taskTag, EdgeName.taskDependency, EdgeName.taskCalendarEventLink,
      EdgeName.habitCompletion,
    ]
    let dedicatedKinds = [EntityName.aiChangelog, EntityName.entityRedirect]
    for et in EntityKind.allSyncableTypes {
      if edges.contains(et) || dedicatedKinds.contains(et) { continue }
      XCTAssertNoThrow(
        try OutboxEnqueue.entityTypeToTable(et),
        "entity_type_to_table missing mapping for syncable type: \(et)")
    }
  }

  func testHlcVersionsAreMonotonicallyIncreasing() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try insertTask(db, "01966a3f-7c8b-7d4e-8f3a-000000002163", "First")
      try insertTask(db, "01966a3f-7c8b-7d4e-8f3a-000000002164", "Second")
      try enqueueEntityUpsert(
        db, entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000002163",
        hlcState: hlc, deviceId: "dev-001")
      try enqueueEntityUpsert(
        db, entityType: "task", entityId: "01966a3f-7c8b-7d4e-8f3a-000000002164",
        hlcState: hlc, deviceId: "dev-001")
      let pending = try Outbox.getPending(db)
      XCTAssertEqual(pending.count, 2)
      XCTAssertTrue(pending[1].envelope.version > pending[0].envelope.version)
    }
  }

  // MARK: - aggregates.rs

  func testAggregateFocusScheduleCarriesBlocks() throws {
    try withDB { db in
      let hlc = try setupHlc()
      let date = "2026-04-10"
      try db.execute(
        sql: """
          INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
          VALUES (?, 'plan', 'UTC', '0000000000000_0000_0000000000000000',
                  '2026-04-10T00:00:00.000Z', '2026-04-10T00:00:00.000Z')
          """,
        arguments: [date])
      try db.execute(
        sql: """
          INSERT INTO focus_schedule_blocks
              (date, position, block_type, start_minutes, end_minutes, title)
          VALUES (?, 0, 'buffer', 540, 600, 'Warm up'), (?, 1, 'buffer', 600, 660, 'Plan')
          """,
        arguments: [date, date])

      try enqueueEntityUpsert(
        db, entityType: EntityName.focusSchedule, entityId: date, hlcState: hlc,
        deviceId: "dev-001")

      let payload = try parseOutboxPayload(db, EntityName.focusSchedule, date)
      guard case .object(let obj) = payload, case .array(let blocks)? = obj["blocks"] else {
        return XCTFail("blocks must be present")
      }
      XCTAssertEqual(blocks.count, 2)
      guard case .object(let b0) = blocks[0], case .object(let b1) = blocks[1] else {
        return XCTFail("block not object")
      }
      XCTAssertEqual(b0["start_minutes"], .int(540))
      XCTAssertEqual(b1["title"], .string("Plan"))
    }
  }

  func testAggregateCurrentFocusCarriesTaskIds() throws {
    try withDB { db in
      let hlc = try setupHlc()
      let date = "2026-04-11"
      try seedDefaultListAndTasks(
        db,
        [
          "01966a3f-7c8b-7d4e-8f3a-000000002152", "01966a3f-7c8b-7d4e-8f3a-000000002153",
        ])
      try db.execute(
        sql: """
          INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
          VALUES (?, 'today', 'UTC', '0000000000000_0000_0000000000000000',
                  '2026-04-11T00:00:00.000Z', '2026-04-11T00:00:00.000Z')
          """,
        arguments: [date])
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: date,
        taskIds: [
          "01966a3f-7c8b-7d4e-8f3a-000000002153", "01966a3f-7c8b-7d4e-8f3a-000000002152",
        ])

      try enqueueEntityUpsert(
        db, entityType: EntityName.currentFocus, entityId: date, hlcState: hlc,
        deviceId: "dev-001")

      let payload = try parseOutboxPayload(db, EntityName.currentFocus, date)
      guard case .object(let obj) = payload, case .array(let arr)? = obj["task_ids"] else {
        return XCTFail("task_ids must be present")
      }
      XCTAssertEqual(
        arr,
        [
          .string("01966a3f-7c8b-7d4e-8f3a-000000002153"),
          .string("01966a3f-7c8b-7d4e-8f3a-000000002152"),
        ])
    }
  }

  func testAggregateDailyReviewCarriesLinks() throws {
    try withDB { db in
      let hlc = try setupHlc()
      let date = "2026-04-12"
      try seedDefaultListAndTasks(db, ["01966a3f-7c8b-7d4e-8f3a-000000002154"])
      try db.execute(
        sql: """
          INSERT INTO daily_reviews (date, summary, version, created_at, updated_at)
          VALUES (?, 'good day', '0000000000000_0000_0000000000000000',
                  '2026-04-12T00:00:00.000Z', '2026-04-12T00:00:00.000Z')
          """,
        arguments: [date])
      try DailyReviewOpsRepo.materializeReviewTaskLinks(
        db, date: date, taskIds: ["01966a3f-7c8b-7d4e-8f3a-000000002154"])
      try DailyReviewOpsRepo.materializeReviewListLinks(
        db, date: date, listIds: ["01966a3f-7c8b-7d4e-8f3a-000000002136"])

      try enqueueEntityUpsert(
        db, entityType: EntityName.dailyReview, entityId: date, hlcState: hlc,
        deviceId: "dev-001")

      let payload = try parseOutboxPayload(db, EntityName.dailyReview, date)
      guard case .object(let obj) = payload else { return XCTFail("payload not object") }
      XCTAssertEqual(
        obj["linked_task_ids"], .array([.string("01966a3f-7c8b-7d4e-8f3a-000000002154")]))
      XCTAssertEqual(
        obj["linked_list_ids"], .array([.string("01966a3f-7c8b-7d4e-8f3a-000000002136")]))
    }
  }

  func testAggregateCalendarEventCarriesAttendees() throws {
    try withDB { db in
      let hlc = try setupHlc()
      try db.execute(
        sql: """
          INSERT INTO calendar_events
              (id, title, start_date, start_time, all_day, event_type, attendees,
               content_version, recurrence_topology_version, version, created_at, updated_at)
          VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002117', 'Sync test', '2026-04-13',
                  '09:00', 0, 'event',
                  '[{"email":"a@example.com","name":"A"},{"email":"b@example.com","name":"B"}]',
                  '0000000000000_0000_0000000000000000',
                  '0000000000000_0000_0000000000000000',
                  '0000000000000_0000_0000000000000000',
                  '2026-04-13T00:00:00.000Z', '2026-04-13T00:00:00.000Z')
          """)

      try enqueueEntityUpsert(
        db, entityType: EntityName.calendarEvent,
        entityId: "01966a3f-7c8b-7d4e-8f3a-000000002117",
        hlcState: hlc, deviceId: "dev-001")

      let payload = try parseOutboxPayload(
        db, EntityName.calendarEvent, "01966a3f-7c8b-7d4e-8f3a-000000002117")
      guard case .object(let obj) = payload, case .array(let attendees)? = obj["attendees"] else {
        return XCTFail("attendees must be present")
      }
      XCTAssertEqual(attendees.count, 2)
      let emails = attendees.compactMap { a -> String? in
        guard case .object(let o) = a, case .string(let e)? = o["email"] else { return nil }
        return e
      }
      XCTAssertTrue(emails.contains("a@example.com"))
      XCTAssertTrue(emails.contains("b@example.com"))
      XCTAssertEqual(obj["all_day"], .bool(false))
    }
  }

  func testEveryRegisteredAggregateRootHasABuilderArm() throws {
    try withDB { db in
      for kind in PayloadBuild.aggregateRootKindsWithDedicatedComposition {
        let value = try PayloadBuild.buildAggregatePayload(
          db, entityType: kind.asString, entityId: "missing")
        XCTAssertNil(value, "aggregate root \(kind.asString) must round-trip to nil for missing id")
      }
      XCTAssertFalse(PayloadBuild.kindNeedsDedicatedComposition(.task))
    }
  }

  func testAggregateMissingRowSurfacesEntityNotFound() throws {
    try withDB { db in
      let hlc = try setupHlc()
      for kind in PayloadBuild.aggregateRootKindsWithDedicatedComposition {
        let et = kind.asString
        var thrown: Error?
        do {
          try enqueueEntityUpsert(
            db, entityType: et, entityId: "missing-id", hlcState: hlc,
            deviceId: "dev-001")
        } catch { thrown = error }
        let err = try XCTUnwrap(thrown as? EnqueueError, "expected error for missing \(et)")
        guard case .entityNotFound(let entityType, let entityId) = err else {
          return XCTFail("expected entityNotFound for missing \(et), got \(err)")
        }
        XCTAssertEqual(entityType, et)
        XCTAssertEqual(entityId, "missing-id")
      }
    }
  }

  /// Mirrors the Rust `upsert_after_delete_clears_stale_tombstone` row-state
  /// contract.
  func testUpsertAfterDeleteClearsStaleTombstone() throws {
    try withDB { db in
      let id = "01966a3f-7c8b-7d4e-8f3a-00000000213d"
      try insertList(db, id, "Resurrected")
      let v1 = "1711234560000_0000_a0a0a0a0a0a0a0a0"
      try self.enqueueSnapshotUpsert(
        db, entityType: EntityName.list, entityId: id, version: v1)

      try db.execute(sql: "DELETE FROM lists WHERE id = ?", arguments: [id])
      let v2 = "1711234561000_0000_a0a0a0a0a0a0a0a0"
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: EntityName.list, entityId: id, payload: .object([:]),
        context: OutboxWriteContext(
          version: v2, deviceId: "dev-001"))
      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.list, entityId: id),
        "delete enqueue should mint a local tombstone")

      try insertList(db, id, "Resurrected v2")
      let v3 = "1711234562000_0000_a0a0a0a0a0a0a0a0"
      try self.enqueueSnapshotUpsert(
        db, entityType: EntityName.list, entityId: id, version: v3)

      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.list, entityId: id),
        "upsert after delete must clear the stale tombstone")
    }
  }

  /// A local re-create (Upsert) of a natural-key entity whose peer DELETE landed
  /// at a DOMINATING future version must not silently destroy that tombstone and
  /// ship an upsert below it (which would lose LWW on push and revert the
  /// re-create). The enqueue surfaces `versionSuperseded` carrying the tombstone's
  /// death version so the write-surface retry advances the clock and re-mints
  /// above it; the tombstone stays put and no losing envelope ships.
  func testUpsertOverDominatingNonRedirectTombstoneSurfacesSupersededForRetry() throws {
    try withDB { db in
      let key = PreferenceKeys.prefWorkingHours
      try insertPreference(db, key, "\"dark\"")
      let futureTombstone = "9999913599990_0000_ffffffffffffffff"
      try Tombstone.createTombstone(
        db, entityType: EntityName.preference, entityId: key, version: futureTombstone,
        deletedAt: "2026-04-19T00:00:00.000Z")

      let localVersion = "1743280000000_0001_deadbeefdeadbeef"
      var thrown: Error?
      do {
        try OutboxEnqueue.enqueuePayloadUpsert(
          db, entityType: EntityName.preference, entityId: key,
          payload: .object([
            "key": .string(key), "value": .string("\"dark\""),
            "updated_at": .string("2026-04-19T00:00:00.000Z"),
          ]),
          context: OutboxWriteContext(
            version: localVersion, deviceId: "dev-001"))
      } catch { thrown = error }

      let err = try XCTUnwrap(thrown as? EnqueueError)
      guard case .versionSuperseded(_, _, _, let existing) = err else {
        return XCTFail("expected versionSuperseded, got \(err)")
      }
      XCTAssertEqual(
        existing, futureTombstone,
        "the retry must advance the clock past the dominating tombstone's death version")

      XCTAssertTrue(
        try Tombstone.isTombstoned(db, entityType: EntityName.preference, entityId: key),
        "a dominating ordinary tombstone must NOT be destroyed by a losing upsert")
      let outboxCount =
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.preference, key]) ?? -1
      XCTAssertEqual(outboxCount, 0, "no upsert envelope may ship below the tombstone")
    }
  }

  /// The post-retry mint: once the context version DOMINATES the tombstone's death
  /// version, the re-create enqueues cleanly, clears the tombstone, and ships an
  /// envelope that out-ranks it.
  func testUpsertOverDominatedNonRedirectTombstoneEnqueuesAndClears() throws {
    try withDB { db in
      let key = PreferenceKeys.prefWorkingHours
      try insertPreference(db, key, "\"dark\"")
      let oldTombstone = "1711234560000_0000_a0a0a0a0a0a0a0a0"
      try Tombstone.createTombstone(
        db, entityType: EntityName.preference, entityId: key, version: oldTombstone,
        deletedAt: "2026-04-19T00:00:00.000Z")

      let dominatingVersion = "1743280000000_0001_deadbeefdeadbeef"
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EntityName.preference, entityId: key,
        payload: .object([
          "key": .string(key), "value": .string("\"dark\""),
          "updated_at": .string("2026-04-19T00:00:00.000Z"),
        ]),
        context: OutboxWriteContext(
          version: dominatingVersion, deviceId: "dev-001"))

      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.preference, entityId: key),
        "a dominating upsert clears the tombstone it out-ranks")
      let shipped = try String.fetchOne(
        db, sql: "SELECT version FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.preference, key])
      XCTAssertEqual(shipped, dominatingVersion)
    }
  }

  /// A normal upsert with NO tombstone enqueues without a spurious supersession.
  func testUpsertWithNoTombstoneEnqueuesWithoutSuperseded() throws {
    try withDB { db in
      let key = PreferenceKeys.prefWorkingHours
      try insertPreference(db, key, "\"dark\"")
      let localVersion = "1743280000000_0001_deadbeefdeadbeef"
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EntityName.preference, entityId: key,
        payload: .object([
          "key": .string(key), "value": .string("\"dark\""),
          "updated_at": .string("2026-04-19T00:00:00.000Z"),
        ]),
        context: OutboxWriteContext(
          version: localVersion, deviceId: "dev-001"))

      let shipped = try String.fetchOne(
        db, sql: "SELECT version FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.preference, key])
      XCTAssertEqual(shipped, localVersion)
    }
  }

  func testStaleDeleteRejectedByOutboxCoalesceDoesNotCreateTombstone() throws {
    try withDB { db in
      let taskId = "01966a3f-7c8b-7d4e-8f3a-00000000219a"
      let newerUpsertVersion = "1711234562000_0000_a0a0a0a0a0a0a0a0"
      let staleDeleteVersion = "1711234561000_0000_a0a0a0a0a0a0a0a0"
      try insertTask(db, taskId, "Fresh local edit")
      try self.enqueueSnapshotUpsert(
        db, entityType: EntityName.task, entityId: taskId, version: newerUpsertVersion)

      try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [taskId])
      try OutboxEnqueue.enqueuePayloadDelete(
        db, entityType: EntityName.task, entityId: taskId, payload: .object([:]),
        context: OutboxWriteContext(
          version: staleDeleteVersion, deviceId: "dev-001"))

      let row = try XCTUnwrap(
        try Row.fetchOne(
          db,
          sql: """
            SELECT operation, version FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.task, taskId]))
      XCTAssertEqual(row["operation"] as String, SyncNaming.opUpsert)
      XCTAssertEqual(row["version"] as String, newerUpsertVersion)
      XCTAssertFalse(
        try Tombstone.isTombstoned(db, entityType: EntityName.task, entityId: taskId),
        "a stale delete rejected by outbox coalescing must not mint a local tombstone")
    }
  }

  // MARK: - pending_drain.rs

  func testLocalWriteWithNoMatchingPendingDoesNotTriggerDrain() throws {
    try withDB { db in
      try insertTask(db, "01966a3f-7c8b-7d4e-8f3a-00000000218a", "Solo task")
      try self.enqueueSnapshotUpsert(
        db, entityType: EntityName.task,
        entityId: "01966a3f-7c8b-7d4e-8f3a-00000000218a",
        version: "1711234568000_0000_b2c3d4e5b2c3d4e5", deviceId: "dev-local")
      XCTAssertEqual(try Outbox.getPending(db).count, 1)
    }
  }

  func testLowLevelParentEnqueueDoesNotConsumePendingChildWithoutHlcOwner() throws {
    try withDB { db in
      let listId = "01966a3f-7c8b-7d4e-8f3a-000000002190"
      let taskId = "01966a3f-7c8b-7d4e-8f3a-000000002191"
      let taskVersion = "1711234567000_0000_a1b2c3d4a1b2c3d4"
      let taskPayload = """
        {"id":"\(taskId)","title":"Pending child","status":"open","list_id":"\(listId)",\
        "defer_count":0,"created_at":"2026-04-25T00:00:00.000Z",\
        "updated_at":"2026-04-25T00:00:00.000Z"}
        """
      let envelope = SyncEnvelope(
        entityType: .task, entityId: taskId, operation: .upsert,
        version: try Hlc.parse(taskVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: taskPayload, deviceId: "dev-remote")
      try PendingInboxDrain.enqueuePending(
        db, envelope: envelope,
        reason: DeferralReason.missingDependency(entityType: .list, entityId: listId).message,
        missingEntityType: EntityName.list, missingEntityID: listId)
      XCTAssertTrue(
        try PendingInbox.hasPendingForTarget(db, entityType: EntityName.list, entityID: listId))

      try insertList(db, listId, "Inbox parent")
      try self.enqueueSnapshotUpsert(
        db, entityType: EntityName.list, entityId: listId,
        version: "1711234568000_0000_b2c3d4e5b2c3d4e5", deviceId: "dev-local")

      XCTAssertEqual(
        try PendingInbox.countPending(db), 1,
        "the low-level enqueue must leave replay to the top-level write funnel that owns the HLC session"
      )
      XCTAssertNil(
        try String.fetchOne(db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [taskId]))
    }
  }
}
