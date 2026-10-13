import GRDB
import XCTest

@testable import LorvexCore

/// Setting a list's AI notes to what they already are writes nothing: no new
/// version, no sync upsert, no changelog row. A different value writes one of each.
final class ListAINotesNoChangeTests: XCTestCase {
  private func counts(_ service: SwiftLorvexCoreService, listID: String) throws -> (changelog: Int, outbox: Int, version: String) {
    try service.read { db in
      (
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ai_changelog WHERE entity_id = ?", arguments: [listID]) ?? -1,
        try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?", arguments: [listID]) ?? -1,
        try String.fetchOne(db, sql: "SELECT version FROM lists WHERE id = ?", arguments: [listID]) ?? ""
      )
    }
  }

  func testRestatingTheNotesWritesNothingAndANewValueWritesOnce() async throws {
    let service = try SwiftLorvexCoreService.inMemory()
    let list = try await service.createList(name: "Project", description: nil, color: nil, icon: nil)
    _ = try await service.setListAINotes(id: list.id, notes: "Prefers short updates.")
    let set = try counts(service, listID: list.id)

    let same = try await service.setListAINotes(id: list.id, notes: "Prefers short updates.")
    XCTAssertEqual(same.aiNotes, "Prefers short updates.")
    let afterSame = try counts(service, listID: list.id)
    XCTAssertEqual(afterSame.changelog, set.changelog)
    XCTAssertEqual(afterSame.outbox, set.outbox)
    XCTAssertEqual(afterSame.version, set.version)

    _ = try await service.setListAINotes(id: list.id, notes: "Prefers long updates.")
    let changed = try counts(service, listID: list.id)
    XCTAssertEqual(changed.changelog, set.changelog + 1)
    XCTAssertNotEqual(changed.version, set.version)
  }
}
