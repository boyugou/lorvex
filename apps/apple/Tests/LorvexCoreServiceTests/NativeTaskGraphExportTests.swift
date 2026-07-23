import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

final class NativeTaskGraphExportTests: XCTestCase {
  private static let v1 = "1700000000000_0000_1111111111111111"
  private static let v2 = "1700000000001_0000_2222222222222222"
  private static let now = "2026-01-01T00:00:00.000Z"
  private static let parentID = "11111111-1111-4111-8111-111111111111"
  private static let blockerID = "22222222-2222-4222-8222-222222222222"
  private static let listID = "33333333-3333-4333-8333-333333333333"
  private static let tagID = "44444444-4444-4444-8444-444444444444"
  private static let checklistID = "55555555-5555-4555-8555-555555555555"
  private static let reminderID = "66666666-6666-4666-8666-666666666666"
  private static let cycleAID = "77777777-7777-4777-8777-777777777777"
  private static let cycleBID = "88888888-8888-4888-8888-888888888888"
  private static let completedID = "99999999-9999-4999-8999-999999999999"
  private static let terminalClockID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
  private static let closureTaskID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
  private static let groupID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
  private static let missingGroupID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
  private static let deletedTaskID = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
  private static let deletedChecklistID = "ffffffff-ffff-4fff-8fff-ffffffffffff"
  private static let deletedReminderID = "abababab-abab-4bab-8bab-abababababab"
  private static let deletedEventID = "cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd"

  private func schemaSQL() throws -> String {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    return try String(contentsOf: schemaURL, encoding: .utf8)
  }

  private func makeService() throws -> SwiftLorvexCoreService {
    SwiftLorvexCoreService(store: try LorvexStore.openInMemory(schemaSQL: schemaSQL()))
  }

