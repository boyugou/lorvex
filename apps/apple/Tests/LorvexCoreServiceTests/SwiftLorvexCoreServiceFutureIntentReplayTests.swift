import Foundation
import GRDB
import LorvexDomain
import LorvexRuntime
import LorvexStore
import XCTest

@testable import LorvexCore
@testable import LorvexSync

final class SwiftLorvexCoreServiceFutureIntentReplayTests: XCTestCase, @unchecked Sendable {
  private let parentListId = "01966a3f-7c8b-7d4e-8f3a-00000000f101"
  private let childTaskId = "01966a3f-7c8b-7d4e-8f3a-00000000f102"
  private let targetTagId = "01966a3f-7c8b-7d4e-8f3a-00000000f1aa"
  private let sourceTagId = "01966a3f-7c8b-7d4e-8f3a-00000000f1bb"
  private let localVersion = "1800000000100_0000_1111222233334444"
  private let childRemoteFloor = "1800000000200_0000_2222333344445555"
  private let parentRemoteFloor = "1800000000300_0000_2222333344445555"

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(
      store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func seedParentAndChild(_ db: Database) throws {
    try db.execute(
      sql: """
        INSERT INTO lists (id, name, version, created_at, updated_at)
        VALUES (?, 'Preserved Parent', ?, '2026-07-15T00:00:00.000Z',
                '2026-07-15T00:00:00.000Z')
        """,
      arguments: [parentListId, localVersion])
    try db.execute(
      sql: """
        INSERT INTO tasks
            (id, list_id, title, status, version,
             content_version, schedule_version, lifecycle_version, archive_version,
             recurrence_rollover_state, recurrence_successor_id, spawned_from_version,
             created_at, updated_at, defer_count)
        VALUES (?, ?, 'Preserved Child', 'open', ?, ?, ?, ?, ?,
                'none', NULL, NULL,
                '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z', 0)
        """,
      arguments: [
        childTaskId, parentListId, localVersion,
        localVersion, localVersion, localVersion, localVersion,
      ])
  }

  private func enqueueAndFenceSnapshot(
    _ db: Database, kind: EntityKind, id: String, remoteFloor: String,
    mutatePayload: ((inout [String: JSONValue]) -> Void)? = nil
  ) throws {
    let snapshot = try OutboxEnqueue.readEntityPayloadSnapshot(
      db, entityType: kind.asString, entityId: id)
    let registerIntent = EntityRegisterIntent.inferredLocalMutation(
      entityType: kind, from: snapshot)
    try OutboxEnqueue.enqueuePayloadUpsert(
      db, entityType: kind.asString, entityId: id, payload: snapshot,
      context: OutboxWriteContext(
        version: localVersion, deviceId: "local-device",
        registerIntent: registerIntent))
    if let mutatePayload {
      guard case .object(var object) = snapshot else {
        throw TestSetupError.payloadWasNotObject
      }
      mutatePayload(&object)
      let payload = try SyncCanonicalize.canonicalizeJSON(.object(object))
      try db.execute(
        sql: "UPDATE sync_outbox SET payload = ? WHERE entity_type = ? AND entity_id = ?",
        arguments: [payload, kind.asString, id])
    }
    try db.execute(
      sql: """
        UPDATE sync_outbox
        SET retry_count = ?, consecutive_error_count = 0,
            last_error = 'future record hold', disposition = ?,
            next_retry_at = NULL, authoritative_session_token = NULL,
            future_record_version = ?, future_record_resolution = ?
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
        """,
      arguments: [
        Outbox.maxRetries, Outbox.Disposition.futureRecordHold.rawValue,
        remoteFloor, FutureRecordHold.Resolution.localAfterFuture.rawValue,
        kind.asString, id,
      ])
  }

  private func parkTerminalDelete(
    _ db: Database, kind: EntityKind, id: String, version: String
  ) throws {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object(["version": .string(version)]))
    let envelope = SyncEnvelope(
      entityType: kind, entityId: id, operation: .delete,
      version: try Hlc.parseCanonical(version),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: payload, deviceId: "remote-device")
    try PendingInboxDrain.enqueuePending(
      db, envelope: envelope, reason: "test_future_terminal",
      missingEntityType: nil, missingEntityID: nil,
      countsTowardRetryBudget: false)
  }

  func testGenericLocalWriteDrainsAndReplaysParentChildOnce() async throws {
    let service = try makeService()
    try service.write { db in
      try seedParentAndChild(db)
      try enqueueAndFenceSnapshot(
        db, kind: .list, id: parentListId, remoteFloor: parentRemoteFloor)
      try enqueueAndFenceSnapshot(
        db, kind: .task, id: childTaskId, remoteFloor: childRemoteFloor)
      // Deliberately reverse dependency order in the pending queue. The drain
      // surfaces child replay first, but the shared fulfillment helper must
      // restore the parent before the child.
      try parkTerminalDelete(
        db, kind: .task, id: childTaskId, version: childRemoteFloor)
      try parkTerminalDelete(
        db, kind: .list, id: parentListId, version: parentRemoteFloor)
    }
    let before = try service.read { db in try LocalChangeSeq.read(db) }

    _ = try await service.createList(name: "Drain Trigger", description: nil)

    let state = try service.read { db in
      let parent = try Row.fetchOne(
        db, sql: "SELECT name, version FROM lists WHERE id = ?",
        arguments: [self.parentListId])
      let child = try Row.fetchOne(
        db, sql: "SELECT title, list_id, version FROM tasks WHERE id = ?",
        arguments: [self.childTaskId])
      let pending = try PendingInbox.countPending(db)
      let seq = try LocalChangeSeq.read(db)
      return (parent, child, pending, seq)
    }
    XCTAssertEqual(state.0?["name"] as String?, "Preserved Parent")
    XCTAssertEqual(state.1?["title"] as String?, "Preserved Child")
    XCTAssertEqual(state.1?["list_id"] as String?, parentListId)
    XCTAssertEqual(state.2, 0)
    XCTAssertEqual(state.3, before + 1, "the top-level local write owns exactly one seq bump")
    XCTAssertGreaterThan(
      try Hlc.parseCanonical(try XCTUnwrap(state.0?["version"] as String?)),
      try Hlc.parseCanonical(parentRemoteFloor))
    XCTAssertGreaterThan(
      try Hlc.parseCanonical(try XCTUnwrap(state.1?["version"] as String?)),
      try Hlc.parseCanonical(childRemoteFloor))

    let replayed = try service.pendingOutbound().map(\.envelope)
    let parent = try XCTUnwrap(
      replayed.first { $0.entityType == .list && $0.entityId == self.parentListId })
    let child = try XCTUnwrap(
      replayed.first { $0.entityType == .task && $0.entityId == self.childTaskId })
    XCTAssertGreaterThan(parent.version, try Hlc.parseCanonical(parentRemoteFloor))
    XCTAssertGreaterThan(child.version, try Hlc.parseCanonical(childRemoteFloor))
  }

