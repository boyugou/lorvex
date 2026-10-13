import GRDB
import LorvexDomain
import LorvexStore
import LorvexSync
import XCTest

@testable import LorvexCore

/// A parent's inbound delete that loses to a newer local row leaves the parent
/// and its children here, while peers that applied the delete dropped the
/// children. The device then re-emits each child at a new version so the parent
/// upsert that outlives the delete reaches those peers with its children.
final class ChildReassertAfterLostDeleteTests: XCTestCase {
  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appending(path: "schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(
      schemaSQL: schemaSQL, migrations: try SwiftLorvexCoreService.resolveSchemaMigrations())
    return SwiftLorvexCoreService(store: store)
  }

  private let taskId = "00000000-0000-7000-8000-0000000000f1"
  private let itemId = "00000000-0000-7000-8000-0000000000c1"
  private let localVersion = "1711234570000_0000_dec0000400000004"
  private let deleteVersion = "1711234569000_0000_dec0000300000003"

  func testLosingTaskDeleteReassertsItsChecklistItemAtANewVersion() throws {
    let service = try makeService()
    let (taskId, itemId, localVersion) = (self.taskId, self.itemId, self.localVersion)
    try service.write { db in
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, status, list_id, version, created_at, updated_at, defer_count)
          VALUES (?, 'X', 'open', 'inbox', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z', 0)
          """,
        arguments: [taskId, localVersion])
      try db.execute(
        sql: """
          INSERT INTO task_checklist_items (id, task_id, position, text, version, created_at, updated_at)
          VALUES (?, ?, 0, 'step', ?, '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [itemId, taskId, localVersion])
    }
    // Start from an empty outbox so only the re-emission shows.
    let before = try service.pendingOutbound().count
    let delete = SyncEnvelope(
      entityType: .task, entityId: taskId, operation: .delete,
      version: try Hlc.parse(deleteVersion),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"version\":\"\(deleteVersion)\"}", deviceId: "device-remote")

    let report = try service.applyInbound([delete], undecodable: 0)

    XCTAssertEqual(report.skipped, 1, "the older delete loses to the local row")
    let pending = try service.pendingOutbound().map(\.envelope)
    let item = pending.first { $0.entityType == .taskChecklistItem && $0.entityId == itemId }
    XCTAssertNotNil(item, "the checklist item is re-emitted (outbox had \(before) before)")
    if let item {
      XCTAssertGreaterThan(item.version, try Hlc.parse(localVersion), "at a version above its stored one")
    }
  }

  func testLosingHabitDeleteReassertsItsCompletionsAtANewVersion() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let habit = try await service.createHabit(
      name: "Read", cue: nil, icon: nil, color: nil, targetCount: 1,
      cadence: HabitCadenceInput(frequencyType: "daily"), milestoneTarget: nil)
    let day = LorvexDateFormatters.ymd.string(from: Date())
    _ = try await service.completeHabit(id: habit.id, date: day)
    // Empty the outbox so only the re-emission shows.
    let queued = try service.pendingOutbound()
    try service.markOutboundSynced(outboxIds: queued.map(\.outboxId))
    let completionKey = "\(habit.id):\(day)"

    // A delete older than every local row loses to them.
    let oldDelete = "1711234569000_0000_dec0000300000003"
    let delete = SyncEnvelope(
      entityType: .habit, entityId: habit.id, operation: .delete,
      version: try Hlc.parse(oldDelete),
      payloadSchemaVersion: LorvexVersion.payloadSchemaVersion,
      payload: "{\"version\":\"\(oldDelete)\"}", deviceId: "device-remote")
    let report = try service.applyInbound([delete], undecodable: 0)

    XCTAssertEqual(report.skipped, 1, "the older delete loses to the local habit")
    let pending = try service.pendingOutbound().map(\.envelope)
    XCTAssertNotNil(
      pending.first { $0.entityType == .habitCompletion && $0.entityId == completionKey },
      "the completion is re-emitted for peers that cascaded it away")
  }
}