  private func seedCompleteGraph(_ service: SwiftLorvexCoreService) throws -> (
    parentID: String, childID: String, blockerID: String
  ) {
    let parentID = Self.parentID
    let blockerID = Self.blockerID
    let groupID = Self.groupID
    let childID = TaskRecurrenceSuccessorID.make(
      parentTaskId: parentID, recurrenceGroupId: groupID)
    try service.write { db in
      try db.execute(
        sql:
          "INSERT INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES (?, 'List', ?, ?, ?)",
        arguments: [Self.listID, Self.v1, Self.now, Self.now])
      try db.execute(
        sql:
          "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at) "
          + "VALUES (?, 'Focus', 'focus', ?, ?, ?)",
        arguments: [Self.tagID, Self.v1, Self.now, Self.now])
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, body, raw_input, ai_notes, status, list_id, priority,
            due_date, estimated_minutes, recurrence, recurrence_group_id,
            canonical_occurrence_date, content_version, schedule_version,
            lifecycle_version, archive_version, recurrence_rollover_state,
            recurrence_successor_id, version, created_at, updated_at, completed_at,
            planned_date, available_from, defer_count, archived_at
          ) VALUES (
            ?, 'Historical parent', 'parent body', 'parent raw', 'parent ai',
            'completed', ?, 1, '2026-01-31', 30, '{"FREQ":"DAILY","INTERVAL":1}', ?,
            '2026-01-31', ?, ?, ?, ?, 'authorized', ?, ?, ?, ?,
            '2026-01-31T10:00:00.000Z', '2026-01-31', '2026-01-01', 1,
            '2026-02-10T00:00:00.000Z'
          )
          """,
        arguments: [
          parentID, Self.listID, groupID, Self.v1, Self.v2, Self.v2, Self.v2, childID,
          Self.v2, Self.now, "2026-02-10T00:00:00.000Z",
        ])
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, body, raw_input, ai_notes, status, list_id, priority,
            due_date, estimated_minutes, recurrence, spawned_from,
            spawned_from_version, recurrence_group_id, recurrence_instance_key,
            canonical_occurrence_date, content_version, schedule_version,
            lifecycle_version, archive_version, recurrence_rollover_state,
            version, created_at, updated_at, last_deferred_at, last_defer_reason,
            planned_date, available_from, defer_count
          ) VALUES (
            ?, 'Exact child', 'child body', 'child raw', 'child ai', 'in_progress',
            ?, 2, '2026-02-01', 45, '{"FREQ":"DAILY","INTERVAL":1}', ?, ?, ?, ?,
            '2026-02-01', ?, ?, ?, ?, 'none', ?, ?, ?,
            '2026-01-20T00:00:00.000Z', 'low_energy', '2026-02-01',
            '2026-01-15', 2
          )
          """,
        arguments: [
          childID, Self.listID, parentID, Self.v2, groupID, "\(groupID):2026-02-01",
          Self.v2, Self.v2, Self.v2, Self.v2, Self.v2, Self.now, Self.now,
        ])
      try db.execute(
        sql:
          "INSERT INTO tasks (id, title, status, list_id, content_version, "
          + "schedule_version, lifecycle_version, archive_version, version, created_at, updated_at) "
          + "VALUES (?, 'Blocker', 'open', ?, ?, ?, ?, ?, ?, ?, ?)",
        arguments: [
          blockerID, Self.listID, Self.v1, Self.v1, Self.v1, Self.v1, Self.v1,
          Self.now, Self.now,
        ])
      try db.execute(
        sql:
          "INSERT INTO task_recurrence_exceptions (task_id, exception_date) VALUES (?, '2026-02-03')",
        arguments: [childID])
      try db.execute(
        sql:
          "INSERT INTO task_tags (task_id, tag_id, version, created_at) "
          + "VALUES (?, ?, ?, ?)",
        arguments: [childID, Self.tagID, Self.v2, Self.now])
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES (?, ?, ?, ?)",
        arguments: [childID, blockerID, Self.v2, Self.now])
      // Completion stops new dependency edits but intentionally retains the
      // existing graph as history. Exact export must accept that persisted
      // state; only cancellation detaches dependency endpoints.
      try db.execute(
        sql:
          "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at) "
          + "VALUES (?, ?, ?, ?)",
        arguments: [parentID, blockerID, Self.v2, Self.now])
      try db.execute(
        sql: """
          INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
          ) VALUES (?, ?, 0, 'Do it', ?, ?, ?, ?)
          """,
        arguments: [Self.checklistID, childID, Self.now, Self.v2, Self.now, Self.now])
      try db.execute(
        sql: """
          INSERT INTO task_reminders (
            id, task_id, reminder_at, version, created_at, original_local_time, original_tz
          ) VALUES (?, ?, '2026-02-01T09:00:00.000Z', ?, ?, '09:00',
                    'America/Los_Angeles')
        """,
        arguments: [Self.reminderID, childID, Self.v2, Self.now])
      for (entityType, entityID) in [
        (EntityName.task, Self.deletedTaskID),
        (EntityName.taskChecklistItem, Self.deletedChecklistID),
        (EntityName.taskReminder, Self.deletedReminderID),
        (EdgeName.taskTag, "\(Self.deletedTaskID):\(Self.tagID)"),
        (EdgeName.taskDependency, "\(Self.deletedTaskID):\(blockerID)"),
        (EdgeName.taskCalendarEventLink, "\(Self.deletedTaskID):\(Self.deletedEventID)"),
      ] {
        try db.execute(
          sql: """
            INSERT INTO sync_tombstones (
              entity_type, entity_id, version, deleted_at, cloud_confirmed_at
            ) VALUES (?, ?, ?, ?, '2026-01-02T00:00:00.000Z')
            """,
          arguments: [entityType, entityID, Self.v2, Self.now])
      }
      try db.execute(
        sql: """
          INSERT INTO sync_payload_shadow (
            entity_type, entity_id, base_version, payload_schema_version,
            raw_payload_json, source_device_id, updated_at
          ) VALUES (?, ?, ?, 2, ?, 'future-peer', ?)
          """,
        arguments: [
          EntityName.task, childID, Self.v2,
          "{\"future_user_field\":\"preserve me\"}", Self.now,
        ])
    }
    return (parentID, childID, blockerID)
  }

  func testBundleCapturesEveryTaskRegisterAndOwnedRelation() async throws {
    let service = try makeService()
    let fixture = try seedCompleteGraph(service)

    let bundle = try await service.loadTaskExportBundleForDataExport()
    let graph = bundle.nativeGraph

    XCTAssertEqual(
      Set(bundle.tasks.map(\.id)), Set([fixture.parentID, fixture.childID, fixture.blockerID]))
    XCTAssertEqual(graph.schemaVersion, NativeTaskGraphSnapshot.currentSchemaVersion)
    XCTAssertEqual(graph.tasks.count, 3)
    let child = try XCTUnwrap(graph.tasks.first { $0.id == fixture.childID })
    XCTAssertEqual(child.body, "child body")
    XCTAssertEqual(child.rawInput, "child raw")
    XCTAssertEqual(child.aiNotes, "child ai")
    XCTAssertEqual(child.status, "in_progress")
    XCTAssertEqual(child.listID, Self.listID)
    XCTAssertEqual(child.priority, 2)
    XCTAssertEqual(child.estimatedMinutes, 45)
    XCTAssertEqual(child.spawnedFrom, fixture.parentID)
    XCTAssertEqual(child.spawnedFromVersion?.description, Self.v2)
    XCTAssertEqual(child.recurrenceGroupID, Self.groupID)
    XCTAssertEqual(child.recurrenceInstanceKey, "\(Self.groupID):2026-02-01")
    XCTAssertEqual(child.canonicalOccurrenceDate, "2026-02-01")
    XCTAssertEqual(child.contentVersion.description, Self.v2)
    XCTAssertEqual(child.scheduleVersion.description, Self.v2)
    XCTAssertEqual(child.lifecycleVersion.description, Self.v2)
    XCTAssertEqual(child.archiveVersion.description, Self.v2)
    XCTAssertEqual(child.version.description, Self.v2)
    XCTAssertEqual(child.lastDeferReason, "low_energy")
    XCTAssertEqual(child.deferCount, 2)
    XCTAssertEqual(
      graph.recurrenceExceptions,
      [NativeTaskRecurrenceExceptionSnapshot(taskID: fixture.childID, exceptionDate: "2026-02-03")])
    XCTAssertEqual(graph.tagEdges.first?.taskID, fixture.childID)
    XCTAssertEqual(graph.tagEdges.first?.tagID, Self.tagID)
    XCTAssertEqual(graph.tagEdges.first?.version.description, Self.v2)
    XCTAssertTrue(
      graph.dependencyEdges.contains {
        $0.taskID == fixture.childID && $0.dependsOnTaskID == fixture.blockerID
      })
    XCTAssertTrue(
      graph.dependencyEdges.contains {
        $0.taskID == fixture.parentID && $0.dependsOnTaskID == fixture.blockerID
      },
      "completed tasks retain dependency history in an exact native archive")
    XCTAssertEqual(graph.checklistItems.first?.taskID, fixture.childID)
    XCTAssertEqual(graph.checklistItems.first?.text, "Do it")
    XCTAssertEqual(graph.checklistItems.first?.version.description, Self.v2)
    XCTAssertEqual(graph.reminders.first?.taskID, fixture.childID)
    XCTAssertEqual(graph.reminders.first?.originalLocalTime, "09:00")
    XCTAssertEqual(graph.reminders.first?.originalTimeZone, "America/Los_Angeles")
    // The task-only bundle excludes task-calendar-link control state; links and
    // their tombstones travel through the separate taskCalendarEventLinks export.
    XCTAssertEqual(graph.tombstones.count, NativeTaskGraphContract.syncedEntityKinds.count - 1)
    XCTAssertFalse(graph.tombstones.contains { $0.entityType == .taskCalendarEventLink })
    XCTAssertEqual(
      graph.tombstones.first { $0.entityType == .task }?.entityID,
      Self.deletedTaskID)
    XCTAssertTrue(graph.tombstones.allSatisfy { $0.version.description == Self.v2 })
    XCTAssertTrue(graph.tombstones.allSatisfy { $0.deletedAt == Self.now })
    XCTAssertEqual(
      graph.payloadShadows,
      [
        NativeTaskPayloadShadowSnapshot(
          entityType: .task, entityID: fixture.childID,
          baseVersion: try clock(Self.v2), payloadSchemaVersion: 2,
          rawPayloadJSON: "{\"future_user_field\":\"preserve me\"}",
          sourceDeviceID: "future-peer", updatedAt: Self.now)
      ])

    let encoded = try JSONEncoder().encode(graph)
    XCTAssertEqual(try JSONDecoder().decode(NativeTaskGraphSnapshot.self, from: encoded), graph)
  }

  func testIdentityClosureRejectsPortableCountOrIdentityDrift() async throws {
    let service = try makeService()
    _ = try seedCompleteGraph(service)
    let bundle = try await service.loadTaskExportBundleForDataExport()

    XCTAssertNoThrow(
      try SwiftLorvexCoreService.validateTaskExportIdentityClosure(
        portableTasks: bundle.tasks, nativeGraph: bundle.nativeGraph))

    var missingPortableTask = bundle.tasks
    missingPortableTask.removeLast()
    assertIdentityClosureRejects(
      portableTasks: missingPortableTask, nativeGraph: bundle.nativeGraph)

    var fabricatedPortableIdentity = bundle.tasks
    fabricatedPortableIdentity[0].id = Self.terminalClockID
    assertIdentityClosureRejects(
      portableTasks: fabricatedPortableIdentity, nativeGraph: bundle.nativeGraph)
  }

  func testZipManifestAndDecoderPreserveNativeTaskGraphMember() async throws {
    let service = try makeService()
    _ = try seedCompleteGraph(service)
    let bundle = try await service.loadTaskExportBundleForDataExport()
    let payload = LorvexDataExportPayload(
      tasks: bundle.tasks, nativeTaskGraph: bundle.nativeGraph)

    let zip = try LorvexDataExporter.renderZip(
      payload: payload, generatedAt: Self.now, appVersion: "1.0")
    let entries = try LorvexZipArchive.read(zip)
    let byPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
    XCTAssertNotNil(byPath["native_task_graph.json"])
    let manifest = try JSONDecoder().decode(
      ExportManifest.self, from: try XCTUnwrap(byPath["manifest.json"]))
    XCTAssertEqual(manifest.schemaVersion, ExportManifest.currentSchemaVersion)
    XCTAssertEqual(manifest.fileCounts["native_task_graph"], 1)

    let decoded = try LorvexDataImporter.decode(zip)
    XCTAssertEqual(decoded.nativeTaskGraph, bundle.nativeGraph)
    XCTAssertEqual(decoded.tasks?.count, bundle.tasks.count)
  }

  func testHumanJSONCarriesNativeGraphButAIExportRemainsPortable() async throws {
    let service = try makeService()
    _ = try seedCompleteGraph(service)

    let human = try await service.exportData(entities: ["tasks"], format: "json")
    let humanPayload = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(human.utf8))
    XCTAssertNotNil(humanPayload.nativeTaskGraph)

    let ai = try await service.exportDataForAI(
      entities: ["tasks"], format: "json", appVersion: nil, generatedAt: nil)
    let aiPayload = try JSONDecoder().decode(
      LorvexDataExportPayload.self, from: Data(ai.utf8))
    XCTAssertNil(aiPayload.nativeTaskGraph)
    XCTAssertEqual(aiPayload.tasks?.count, humanPayload.tasks?.count)
  }

  func testBundleUsesOneSnapshotAcrossConcurrentChildInsert() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lorvex-task-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("lorvex.sqlite").path
    let sql = try schemaSQL()
    let source = SwiftLorvexCoreService(databasePath: path, schemaSQL: sql)
    let peer = SwiftLorvexCoreService(databasePath: path, schemaSQL: sql)
    let task = try await source.createTask(title: "Snapshot task", notes: "")

    let hookEntered = expectation(description: "native task export read its roots")
    let continueExport = DispatchSemaphore(value: 0)
    let exportTask = Task {
      try await SwiftLorvexCoreService.$afterNativeTaskRowsExportReadForTesting.withValue({
        hookEntered.fulfill()
        _ = continueExport.wait(timeout: .now() + 5)
      }) {
        try await source.loadTaskExportBundleForDataExport()
      }
    }
    await fulfillment(of: [hookEntered], timeout: 5)
    do {
      _ = try await peer.addTaskChecklistItem(taskID: task.id, text: "Concurrent child")
    } catch {
      continueExport.signal()
      throw error
    }
    continueExport.signal()

    let concurrent = try await exportTask.value
    XCTAssertFalse(concurrent.nativeGraph.checklistItems.contains { $0.text == "Concurrent child" })
    let fresh = try await source.loadTaskExportBundleForDataExport()
    XCTAssertTrue(fresh.nativeGraph.checklistItems.contains { $0.text == "Concurrent child" })
  }

  func testExportRejectsAuthorizedParentWithoutItsSuccessor() async throws {
    let service = try makeService()
    let groupID = Self.missingGroupID
    let successorID = TaskRecurrenceSuccessorID.make(
      parentTaskId: Self.parentID, recurrenceGroupId: groupID)
    try service.write { db in
      try db.execute(
        sql:
          "INSERT INTO lists (id, name, version, created_at, updated_at) "
          + "VALUES (?, 'List', ?, ?, ?)",
        arguments: [Self.listID, Self.v1, Self.now, Self.now])
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, status, list_id, due_date, recurrence, recurrence_group_id,
            canonical_occurrence_date, lifecycle_version, recurrence_rollover_state,
            recurrence_successor_id, version, created_at, updated_at, completed_at
          ) VALUES (
            ?, 'Parent', 'completed', ?, '2026-02-01',
            '{"FREQ":"DAILY","INTERVAL":1}', ?, '2026-02-01', ?, 'authorized', ?, ?, ?, ?, ?
          )
          """,
        arguments: [
          Self.parentID, Self.listID, groupID, Self.v2, successorID, Self.v2,
          Self.now, Self.now, Self.now,
        ])
    }

    do {
      _ = try await service.loadTaskExportBundleForDataExport()
      XCTFail("an authorized pointer without its successor must not be exported")
    } catch let error as LorvexCoreError {
      guard case .validation(let field, let message) = error else {
        return XCTFail("expected typed validation, got \(error)")
      }
      XCTAssertEqual(field, "nativeTaskGraph")
      XCTAssertTrue(message.contains("Retry the export"))
    }
  }

  func testValidatorRejectsDependencyCyclesAndTerminalActiveReminders() throws {
    let a = try minimalTask(id: Self.cycleAID)
    let b = try minimalTask(id: Self.cycleBID)
    let cycle = NativeTaskGraphSnapshot(
      tasks: [a, b], recurrenceExceptions: [], tagEdges: [],
      dependencyEdges: [
        NativeTaskDependencyEdgeSnapshot(
          taskID: Self.cycleAID, dependsOnTaskID: Self.cycleBID,
          version: try clock(Self.v1), createdAt: Self.now),
        NativeTaskDependencyEdgeSnapshot(
          taskID: Self.cycleBID, dependsOnTaskID: Self.cycleAID,
          version: try clock(Self.v1), createdAt: Self.now),
      ],
      checklistItems: [], reminders: [])
    XCTAssertThrowsError(
      try NativeTaskGraphValidator.validate(
        cycle, knownListIDs: [Self.listID], knownTagIDs: [])
    ) { error in
      guard case NativeTaskGraphValidationError.dependencyCycle = error else {
        return XCTFail("expected dependencyCycle, got \(error)")
      }
    }

    let terminal = try minimalTask(
      id: Self.completedID, status: "completed", completedAt: Self.now)
    let activeReminder = NativeTaskGraphSnapshot(
      tasks: [terminal], recurrenceExceptions: [], tagEdges: [], dependencyEdges: [],
      checklistItems: [],
      reminders: [
        NativeTaskReminderSnapshot(
          id: Self.reminderID, taskID: Self.completedID, reminderAt: Self.now,
          dismissedAt: nil,
          cancelledAt: nil, version: try clock(Self.v1), createdAt: Self.now,
          originalLocalTime: nil, originalTimeZone: nil)
      ])
    XCTAssertThrowsError(
      try NativeTaskGraphValidator.validate(
        activeReminder, knownListIDs: [Self.listID], knownTagIDs: [])
    ) { error in
      guard case NativeTaskGraphValidationError.invalidRelation = error else {
        return XCTFail("expected invalidRelation, got \(error)")
      }
    }
  }

  func testValidatorRejectsMaximumHlcWithoutSuccessorHeadroom() throws {
    let terminalClock = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs, counter: Hlc.maxCounter,
      deviceSuffix: "1111111111111111")
    let task = NativeTaskSnapshot(
      id: Self.terminalClockID, title: "Task", body: nil, rawInput: nil, aiNotes: nil,
      status: "open", listID: Self.listID, priority: nil, dueDate: nil,
      estimatedMinutes: nil, recurrence: nil, spawnedFrom: nil,
      spawnedFromVersion: nil, recurrenceGroupID: nil, recurrenceInstanceKey: nil,
      canonicalOccurrenceDate: nil, contentVersion: terminalClock,
      scheduleVersion: terminalClock, lifecycleVersion: terminalClock,
      archiveVersion: terminalClock, recurrenceRolloverState: "none",
      recurrenceSuccessorID: nil, version: terminalClock, createdAt: Self.now,
      updatedAt: Self.now, completedAt: nil, lastDeferredAt: nil,
      lastDeferReason: nil, plannedDate: nil, availableFrom: nil, deferCount: 0,
      archivedAt: nil)
    let graph = NativeTaskGraphSnapshot(
      tasks: [task], recurrenceExceptions: [], tagEdges: [], dependencyEdges: [],
      checklistItems: [], reminders: [])

    XCTAssertThrowsError(
      try NativeTaskGraphValidator.validate(
        graph, knownListIDs: [Self.listID], knownTagIDs: [])
    ) { error in
      guard case NativeTaskGraphValidationError.terminalHlc = error else {
        return XCTFail("expected terminalHlc, got \(error)")
      }
    }
  }

  func testArchiveClosureRejectsSelectedMissingRootsButAllowsTaskOnlyFallback() throws {
    let task = try minimalTask(id: Self.closureTaskID)
    let graph = NativeTaskGraphSnapshot(
      tasks: [task], recurrenceExceptions: [],
      tagEdges: [
        NativeTaskTagEdgeSnapshot(
          taskID: task.id, tagID: Self.tagID, version: try clock(Self.v1),
          createdAt: Self.now)
      ],
      dependencyEdges: [], checklistItems: [], reminders: [])

    XCTAssertNoThrow(
      try NativeTaskGraphArchiveClosureValidator.validate(
        graph, exportedListIDs: nil, exportedTagIDs: nil),
      "a task-only archive is allowed to use portable import fallback")
    XCTAssertThrowsError(
      try NativeTaskGraphArchiveClosureValidator.validate(
        graph, exportedListIDs: [], exportedTagIDs: [Self.tagID])
    ) { error in
      guard
        case NativeTaskGraphValidationError.missingEndpoint(
          relation: "exported list category", identity: Self.listID) = error
      else { return XCTFail("expected missing exported list root, got \(error)") }
    }
    XCTAssertThrowsError(
      try NativeTaskGraphArchiveClosureValidator.validate(
        graph, exportedListIDs: [Self.listID], exportedTagIDs: [])
    ) { error in
      guard
        case NativeTaskGraphValidationError.missingEndpoint(
          relation: "exported tag category", identity: Self.tagID) = error
      else { return XCTFail("expected missing exported tag root, got \(error)") }
    }
  }

  func testValidatorAcceptsInboxSentinelButRejectsMalformedEntityIDs() throws {
    var inboxTask = try minimalTask(id: Self.closureTaskID)
    inboxTask.listID = ListId.inboxSentinel
    let valid = NativeTaskGraphSnapshot(
      tasks: [inboxTask], recurrenceExceptions: [], tagEdges: [],
      dependencyEdges: [], checklistItems: [], reminders: [])
    XCTAssertNoThrow(
      try NativeTaskGraphValidator.validate(
        valid, knownListIDs: [ListId.inboxSentinel], knownTagIDs: []))

    inboxTask.id = "NOT-A-CANONICAL-UUID"
    let malformed = NativeTaskGraphSnapshot(
      tasks: [inboxTask], recurrenceExceptions: [], tagEdges: [],
      dependencyEdges: [], checklistItems: [], reminders: [])
    XCTAssertThrowsError(
      try NativeTaskGraphValidator.validate(
        malformed, knownListIDs: [ListId.inboxSentinel], knownTagIDs: [])
    ) { error in
      guard
        case NativeTaskGraphValidationError.invalidValue(
          field: "task.id", reason: _) = error
      else { return XCTFail("expected canonical task-id rejection, got \(error)") }
    }
  }

  func testValidatorRejectsContradictoryOrUnboundedTaskSyncArtifacts() throws {
    let task = try minimalTask(id: Self.closureTaskID)
    let version = try clock(Self.v1)
    let contradictory = NativeTaskGraphSnapshot(
      tasks: [task], recurrenceExceptions: [], tagEdges: [], dependencyEdges: [],
      checklistItems: [], reminders: [],
      tombstones: [
        NativeTaskTombstoneSnapshot(
          entityType: .task, entityID: task.id, version: version,
          deletedAt: Self.now)
      ])
    XCTAssertThrowsError(
      try NativeTaskGraphValidator.validate(
        contradictory, knownListIDs: [Self.listID], knownTagIDs: [])
    ) { error in
      guard case NativeTaskGraphValidationError.invalidRelation = error else {
        return XCTFail("expected a live/tombstone contradiction, got \(error)")
      }
    }

    let oversized = NativeTaskGraphSnapshot(
      tasks: [task], recurrenceExceptions: [], tagEdges: [], dependencyEdges: [],
      checklistItems: [], reminders: [],
      payloadShadows: [
        NativeTaskPayloadShadowSnapshot(
          entityType: .task, entityID: task.id, baseVersion: version,
          payloadSchemaVersion: 2,
          rawPayloadJSON:
            "{\"future\":\""
            + String(
              repeating: "x",
              count: PayloadShadow.maxRawPayloadJSONBytes)
            + "\"}",
          sourceDeviceID: "future-peer", updatedAt: Self.now)
      ])
    XCTAssertThrowsError(
      try NativeTaskGraphValidator.validate(
        oversized, knownListIDs: [Self.listID], knownTagIDs: [])
    ) { error in
      guard
        case NativeTaskGraphValidationError.invalidValue(
          field: "payloadShadow.rawPayloadJSON", reason: _) = error
      else { return XCTFail("expected bounded shadow rejection, got \(error)") }
    }
  }

  private func minimalTask(
    id: String, status: String = "open", completedAt: String? = nil
  ) throws -> NativeTaskSnapshot {
    let version = try clock(Self.v1)
    return NativeTaskSnapshot(
      id: id, title: id, body: nil, rawInput: nil, aiNotes: nil, status: status,
      listID: Self.listID, priority: nil, dueDate: nil, estimatedMinutes: nil,
      recurrence: nil, spawnedFrom: nil, spawnedFromVersion: nil,
      recurrenceGroupID: nil, recurrenceInstanceKey: nil,
      canonicalOccurrenceDate: nil, contentVersion: version,
      scheduleVersion: version, lifecycleVersion: version, archiveVersion: version,
      recurrenceRolloverState: "none", recurrenceSuccessorID: nil, version: version,
      createdAt: Self.now, updatedAt: Self.now, completedAt: completedAt,
      lastDeferredAt: nil, lastDeferReason: nil, plannedDate: nil,
      availableFrom: nil, deferCount: 0, archivedAt: nil)
  }

  private func clock(_ raw: String) throws -> Hlc {
    try Hlc.parseCanonical(raw)
  }

  private func assertIdentityClosureRejects(
    portableTasks: [ExportTask], nativeGraph: NativeTaskGraphSnapshot,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try SwiftLorvexCoreService.validateTaskExportIdentityClosure(
        portableTasks: portableTasks, nativeGraph: nativeGraph),
      file: file, line: line
    ) { error in
      guard case LorvexCoreError.validation(let field, let message) = error else {
        return XCTFail("expected typed validation, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(field, "nativeTaskGraph", file: file, line: line)
      XCTAssertTrue(message.contains("Retry the export"), file: file, line: line)
    }
  }
}
