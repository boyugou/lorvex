import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class NativeTaskGraphImportTests: XCTestCase {
  private static let v1 = "1700000000000_0000_1111111111111111"
  private static let v2 = "1700000000001_0000_2222222222222222"
  private static let v3 = "1700000000002_0000_3333333333333333"
  private static let now = "2026-01-01T00:00:00.000Z"
  private static let recurrence = "{\"FREQ\":\"DAILY\",\"INTERVAL\":1}"
  private static let listID = "11111111-1111-4111-8111-111111111111"
  private static let tagID = "22222222-2222-4222-8222-222222222222"

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    return SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL))
  }

  private func clock(_ raw: String) throws -> Hlc {
    try Hlc.parseCanonical(raw)
  }

  private func seedRoots(
    _ service: SwiftLorvexCoreService,
    listID: String = NativeTaskGraphImportTests.listID,
    tagID: String? = NativeTaskGraphImportTests.tagID
  ) throws {
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at)
          VALUES (?, 'Imported root', ?, ?, ?)
          """,
        arguments: [listID, Self.v1, Self.now, Self.now])
      if let tagID {
        try db.execute(
          sql: """
            INSERT INTO tags (
              id, display_name, lookup_key, version, created_at, updated_at
            ) VALUES (?, 'Focus', 'focus', ?, ?, ?)
            """,
          arguments: [tagID, Self.v1, Self.now, Self.now])
      }
    }
  }

  private func task(
    id: String,
    title: String? = nil,
    status: String = "open",
    listID: String = NativeTaskGraphImportTests.listID,
    dueDate: String? = nil,
    recurrence: String? = nil,
    spawnedFrom: String? = nil,
    spawnedFromVersion: Hlc? = nil,
    groupID: String? = nil,
    occurrenceDate: String? = nil,
    contentVersion: Hlc? = nil,
    scheduleVersion: Hlc? = nil,
    lifecycleVersion: Hlc? = nil,
    archiveVersion: Hlc? = nil,
    rollover: String = "none",
    successorID: String? = nil,
    version: Hlc? = nil,
    completedAt: String? = nil
  ) throws -> NativeTaskSnapshot {
    let base = try clock(Self.v1)
    let rowVersion = version ?? base
    let instanceKey: String?
    if spawnedFrom != nil, let groupID, let occurrenceDate {
      instanceKey = Recurrence.generateInstanceKey(
        recurrenceGroupID: groupID, canonicalOccurrenceDate: occurrenceDate)
    } else {
      instanceKey = nil
    }
    return NativeTaskSnapshot(
      id: id,
      title: title ?? id,
      body: "body-\(id)",
      rawInput: "raw-\(id)",
      aiNotes: "ai-\(id)",
      status: status,
      listID: listID,
      priority: 2,
      dueDate: dueDate,
      estimatedMinutes: 30,
      recurrence: recurrence,
      spawnedFrom: spawnedFrom,
      spawnedFromVersion: spawnedFromVersion,
      recurrenceGroupID: groupID,
      recurrenceInstanceKey: instanceKey,
      canonicalOccurrenceDate: occurrenceDate,
      contentVersion: contentVersion ?? rowVersion,
      scheduleVersion: scheduleVersion ?? rowVersion,
      lifecycleVersion: lifecycleVersion ?? rowVersion,
      archiveVersion: archiveVersion ?? rowVersion,
      recurrenceRolloverState: rollover,
      recurrenceSuccessorID: successorID,
      version: rowVersion,
      createdAt: Self.now,
      updatedAt: Self.now,
      completedAt: completedAt,
      lastDeferredAt: nil,
      lastDeferReason: nil,
      plannedDate: dueDate,
      availableFrom: nil,
      deferCount: 0,
      archivedAt: nil)
  }

  private func graph(
    tasks: [NativeTaskSnapshot],
    recurrenceExceptions: [NativeTaskRecurrenceExceptionSnapshot] = [],
    tagEdges: [NativeTaskTagEdgeSnapshot] = [],
    dependencyEdges: [NativeTaskDependencyEdgeSnapshot] = [],
    checklistItems: [NativeTaskChecklistItemSnapshot] = [],
    reminders: [NativeTaskReminderSnapshot] = [],
    tombstones: [NativeTaskTombstoneSnapshot] = [],
    payloadShadows: [NativeTaskPayloadShadowSnapshot] = []
  ) -> NativeTaskGraphSnapshot {
    NativeTaskGraphSnapshot(
      tasks: tasks,
      recurrenceExceptions: recurrenceExceptions,
      tagEdges: tagEdges,
      dependencyEdges: dependencyEdges,
      checklistItems: checklistItems,
      reminders: reminders,
      tombstones: tombstones,
      payloadShadows: payloadShadows)
  }

  private func portableTask(
    from native: NativeTaskSnapshot, tags: [String]? = nil
  ) -> ExportTask {
    let priority: String
    switch native.priority {
    case 1: priority = "P1"
    case 3: priority = "P3"
    default: priority = "P2"
    }
    return ExportTask(
      id: native.id, title: native.title, notes: native.body, priority: priority,
      status: native.status, dueDate: native.dueDate, plannedDate: native.plannedDate,
      availableFrom: native.availableFrom, estimatedMinutes: native.estimatedMinutes,
      tags: tags, rawInput: native.rawInput, listID: native.listID,
      aiNotes: native.aiNotes, deferCount: native.deferCount,
      lastDeferReason: native.lastDeferReason, lastDeferredAt: native.lastDeferredAt,
      completedAt: native.completedAt, createdAt: native.createdAt,
      updatedAt: native.updatedAt, archivedAt: native.archivedAt)
  }

  func testExactRestorePreservesCompletedRecurringChainDependencyAndOriginalClocks()
    async throws
  {
    let service = try makeService()
    try seedRoots(service)
    let v1 = try clock(Self.v1)
    let v2 = try clock(Self.v2)
    let groupID = "99999999-9999-4999-8999-999999999999"
    let parentID = "33333333-3333-4333-8333-333333333333"
    let blockerID = "44444444-4444-4444-8444-444444444444"
    let childID = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentID, recurrenceGroupId: groupID)
    let parent = try task(
      id: parentID,
      status: "completed",
      dueDate: "2026-01-31",
      recurrence: Self.recurrence,
      groupID: groupID,
      occurrenceDate: "2026-01-31",
      contentVersion: v1,
      scheduleVersion: v1,
      lifecycleVersion: v2,
      archiveVersion: v1,
      rollover: "authorized",
      successorID: childID,
      version: v2,
      completedAt: Self.now)
    let child = try task(
      id: childID,
      status: "in_progress",
      dueDate: "2026-02-01",
      recurrence: Self.recurrence,
      spawnedFrom: parentID,
      spawnedFromVersion: v2,
      groupID: groupID,
      occurrenceDate: "2026-02-01",
      version: v2)
    let blocker = try task(
      id: blockerID, status: "completed", completedAt: Self.now)
    let snapshot = graph(
      tasks: [parent, child, blocker],
      recurrenceExceptions: [
        NativeTaskRecurrenceExceptionSnapshot(
          taskID: childID, exceptionDate: "2026-02-03")
      ],
      tagEdges: [
        NativeTaskTagEdgeSnapshot(
          taskID: childID, tagID: Self.tagID, version: v2, createdAt: Self.now)
      ],
      dependencyEdges: [
        NativeTaskDependencyEdgeSnapshot(
          taskID: childID, dependsOnTaskID: blockerID, version: v2,
          createdAt: Self.now)
      ],
      checklistItems: [
        NativeTaskChecklistItemSnapshot(
          id: "55555555-5555-4555-8555-555555555555", taskID: childID,
          position: 0, text: "Preserve me",
          completedAt: Self.now, version: v2, createdAt: Self.now,
          updatedAt: Self.now)
      ],
      reminders: [
        NativeTaskReminderSnapshot(
          id: "66666666-6666-4666-8666-666666666666", taskID: childID,
          reminderAt: "2026-02-01T09:00:00.000Z", dismissedAt: nil,
          cancelledAt: nil, version: v2, createdAt: Self.now,
          originalLocalTime: "09:00", originalTimeZone: "America/Los_Angeles")
      ])

    let disposition = try await service.importNativeTaskGraphIfFresh(snapshot)
    XCTAssertEqual(disposition, .imported(taskCount: 3))

    let parentState = try service.read { db -> (String, String, String?, String) in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT status, recurrence_rollover_state, recurrence_successor_id,
                   lifecycle_version
            FROM tasks WHERE id = ?
            """,
          arguments: [parentID]))
      return (
        row["status"], row["recurrence_rollover_state"],
        row["recurrence_successor_id"], row["lifecycle_version"]
      )
    }
    XCTAssertEqual(parentState.0, "completed")
    XCTAssertEqual(parentState.1, "authorized")
    XCTAssertEqual(parentState.2, childID)
    XCTAssertEqual(parentState.3, Self.v2)

    let childState = try service.read { db -> (String, String?, String?, String) in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT status, spawned_from, spawned_from_version, version
            FROM tasks WHERE id = ?
            """,
          arguments: [childID]))
      return (
        row["status"], row["spawned_from"], row["spawned_from_version"],
        row["version"]
      )
    }
    XCTAssertEqual(childState.0, "in_progress")
    XCTAssertEqual(childState.1, parentID)
    XCTAssertEqual(childState.2, Self.v2)
    XCTAssertEqual(childState.3, Self.v2)
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM task_dependencies
            WHERE task_id = ? AND depends_on_task_id = ?
            """,
          arguments: [childID, blockerID])
      },
      1)
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM task_recurrence_exceptions
            WHERE task_id = ? AND exception_date = '2026-02-03'
            """,
          arguments: [childID])
      },
      1)

    let taskOutbox = try service.read { db -> [(String, String, Int64)] in
      try Row.fetchAll(
        db,
        sql: """
          SELECT entity_id, version, register_intent FROM sync_outbox
          WHERE entity_type = ? ORDER BY entity_id
          """,
        arguments: [EntityName.task]
      ).map { ($0["entity_id"], $0["version"], $0["register_intent"]) }
    }
    XCTAssertEqual(taskOutbox.count, 3)
    XCTAssertEqual(taskOutbox.first { $0.0 == parentID }?.1, Self.v2)
    XCTAssertEqual(taskOutbox.first { $0.0 == childID }?.1, Self.v2)
    XCTAssertEqual(taskOutbox.first { $0.0 == blockerID }?.1, Self.v1)
    XCTAssertTrue(taskOutbox.allSatisfy { $0.2 == TaskRegisterIntent.all.rawValue })
    for (entityType, expectedVersion) in [
      (EdgeName.taskTag, Self.v2),
      (EdgeName.taskDependency, Self.v2),
      (EntityName.taskChecklistItem, Self.v2),
      (EntityName.taskReminder, Self.v2),
    ] {
      XCTAssertEqual(
        try service.read { db in
          try String.fetchOne(
            db,
            sql: "SELECT version FROM sync_outbox WHERE entity_type = ?",
            arguments: [entityType])
        },
        expectedVersion)
    }
    let changelogOutboxVersion = try XCTUnwrap(
      service.read { db in
        try String.fetchOne(
          db,
          sql: "SELECT version FROM sync_outbox WHERE entity_type = ?",
          arguments: [EntityName.aiChangelog])
      })
    XCTAssertGreaterThan(try clock(changelogOutboxVersion), v2)
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT initiated_by FROM ai_changelog
            WHERE operation = 'import_native_task_graph'
            """)
      },
      SwiftLorvexCoreService.ChangelogInitiator.importAttribution)
  }

  func testExactRestoreReemitsDeletionHistoryAndOpaqueFutureTaskFields() async throws {
    let service = try makeService()
    try seedRoots(service)
    let v1 = try clock(Self.v1)
    let v2 = try clock(Self.v2)
    let liveTaskID = "12121212-1212-4212-8212-121212121212"
    let deletedTaskID = "13131313-1313-4313-8313-131313131313"
    let deletedChecklistID = "14141414-1414-4414-8414-141414141414"
    let deletedReminderID = "15151515-1515-4515-8515-151515151515"
    let deletedEventID = "16161616-1616-4616-8616-161616161616"
    let deletedAt = "2025-12-31T00:00:00.000Z"
    let tombstones = [
      NativeTaskTombstoneSnapshot(
        entityType: .task, entityID: deletedTaskID, version: v2,
        deletedAt: deletedAt),
      NativeTaskTombstoneSnapshot(
        entityType: .taskChecklistItem, entityID: deletedChecklistID,
        version: v2, deletedAt: deletedAt),
      NativeTaskTombstoneSnapshot(
        entityType: .taskReminder, entityID: deletedReminderID,
        version: v2, deletedAt: deletedAt),
      NativeTaskTombstoneSnapshot(
        entityType: .taskTag, entityID: "\(deletedTaskID):\(Self.tagID)",
        version: v2, deletedAt: deletedAt),
      NativeTaskTombstoneSnapshot(
        entityType: .taskDependency, entityID: "\(deletedTaskID):\(liveTaskID)",
        version: v2, deletedAt: deletedAt),
      NativeTaskTombstoneSnapshot(
        entityType: .taskCalendarEventLink,
        entityID: "\(deletedTaskID):\(deletedEventID)", version: v2,
        deletedAt: deletedAt),
    ]
    let futureJSON = "{\"future_user_field\":{\"value\":\"preserve me\"}}"
    let snapshot = graph(
      tasks: [try task(id: liveTaskID, version: v1)],
      tombstones: tombstones,
      payloadShadows: [
        NativeTaskPayloadShadowSnapshot(
          entityType: .task, entityID: liveTaskID, baseVersion: v1,
          payloadSchemaVersion: 2, rawPayloadJSON: futureJSON,
          sourceDeviceID: "future-peer", updatedAt: Self.now)
      ])

    let disposition = try await service.importNativeTaskGraphIfFresh(snapshot)
    XCTAssertEqual(disposition, .imported(taskCount: 1))

    let restoredDeletes = try service.read { db -> [(String, String, String, String?)] in
      try Row.fetchAll(
        db,
        sql: """
          SELECT entity_type, entity_id, version, cloud_confirmed_at
          FROM sync_tombstones ORDER BY entity_type, entity_id
          """
      ).map { ($0["entity_type"], $0["entity_id"], $0["version"], $0["cloud_confirmed_at"]) }
    }
    XCTAssertEqual(restoredDeletes.count, tombstones.count)
    XCTAssertTrue(restoredDeletes.allSatisfy { $0.2 == Self.v2 && $0.3 == nil })
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_tombstones
            WHERE deleted_at = ?
            """,
          arguments: [deletedAt])
      },
      tombstones.count)
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM sync_outbox
            WHERE operation = 'delete' AND version = ?
            """,
          arguments: [Self.v2])
      },
      tombstones.count)
    let auditVersion = try XCTUnwrap(
      service.read { db in
        try String.fetchOne(
          db,
          sql: """
            SELECT version FROM sync_outbox
            WHERE entity_type = ?
            """,
          arguments: [EntityName.aiChangelog])
      })
    XCTAssertGreaterThan(try clock(auditVersion), v2)

    let shadowState = try service.read { db -> (String, Int, String, String, String) in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT base_version, payload_schema_version, raw_payload_json,
                   source_device_id, updated_at
            FROM sync_payload_shadow
            WHERE entity_type = ? AND entity_id = ?
            """,
          arguments: [EntityName.task, liveTaskID]))
      return (
        row["base_version"], row["payload_schema_version"], row["raw_payload_json"],
        row["source_device_id"], row["updated_at"])
    }
    XCTAssertEqual(shadowState.0, Self.v1)
    XCTAssertEqual(shadowState.1, 2)
    XCTAssertEqual(shadowState.2, futureJSON)
    XCTAssertEqual(shadowState.3, "future-peer")
    XCTAssertEqual(shadowState.4, Self.now)
    let liveOutbox = try service.read { db -> (Int, String) in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT payload_schema_version, payload FROM sync_outbox
            WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'
            """,
          arguments: [EntityName.task, liveTaskID]))
      return (row["payload_schema_version"], row["payload"])
    }
    XCTAssertEqual(liveOutbox.0, 2)
    guard case .object(let emitted)? = JSONValue.parse(liveOutbox.1) else {
      return XCTFail("restored task outbox payload must remain a JSON object")
    }
    XCTAssertEqual(
      emitted["future_user_field"],
      .object(["value": .string("preserve me")]))

    let stalePayload = try canonicalizeJSON(
      .object([
        "id": .string(deletedChecklistID),
        "task_id": .string(liveTaskID),
        "position": .int(0),
        "text": .string("stale child"),
        "completed_at": .null,
        "version": .string(Self.v1),
        "created_at": .string(Self.now),
        "updated_at": .string(Self.now),
      ]))
    let staleResult = try service.write { db in
      try Apply.applyEnvelope(
        db,
        registry: EntityApplierRegistry(
          appliers: EntityApplierRegistry.defaultEntityAppliers()),
        envelope: SyncEnvelope(
          entityType: .taskChecklistItem,
          entityId: deletedChecklistID,
          operation: .upsert,
          version: v1,
          payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
          payload: stalePayload,
          deviceId: "stale-peer"))
    }
    guard case .skipped = staleResult else {
      return XCTFail("the restored tombstone must beat a stale child upsert")
    }
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM task_checklist_items WHERE id = ?",
          arguments: [deletedChecklistID])
      },
      0,
      "a stale child upsert must not resurrect through an exact restore")
  }

  func testExactRestorePreservesRevokedCancelledSuccessorChain() async throws {
    let service = try makeService()
    try seedRoots(service, tagID: nil)
    let v2 = try clock(Self.v2)
    let v3 = try clock(Self.v3)
    let groupID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let parentID = "77777777-7777-4777-8777-777777777777"
    let childID = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentID, recurrenceGroupId: groupID)
    let parent = try task(
      id: parentID,
      status: "in_progress",
      dueDate: "2026-03-01",
      recurrence: Self.recurrence,
      groupID: groupID,
      occurrenceDate: "2026-03-01",
      lifecycleVersion: v3,
      rollover: "revoked",
      successorID: childID,
      version: v3)
    let child = try task(
      id: childID,
      status: "cancelled",
      dueDate: "2026-03-02",
      recurrence: Self.recurrence,
      spawnedFrom: parentID,
      spawnedFromVersion: v2,
      groupID: groupID,
      occurrenceDate: "2026-03-02",
      rollover: "ended",
      version: v2)

    let disposition = try await service.importNativeTaskGraphIfFresh(
      graph(tasks: [parent, child]))
    XCTAssertEqual(disposition, .imported(taskCount: 2))
    let restored = try service.read { db -> (String, String, String, String?) in
      let parentRow = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT status, recurrence_rollover_state FROM tasks WHERE id = ?
            """,
          arguments: [parentID]))
      let childRow = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT status, spawned_from_version FROM tasks WHERE id = ?
            """,
          arguments: [childID]))
      return (
        parentRow["status"], parentRow["recurrence_rollover_state"],
        childRow["status"], childRow["spawned_from_version"]
      )
    }
    XCTAssertEqual(restored.0, "in_progress")
    XCTAssertEqual(restored.1, "revoked")
    XCTAssertEqual(restored.2, "cancelled")
    XCTAssertEqual(restored.3, Self.v2)
  }

  func testInvalidGraphFailsBeforeMaterializationAndRollsBackEverything() async throws {
    let service = try makeService()
    try seedRoots(service, tagID: nil)
    let oneID = "88888888-8888-4888-8888-888888888888"
    let one = try task(id: oneID)
    let invalid = graph(
      tasks: [one],
      dependencyEdges: [
        NativeTaskDependencyEdgeSnapshot(
          taskID: oneID, dependsOnTaskID: oneID, version: try clock(Self.v1),
          createdAt: Self.now)
      ])

    do {
      _ = try await service.importNativeTaskGraphIfFresh(invalid)
      XCTFail("A self dependency must reject the complete native restore")
    } catch let error as NativeTaskGraphImportError {
      XCTAssertTrue(error.localizedDescription.contains("depend on itself"))
    }
    let counts = try service.read { db -> (Int, Int, Int) in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1
      )
    }
    XCTAssertEqual(counts.0, 0)
    XCTAssertEqual(counts.1, 0)
    XCTAssertEqual(counts.2, 0)
  }

  func testNonFreshDomainUsesExistingPortableImportPath() async throws {
    let service = try makeService()
    _ = try await service.createTask(title: "Already here", notes: "")
    let importedID = UUID().uuidString.lowercased()
    let native = try task(id: importedID, title: "Shared title", listID: "inbox")
    let portable = portableTask(from: native)
    let payload = LorvexDataExportPayload(
      tasks: [portable], nativeTaskGraph: graph(tasks: [native]))

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Portable fallback failed: \(summary.errors)")
    XCTAssertEqual(summary.results.first { $0.category == .tasks }?.imported, 1)
    let restored = try await service.loadTask(id: importedID)
    XCTAssertEqual(restored.title, "Shared title")
    XCTAssertNotEqual(
      try service.read { db in
        try String.fetchOne(
          db, sql: "SELECT version FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.task, importedID])
      },
      Self.v1, "A non-fresh domain must use a newly versioned portable restore")
  }

  func testFullImporterCreatesListAndTagRootsBeforeExactGraphRestore() async throws {
    let service = try makeService()
    let taskID = UUID().uuidString.lowercased()
    let version = try clock(Self.v1)
    let native = try task(id: taskID, title: "Shared exact title")
    let snapshot = graph(
      tasks: [native],
      tagEdges: [
        NativeTaskTagEdgeSnapshot(
          taskID: taskID, tagID: Self.tagID, version: version,
          createdAt: Self.now)
      ])
    let portable = portableTask(from: native, tags: ["Focus"])
    let payload = LorvexDataExportPayload(
      tasks: [portable],
      nativeTaskGraph: snapshot,
      lists: [ExportList(id: Self.listID, name: "Imported root")],
      tags: [
        ExportTag(
          id: Self.tagID, displayName: "Focus", createdAt: Self.now,
          updatedAt: Self.now)
      ])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Exact import failed: \(summary.errors)")
    XCTAssertEqual(summary.totalImported, 3)
    let restored = try await service.loadTask(id: taskID)
    XCTAssertEqual(restored.title, "Shared exact title")
    XCTAssertEqual(
      try service.read { db in
        try String.fetchOne(
          db,
          sql: "SELECT version FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
          arguments: [EntityName.task, taskID])
      },
      Self.v1)
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_tags WHERE task_id = ? AND tag_id = ?",
          arguments: [taskID, Self.tagID])
      },
      1)
  }

  func testMissingNativeRootsUsesPortableImportRatherThanRejectingWholeImport() async throws {
    let service = try makeService()
    let importedID = UUID().uuidString.lowercased()
    let missingListID = "99999999-9999-4999-8999-999999999999"
    let native = try task(
      id: importedID, title: "Shared missing-root title", listID: missingListID)
    let portable = portableTask(from: native)
    let payload = LorvexDataExportPayload(
      tasks: [portable], nativeTaskGraph: graph(tasks: [native]))

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Missing roots should fall back: \(summary.errors)")
    XCTAssertEqual(summary.totalImported, 1)
    let restored = try await service.loadTask(id: importedID)
    XCTAssertEqual(restored.title, "Shared missing-root title")
  }

  func testNativePortableIdentityMismatchFailsClosedWithoutWrites() async throws {
    let service = try makeService()
    let portableID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    let nativeID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    let portable = portableTask(from: try task(id: portableID, listID: "inbox"))
    let payload = LorvexDataExportPayload(
      tasks: [portable],
      nativeTaskGraph: graph(tasks: [try task(id: nativeID, listID: "inbox")]))

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertEqual(summary.totalImported, 0)
    XCTAssertTrue(
      summary.errors.contains { $0.message.contains("identity sets differ") })
    let counts = try service.read { db -> (Int, Int, Int) in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tasks") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1
      )
    }
    XCTAssertEqual(counts.0, 0)
    XCTAssertEqual(counts.1, 0)
    XCTAssertEqual(counts.2, 0)
  }

  func testContradictoryProjectionFailsBeforeImportingRootCategories() async throws {
    let service = try makeService()
    let taskID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    let native = try task(id: taskID, title: "Native", listID: Self.listID)
    var portable = portableTask(from: native)
    portable.title = "Portable"
    let payload = LorvexDataExportPayload(
      tasks: [portable], nativeTaskGraph: graph(tasks: [native]),
      lists: [ExportList(id: Self.listID, name: "Must not be written")])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertEqual(summary.totalImported, 0)
    XCTAssertTrue(summary.errors.contains { $0.message.contains("contradictory") })
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [Self.listID])
      }, 0)
  }

  func testInvalidNativeGraphFailsBeforeImportingRootCategories() async throws {
    let service = try makeService()
    let taskID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
    let native = try task(id: taskID, listID: Self.listID)
    let invalid = graph(
      tasks: [native],
      dependencyEdges: [
        NativeTaskDependencyEdgeSnapshot(
          taskID: taskID, dependsOnTaskID: taskID, version: try clock(Self.v1),
          createdAt: Self.now)
      ])
    let payload = LorvexDataExportPayload(
      tasks: [portableTask(from: native)], nativeTaskGraph: invalid,
      lists: [ExportList(id: Self.listID, name: "Must not be written")])

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertEqual(summary.totalImported, 0)
    XCTAssertTrue(summary.errors.contains { $0.message.contains("invalid native task graph") })
    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db, sql: "SELECT COUNT(*) FROM lists WHERE id = ?", arguments: [Self.listID])
      }, 0)
  }

  func testTaskOnlyBackupWithTagEdgesAlwaysUsesPortableNameMapping() async throws {
    let service = try makeService()
    try service.write { db in
      try db.execute(
        sql: "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES (?, 'List', ?, ?, ?)",
        arguments: [Self.listID, Self.v1, Self.now, Self.now])
      try db.execute(
        sql: "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) VALUES (?, 'Unrelated', 'unrelated', ?, ?, ?)",
        arguments: [Self.tagID, Self.v1, Self.now, Self.now])
    }
    let taskID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
    let native = try task(id: taskID)
    let snapshot = graph(
      tasks: [native],
      tagEdges: [
        NativeTaskTagEdgeSnapshot(
          taskID: taskID, tagID: Self.tagID, version: try clock(Self.v1),
          createdAt: Self.now)
      ])
    let payload = LorvexDataExportPayload(
      tasks: [portableTask(from: native, tags: ["Work"])], nativeTaskGraph: snapshot)

    let summary = await LorvexDataImporter.apply(
      plan: LorvexDataImporter.plan(for: payload), payload: payload, using: service)

    XCTAssertTrue(summary.errors.isEmpty, "Portable restore failed: \(summary.errors)")
    XCTAssertEqual(summary.totalImported, 1)
    let restoredTag = try service.read { db in
      try Row.fetchOne(
          db,
          sql: """
            SELECT tags.id, tags.display_name FROM task_tags
            JOIN tags ON tags.id = task_tags.tag_id
            WHERE task_tags.task_id = ?
            """,
          arguments: [taskID])
    }
    XCTAssertEqual(restoredTag?["display_name"] as String?, "work")
    XCTAssertNotEqual(restoredTag?["id"] as String?, Self.tagID)
  }

  func testLargeAndEmptyRestoreAuditsAreDeterministicallyBounded() async throws {
    let service = try makeService()
    try seedRoots(service, tagID: nil)
    let taskCount = LorvexBatchLimits.maxItems + 1
    let tasks = try (0..<taskCount).map { _ in
      try task(id: UUID().uuidString.lowercased())
    }

    let largeDisposition = try await service.importNativeTaskGraphIfFresh(
      graph(tasks: tasks))
    XCTAssertEqual(largeDisposition, .imported(taskCount: taskCount))
    let auditProbe = try service.read { db -> (Int, Int, [Int]) in
      let auditCount =
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog
            WHERE operation = 'import_native_task_graph'
            """) ?? -1
      let linkedCount =
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog_entities ace
            JOIN ai_changelog ac ON ac.id = ace.changelog_id
            WHERE ac.operation = 'import_native_task_graph'
            """) ?? -1
      let chunkSizes = try Int.fetchAll(
        db,
        sql: """
          SELECT COUNT(*) FROM ai_changelog_entities ace
          JOIN ai_changelog ac ON ac.id = ace.changelog_id
          WHERE ac.operation = 'import_native_task_graph'
          GROUP BY ace.changelog_id ORDER BY COUNT(*)
          """)
      return (auditCount, linkedCount, chunkSizes)
    }
    XCTAssertEqual(auditProbe.0, 2)
    XCTAssertEqual(auditProbe.1, taskCount)
    XCTAssertEqual(auditProbe.2, [1, LorvexBatchLimits.maxItems])

    let emptyService = try makeService()
    let emptyDisposition = try await emptyService.importNativeTaskGraphIfFresh(
      graph(tasks: []))
    XCTAssertEqual(emptyDisposition, .imported(taskCount: 0))
    XCTAssertEqual(
      try emptyService.read { db in
        try Int.fetchOne(
          db,
          sql: """
            SELECT COUNT(*) FROM ai_changelog
            WHERE operation = 'import_native_task_graph'
            """)
      },
      1)
    XCTAssertEqual(
      SwiftLorvexCoreService.nativeTaskGraphAuditChunks(taskIDs: []),
      [[]])
  }
}
