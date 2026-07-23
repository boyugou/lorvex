import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceRemoteAuthoritativeDeletionTests: XCTestCase {
  private let account = "account-a"
  private let zone = "LorvexZone-g7"

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

  private func boundary() throws -> CloudTraversalBoundary {
    try CloudTraversalBoundary(
      accountIdentifier: account, zoneIdentifier: zone, generation: 7,
      generationIdentifier: "generation-7", readyWitness: "ready-7")
  }

  private func proof(
    _ boundary: CloudTraversalBoundary, traversalIdentifier: String
  ) throws -> CloudTraversalPageObservation {
    try CloudTraversalPageObservation(
      generationRootIdentifier: boundary.generationIdentifier,
      readyWitness: boundary.readyWitness,
      traversalWitnessIdentifier: traversalIdentifier)
  }

  private func inboxRecord() throws -> AuthoritativeSnapshotRemoteRecord {
    let version = try Hlc.parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "id": .string("inbox"),
        "name": .string("Inbox"),
        "created_at": .string("2026-07-14T00:00:00.000Z"),
        "updated_at": .string("2026-07-14T00:00:00.000Z"),
        "version": .string(version.description),
      ]))
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .list, entityId: "inbox", operation: .upsert,
        version: version, payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device"))
    return AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: EntityName.list, entityId: "inbox"),
      state: .decoded, envelope: envelope)
  }

  private func remoteRecord(
    _ service: SwiftLorvexCoreService, kind: EntityKind, entityID: String
  ) throws -> AuthoritativeSnapshotRemoteRecord {
    let (payload, version) = try service.read { db in
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: kind.asString, entityId: entityID)
      let table = try XCTUnwrap(kind.tableName)
      let primaryKey = try XCTUnwrap(kind.tablePk?.pk)
      let version = try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM \(table) WHERE \(primaryKey) = ?",
          arguments: [entityID]))
      return (payload, version)
    }
    let envelope = try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: kind, entityId: entityID, operation: .upsert,
        version: try Hlc.parseCanonical(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: try SyncCanonicalize.canonicalizeJSON(payload),
        deviceId: "remote-device"))
    return AuthoritativeSnapshotRemoteRecord(
      recordName: SyncRecordName.opaque(
        entityType: kind.asString, entityId: entityID),
      state: .decoded, envelope: envelope)
  }

  private func tagUpsert(
    id: String, name: String, version: String
  ) throws -> SyncEnvelope {
    let payload = try SyncCanonicalize.canonicalizeJSON(
      .object([
        "display_name": .string(name),
        "lookup_key": .string(normalizeLookupKey(name)),
        "color": .null,
        "created_at": .string("2026-07-18T00:00:00.000Z"),
        "updated_at": .string("2026-07-18T00:00:00.000Z"),
      ]))
    return try CurrentSyncEnvelopeTestSupport.complete(
      SyncEnvelope(
        entityType: .tag, entityId: id, operation: .upsert,
        version: try Hlc.parseCanonical(version),
        payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
        payload: payload, deviceId: "remote-device"))
  }

  private func seedRemoteAuthoritativeRedirectFence(
    _ service: SwiftLorvexCoreService
  ) throws -> (sourceID: String, targetID: String, wireID: String) {
    let targetID = "00000000-0000-7000-8000-00000000000a"
    let sourceID = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    _ = try service.applyInbound(
      [
        try tagUpsert(
          id: sourceID, name: "Shared",
          version: "1711234567000_0000_dec0000200000002"),
        try tagUpsert(
          id: targetID, name: "Shared",
          version: "1711234568000_0000_dec0000100000001"),
      ], undecodable: 0)
    let wireID = EntityRedirect.wireEntityId(
      sourceType: .tag, sourceId: sourceID)
    try service.write { db in
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT target_id FROM sync_entity_redirects
            WHERE source_type = ? AND source_id = ?
            """,
          arguments: [EntityName.tag, sourceID]),
        targetID)
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type != ? OR entity_id != ?",
        arguments: [EntityName.entityRedirect, wireID])
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, consecutive_error_count = 0,
              last_error = 'test future-record fence',
              disposition = ?, next_retry_at = NULL,
              authoritative_session_token = NULL,
              future_record_version = ?, future_record_resolution = ?
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.futureRecordHold.rawValue,
          "1711234569000_0000_dec0000300000003",
          FutureRecordHold.Resolution.remoteAuthoritative.rawValue,
          EntityName.entityRedirect, wireID,
        ])
      XCTAssertEqual(db.changesCount, 1)
    }
    return (sourceID, targetID, wireID)
  }

  private func armRemoteAuthoritativeFence(
    _ service: SwiftLorvexCoreService, kind: EntityKind, entityID: String,
    registerIntent: EntityRegisterIntent = .none
  ) throws {
    try service.write { db in
      let payload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: kind.asString, entityId: entityID)
      let version = try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM \(try XCTUnwrap(kind.tableName)) WHERE \(try XCTUnwrap(kind.tablePk?.pk)) = ?",
          arguments: [entityID]))
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [kind.asString, entityID])
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: kind.asString, entityId: entityID, payload: payload,
        context: OutboxWriteContext(
          version: version, deviceId: "local-device", registerIntent: registerIntent))
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, consecutive_error_count = 0,
              last_error = 'test future-record fence',
              disposition = ?, next_retry_at = NULL,
              authoritative_session_token = NULL,
              future_record_version = ?, future_record_resolution = ?
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.futureRecordHold.rawValue,
          "1711234567892_0000_b1c2d3e4b1c2d3e4",
          FutureRecordHold.Resolution.remoteAuthoritative.rawValue,
          kind.asString, entityID,
        ])
      XCTAssertEqual(db.changesCount, 1)
    }
  }

  private func armExistingDeleteAsRemoteAuthoritativeFence(
    _ service: SwiftLorvexCoreService, kind: EntityKind, entityID: String
  ) throws {
    try service.write { db in
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = ?, consecutive_error_count = 0,
              last_error = 'test future-record fence',
              disposition = ?, next_retry_at = NULL,
              authoritative_session_token = NULL,
              future_record_version = ?, future_record_resolution = ?
          WHERE entity_type = ? AND entity_id = ? AND operation = ?
            AND synced_at IS NULL
          """,
        arguments: [
          Outbox.maxRetries, Outbox.Disposition.futureRecordHold.rawValue,
          "1800000000000_0000_b1c2d3e4b1c2d3e4",
          FutureRecordHold.Resolution.remoteAuthoritative.rawValue,
          kind.asString, entityID, SyncNaming.opDelete,
        ])
      XCTAssertEqual(db.changesCount, 1)
    }
  }

  private func applyPhysicalDeletion(
    _ service: SwiftLorvexCoreService, recordNames: [String],
    traversalIdentifier: String = "physical-deletion"
  ) throws -> InboundApplyReport {
    let boundary = try boundary()
    _ = try service.claimCloudTraversalAccount(accountIdentifier: account)
    _ = try service.beginCloudTraversal(
      boundary: boundary, traversalIdentifier: traversalIdentifier,
      start: .baseline)
    return try service.applyInboundTraversalPage(
      [], cloudReceipts: [], undecodable: 0,
      boundary: boundary, traversalIdentifier: traversalIdentifier,
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x72]), moreComing: false,
        observation: try proof(boundary, traversalIdentifier: traversalIdentifier)),
      inboundObservation: CloudInboundPageObservation(
        deletedRecordNames: recordNames))
  }

  private func seedPermanentRedirectTarget(
    _ service: SwiftLorvexCoreService, kind: EntityKind
  ) async throws -> (targetID: String, sourceID: String) {
    let targetID: String
    switch kind {
    case .tag:
      targetID = "00000000-0000-7000-8000-0000000000a1"
      try await service.importTag(
        ExportTag(id: targetID, displayName: "Redirect target tag"))
    case .habit:
      targetID = try await service.createHabit(
        name: "Redirect target habit", cue: nil, targetCount: 1).id
    case .memory:
      _ = try await service.upsertMemory(
        key: "redirect-target-memory", content: "Keep this terminal value")
      targetID = try service.read { db in
        try XCTUnwrap(
          String.fetchOne(
            db, sql: "SELECT id FROM memories WHERE key = 'redirect-target-memory'"))
      }
    case .habitReminderPolicy:
      let habit = try await service.createHabit(
        name: "Redirect policy parent", cue: nil, targetCount: 1)
      targetID = try await service.upsertHabitReminderPolicy(
        id: habit.id,
        policy: HabitReminderPolicy(
          id: "", habitID: habit.id, habitName: habit.name,
          reminderTime: "08:00", enabled: true, createdAt: "", updatedAt: "")
      ).id
    default:
      throw XCTSkip("Entity kind does not support permanent redirects")
    }

    let sourceID = "ffffffff-ffff-7fff-8fff-ffffffffffff"
    let redirectVersion = "1800000000000_0000_dec0000300000003"
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO sync_entity_redirects
            (source_type, source_id, target_id, version, created_at)
          VALUES (?, ?, ?, ?, '2026-07-18T00:00:00.000Z')
          """,
        arguments: [kind.asString, sourceID, targetID, redirectVersion])
      try Tombstone.createTombstone(
        db, entityType: kind.asString, entityId: sourceID,
        version: redirectVersion, deletedAt: "2026-07-18T00:00:00.000Z")
      try db.execute(sql: "DELETE FROM sync_outbox")
    }
    return (targetID, sourceID)
  }

  func testGraphRootPhysicalDeletionDefersToIntentPreservingCompleteInventory() async throws {
    let service = try makeService()
    let focusDate = "2026-07-17"
    let staleTask = try await service.createTask(
      title: "Stale local fallback", notes: "")
    _ = try await service.addTaskChecklistItem(
      taskID: staleTask.id, text: "Must not cascade incrementally")
    _ = try await service.setCurrentFocus(
      date: focusDate, taskIDs: [staleTask.id], briefing: nil,
      timezone: "UTC")
    _ = try await service.saveFocusSchedule(
      date: focusDate,
      blocks: [
        FocusScheduleBlock(
          blockType: "task", startTime: "09:00", endTime: "10:00",
          taskID: staleTask.id, title: staleTask.title)
      ],
      rationale: "Remote plan")
    let remoteCurrentFocus = try remoteRecord(
      service, kind: .currentFocus, entityID: focusDate)
    let unrelatedTask = try await service.createTask(
      title: "Unrelated local intent survives", notes: "")

    // Make the task's children and current-focus aggregate stale, already-sent
    // state. Keep the focus schedule and unrelated task as ordinary active local
    // intents, plus only the exact task identity as a remote-authoritative fence.
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
      let unrelatedPayload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.task, entityId: unrelatedTask.id)
      let unrelatedVersion = try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?",
          arguments: [unrelatedTask.id]))
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EntityName.task, entityId: unrelatedTask.id,
        payload: unrelatedPayload,
        context: OutboxWriteContext(
          version: unrelatedVersion, deviceId: "local-device",
          registerIntent: .task(.all)))
      let schedulePayload = try OutboxEnqueue.readEntityPayloadSnapshot(
        db, entityType: EntityName.focusSchedule, entityId: focusDate)
      let scheduleVersion = try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM focus_schedule WHERE date = ?",
          arguments: [focusDate]))
      try OutboxEnqueue.enqueuePayloadUpsert(
        db, entityType: EntityName.focusSchedule, entityId: focusDate,
        payload: schedulePayload,
        context: OutboxWriteContext(
          version: scheduleVersion, deviceId: "local-device"))
    }
    try armRemoteAuthoritativeFence(
      service, kind: .task, entityID: staleTask.id,
      registerIntent: .task(.all))

    let taskRecordName = SyncRecordName.opaque(
      entityType: EntityName.task, entityId: staleTask.id)
    let report = try applyPhysicalDeletion(
      service, recordNames: [taskRecordName])

    XCTAssertFalse(report.appliedEntityTypes.contains(.task))
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT title FROM tasks WHERE id = ?",
          arguments: [staleTask.id])
      },
      "Stale local fallback")
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*)
            FROM task_checklist_items
            WHERE task_id = ?
            """,
          arguments: [staleTask.id])
      },
      1, "single-record deletion must not cascade an independently synced child")
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM current_focus_items WHERE task_id = ?",
          arguments: [staleTask.id])
      },
      1, "single-record deletion must not mutate an aggregate projection")
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = ?",
          arguments: [staleTask.id])
      },
      1, "single-record deletion must not mutate a persisted schedule")
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.task, staleTask.id]) ?? -1
      },
      0)
    let session = try XCTUnwrap(try service.authoritativeSnapshotSession())
    XCTAssertEqual(session.phase, .preparing)
    XCTAssertEqual(
      try service.cloudInboundCompletenessState(boundary: try boundary()).pendingRecordCount,
      1, "the durable snapshot session must block a terminal inbound boundary")
    let unrelatedFence = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT disposition FROM sync_outbox
          WHERE entity_type = 'task' AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [unrelatedTask.id])
    }
    XCTAssertNotNil(unrelatedFence)
    XCTAssertNil(unrelatedFence?["disposition"] as String?)

    // Complete inventory, not the incremental slot deletion, now removes the
    // stale graph child-first. The unrelated active intent is replayed above the
    // remote snapshot and remains queued.
    try service.markAuthoritativeSnapshotReady(sessionToken: session.sessionToken)
    let finalized = try service.finalizeAuthoritativeSnapshotTerminalPage(
      records: [try inboxRecord(), remoteCurrentFocus],
      deletedRecordNames: [],
      sessionToken: session.sessionToken, boundary: try boundary(),
      traversalIdentifier: session.sessionToken,
      page: try CloudTraversalPageCommit(
        pageIndex: 0, continuationToken: Data([0x73]), moreComing: false,
        observation: try proof(
          try boundary(), traversalIdentifier: session.sessionToken)))
    XCTAssertTrue(finalized.changedEntityTypes.contains(.task))
    XCTAssertTrue(finalized.changedEntityTypes.contains(.taskChecklistItem))
    XCTAssertTrue(finalized.changedEntityTypes.contains(.currentFocus))
    XCTAssertTrue(finalized.changedEntityTypes.contains(.focusSchedule))
    XCTAssertNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [staleTask.id])
      })
    XCTAssertNotNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [unrelatedTask.id])
      })
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?",
          arguments: [focusDate])
      },
      0, "complete inventory must remove a proven-absent task soft reference")
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: [focusDate])
      },
      0, "complete inventory must remove a proven-absent task schedule block")
    let repairedAggregates = try service.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT entity_type, operation, version, payload
          FROM sync_outbox
          WHERE synced_at IS NULL AND disposition IS NULL
            AND entity_id = ?
            AND entity_type IN ('current_focus', 'focus_schedule')
          ORDER BY entity_type
          """,
        arguments: [focusDate])
    }
    XCTAssertEqual(repairedAggregates.count, 2)
    for row in repairedAggregates {
      XCTAssertEqual(row["operation"] as String, SyncNaming.opUpsert)
      let payload = try XCTUnwrap(JSONValue.parse(row["payload"] as String))
      XCTAssertFalse(
        String(describing: payload).contains(staleTask.id),
        "the convergence successor must not re-publish the absent task reference")
    }
    XCTAssertNil(try service.authoritativeSnapshotSession())
    XCTAssertEqual(
      try service.cloudInboundCompletenessState(boundary: try boundary()).pendingRecordCount,
      0)
  }

  func testCleanGraphRootPhysicalDeletionAlsoRequiresCompleteInventory() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Already synced root", notes: "")
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    let report = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(entityType: EntityName.task, entityId: task.id)
      ],
      traversalIdentifier: "clean-root-delete")

    XCTAssertFalse(report.appliedEntityTypes.contains(.task))
    XCTAssertNotNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [task.id])
      }, "incremental deletion must not cascade a relational root")
    XCTAssertEqual(try service.authoritativeSnapshotSession()?.phase, .preparing)
    XCTAssertEqual(
      try service.cloudInboundCompletenessState(boundary: try boundary()).pendingRecordCount,
      1)
  }

  func testCleanLeafPhysicalDeletionPrunesWithoutPriorFence() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Keep parent", notes: "")
    let withItem = try await service.addTaskChecklistItem(
      taskID: task.id, text: "Already synced leaf")
    let itemID = try XCTUnwrap(withItem.checklistItems.first?.id)
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    let report = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(
          entityType: EntityName.taskChecklistItem, entityId: itemID)
      ],
      traversalIdentifier: "clean-leaf-delete")

    XCTAssertTrue(report.appliedEntityTypes.contains(.taskChecklistItem))
    XCTAssertNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM task_checklist_items WHERE id = ?",
          arguments: [itemID])
      })
    XCTAssertNotNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [task.id])
      })
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testCleanAuditPhysicalDeletionPrunesAlreadySentRowWithoutSnapshot() async throws {
    let service = try makeService()
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: zone)
    let task = try await service.createTask(
      title: "Audit record already present in CloudKit", notes: "")
    let auditID = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db,
          sql: "SELECT id FROM ai_changelog WHERE entity_id = ? ORDER BY id LIMIT 1",
          arguments: [task.id]))
    }
    try service.write { db in
      // Model an already-confirmed audit upsert. There is no local intent left;
      // the exact CloudKit slot deletion is therefore authoritative.
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    let report = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(
          entityType: EntityName.aiChangelog, entityId: auditID)
      ],
      traversalIdentifier: "clean-audit-delete")

    XCTAssertTrue(report.appliedEntityTypes.contains(.aiChangelog))
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE id = ?",
          arguments: [auditID]),
        0)
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM ai_changelog_entities WHERE changelog_id = ?",
          arguments: [auditID]),
        0, "audit entity-id children must cascade with the authoritative prune")
    }
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testPendingAuditPhysicalDeletionKeepsAppendOnlyUpsertForRemoteRecreation() async throws {
    let service = try makeService()
    _ = try service.activateAuditRetentionAccount(
      accountIdentifier: account, zoneName: zone)
    let task = try await service.createTask(
      title: "Audit upsert still pending", notes: "")
    let before = try service.read { db -> (String, Int64, String, String, String, String?) in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT a.id, o.id AS outbox_id, o.operation, o.version, o.payload,
                   o.disposition
            FROM ai_changelog a
            JOIN sync_outbox o
              ON o.entity_type = ? AND o.entity_id = a.id AND o.synced_at IS NULL
            WHERE a.entity_id = ?
            ORDER BY a.id
            LIMIT 1
            """,
          arguments: [EntityName.aiChangelog, task.id]))
      return (
        row["id"], row["outbox_id"], row["operation"], row["version"],
        row["payload"], row["disposition"])
    }

    let report = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(
          entityType: EntityName.aiChangelog, entityId: before.0)
      ],
      traversalIdentifier: "pending-audit-delete")

    XCTAssertFalse(report.appliedEntityTypes.contains(.aiChangelog))
    let after = try service.read { db -> (Int64, String, String, String, String?)? in
      try Row.fetchOne(
        db,
        sql: """
          SELECT o.id, o.operation, o.version, o.payload, o.disposition
          FROM ai_changelog a
          JOIN sync_outbox o
            ON o.entity_type = ? AND o.entity_id = a.id AND o.synced_at IS NULL
          WHERE a.id = ?
          """,
        arguments: [EntityName.aiChangelog, before.0]
      ).map {
        ($0["id"], $0["operation"], $0["version"], $0["payload"], $0["disposition"])
      }
    }
    let pending = try XCTUnwrap(after)
    XCTAssertEqual(pending.0, before.1)
    XCTAssertEqual(pending.1, before.2)
    XCTAssertEqual(pending.2, before.3)
    XCTAssertEqual(pending.3, before.4)
    XCTAssertEqual(pending.4, before.5)
    XCTAssertEqual(pending.1, SyncNaming.opUpsert)
    XCTAssertNil(pending.4)
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testPendingLocalWriteRecreatesPhysicallyDeletedRoot() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Pending local root", notes: "")
    let oldVersion = try service.read { db in
      try XCTUnwrap(
        try String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id]))
    }

    let report = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(entityType: EntityName.task, entityId: task.id)
      ],
      traversalIdentifier: "pending-root-delete")

    XCTAssertTrue(report.appliedEntityTypes.contains(.task))
    XCTAssertNil(try service.authoritativeSnapshotSession())
    let state = try service.read { db in
      try Row.fetchOne(
        db,
        sql: """
          SELECT t.version, o.operation, o.version AS outbox_version,
                 o.disposition
          FROM tasks t
          JOIN sync_outbox o
            ON o.entity_type = 'task' AND o.entity_id = t.id
             AND o.synced_at IS NULL
          WHERE t.id = ?
          """,
        arguments: [task.id])
    }
    let row = try XCTUnwrap(state)
    let successor = try Hlc.parseCanonical(row["version"] as String)
    XCTAssertGreaterThan(successor, try Hlc.parseCanonical(oldVersion))
    XCTAssertEqual(row["operation"] as String, SyncNaming.opUpsert)
    XCTAssertEqual(row["outbox_version"] as String, successor.description)
    XCTAssertNil(row["disposition"] as String?)
  }

  func testPhysicallyDeletedPermanentRedirectTargetsAreReasserted() async throws {
    for kind in [
      EntityKind.tag, .habit, .memory, .habitReminderPolicy,
    ] {
      let service = try makeService()
      let target = try await seedPermanentRedirectTarget(service, kind: kind)

      let report = try applyPhysicalDeletion(
        service,
        recordNames: [
          SyncRecordName.opaque(
            entityType: kind.asString, entityId: target.targetID)
        ],
        traversalIdentifier: "redirect-target-\(kind.asString)")

      XCTAssertTrue(report.appliedEntityTypes.contains(kind), "kind=\(kind)")
      XCTAssertNil(try service.authoritativeSnapshotSession(), "kind=\(kind)")
      try service.read { db in
        let table = try XCTUnwrap(kind.tablePk?.table)
        let primaryKey = try XCTUnwrap(kind.tablePk?.pk)
        XCTAssertEqual(
          try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM \(table) WHERE \(primaryKey) = ?",
            arguments: [target.targetID]),
          1, "redirect target must remain live for kind=\(kind)")
        XCTAssertEqual(
          try String.fetchOne(
            db,
            sql: """
              SELECT target_id FROM sync_entity_redirects
              WHERE source_type = ? AND source_id = ?
              """,
            arguments: [kind.asString, target.sourceID]),
          target.targetID)
        let outbox = try XCTUnwrap(
          Row.fetchOne(
            db,
            sql: """
              SELECT operation, disposition
              FROM sync_outbox
              WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
              """,
            arguments: [kind.asString, target.targetID]))
        XCTAssertEqual(outbox["operation"] as String, SyncNaming.opUpsert)
        XCTAssertNil(outbox["disposition"] as String?)
      }
    }
  }

  func testRemoteAuthoritativeFutureFenceCannotPrunePermanentRedirectTarget() async throws {
    let service = try makeService()
    let target = try await seedPermanentRedirectTarget(service, kind: .memory)
    try armRemoteAuthoritativeFence(
      service, kind: .memory, entityID: target.targetID)

    let report = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(
          entityType: EntityName.memory, entityId: target.targetID)
      ],
      traversalIdentifier: "redirect-target-future-fence")

    XCTAssertTrue(report.appliedEntityTypes.contains(.memory))
    XCTAssertNil(try service.authoritativeSnapshotSession())
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM memories WHERE id = ?",
          arguments: [target.targetID]),
        1)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT target_id FROM sync_entity_redirects
            WHERE source_type = ? AND source_id = ?
            """,
          arguments: [EntityName.memory, target.sourceID]),
        target.targetID)
      let outbox = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT operation, disposition
            FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.memory, target.targetID]))
      XCTAssertEqual(outbox["operation"] as String, SyncNaming.opUpsert)
      XCTAssertNil(outbox["disposition"] as String?)
    }
  }

  func testTombstonedPermanentRedirectTargetsReassertOriginalDelete() async throws {
    for kind in [EntityKind.memory, .habit] {
      let service = try makeService()
      let target = try await seedPermanentRedirectTarget(service, kind: kind)
      switch kind {
      case .memory:
        let deleted = try await service.deleteMemory(key: "redirect-target-memory")
        XCTAssertTrue(deleted)
      case .habit:
        _ = try await service.deleteHabit(id: target.targetID)
      default:
        XCTFail("unexpected redirect target kind")
      }

      let originalTombstone = try service.read { db in
        try XCTUnwrap(
          Tombstone.getTombstone(
            db, entityType: kind.asString, entityId: target.targetID))
      }
      try armExistingDeleteAsRemoteAuthoritativeFence(
        service, kind: kind, entityID: target.targetID)

      let report = try applyPhysicalDeletion(
        service,
        recordNames: [
          SyncRecordName.opaque(
            entityType: kind.asString, entityId: target.targetID)
        ],
        traversalIdentifier: "tombstoned-redirect-target-\(kind.asString)")

      XCTAssertTrue(report.appliedEntityTypes.contains(kind), "kind=\(kind)")
      XCTAssertNil(try service.authoritativeSnapshotSession(), "kind=\(kind)")
      try service.read { db in
        let table = try XCTUnwrap(kind.tablePk?.table)
        let primaryKey = try XCTUnwrap(kind.tablePk?.pk)
        XCTAssertEqual(
          try Int.fetchOne(
            db, sql: "SELECT COUNT(*) FROM \(table) WHERE \(primaryKey) = ?",
            arguments: [target.targetID]),
          0, "terminal redirect target must remain deleted for kind=\(kind)")
        XCTAssertEqual(
          try Tombstone.getTombstone(
            db, entityType: kind.asString, entityId: target.targetID),
          originalTombstone,
          "reassertion must preserve the original death ledger for kind=\(kind)")
        XCTAssertEqual(
          try String.fetchOne(
            db,
            sql: """
              SELECT target_id FROM sync_entity_redirects
              WHERE source_type = ? AND source_id = ?
              """,
            arguments: [kind.asString, target.sourceID]),
          target.targetID)
        let outbox = try XCTUnwrap(
          Row.fetchOne(
            db,
            sql: """
              SELECT operation, version, disposition, retry_count
              FROM sync_outbox
              WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
              """,
            arguments: [kind.asString, target.targetID]))
        XCTAssertEqual(outbox["operation"] as String, SyncNaming.opDelete)
        XCTAssertEqual(outbox["version"] as String, originalTombstone.version)
        XCTAssertNil(outbox["disposition"] as String?)
        XCTAssertLessThan(outbox["retry_count"] as Int64, Outbox.maxRetries)
      }
    }
  }

  func testCleanConfirmedPermanentRedirectTargetTombstoneReassertsOriginalDelete() async throws {
    let service = try makeService()
    let target = try await seedPermanentRedirectTarget(service, kind: .memory)
    let deleted = try await service.deleteMemory(key: "redirect-target-memory")
    XCTAssertTrue(deleted)

    let originalTombstone = try service.read { db in
      try XCTUnwrap(
        Tombstone.getTombstone(
          db, entityType: EntityName.memory, entityId: target.targetID))
    }
    let confirmedAt = "2026-07-18T00:00:00.000Z"
    try service.write { db in
      let outboxID = try XCTUnwrap(
        Int64.fetchOne(
          db,
          sql: """
            SELECT id FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND operation = ?
              AND synced_at IS NULL AND disposition IS NULL
            """,
          arguments: [EntityName.memory, target.targetID, SyncNaming.opDelete]))
      try Outbox.markManySynced(db, outboxIds: [outboxID], syncedAt: confirmedAt)
      XCTAssertTrue(
        try Tombstone.confirmCloudPresence(
          db,
          confirmation: Tombstone.CloudConfirmation(
            entityType: EntityName.memory, entityId: target.targetID,
            version: originalTombstone.version, confirmedAt: confirmedAt)))
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.memory, target.targetID]),
        0, "the regression starts after the original Delete was cleanly confirmed")
    }

    let report = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(
          entityType: EntityName.memory, entityId: target.targetID)
      ],
      traversalIdentifier: "clean-tombstoned-redirect-target")

    XCTAssertTrue(report.appliedEntityTypes.contains(.memory))
    XCTAssertNil(try service.authoritativeSnapshotSession())
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM memories WHERE id = ?",
          arguments: [target.targetID]),
        0)
      let retainedTombstone = try XCTUnwrap(
        Tombstone.getTombstone(
          db, entityType: EntityName.memory, entityId: target.targetID))
      XCTAssertEqual(retainedTombstone.entityType, originalTombstone.entityType)
      XCTAssertEqual(retainedTombstone.entityId, originalTombstone.entityId)
      XCTAssertEqual(retainedTombstone.version, originalTombstone.version)
      XCTAssertEqual(retainedTombstone.deletedAt, originalTombstone.deletedAt)
      XCTAssertEqual(retainedTombstone.cloudConfirmedAt, confirmedAt)
      let outbox = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT operation, version, disposition, retry_count
            FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.memory, target.targetID]))
      XCTAssertEqual(outbox["operation"] as String, SyncNaming.opDelete)
      XCTAssertEqual(outbox["version"] as String, originalTombstone.version)
      XCTAssertNil(outbox["disposition"] as String?)
      XCTAssertLessThan(outbox["retry_count"] as Int64, Outbox.maxRetries)
    }
  }

  func testMissingPermanentRedirectTargetStateFailsClosed() async throws {
    let service = try makeService()
    let target = try await seedPermanentRedirectTarget(service, kind: .memory)
    try armRemoteAuthoritativeFence(
      service, kind: .memory, entityID: target.targetID)
    try service.write { db in
      try db.execute(
        sql: "DELETE FROM memories WHERE id = ?", arguments: [target.targetID])
      try db.execute(
        sql: "DELETE FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.memory, target.targetID])
    }

    let recordName = SyncRecordName.opaque(
      entityType: EntityName.memory, entityId: target.targetID)
    XCTAssertThrowsError(
      try applyPhysicalDeletion(
        service, recordNames: [recordName],
        traversalIdentifier: "missing-redirect-target-state")
    ) { error in
      XCTAssertTrue(
        String(describing: error).contains("neither a live row nor a tombstone"))
    }

    let account = self.account
    let zone = self.zone
    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
              AND disposition = ?
            """,
          arguments: [
            EntityName.memory, target.targetID,
            Outbox.Disposition.futureRecordHold.rawValue,
          ]),
        1, "failed reassertion must roll the original fence back")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT next_page_index FROM sync_cloudkit_traversal_progress
            WHERE account_identifier = ? AND zone_identifier = ?
              AND generation = 7
              AND traversal_identifier = 'missing-redirect-target-state'
            """,
          arguments: [account, zone]),
        0, "failed reassertion must not commit the traversal page")
    }
  }

  func testPhysicalDeletionLocalIntentReassertionPreservesFuturePayloadShadow() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Shadow-preserving task", notes: "")
    let futureSchema = Int(LorvexVersion.payloadSchemaVersion) + 1
    let remoteFloor = "1800000000000_0000_dec0000300000003"
    try service.write { db in
      let version = try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id]))
      try PayloadShadow.upsertShadow(
        db, entityType: EntityName.task, entityID: task.id,
        baseVersion: version, payloadSchemaVersion: futureSchema,
        rawPayloadJSON: #"{"future_sync_field":"preserve-me"}"#,
        sourceDeviceID: "future-device")
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
          EntityName.task, task.id,
        ])
      XCTAssertEqual(db.changesCount, 1)
    }

    _ = try applyPhysicalDeletion(
      service,
      recordNames: [
        SyncRecordName.opaque(entityType: EntityName.task, entityId: task.id)
      ],
      traversalIdentifier: "local-shadow-reassert")

    try service.read { db in
      let outbox = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT payload, payload_schema_version, disposition
            FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
            """,
          arguments: [EntityName.task, task.id]))
      let payloadValue = try XCTUnwrap(JSONValue.parse(outbox["payload"] as String))
      guard case .object(let payload) = payloadValue else {
        return XCTFail("reasserted outbox payload must be an object")
      }
      XCTAssertEqual(payload["future_sync_field"], JSONValue.string("preserve-me"))
      XCTAssertEqual(outbox["payload_schema_version"] as Int64, Int64(futureSchema))
      XCTAssertNil(outbox["disposition"] as String?)
      XCTAssertNotNil(
        try PayloadShadow.getShadow(
          db, entityType: EntityName.task, entityID: task.id))
    }
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testSafeLeafPhysicalDeletionPrunesExactlyWithoutSnapshot() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Keep parent", notes: "")
    let withItem = try await service.addTaskChecklistItem(
      taskID: task.id, text: "Remote leaf")
    let itemID = try XCTUnwrap(withItem.checklistItems.first?.id)
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }
    try armRemoteAuthoritativeFence(
      service, kind: .taskChecklistItem, entityID: itemID)
    let recordName = SyncRecordName.opaque(
      entityType: EntityName.taskChecklistItem, entityId: itemID)

    let report = try applyPhysicalDeletion(
      service, recordNames: [recordName], traversalIdentifier: "leaf-delete")

    XCTAssertTrue(report.appliedEntityTypes.contains(.taskChecklistItem))
    XCTAssertNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM task_checklist_items WHERE id = ?",
          arguments: [itemID])
      })
    XCTAssertNotNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM tasks WHERE id = ?", arguments: [task.id])
      })
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testPermanentInboxAndCutoverPhysicalDeletionReassertsUpserts() throws {
    let service = try makeService()
    let rootID = "01966a3f-7c8b-7d4e-8f3a-00000000c001"
    let cutoverID = CalendarSeriesCutoverID.make(
      lineageRootId: rootID, cutoverDate: "2026-07-17")
    _ = try service.write { db in
      try CalendarSeriesCutoverRepo.upsert(
        db,
        row: CalendarSeriesCutoverRow(
          id: cutoverID, lineageRootId: rootID, cutoverDate: "2026-07-17",
          state: .deleted, version: Hlc.testVersion,
          createdAt: "2026-07-17T00:00:00.000Z",
          updatedAt: "2026-07-17T00:00:00.000Z"))
      try db.execute(sql: "DELETE FROM sync_outbox")
    }
    let inboxName = SyncRecordName.opaque(
      entityType: EntityName.list, entityId: "inbox")
    let cutoverName = SyncRecordName.opaque(
      entityType: EntityName.calendarSeriesCutover, entityId: cutoverID)

    let report = try applyPhysicalDeletion(
      service, recordNames: [inboxName, cutoverName],
      traversalIdentifier: "invariant-delete")

    XCTAssertTrue(report.appliedEntityTypes.contains(.list))
    XCTAssertTrue(report.appliedEntityTypes.contains(.calendarSeriesCutover))
    XCTAssertNotNil(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT id FROM lists WHERE id = 'inbox'")
      })
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT state FROM calendar_series_cutovers WHERE id = ?",
          arguments: [cutoverID])
      },
      "deleted")
    let activeKinds = try service.read { db in
      try String.fetchAll(
        db,
        sql: """
          SELECT entity_type FROM sync_outbox
          WHERE synced_at IS NULL AND disposition IS NULL
            AND ((entity_type = 'list' AND entity_id = 'inbox')
              OR (entity_type = 'calendar_series_cutover' AND entity_id = ?))
          ORDER BY entity_type
          """,
        arguments: [cutoverID])
    }
    XCTAssertEqual(activeKinds, [EntityName.calendarSeriesCutover, EntityName.list])
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testPermanentEntityRedirectPhysicalDeletionReassertsSameAlias() throws {
    let service = try makeService()
    let redirect = try seedRemoteAuthoritativeRedirectFence(service)
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }
    let recordName = SyncRecordName.opaque(
      entityType: EntityName.entityRedirect, entityId: redirect.wireID)

    let report = try applyPhysicalDeletion(
      service, recordNames: [recordName], traversalIdentifier: "redirect-delete")

    XCTAssertFalse(report.appliedEntityTypes.contains(.entityRedirect))
    let state = try service.read { db -> Row? in
      try Row.fetchOne(
        db,
        sql: """
          SELECT r.target_id, r.version, o.operation, o.version AS outbox_version,
                 o.disposition
          FROM sync_entity_redirects r
          JOIN sync_outbox o
            ON o.entity_type = ? AND o.entity_id = ? AND o.synced_at IS NULL
          WHERE r.source_type = ? AND r.source_id = ?
          """,
        arguments: [
          EntityName.entityRedirect, redirect.wireID,
          EntityName.tag, redirect.sourceID,
        ])
    }
    let row = try XCTUnwrap(state)
    XCTAssertEqual(row["target_id"] as String, redirect.targetID)
    XCTAssertEqual(row["operation"] as String, SyncNaming.opUpsert)
    XCTAssertEqual(row["outbox_version"] as String, row["version"] as String)
    XCTAssertNil(row["disposition"] as String?)
    XCTAssertNil(try service.authoritativeSnapshotSession())

    let redirectVersion = try Hlc.parseCanonical(row["version"] as String)
    let laterSourceVersion = try Hlc(
      physicalMs: redirectVersion.physicalMs + 1, counter: 0,
      deviceSuffix: "dec0000400000004")
    let remap = try service.applyInbound(
      [
        try tagUpsert(
          id: redirect.sourceID, name: "Renamed after stale edit",
          version: laterSourceVersion.description)
      ], undecodable: 0)
    XCTAssertEqual(remap.remapped, 1)
    try service.read { db in
      XCTAssertNil(
        try String.fetchOne(
          db, sql: "SELECT id FROM tags WHERE id = ?",
          arguments: [redirect.sourceID]))
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT display_name FROM tags WHERE id = ?",
          arguments: [redirect.targetID]),
        "Renamed after stale edit")
    }
  }

  func testPermanentEntityRedirectDeletionAcceptsExactPendingReassertion() throws {
    let service = try makeService()
    let redirect = try seedRemoteAuthoritativeRedirectFence(service)
    try service.write { db in
      try db.execute(
        sql: """
          UPDATE sync_outbox
          SET retry_count = 0, consecutive_error_count = 0,
              last_error = NULL, disposition = NULL,
              next_retry_at = NULL, future_record_version = NULL,
              future_record_resolution = NULL
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [EntityName.entityRedirect, redirect.wireID])
      XCTAssertEqual(db.changesCount, 1)
    }
    let recordName = SyncRecordName.opaque(
      entityType: EntityName.entityRedirect, entityId: redirect.wireID)

    _ = try applyPhysicalDeletion(
      service, recordNames: [recordName], traversalIdentifier: "redirect-pending")

    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
              AND disposition IS NULL AND retry_count < ?
            """,
          arguments: [
            EntityName.entityRedirect, redirect.wireID, Outbox.maxRetries,
          ]),
        1)
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT target_id FROM sync_entity_redirects
            WHERE source_type = ? AND source_id = ?
            """,
          arguments: [EntityName.tag, redirect.sourceID]),
        redirect.targetID)
    }
    XCTAssertNil(try service.authoritativeSnapshotSession())
  }

  func testEntityRedirectReassertionFailureRollsBackFenceAndTraversalPage() throws {
    let service = try makeService()
    let redirect = try seedRemoteAuthoritativeRedirectFence(service)
    let account = self.account
    let zone = self.zone
    try service.write { db in
      try db.execute(
        sql: """
          CREATE TEMP TRIGGER reject_redirect_reassert
          BEFORE INSERT ON sync_outbox
          WHEN NEW.entity_type = 'entity_redirect'
          BEGIN
            SELECT RAISE(ABORT, 'injected redirect reassert failure');
          END
          """)
    }
    let recordName = SyncRecordName.opaque(
      entityType: EntityName.entityRedirect, entityId: redirect.wireID)

    XCTAssertThrowsError(
      try applyPhysicalDeletion(
        service, recordNames: [recordName], traversalIdentifier: "redirect-rollback"))

    try service.read { db in
      XCTAssertEqual(
        try String.fetchOne(
          db,
          sql: """
            SELECT target_id FROM sync_entity_redirects
            WHERE source_type = ? AND source_id = ?
            """,
          arguments: [EntityName.tag, redirect.sourceID]),
        redirect.targetID)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
              AND disposition = ?
            """,
          arguments: [
            EntityName.entityRedirect, redirect.wireID,
            Outbox.Disposition.futureRecordHold.rawValue,
          ]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: """
            SELECT next_page_index FROM sync_cloudkit_traversal_progress
            WHERE account_identifier = ? AND zone_identifier = ?
              AND generation = 7 AND traversal_identifier = 'redirect-rollback'
            """,
          arguments: [account, zone]),
        0)
    }
  }
}
