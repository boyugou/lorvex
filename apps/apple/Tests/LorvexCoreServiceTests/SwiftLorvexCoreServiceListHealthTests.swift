import LorvexStore
import XCTest

@testable import LorvexCore

/// Service-level coverage for `getListHealthSnapshot` on `SwiftLorvexCoreService`,
/// against a temp store seeded with the authoritative `schema/schema.sql`:
/// archived lists must not resurface (archiving keeps their tasks but drops the
/// list from the active catalog), and rows must sort by open count descending as
/// the `get_list_health_snapshot` tool documents.
final class SwiftLorvexCoreServiceListHealthTests: XCTestCase {

  private func makeService() throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // LorvexCoreServiceTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // apple
      .deletingLastPathComponent()  // apps
      .deletingLastPathComponent()  // repo root
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store)
  }

  private func addOpenTasks(
    _ service: SwiftLorvexCoreService, listID: LorvexList.ID, count: Int, prefix: String
  ) async throws {
    for i in 0..<count {
      _ = try await service.createTask(TaskCreateDraft(title: "\(prefix)-\(i)", listID: listID))
    }
  }

  /// M6: the documented order is open-count descending. `low` is created before
  /// `high` (so a naive `created_at ASC` order would surface it first) yet holds
  /// fewer open tasks, so `high` must lead.
  /// M3: the archived list keeps its five open tasks in storage but must not
  /// appear in the snapshot at all.
  func testListHealthSnapshotHidesArchivedAndSortsByOpenCountDescending() async throws {
    let service = try makeService()

    let low = try await service.createList(
      name: "Low", description: nil, color: nil, icon: nil, aiNotes: nil)
    let high = try await service.createList(
      name: "High", description: nil, color: nil, icon: nil, aiNotes: nil)
    let archived = try await service.createList(
      name: "Archived", description: nil, color: nil, icon: nil, aiNotes: nil)

    try await addOpenTasks(service, listID: low.id, count: 1, prefix: "low")
    try await addOpenTasks(service, listID: high.id, count: 3, prefix: "high")
    try await addOpenTasks(service, listID: archived.id, count: 5, prefix: "arc")
    _ = try await service.archiveList(id: archived.id)

    let snapshot = try await service.getListHealthSnapshot()

    // M3: the archived list is gone; only the seeded `inbox` plus low/high remain.
    XCTAssertEqual(snapshot.totalLists, 3)
    XCTAssertFalse(snapshot.lists.contains { $0.id == archived.id })

    // M6: open-count-descending — `high` (3) leads `low` (1) despite being newer.
    let ordered = snapshot.lists.map { ($0.id, $0.openCount) }
    XCTAssertEqual(snapshot.lists.first?.id, high.id, "got \(ordered)")
    XCTAssertEqual(snapshot.lists.first?.openCount, 3)
    let lowIdx = snapshot.lists.firstIndex { $0.id == low.id }
    let highIdx = snapshot.lists.firstIndex { $0.id == high.id }
    XCTAssertNotNil(lowIdx, "low must be present; got \(ordered)")
    XCTAssertNotNil(highIdx, "high must be present; got \(ordered)")
    if let lowIdx, let highIdx {
      XCTAssertLessThan(highIdx, lowIdx, "high (3 open) must sort before low (1 open); got \(ordered)")
    }
  }
}
