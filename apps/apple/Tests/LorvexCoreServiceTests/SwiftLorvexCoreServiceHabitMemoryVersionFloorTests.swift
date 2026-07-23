import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

final class SwiftLorvexCoreServiceHabitMemoryVersionFloorTests: XCTestCase {
  private static let futureA = "9000000000000_0000_aaaaaaaaaaaaaaaa"
  private static let futureB = "9000000000001_0000_bbbbbbbbbbbbbbbb"

  private static func seedIgnoringCheckConstraints<T>(
    _ db: Database, _ body: () throws -> T
  ) throws -> T {
    try db.execute(sql: "PRAGMA ignore_check_constraints = ON")
    do {
      let result = try body()
      try db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
      return result
    } catch {
      try? db.execute(sql: "PRAGMA ignore_check_constraints = OFF")
      throw error
    }
  }

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

  func testCompletionEditsAndDeleteDominateFutureCompositeRow() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Version-floor completion", cue: nil, icon: nil, color: nil, targetCount: 3,
      cadence: .daily, milestoneTarget: nil)
    let date = "2026-07-14"
    let futureA = Self.futureA
    let futureB = Self.futureB
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO habit_completions
            (habit_id, completed_date, value, version, created_at, updated_at)
          VALUES (?, ?, 1, ?, '2026-07-14T00:00:00.000Z', '2026-07-14T00:00:00.000Z')
          """,
        arguments: [habit.id, date, futureA])
      try db.execute(sql: "DELETE FROM sync_outbox")
      try db.execute(sql: "DELETE FROM ai_changelog")
    }

    _ = try await service.completeHabit(id: habit.id, date: date)

    let futureAHlc = try Hlc.parse(futureA)
    let incrementedVersion = try service.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT version FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
        arguments: [habit.id, date])
    }
    XCTAssertGreaterThan(try Hlc.parse(try XCTUnwrap(incrementedVersion)), futureAHlc)

    try service.write { db in
      try db.execute(
        sql: "UPDATE habit_completions SET value = 1, version = ? "
          + "WHERE habit_id = ? AND completed_date = ?",
        arguments: [futureB, habit.id, date])
      try db.execute(sql: "DELETE FROM sync_outbox")
    }
    _ = try await service.adjustHabitCompletion(id: habit.id, date: date, delta: -1)

    let rowCount = try service.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM habit_completions WHERE habit_id = ? AND completed_date = ?",
        arguments: [habit.id, date]) ?? 0
    }
    XCTAssertEqual(rowCount, 0)
    let delete = try XCTUnwrap(
      service.pendingOutbound().first {
        $0.envelope.entityType == .habitCompletion
          && $0.envelope.entityId == "\(habit.id):\(date)"
      })
    XCTAssertEqual(delete.envelope.operation, .delete)
    XCTAssertGreaterThan(delete.envelope.version, try Hlc.parse(futureB))
  }

  func testBatchCompletionUsesPerRowFloorsAndRollsBackOnMalformedSecondFloor() async throws {
    let service = try makeService()
    let first = try await service.createHabit(
      name: "Batch floor one", cue: nil, icon: nil, color: nil, targetCount: 3,
      cadence: .daily, milestoneTarget: nil)
    let second = try await service.createHabit(
      name: "Batch floor two", cue: nil, icon: nil, color: nil, targetCount: 3,
      cadence: .daily, milestoneTarget: nil)
    let date = "2026-07-15"
    let futureA = Self.futureA
    let futureB = Self.futureB
    try service.write { db in
      try Self.seedIgnoringCheckConstraints(db) {
        for (id, version) in [(first.id, futureA), (second.id, "not-an-hlc")] {
          try db.execute(
            sql: """
              INSERT INTO habit_completions
                (habit_id, completed_date, value, version, created_at, updated_at)
              VALUES (?, ?, 1, ?, '2026-07-15T00:00:00.000Z', '2026-07-15T00:00:00.000Z')
              """,
            arguments: [id, date, version])
        }
      }
      try db.execute(sql: "DELETE FROM sync_outbox")
      try db.execute(sql: "DELETE FROM ai_changelog")
    }

    do {
      _ = try await service.batchCompleteHabits(ids: [first.id, second.id], date: date)
      XCTFail("a malformed stored version must fail the whole batch")
    } catch let error as StoreError {
      guard case .invariant = error else {
        return XCTFail("unexpected store error: \(error)")
      }
    }

    let afterFailure = try service.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT habit_id, value, version FROM habit_completions "
          + "WHERE completed_date = ? ORDER BY habit_id",
        arguments: [date])
    }
    XCTAssertEqual(afterFailure.map { $0["value"] as Int }, [1, 1])
    XCTAssertEqual(Set(afterFailure.map { $0["version"] as String }), Set([futureA, "not-an-hlc"]))
    XCTAssertTrue(try service.pendingOutbound().isEmpty)

    try service.write { db in
      try db.execute(
        sql: "UPDATE habit_completions SET version = ? WHERE habit_id = ? AND completed_date = ?",
        arguments: [futureB, second.id, date])
    }
    _ = try await service.batchCompleteHabits(ids: [first.id, second.id], date: date)

    let versions = try service.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT habit_id, value, version FROM habit_completions "
          + "WHERE completed_date = ? ORDER BY habit_id",
        arguments: [date])
    }
    XCTAssertEqual(versions.map { $0["value"] as Int }, [2, 2])
    let floors = [first.id: try Hlc.parse(futureA), second.id: try Hlc.parse(futureB)]
    for row in versions {
      let id: String = row["habit_id"]
      XCTAssertGreaterThan(try Hlc.parse(row["version"] as String), try XCTUnwrap(floors[id]))
    }
  }

  func testHabitAndReminderPolicyRestoreDominateFutureRows() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Old habit", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily, milestoneTarget: nil)
    let createdPolicy = try await service.upsertHabitReminderPolicy(
      id: habit.id,
      policy: HabitReminderPolicy(
        id: "", habitID: habit.id, habitName: habit.name, reminderTime: "07:00",
        enabled: true, createdAt: "", updatedAt: ""))
    let futureA = Self.futureA
    let futureB = Self.futureB
    try service.write { db in
      try db.execute(
        sql: "UPDATE habits SET version = ? WHERE id = ?", arguments: [futureA, habit.id])
      try db.execute(
        sql: "UPDATE habit_reminder_policies SET version = ? WHERE id = ?",
        arguments: [futureB, createdPolicy.id])
      try db.execute(sql: "DELETE FROM sync_outbox")
      try db.execute(sql: "DELETE FROM ai_changelog")
    }

    let imported = try await service.importHabit(
      id: habit.id, name: "Restored habit", icon: nil, color: nil, cue: nil,
      frequencyType: "daily", weekdays: [], perPeriodTarget: nil, dayOfMonth: nil,
      targetCount: 2, milestoneTarget: nil, archived: false, position: 4)
    XCTAssertEqual(imported.name, "Restored habit")

    try await service.importHabitReminderPolicy(
      habitID: habit.id,
      policy: ExportHabitReminderPolicy(
        id: createdPolicy.id, reminderTime: "08:15", enabled: false,
        createdAt: "2026-01-01T00:00:00.000Z", updatedAt: "2026-07-14T00:00:00.000Z"))

    let rows = try service.read { db in
      (
        try Row.fetchOne(db, sql: "SELECT name, version FROM habits WHERE id = ?", arguments: [habit.id]),
        try Row.fetchOne(
          db,
          sql: "SELECT reminder_time, enabled, version FROM habit_reminder_policies WHERE id = ?",
          arguments: [createdPolicy.id])
      )
    }
    let habitRow = try XCTUnwrap(rows.0)
    let policyRow = try XCTUnwrap(rows.1)
    XCTAssertEqual(habitRow["name"] as String, "Restored habit")
    XCTAssertGreaterThan(try Hlc.parse(habitRow["version"] as String), try Hlc.parse(futureA))
    XCTAssertEqual(policyRow["reminder_time"] as String, "08:15")
    XCTAssertEqual(policyRow["enabled"] as Int, 0)
    XCTAssertGreaterThan(try Hlc.parse(policyRow["version"] as String), try Hlc.parse(futureB))
  }

  func testNormalPolicyEditAndBothMemoryImportPathsDominateFutureRows() async throws {
    let service = try makeService()
    let habit = try await service.createHabit(
      name: "Policy floor", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: .daily, milestoneTarget: nil)
    let policy = try await service.upsertHabitReminderPolicy(
      id: habit.id,
      policy: HabitReminderPolicy(
        id: "", habitID: habit.id, habitName: habit.name, reminderTime: "06:00",
        enabled: true, createdAt: "", updatedAt: ""))
    _ = try await service.upsertMemory(key: "restore-key", content: "old")
    let memoryID = try service.read { db in
      try String.fetchOne(db, sql: "SELECT id FROM memories WHERE key = 'restore-key'")
    }
    let futureA = Self.futureA
    let futureB = Self.futureB
    try service.write { db in
      try db.execute(
        sql: "UPDATE habit_reminder_policies SET version = ? WHERE id = ?",
        arguments: [futureA, policy.id])
      try db.execute(
        sql: "UPDATE memories SET version = ? WHERE key = 'restore-key'", arguments: [futureB])
      try db.execute(sql: "DELETE FROM sync_outbox")
      try db.execute(sql: "DELETE FROM ai_changelog")
    }

    let editedPolicy = try await service.upsertHabitReminderPolicy(
      id: habit.id,
      policy: HabitReminderPolicy(
        id: policy.id, habitID: habit.id, habitName: habit.name, reminderTime: "06:30",
        enabled: false, createdAt: policy.createdAt, updatedAt: policy.updatedAt))
    XCTAssertEqual(editedPolicy.reminderTime, "06:30")

    let normal = try await service.upsertMemory(key: "restore-key", content: "normal edit")
    XCTAssertEqual(normal.content, "normal edit")

    try service.write { db in
      try db.execute(
        sql: "UPDATE memories SET version = ? WHERE key = 'restore-key'", arguments: [futureB])
    }
    let simpleImport = try await service.importMemoryEntry(
      key: "restore-key", content: "simple restore", updatedAt: "2026-07-14T12:00:00.000Z")
    XCTAssertEqual(simpleImport.content, "simple restore")

    try service.write { db in
      try db.execute(
        sql: "UPDATE memories SET version = ? WHERE key = 'restore-key'", arguments: [futureB])
    }
    let nativeImport = try await service.importMemoryEntry(
      ExportMemoryEntry(
        id: try XCTUnwrap(memoryID), key: "restore-key", content: "native restore",
        updatedAt: "2026-07-14T13:00:00.000Z"))
    XCTAssertEqual(nativeImport.content, "native restore")

    let finalRows = try service.read { db in
      (
        try String.fetchOne(
          db, sql: "SELECT version FROM habit_reminder_policies WHERE id = ?",
          arguments: [policy.id]),
        try String.fetchOne(db, sql: "SELECT version FROM memories WHERE key = 'restore-key'")
      )
    }
    XCTAssertGreaterThan(try Hlc.parse(try XCTUnwrap(finalRows.0)), try Hlc.parse(futureA))
    XCTAssertGreaterThan(try Hlc.parse(try XCTUnwrap(finalRows.1)), try Hlc.parse(futureB))
  }
}
