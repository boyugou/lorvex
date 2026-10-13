import GRDB
import XCTest

@testable import LorvexCore

/// A task update whose every value is already the task's own writes nothing: no
/// new version, no sync upsert, no changelog row. A real change writes one of each.
final class TaskUpdateNoChangeTests: XCTestCase {
  private func counts(_ service: SwiftLorvexCoreService, taskID: String) throws -> (changelog: Int, outbox: Int, version: String) {
    try service.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE entity_id = ?", arguments: [taskID]) ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?", arguments: [taskID]) ?? -1,
        try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [taskID]) ?? ""
      )
    }
  }

  func testRestatingTheTaskWritesNothingAndAChangeWritesOnce() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let task = try await service.createTask(title: "Write report", notes: "Draft first")
    let created = try counts(service, taskID: task.id)

    // The same title and notes, no dependencies, and no tags: nothing differs.
    let same = try await service.updateTask(
      TaskUpdateDraft(id: task.id, title: "Write report", notes: "Draft first", tags: [], dependsOn: []))
    XCTAssertEqual(same.title, "Write report")
    let afterSame = try counts(service, taskID: task.id)
    XCTAssertEqual(afterSame.changelog, created.changelog, "no changelog row for no change")
    XCTAssertEqual(afterSame.outbox, created.outbox, "no sync upsert for no change")
    XCTAssertEqual(afterSame.version, created.version, "no new version for no change")

    let changed = try await service.updateTask(
      TaskUpdateDraft(id: task.id, notes: "Draft, then review"))
    XCTAssertEqual(changed.notes, "Draft, then review")
    let afterChange = try counts(service, taskID: task.id)
    XCTAssertEqual(afterChange.changelog, created.changelog + 1)
    XCTAssertNotEqual(afterChange.version, created.version)
  }
}
