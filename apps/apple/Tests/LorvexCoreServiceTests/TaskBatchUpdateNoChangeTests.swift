import GRDB
import XCTest

@testable import LorvexCore

/// A batch update writes only for the rows it changes. A row whose every supplied value is already
/// the task's own, or whose entry names no field, leaves no new version and no sync upsert, and a
/// batch that changed nothing leaves no changelog row. Every requested task still comes back, in
/// request order.
final class TaskBatchUpdateNoChangeTests: XCTestCase {
  private struct Counts: Equatable {
    var changelog: Int
    var outbox: Int
    var versions: [String]
  }

  private func counts(_ service: SwiftLorvexCoreService, taskIDs: [String]) throws -> Counts {
    try service.read { db in
      Counts(
        changelog: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog") ?? -1,
        outbox: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox") ?? -1,
        versions: try taskIDs.map {
          try String.fetchOne(db, sql: "SELECT version FROM tasks WHERE id = ?", arguments: [$0]) ?? ""
        })
    }
  }

  func testABatchOfRestatedValuesAndEmptyEntriesWritesNothing() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let first = try await service.createTask(title: "Write report", notes: "Draft first")
    let second = try await service.createTask(title: "Send invoice", notes: "")
    let ids = [first.id, second.id]
    let before = try counts(service, taskIDs: ids)

    let returned = try await service.batchUpdateTasks([
      TaskUpdateDraft(id: first.id, title: "Write report", notes: "Draft first"),
      TaskUpdateDraft(id: second.id),
    ])

    XCTAssertEqual(returned.map(\.id), ids, "every requested task comes back, in request order")
    XCTAssertEqual(try counts(service, taskIDs: ids), before, "nothing was written")
  }

  func testABatchWritesOnlyForTheRowsItChanges() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let unchanged = try await service.createTask(title: "Write report", notes: "Draft first")
    let changed = try await service.createTask(title: "Send invoice", notes: "")
    let ids = [unchanged.id, changed.id]
    let before = try counts(service, taskIDs: ids)

    let returned = try await service.batchUpdateTasks([
      TaskUpdateDraft(id: unchanged.id, notes: "Draft first"),
      TaskUpdateDraft(id: changed.id, notes: "Net 30"),
    ])

    XCTAssertEqual(returned.map(\.id), ids)
    XCTAssertEqual(returned[1].notes, "Net 30")
    let after = try counts(service, taskIDs: ids)
    XCTAssertEqual(after.versions[0], before.versions[0], "the restated row kept its version")
    XCTAssertNotEqual(after.versions[1], before.versions[1])
    XCTAssertEqual(after.changelog, before.changelog + 1, "one changelog row for the batch")
  }
}
