import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceTaskChildFutureHlcTests: XCTestCase {
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

  private func futureVersion(day: UInt64, counter: UInt32 = 0) throws -> String {
    let now = UInt64(Date().timeIntervalSince1970 * 1000)
    return try Hlc(
      physicalMs: now + day * 24 * 60 * 60 * 1000,
      counter: counter,
      deviceSuffix: "ffffffffffffffff"
    ).description
  }

  private static func assertDominates(
    _ actual: String?,
    _ floor: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let actual = try XCTUnwrap(actual, file: file, line: line)
    XCTAssertGreaterThan(
      try Hlc.parse(actual), try Hlc.parse(floor), file: file, line: line)
  }

  func testReminderRemoveAndReplaceDominateChildFloorsWithoutTouchingParent() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Future reminders", notes: "")
    let seeded = try await service.setTaskReminders(
      taskID: task.id,
      reminderAts: ["2026-08-01T09:00:00Z", "2026-08-02T09:00:00Z"])
    XCTAssertEqual(seeded.reminders.count, 2)
    let ids = seeded.reminders.map(\.id).sorted()
    let firstFloor = try futureVersion(day: 8, counter: 1)
    let secondFloor = try futureVersion(day: 12, counter: 2)
    let parentFloor = try futureVersion(day: 15, counter: 3)
    try service.write { db in
      try db.execute(
        sql: "UPDATE task_reminders SET version = ? WHERE id = ?",
        arguments: [firstFloor, ids[0]])
      try db.execute(
        sql: "UPDATE task_reminders SET version = ? WHERE id = ?",
        arguments: [secondFloor, ids[1]])
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: [parentFloor, task.id])
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.task, task.id])
    }

    let replaced = try await service.setTaskReminders(
      taskID: task.id,
      reminderAts: ["2026-08-03T09:00:00Z"])
    XCTAssertEqual(replaced.reminders.count, 1)
    try service.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT id, cancelled_at, version FROM task_reminders WHERE id IN (?, ?)",
        arguments: [ids[0], ids[1]])
      XCTAssertEqual(rows.count, 2)
      let versions = Dictionary(
        uniqueKeysWithValues: rows.map { ($0["id"] as String, $0["version"] as String) })
      XCTAssertTrue(rows.allSatisfy { ($0["cancelled_at"] as String?) != nil })
      try Self.assertDominates(versions[ids[0]], firstFloor)
      try Self.assertDominates(versions[ids[1]], secondFloor)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id]),
        parentFloor)
      XCTAssertNil(
        try Self.pendingOutboxVersion(db, entityType: EntityName.task, entityID: task.id))
    }

    let activeID = try XCTUnwrap(replaced.reminders.first?.id)
    let removeFloor = try futureVersion(day: 20, counter: 4)
    let removeParentFloor = try futureVersion(day: 22, counter: 5)
    try service.write { db in
      try db.execute(
        sql: "UPDATE task_reminders SET version = ? WHERE id = ?",
        arguments: [removeFloor, activeID])
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: [removeParentFloor, task.id])
    }
    let removed = try await service.removeTaskReminder(taskID: task.id, reminderID: activeID)
    XCTAssertTrue(removed.reminders.isEmpty)
    try service.read { db in
      try Self.assertDominates(
        try String.fetchOne(
          db, sql: "SELECT version FROM task_reminders WHERE id = ?", arguments: [activeID]),
        removeFloor)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id]),
        removeParentFloor)
      XCTAssertNil(
        try Self.pendingOutboxVersion(db, entityType: EntityName.task, entityID: task.id))
    }
  }

  func testTimezoneRematerializationDominatesReminderFloorWithoutTouchingParent() async throws {
    let service = try makeService()
    _ = try await service.setPreference(key: PreferenceKeys.prefTimezone, value: "UTC")
    let task = try await service.createTask(title: "Anchored reminder", notes: "")
    let reminded = try await service.addTaskReminder(
      taskID: task.id, reminderAt: "2026-08-10T09:00:00Z")
    let reminderID = try XCTUnwrap(reminded.reminders.first?.id)
    let reminderFloor = try futureVersion(day: 9, counter: 10)
    let parentFloor = try futureVersion(day: 13, counter: 11)
    try service.write { db in
      try db.execute(
        sql: "UPDATE task_reminders SET version = ? WHERE id = ?",
        arguments: [reminderFloor, reminderID])
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: [parentFloor, task.id])
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.task, task.id])
    }

    _ = try await service.setPreference(
      key: PreferenceKeys.prefTimezone, value: "America/Los_Angeles")

    try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT original_tz, version FROM task_reminders WHERE id = ?",
          arguments: [reminderID]))
      XCTAssertEqual(row["original_tz"] as String?, "America/Los_Angeles")
      try Self.assertDominates(row["version"] as String?, reminderFloor)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id]),
        parentFloor)
      XCTAssertNil(
        try Self.pendingOutboxVersion(db, entityType: EntityName.task, entityID: task.id))
    }
  }

  func testChildImportsDominateExistingRowsWithoutTouchingParent() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Import children", notes: "")
    let reminderID = UUID().uuidString.lowercased()
    let checklistID = UUID().uuidString.lowercased()
    try await service.importTaskReminder(
      taskID: task.id,
      reminder: ExportTaskReminder(id: reminderID, reminderAt: "2026-09-01T08:00:00Z"))
    try await service.importTaskChecklistItem(
      taskID: task.id,
      item: ExportChecklistItem(id: checklistID, position: 0, text: "Old", completed: false))

    let reminderFloor = try futureVersion(day: 10, counter: 20)
    let checklistFloor = try futureVersion(day: 14, counter: 21)
    let parentFloor = try futureVersion(day: 18, counter: 22)
    try service.write { db in
      try db.execute(
        sql: "UPDATE task_reminders SET version = ? WHERE id = ?",
        arguments: [reminderFloor, reminderID])
      try db.execute(
        sql: "UPDATE task_checklist_items SET version = ? WHERE id = ?",
        arguments: [checklistFloor, checklistID])
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: [parentFloor, task.id])
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.task, task.id])
    }

    try await service.importTaskReminder(
      taskID: task.id,
      reminder: ExportTaskReminder(id: reminderID, reminderAt: "2026-09-02T08:00:00Z"))
    try await service.importTaskChecklistItem(
      taskID: task.id,
      item: ExportChecklistItem(
        id: checklistID, position: 0, text: "New", completed: true,
        completedAt: "2026-09-02T08:30:00Z"))

    try service.read { db in
      let reminder = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT reminder_at, version FROM task_reminders WHERE id = ?",
          arguments: [reminderID]))
      XCTAssertEqual(reminder["reminder_at"] as String?, "2026-09-02T08:00:00.000Z")
      try Self.assertDominates(reminder["version"] as String?, reminderFloor)
      let item = try XCTUnwrap(
        Row.fetchOne(
          db, sql: "SELECT text, completed_at, version FROM task_checklist_items WHERE id = ?",
          arguments: [checklistID]))
      XCTAssertEqual(item["text"] as String?, "New")
      XCTAssertNotNil(item["completed_at"] as String?)
      try Self.assertDominates(item["version"] as String?, checklistFloor)
      XCTAssertEqual(
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [task.id]),
        parentFloor)
      XCTAssertNil(
        try Self.pendingOutboxVersion(db, entityType: EntityName.task, entityID: task.id))
    }
  }

  func testEveryChecklistMutationDominatesItemFloorsWithoutTouchingParent() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Checklist floors", notes: "")
    var loaded = try await service.addTaskChecklistItem(taskID: task.id, text: "A")
    loaded = try await service.addTaskChecklistItem(taskID: task.id, text: "B")
    let aID = try XCTUnwrap(loaded.checklistItems.first { $0.text == "A" }?.id)
    let bID = try XCTUnwrap(loaded.checklistItems.first { $0.text == "B" }?.id)

    let addAFloor = try futureVersion(day: 5, counter: 30)
    let addBFloor = try futureVersion(day: 7, counter: 31)
    let addParentFloor = try futureVersion(day: 9, counter: 32)
    try stampChecklistFloors(
      service, taskID: task.id,
      itemFloors: [aID: addAFloor, bID: addBFloor],
      parentFloor: addParentFloor)
    loaded = try await service.addTaskChecklistItem(taskID: task.id, text: "C")
    let cID = try XCTUnwrap(loaded.checklistItems.first { $0.text == "C" }?.id)
    try assertChecklistVersions(
      service, taskID: task.id,
      itemFloors: [aID: addAFloor, bID: addBFloor],
      parentFloor: addParentFloor)

    let updateFloor = try futureVersion(day: 11, counter: 33)
    let updateParentFloor = try futureVersion(day: 13, counter: 34)
    try stampChecklistFloors(
      service, taskID: task.id, itemFloors: [aID: updateFloor],
      parentFloor: updateParentFloor)
    loaded = try await service.updateTaskChecklistItem(itemID: aID, text: "A updated")
    XCTAssertEqual(loaded.checklistItems.first { $0.id == aID }?.text, "A updated")
    try assertChecklistVersions(
      service, taskID: task.id, itemFloors: [aID: updateFloor],
      parentFloor: updateParentFloor)

    let toggleFloor = try futureVersion(day: 15, counter: 35)
    let toggleParentFloor = try futureVersion(day: 17, counter: 36)
    try stampChecklistFloors(
      service, taskID: task.id, itemFloors: [aID: toggleFloor],
      parentFloor: toggleParentFloor)
    loaded = try await service.toggleTaskChecklistItem(itemID: aID, completed: true)
    XCTAssertNotNil(loaded.checklistItems.first { $0.id == aID }?.completedAt)
    try assertChecklistVersions(
      service, taskID: task.id, itemFloors: [aID: toggleFloor],
      parentFloor: toggleParentFloor)

    let reorderAFloor = try futureVersion(day: 19, counter: 37)
    let reorderBFloor = try futureVersion(day: 21, counter: 38)
    let reorderCFloor = try futureVersion(day: 23, counter: 39)
    let reorderParentFloor = try futureVersion(day: 25, counter: 40)
    try stampChecklistFloors(
      service, taskID: task.id,
      itemFloors: [aID: reorderAFloor, bID: reorderBFloor, cID: reorderCFloor],
      parentFloor: reorderParentFloor)
    loaded = try await service.reorderTaskChecklistItems(taskID: task.id, itemIDs: [cID, bID, aID])
    XCTAssertEqual(loaded.checklistItems.sorted { $0.position < $1.position }.map(\.id), [cID, bID, aID])
    try assertChecklistVersions(
      service, taskID: task.id,
      itemFloors: [aID: reorderAFloor, bID: reorderBFloor, cID: reorderCFloor],
      parentFloor: reorderParentFloor)

    let removeAFloor = try futureVersion(day: 27, counter: 41)
    let removeBFloor = try futureVersion(day: 29, counter: 42)
    let removeCFloor = try futureVersion(day: 31, counter: 43)
    let removeParentFloor = try futureVersion(day: 33, counter: 44)
    try stampChecklistFloors(
      service, taskID: task.id,
      itemFloors: [aID: removeAFloor, bID: removeBFloor, cID: removeCFloor],
      parentFloor: removeParentFloor)
    loaded = try await service.removeTaskChecklistItem(itemID: bID)
    XCTAssertFalse(loaded.checklistItems.contains { $0.id == bID })
    try assertChecklistVersions(
      service, taskID: task.id,
      itemFloors: [aID: removeAFloor, cID: removeCFloor],
      parentFloor: removeParentFloor)
    try service.read { db in
      let tombstoneVersion = try String.fetchOne(
        db,
        sql: "SELECT version FROM sync_tombstones WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.taskChecklistItem, bID])
      let outboxVersion = try Self.pendingOutboxVersion(
        db, entityType: EntityName.taskChecklistItem, entityID: bID)
      try Self.assertDominates(tombstoneVersion, removeBFloor)
      try Self.assertDominates(outboxVersion, removeBFloor)
      XCTAssertEqual(tombstoneVersion, outboxVersion)
    }
  }

  func testTopLevelRetryUsesCounterHeadroomAtOperationalWireCeiling() async throws {
    let service = try makeService()
    let task = try await service.createTask(title: "Canonical ceiling", notes: "")
    let floor = try Hlc(
      physicalMs: Hlc.maxOperationalWirePhysicalMs,
      counter: Hlc.maxCounter - 100,
      deviceSuffix: "ffffffffffffffff"
    ).description
    try service.write { db in
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: [floor, task.id])
    }

    _ = try await service.completeTask(id: task.id)

    try service.read { db in
      let row = try XCTUnwrap(
        Row.fetchOne(
          db,
          sql: "SELECT status, version FROM tasks WHERE id = ?",
          arguments: [task.id]))
      XCTAssertEqual(row["status"] as String?, StatusName.completed)
      try Self.assertDominates(row["version"] as String?, floor)
    }
  }

  private func stampChecklistFloors(
    _ service: SwiftLorvexCoreService,
    taskID: String,
    itemFloors: [String: String],
    parentFloor: String
  ) throws {
    try service.write { db in
      for (id, floor) in itemFloors {
        try db.execute(
          sql: "UPDATE task_checklist_items SET version = ? WHERE id = ?",
          arguments: [floor, id])
      }
      try db.execute(
        sql: "UPDATE tasks SET version = ? WHERE id = ?",
        arguments: [parentFloor, taskID])
      try db.execute(
        sql: "DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?",
        arguments: [EntityName.task, taskID])
    }
  }

  private func assertChecklistVersions(
    _ service: SwiftLorvexCoreService,
    taskID: String,
    itemFloors: [String: String],
    parentFloor: String
  ) throws {
    try service.read { db in
      for (id, floor) in itemFloors {
        let rowVersion = try String.fetchOne(
          db, sql: "SELECT version FROM task_checklist_items WHERE id = ?", arguments: [id])
        try Self.assertDominates(
          rowVersion, floor)
        XCTAssertEqual(
          try Self.pendingOutboxVersion(
            db, entityType: EntityName.taskChecklistItem, entityID: id),
          rowVersion)
      }
      let parentVersion = try String.fetchOne(
        db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskID])
      XCTAssertEqual(parentVersion, parentFloor)
      XCTAssertNil(
        try Self.pendingOutboxVersion(db, entityType: EntityName.task, entityID: taskID))
    }
  }

  private static func pendingOutboxVersion(
    _ db: Database, entityType: String, entityID: String
  ) throws -> String? {
    try String.fetchOne(
      db,
      sql: """
        SELECT version FROM sync_outbox
        WHERE entity_type = ? AND entity_id = ? AND synced_at IS NULL
        """,
      arguments: [entityType, entityID])
  }
}
