import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class FutureLocalIntentReplayOrderTests: XCTestCase {
  private let registry = EntityApplierRegistry(
    appliers: EntityApplierRegistry.defaultEntityAppliers())
  private let deviceId = "local-device"
  private let parentListId = "01966a3f-7c8b-7d4e-8f3a-00000000e101"
  private let childTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000e102"
  private let lexicalChildTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000e110"
  private let lexicalParentTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000e1f0"
  private let deleteParentTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000e120"
  private let deleteChildTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000e1e0"
  private let targetTagId = "01966a3f-7c8b-7d4e-8f3a-00000000e1aa"
  private let sourceTagId = "01966a3f-7c8b-7d4e-8f3a-00000000e1bb"

  private func version(_ physical: UInt64, counter: UInt32 = 0) throws -> Hlc {
    try Hlc(
      physicalMs: physical, counter: counter,
      deviceSuffix: "1111222233334444")
  }

  private func minter(
    recording minted: UnsafeMutablePointer<[Hlc]>? = nil
  ) throws -> (Hlc?) -> String {
    let state = try HlcState(deviceSuffix: "aaaaaaaaaaaaaaaa")
    return { floor in
      if let floor {
        state.updateOnReceive(remote: floor, physicalMs: 0)
      }
      let next = state.generate(withPhysicalMs: 0)
      minted?.pointee.append(next)
      return next.description
    }
  }

  private func listPayload(version: Hlc) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "created_at": .string("2026-07-15T00:00:00.000Z"),
        "name": .string("Parent"),
        "updated_at": .string("2026-07-15T00:00:00.000Z"),
        "version": .string(version.description),
      ]))
  }

  private func taskPayload(
    version: Hlc, title: String = "Child", spawnedFrom: String? = nil
  ) throws -> String {
    var object: [String: JSONValue] = [
      "created_at": .string("2026-07-15T00:00:00.000Z"),
      "defer_count": .int(0),
      "list_id": .string(parentListId),
      "status": .string("open"),
      "title": .string(title),
      "updated_at": .string("2026-07-15T00:00:00.000Z"),
      "version": .string(version.description),
    ]
    if let spawnedFrom {
      object["spawned_from"] = .string(spawnedFrom)
      object["spawned_from_version"] = .string(version.description)
    }
    return try SyncCanonicalize.canonicalizeJSON(.object(object))
  }

  private func tagPayload(name: String, version: Hlc) throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "color": .null,
        "created_at": .string("2026-07-15T00:00:00.000Z"),
        "display_name": .string(name),
        "updated_at": .string("2026-07-15T00:00:00.000Z"),
        "version": .string(version.description),
      ]))
  }

  private func replay(
    kind: EntityKind, id: String, operation: SyncOperation, version: Hlc,
    payload: String, remoteFloor: Hlc
  ) -> FutureRecordHold.LocalIntentReplay {
    let registerIntent: EntityRegisterIntent =
      kind == .task && operation == .upsert ? .task(.all) : .none
    return FutureRecordHold.LocalIntentReplay(
      intent: try! SyncTestSupport.completeEnvelope(
        entityType: kind, entityId: id, operation: operation,
        version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: deviceId),
      remoteFloor: remoteFloor,
      registerIntent: registerIntent)
  }

  func testExactOperationalTerminalClockIsHeldBeforeCanonicalApply() throws {
    let store = try SyncTestSupport.freshStore()
    let terminal = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs,
      counter: Hlc.maxCounter, deviceSuffix: "ffffffffffffffff")
    XCTAssertTrue(Hlc.isOperationallyAcceptableWire(terminal))
    XCTAssertFalse(Hlc.hasOperationalWireSuccessor(after: terminal))

    try store.writer.write { db in
      let incoming = try SyncTestSupport.completeEnvelope(
        entityType: .list, entityId: parentListId, operation: .upsert,
        version: terminal, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try listPayload(version: terminal), deviceId: "remote-device")
      let outcome = try Apply.applyEnvelope(db, registry: registry, envelope: incoming)
      guard case .deferred(.operationallyUnusableHlc(let held, _)) = outcome else {
        return XCTFail("the exact terminal operational HLC must enter the durable hold")
      }
      XCTAssertEqual(held, terminal)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [parentListId]),
        0)
    }
  }

  func testBatchReplayOrdersReversedParentChildUpsertsParentFirst() throws {
    let store = try SyncTestSupport.freshStore()
    let local = try version(1_800_000_000_100)
    let remote = try version(1_800_000_000_200)

    try store.writer.write { db in
      let child = replay(
        kind: .task, id: childTaskId, operation: .upsert, version: local,
        payload: try taskPayload(version: local), remoteFloor: remote)
      let parent = replay(
        kind: .list, id: parentListId, operation: .upsert, version: local,
        payload: try listPayload(version: local), remoteFloor: remote)

      try FutureRecordHold.fulfillLocalIntentReplays(
        db, replays: [child, parent], registry: registry,
        mintVersion: try minter(), deviceId: deviceId)

      let queued = try Row.fetchAll(
        db,
        sql: """
          SELECT entity_type, entity_id FROM sync_outbox
          WHERE entity_id IN (?, ?) ORDER BY id
          """,
        arguments: [parentListId, childTaskId])
      XCTAssertEqual(
        queued.map { $0["entity_type"] as String }, [EntityName.list, EntityName.task])
      XCTAssertEqual(queued.map { $0["entity_id"] as String }, [parentListId, childTaskId])
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT list_id FROM tasks WHERE id = ?", arguments: [childTaskId]),
        parentListId)
    }
  }

  func testTaskUpsertsUseLineageWhenChildIdSortsBeforeParentId() throws {
    let store = try SyncTestSupport.freshStore()
    let local = try version(1_800_000_000_100)
    let remote = try version(1_800_000_000_200)
    XCTAssertLessThan(
      lexicalChildTaskId, lexicalParentTaskId,
      "fixture must reproduce the lexical child-before-parent bug")

    try store.writer.write { db in
      let child = replay(
        kind: .task, id: lexicalChildTaskId, operation: .upsert, version: local,
        payload: try taskPayload(
          version: local, title: "Generated child", spawnedFrom: lexicalParentTaskId),
        remoteFloor: remote)
      let parent = replay(
        kind: .task, id: lexicalParentTaskId, operation: .upsert, version: local,
        payload: try taskPayload(version: local, title: "Parent"),
        remoteFloor: remote)

      let ordered = try FutureRecordHold.orderedLocalIntentReplays(
        db, replays: [child, parent])
      XCTAssertEqual(
        ordered.map(\.intent.entityId), [lexicalParentTaskId, lexicalChildTaskId])
    }
  }

  func testTaskDeletesUseMaterializedLineageAndRemoveChildFirst() throws {
    let store = try SyncTestSupport.freshStore()
    let local = try version(1_800_000_000_100)
    let remote = try version(1_800_000_000_200)
    XCTAssertLessThan(
      deleteParentTaskId, deleteChildTaskId,
      "fixture must reproduce the lexical parent-before-child bug")

    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks
              (id, title, status, list_id, spawned_from, spawned_from_version,
               version, created_at, updated_at)
          VALUES (?, 'Parent', 'open', 'inbox', NULL, NULL, ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z'),
                 (?, 'Child', 'open', 'inbox', ?, ?, ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [
          deleteParentTaskId, local.description,
          deleteChildTaskId, deleteParentTaskId, local.description, local.description,
        ])
      let parent = replay(
        kind: .task, id: deleteParentTaskId, operation: .delete, version: local,
        payload: "{}", remoteFloor: remote)
      let child = replay(
        kind: .task, id: deleteChildTaskId, operation: .delete, version: local,
        payload: "{}", remoteFloor: remote)

      let ordered = try FutureRecordHold.orderedLocalIntentReplays(
        db, replays: [parent, child])
      XCTAssertEqual(
        ordered.map(\.intent.entityId), [deleteChildTaskId, deleteParentTaskId])
    }
  }

  func testTaskLineageCycleFailsClosedBeforeAnyReplay() throws {
    let store = try SyncTestSupport.freshStore()
    let local = try version(1_800_000_000_100)
    let remote = try version(1_800_000_000_200)
    let firstId = lexicalChildTaskId
    let secondId = lexicalParentTaskId

    try store.writer.write { db in
      let first = replay(
        kind: .task, id: firstId, operation: .upsert, version: local,
        payload: try taskPayload(
          version: local, title: "First", spawnedFrom: secondId),
        remoteFloor: remote)
      let second = replay(
        kind: .task, id: secondId, operation: .upsert, version: local,
        payload: try taskPayload(
          version: local, title: "Second", spawnedFrom: firstId),
        remoteFloor: remote)

      XCTAssertThrowsError(
        try FutureRecordHold.fulfillLocalIntentReplays(
          db, replays: [second, first], registry: registry,
          mintVersion: try minter(), deviceId: deviceId)
      ) { error in
        XCTAssertEqual(
          error as? ApplyError,
          .invalidPayload(
            "future local task upsert replay contains a spawned_from cycle at \(firstId)"))
      }
      XCTAssertEqual(
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0,
        "ordering failure must occur before replay mutates durable state")
    }
  }

  func testSingleTaskSelfLineageCycleAlsoFailsClosed() throws {
    let store = try SyncTestSupport.freshStore()
    let local = try version(1_800_000_000_100)
    let remote = try version(1_800_000_000_200)

    try store.writer.write { db in
      let replay = replay(
        kind: .task, id: lexicalChildTaskId, operation: .upsert, version: local,
        payload: try taskPayload(
          version: local, title: "Self cycle", spawnedFrom: lexicalChildTaskId),
        remoteFloor: remote)

      XCTAssertThrowsError(
        try FutureRecordHold.fulfillLocalIntentReplays(
          db, replays: [replay], registry: registry,
          mintVersion: try minter(), deviceId: deviceId)
      ) { error in
        XCTAssertEqual(
          error as? ApplyError,
          .invalidPayload(
            "future local task upsert replay contains a spawned_from cycle at "
              + lexicalChildTaskId))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testTaskDeleteLineageCycleFailsClosedBeforeAnyReplay() throws {
    let store = try SyncTestSupport.freshStore()
    let local = try version(1_800_000_000_100)
    let remote = try version(1_800_000_000_200)
    let firstId = deleteParentTaskId
    let secondId = deleteChildTaskId

    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks
              (id, title, status, list_id, spawned_from, spawned_from_version,
               version, created_at, updated_at)
          VALUES (?, 'First', 'open', 'inbox', ?, ?, ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z'),
                 (?, 'Second', 'open', 'inbox', ?, ?, ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [
          firstId, secondId, local.description, local.description,
          secondId, firstId, local.description, local.description,
        ])
      let first = replay(
        kind: .task, id: firstId, operation: .delete, version: local,
        payload: "{}", remoteFloor: remote)
      let second = replay(
        kind: .task, id: secondId, operation: .delete, version: local,
        payload: "{}", remoteFloor: remote)

      XCTAssertThrowsError(
        try FutureRecordHold.fulfillLocalIntentReplays(
          db, replays: [second, first], registry: registry,
          mintVersion: try minter(), deviceId: deviceId)
      ) { error in
        XCTAssertEqual(
          error as? ApplyError,
          .invalidPayload(
            "future local task delete replay contains a spawned_from cycle at \(firstId)"))
      }
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testBatchReplayOrdersReversedParentChildDeletesChildFirst() throws {
    let store = try SyncTestSupport.freshStore()
    let local = try version(1_800_000_000_100)
    let remote = try version(1_800_000_000_200)

    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at)
          VALUES (?, 'Parent', ?, '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [parentListId, local.description])
      try db.execute(
        sql: """
          INSERT INTO tasks
              (id, list_id, title, status, version, created_at, updated_at, defer_count)
          VALUES (?, ?, 'Child', 'open', ?, '2026-07-15T00:00:00.000Z',
                  '2026-07-15T00:00:00.000Z', 0)
          """,
        arguments: [childTaskId, parentListId, local.description])

      let parent = replay(
        kind: .list, id: parentListId, operation: .delete, version: local,
        payload: "{}", remoteFloor: remote)
      let child = replay(
        kind: .task, id: childTaskId, operation: .delete, version: local,
        payload: "{}", remoteFloor: remote)

      try FutureRecordHold.fulfillLocalIntentReplays(
        db, replays: [parent, child], registry: registry,
        mintVersion: try minter(), deviceId: deviceId)

      let queued = try Row.fetchAll(
        db,
        sql: """
          SELECT entity_type, entity_id FROM sync_outbox
          WHERE entity_id IN (?, ?) ORDER BY id
          """,
        arguments: [parentListId, childTaskId])
      XCTAssertEqual(
        queued.map { $0["entity_type"] as String }, [EntityName.task, EntityName.list])
      XCTAssertEqual(queued.map { $0["entity_id"] as String }, [childTaskId, parentListId])
    }
  }

  func testRemappedReplayEmitsCanonicalTargetAtSecondStrictSuccessor() throws {
    let store = try SyncTestSupport.freshStore()
    let targetVersion = try version(1_800_000_000_100)
    let intentVersion = try version(1_800_000_000_150)
    let remoteFloor = try version(1_800_000_000_200)
    let redirectVersion = try version(1_800_000_000_250)

    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Target', 'target', ?, '2026-07-15T00:00:00.000Z',
                  '2026-07-15T00:00:00.000Z')
          """,
        arguments: [targetTagId, targetVersion.description])
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
              (source_type, source_id, target_id, version, created_at)
          VALUES (?, ?, ?, ?, '2026-07-15T00:00:00.000Z')
          """,
        arguments: [EntityName.tag, sourceTagId, targetTagId, redirectVersion.description])

      let held = replay(
        kind: .tag, id: sourceTagId, operation: .upsert, version: intentVersion,
        payload: try tagPayload(name: "Preserved Local", version: intentVersion),
        remoteFloor: remoteFloor)
      var minted: [Hlc] = []
      _ = try withUnsafeMutablePointer(to: &minted) { pointer in
        try FutureRecordHold.fulfillLocalIntentReplays(
          db, replays: [held], registry: registry,
          mintVersion: try minter(recording: pointer), deviceId: deviceId)
      }

      XCTAssertEqual(minted.count, 2, "remap must mint replay successor plus convergence successor")
      XCTAssertGreaterThan(minted[0], max(intentVersion, remoteFloor))
      XCTAssertGreaterThan(minted[1], minted[0])
      let target = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT display_name, version FROM tags WHERE id = ?",
          arguments: [targetTagId]))
      XCTAssertEqual(target["display_name"] as String, "Preserved Local")
      XCTAssertEqual(target["version"] as String, minted[1].description)
      let outbound = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT version, payload FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.tag, targetTagId]))
      XCTAssertEqual(outbound["version"] as String, minted[1].description)
      guard case .object(let payload)? = JSONValue.parse(outbound["payload"] as String) else {
        return XCTFail("canonical target outbox payload must be an object")
      }
      XCTAssertEqual(payload["version"], .string(minted[1].description))
    }
  }
}