  func testReplayFailureRollsBackTriggerDrainAndLocalWrite() async throws {
    let service = try makeService()
    let missingListId = "01966a3f-7c8b-7d4e-8f3a-00000000ffff"
    try service.write { db in
      try seedParentAndChild(db)
      try enqueueAndFenceSnapshot(
        db, kind: .task, id: childTaskId, remoteFloor: childRemoteFloor,
        mutatePayload: { $0["list_id"] = .string(missingListId) })
      try parkTerminalDelete(
        db, kind: .task, id: childTaskId, version: childRemoteFloor)
    }
    let before = try service.read { db in try LocalChangeSeq.read(db) }

    do {
      _ = try await service.createList(name: "Must Roll Back", description: nil)
      XCTFail("a replay with a missing dependency must abort the entire local write")
    } catch {
      // Expected: the replay remains durable and no partial local write commits.
    }

    try service.read { db in
      XCTAssertEqual(try LocalChangeSeq.read(db), before)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE name = 'Must Roll Back'"),
        0)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?", arguments: [self.childTaskId]),
        "Preserved Child")
      XCTAssertEqual(try PendingInbox.countPending(db), 1)
      let fence = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT disposition, future_record_resolution
            FROM sync_outbox WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.task, self.childTaskId]))
      XCTAssertEqual(
        fence["disposition"] as String,
        Outbox.Disposition.futureRecordHold.rawValue)
      XCTAssertEqual(
        fence["future_record_resolution"] as String,
        FutureRecordHold.Resolution.localAfterFuture.rawValue)
    }
  }

  func testInboundTerminalAndRedirectReplaysOntoCanonicalTarget() throws {
    let service = try makeService()
    let terminalVersion = "1800000000200_0000_2222333344445555"
    let redirectVersion = "1800000000300_0000_2222333344445555"
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Canonical Target', 'canonical target', ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [targetTagId, localVersion])
      try db.execute(
        sql: """
          INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
          VALUES (?, 'Preserved Local', 'preserved local', ?,
                  '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
          """,
        arguments: [sourceTagId, localVersion])
      try enqueueAndFenceSnapshot(
        db, kind: .tag, id: sourceTagId, remoteFloor: terminalVersion)
    }

    let terminalPayload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "color": .null,
        "created_at": .string("2026-07-15T00:00:00.000Z"),
        "display_name": .string("Understood Remote"),
        "updated_at": .string("2026-07-15T00:00:00.000Z"),
        "version": .string(terminalVersion),
      ]))
    let terminal = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .tag, entityId: sourceTagId, operation: .upsert,
        version: try Hlc.parseCanonical(terminalVersion),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: terminalPayload, deviceId: "remote-device"))
    let redirect = try EntityRedirect.makeEnvelope(
      record: EntityRedirect.Record(
        sourceType: .tag, sourceId: sourceTagId, targetId: targetTagId,
        version: redirectVersion, createdAt: "2026-07-15T00:00:00.000Z"),
      deviceId: "remote-device")

    _ = try service.applyInbound([terminal, redirect], undecodable: 0)

    let state = try service.read { db in
      let target = try Row.fetchOne(
        db, sql: "SELECT display_name, version FROM tags WHERE id = ?",
        arguments: [self.targetTagId])
      let sourceCount = try Int.fetchOne(
        db, sql: "SELECT COUNT(*) FROM tags WHERE id = ?", arguments: [self.sourceTagId])
      let alias = try EntityRedirect.get(
        db, sourceType: EntityName.tag, sourceId: self.sourceTagId)
      return (target, sourceCount, alias)
    }
    XCTAssertEqual(state.0?["display_name"] as String?, "Preserved Local")
    XCTAssertEqual(state.1, 0)
    XCTAssertEqual(state.2?.targetId, targetTagId)

    let targetOutbound = try XCTUnwrap(
      try service.pendingOutbound().map(\.envelope).first {
        $0.entityType == .tag && $0.entityId == self.targetTagId
          && $0.operation == .upsert
      })
    let targetVersion = try Hlc.parseCanonical(
      try XCTUnwrap(state.0?["version"] as String?))
    XCTAssertEqual(targetOutbound.version, targetVersion)
    XCTAssertGreaterThan(targetOutbound.version, redirect.version)
  }

  private enum TestSetupError: Error {
    case payloadWasNotObject
  }
}
