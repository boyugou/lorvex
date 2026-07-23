import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class TaskRegisterIntentProvenanceTests: XCTestCase {
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

  private func clearTaskOutbox(
    _ service: SwiftLorvexCoreService, taskID: String
  ) throws {
    try service.write { db in
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.task, taskID])
    }
  }

  private func pendingTaskIntent(
    _ service: SwiftLorvexCoreService, taskID: String
  ) throws -> Int64? {
    try service.read { db in
      try Int64.fetchOne(
        db,
        sql: """
          SELECT register_intent FROM sync_outbox
          WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
          """,
        arguments: [EntityName.task, taskID])
    }
  }

  func testCreateAndMultiRegisterUpdatePersistExactProvenance() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Grouped task", notes: "")
    XCTAssertEqual(
      try pendingTaskIntent(service, taskID: task.id),
      TaskRegisterIntent.all.rawValue)

    try clearTaskOutbox(service, taskID: task.id)
    _ = try await service.updateTask(
      TaskUpdateDraft(
        id: task.id,
        title: "Renamed grouped task",
        dueDate: .set(Date(timeIntervalSince1970: 1_785_628_800))))

    XCTAssertEqual(
      try pendingTaskIntent(service, taskID: task.id),
      TaskRegisterIntent.content.rawValue | TaskRegisterIntent.schedule.rawValue)
  }

  func testEdgeOnlyTaskUpdateDoesNotManufactureTaskRegisterWork() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Edges only", notes: "")
    try clearTaskOutbox(service, taskID: task.id)

    _ = try await service.updateTask(
      TaskUpdateDraft(id: task.id, tags: ["sync-edge-only"]))

    XCTAssertNil(try pendingTaskIntent(service, taskID: task.id))
    XCTAssertTrue(
      try service.pendingOutbound().contains {
        $0.envelope.entityType == .taskTag && $0.envelope.operation == .upsert
      })
  }

  func testBatchMoveStampsContentRegisterAndContentIntent() async throws {
    let service = try makeService()
    let destination = try await service.createList(name: "Destination", description: nil)
    let task = try await service.createTask(title: "Move me", notes: "")
    try clearTaskOutbox(service, taskID: task.id)

    let result = try await service.batchMoveTasks(ids: [task.id], toListID: destination.id)
    XCTAssertEqual(result.moved.map(\.id), [task.id])
    XCTAssertEqual(
      try pendingTaskIntent(service, taskID: task.id),
      TaskRegisterIntent.content.rawValue)
    try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT content_version, version, list_id FROM tasks WHERE id = ?",
          arguments: [task.id]))
      XCTAssertEqual(row["list_id"] as String, destination.id)
      XCTAssertEqual(row["content_version"] as String, row["version"] as String)
    }
  }

  func testChildMutationsOnlyQueueTheirIndependentRecords() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Independent children", notes: "")
    try clearTaskOutbox(service, taskID: task.id)
    let before = try service.read { db in
      try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT content_version, schedule_version, lifecycle_version,
                   archive_version, version
            FROM tasks WHERE id = ?
            """,
          arguments: [task.id]))
    }

    _ = try await service.addTaskReminder(
      taskID: task.id, reminderAt: "2026-10-01T09:00:00Z")
    _ = try await service.addTaskChecklistItem(taskID: task.id, text: "Child item")

    XCTAssertNil(try pendingTaskIntent(service, taskID: task.id))
    let after = try service.read { db in
      try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT content_version, schedule_version, lifecycle_version,
                   archive_version, version
            FROM tasks WHERE id = ?
            """,
          arguments: [task.id]))
    }
    for key in [
      "content_version", "schedule_version", "lifecycle_version",
      "archive_version", "version",
    ] {
      XCTAssertEqual(before[key] as String, after[key] as String, key)
    }
  }

  func testRecurrenceExceptionWritesOnlyTheScheduleRegister() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Exception provenance", notes: "")
    let task = try await service.setTaskRecurrence(
      taskID: created.id,
      rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    try clearTaskOutbox(service, taskID: task.id)
    let before = try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT content_version, lifecycle_version, archive_version
            FROM tasks WHERE id = ?
            """,
          arguments: [task.id]))
      return [
        "content_version": row["content_version"] as String,
        "lifecycle_version": row["lifecycle_version"] as String,
        "archive_version": row["archive_version"] as String,
      ]
    }

    _ = try await service.addTaskRecurrenceException(
      taskID: task.id, exceptionDate: "2026-10-01")

    XCTAssertEqual(
      try pendingTaskIntent(service, taskID: task.id),
      TaskRegisterIntent.schedule.rawValue)
    try service.read { db in
      let after = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT content_version, schedule_version, lifecycle_version,
                   archive_version, version
            FROM tasks WHERE id = ?
            """,
          arguments: [task.id]))
      XCTAssertEqual(after["schedule_version"] as String, after["version"] as String)
      for key in ["content_version", "lifecycle_version", "archive_version"] {
        XCTAssertEqual(before[key], after[key] as String, key)
      }
    }
  }

  func testImportedMetadataStampsEveryAuthoredRegister() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Restore metadata", notes: "")
    _ = try await service.completeTaskReturningTask(id: task.id)
    try clearTaskOutbox(service, taskID: task.id)

    try await service.restoreImportedTaskMetadata(
      id: task.id,
      archivedAt: "2026-09-04T12:00:00Z",
      deferCount: 3,
      lastDeferReason: "blocked",
      lastDeferredAt: "2026-09-03T12:00:00Z",
      completedAt: "2026-09-02T12:00:00Z",
      createdAt: "2020-01-01T00:00:00Z",
      updatedAt: "2026-09-04T12:00:00Z")

    XCTAssertEqual(
      try pendingTaskIntent(service, taskID: task.id),
      TaskRegisterIntent.all.rawValue)
    try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: """
            SELECT content_version, schedule_version, lifecycle_version,
                   archive_version, version, created_at
            FROM tasks WHERE id = ?
            """,
          arguments: [task.id]))
      let version: String = row["version"]
      for key in [
        "content_version", "schedule_version", "lifecycle_version", "archive_version",
      ] {
        XCTAssertEqual(row[key] as String, version, key)
      }
      XCTAssertEqual(row["created_at"] as String, "2020-01-01T00:00:00.000Z")
    }
  }

  func testRecurrenceDisableFlushesEveryCrossRowEffectWithExactTaskIntent() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Recurring parent", notes: "")
    let parent = try await service.setTaskRecurrence(
      taskID: created.id,
      rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    _ = try await service.completeTaskReturningTask(id: parent.id)
    let successorID = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT recurrence_successor_id FROM tasks WHERE id = ?",
          arguments: [parent.id]))
    }
    _ = try await service.addTaskReminder(
      taskID: successorID, reminderAt: "2026-10-02T09:00:00Z")
    let dependent = try await service.createTask(
      TaskCreateDraft(title: "Depends on successor", dependsOn: [successorID]))
    let reminderID = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT id FROM task_reminders WHERE task_id = ?",
          arguments: [successorID]))
    }
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    _ = try await service.removeTaskRecurrence(taskID: parent.id)

    try service.read { db in
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT status FROM tasks WHERE id = ?", arguments: [successorID]),
        "cancelled")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_reminders WHERE id = ? AND cancelled_at IS NOT NULL",
          arguments: [reminderID]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ? AND depends_on_task_id = ?",
          arguments: [dependent.id, successorID]),
        0)

      let parentIntent = try Int64.fetchOne(
        db,
        sql: "SELECT register_intent FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
        arguments: [parent.id])
      XCTAssertEqual(
        parentIntent,
        TaskRegisterIntent.schedule.rawValue | TaskRegisterIntent.lifecycle.rawValue)
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT register_intent FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [successorID]),
        TaskRegisterIntent.lifecycle.rawValue)
      XCTAssertNil(
        try Int64.fetchOne(
          db,
          sql: "SELECT register_intent FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [dependent.id]),
        "detaching the edge does not mutate the dependent task row")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task_reminder' AND entity_id = ? AND operation = 'upsert'",
          arguments: [reminderID]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task_dependency' AND entity_id = ? AND operation = 'delete'",
          arguments: ["\(dependent.id):\(successorID)"]),
        1)
    }
  }

  func testMarkSomedayRewindsAuthorizedRecurringSuccessorAndFlushesGraph() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Recurring someday parent", notes: "")
    let parent = try await service.setTaskRecurrence(
      taskID: created.id,
      rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    _ = try await service.completeTaskReturningTask(id: parent.id)
    let successorID = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT recurrence_successor_id FROM tasks WHERE id = ?",
          arguments: [parent.id]))
    }
    _ = try await service.addTaskReminder(
      taskID: successorID, reminderAt: "2026-10-02T09:00:00Z")
    let dependent = try await service.createTask(
      TaskCreateDraft(title: "Depends on someday successor", dependsOn: [successorID]))
    let reminderID = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT id FROM task_reminders WHERE task_id = ?",
          arguments: [successorID]))
    }
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    _ = try await service.markTaskSomeday(id: parent.id)

    try service.read { db in
      let parentRow = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT status, recurrence_rollover_state, recurrence_successor_id FROM tasks WHERE id = ?",
          arguments: [parent.id]))
      XCTAssertEqual(parentRow["status"] as String, "someday")
      XCTAssertEqual(parentRow["recurrence_rollover_state"] as String, "revoked")
      XCTAssertEqual(parentRow["recurrence_successor_id"] as String?, successorID)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT status FROM tasks WHERE id = ?", arguments: [successorID]),
        "cancelled")
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_reminders WHERE id = ? AND cancelled_at IS NOT NULL",
          arguments: [reminderID]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ? AND depends_on_task_id = ?",
          arguments: [dependent.id, successorID]),
        0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT register_intent FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [successorID]),
        TaskRegisterIntent.schedule.rawValue | TaskRegisterIntent.lifecycle.rawValue)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task_reminder' AND entity_id = ? AND operation = 'upsert'",
          arguments: [reminderID]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task_dependency' AND entity_id = ? AND operation = 'delete'",
          arguments: ["\(dependent.id):\(successorID)"]),
        1)
    }
  }

  func testMarkSomedayRejectsRewindAfterRecurringSuccessorAdvanced() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Advanced recurring parent", notes: "")
    let parent = try await service.setTaskRecurrence(
      taskID: created.id,
      rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    _ = try await service.completeTaskReturningTask(id: parent.id)
    let successorID = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT recurrence_successor_id FROM tasks WHERE id = ?",
          arguments: [parent.id]))
    }
    _ = try await service.completeTaskReturningTask(id: successorID)
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    await XCTAssertThrowsErrorAsync(try await service.markTaskSomeday(id: parent.id))

    try service.read { db in
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT status FROM tasks WHERE id = ?", arguments: [parent.id]),
        "completed")
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT status FROM tasks WHERE id = ?", arguments: [successorID]),
        "completed")
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testPermanentDeleteEnqueuesTheSurvivingRerootedTask() async throws {
    let service = try makeService()
    let created = try await service.createTask(title: "Delete recurring parent", notes: "")
    let parent = try await service.setTaskRecurrence(
      taskID: created.id,
      rule: TaskRecurrenceRule(freq: .daily, interval: 1))
    _ = try await service.completeTaskReturningTask(id: parent.id)
    let successorID = try service.read { db in
      try XCTUnwrap(
        String.fetchOne(
          db, sql: "SELECT recurrence_successor_id FROM tasks WHERE id = ?",
          arguments: [parent.id]))
    }
    let beforeRerootScheduleVersion = try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT spawned_from, schedule_version FROM tasks WHERE id = ?",
          arguments: [successorID]))
      XCTAssertEqual(row["spawned_from"] as String?, parent.id)
      return row["schedule_version"] as String
    }
    _ = try await service.archiveTask(id: parent.id)
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    try await service.deleteTask(id: parent.id)

    try service.read { db in
      let successor = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT spawned_from, schedule_version, version FROM tasks WHERE id = ?",
          arguments: [successorID]))
      XCTAssertNil(successor["spawned_from"] as String?)
      XCTAssertGreaterThan(successor["schedule_version"] as String, beforeRerootScheduleVersion)
      XCTAssertEqual(
        try Int64.fetchOne(
          db,
          sql: "SELECT register_intent FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?",
          arguments: [successorID]),
        TaskRegisterIntent.schedule.rawValue)
    }
  }

  func testTerminalTasksCannotCreateOrReplaceActiveReminders() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Terminal reminder guard", notes: "")
    _ = try await service.addTaskReminder(
      taskID: task.id, reminderAt: "2026-10-01T09:00:00Z")
    _ = try await service.completeTaskReturningTask(id: task.id)
    try service.write { db in
      try db.execute(sql: "DELETE FROM sync_outbox")
    }

    await XCTAssertThrowsErrorAsync(
      try await service.addTaskReminder(
        taskID: task.id, reminderAt: "2026-10-02T09:00:00Z"))
    await XCTAssertThrowsErrorAsync(
      try await service.setTaskReminders(
        taskID: task.id, reminderAts: ["2026-10-03T09:00:00Z"]))

    try service.read { db in
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_reminders WHERE task_id = ?",
          arguments: [task.id]),
        1)
      XCTAssertEqual(
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_reminders WHERE task_id = ? AND cancelled_at IS NULL",
          arguments: [task.id]),
        0)
      XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox"), 0)
    }
  }

  func testSomedayTaskMayRetainAnInactiveReminderForLaterReopen() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Someday reminder", notes: "")
    _ = try await service.markTaskSomeday(id: task.id)

    _ = try await service.addTaskReminder(
      taskID: task.id, reminderAt: "2026-10-04T09:00:00Z")

    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_reminders WHERE task_id = ? AND cancelled_at IS NULL",
          arguments: [task.id])
      },
      1)
  }

  func testImportRejectsActiveReminderForTerminalTaskButAllowsCancelledHistory() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Imported reminder guard", notes: "")
    _ = try await service.completeTaskReturningTask(id: task.id)

    await XCTAssertThrowsErrorAsync(
      try await service.importTaskReminder(
        taskID: task.id,
        reminder: ExportTaskReminder(
          id: "aaaaaaaa-aaaa-7aaa-8aaa-aaaaaaaaaaaa",
          reminderAt: "2026-10-05T09:00:00Z")))
    try await service.importTaskReminder(
      taskID: task.id,
      reminder: ExportTaskReminder(
        id: "bbbbbbbb-bbbb-7bbb-8bbb-bbbbbbbbbbbb",
        reminderAt: "2026-10-05T09:00:00Z",
        cancelledAt: "2026-10-04T09:00:00Z"))

    XCTAssertEqual(
      try service.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM task_reminders WHERE task_id = ?",
          arguments: [task.id])
      },
      1)
  }
}
