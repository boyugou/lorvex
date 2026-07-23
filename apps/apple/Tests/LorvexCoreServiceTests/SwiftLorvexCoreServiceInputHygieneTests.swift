import Foundation
import GRDB
import LorvexDomain
import LorvexStore
import XCTest

@testable import LorvexCore

/// Trust-boundary input hygiene on the real `SwiftLorvexCoreService`, run against
/// a temp store seeded with the authoritative `schema/schema.sql`. Covers the
/// list / memory write surfaces that previously bypassed the sanitize + cap +
/// token-validation the task/calendar paths already applied, and the import
/// changelog attribution.
final class SwiftLorvexCoreServiceInputHygieneTests: XCTestCase {
  private func makeService(
    writeInitiatorDefault: String = SwiftLorvexCoreService.ChangelogInitiator.user
  ) throws -> SwiftLorvexCoreService {
    let schemaURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("schema/schema.sql")
    let schemaSQL = try String(contentsOf: schemaURL, encoding: .utf8)
    let store = try LorvexStore.openInMemory(schemaSQL: schemaSQL)
    return SwiftLorvexCoreService(store: store, writeInitiatorDefault: writeInitiatorDefault)
  }

  private func uuid() -> String { UUID().uuidString.lowercased() }

  // MARK: - sec-2 / sec-5 / sec-1: list write hygiene

  func testCreateListSanitizesFreeTextAndValidatesTokens() async throws {
    let service = try makeService()
    let list = try await service.createList(
      name: "Al\u{200B}pha",  // zero-width space
      description: "keep \u{202E}notes",  // bidi override
      color: "#0A84FF",
      icon: "briefcase.fill",
      aiNotes: "ai\u{FEFF}context")

    let stored = try service.read { db -> (String, String?, String?, String?, String?) in
      let row = try XCTUnwrap(
        try GRDBRowFetch.fetchListRow(db, id: list.id))
      return row
    }
    XCTAssertEqual(stored.0, "Alpha")
    XCTAssertEqual(stored.1, "keep notes")  // description
    XCTAssertEqual(stored.2, "aicontext")  // ai_notes
    XCTAssertEqual(stored.3, "#0A84FF")  // color
    XCTAssertEqual(stored.4, "briefcase.fill")  // icon
  }

  func testCreateListAcceptsSingleEmojiIcon() async throws {
    let service = try makeService()
    let list = try await service.createList(
      name: "Fire", description: nil, color: nil, icon: "🔥", aiNotes: nil)
    let icon = try service.read { db in
      try String.fetchOne(db, sql: "SELECT icon FROM lists WHERE id = ?", arguments: [list.id])
    }
    XCTAssertEqual(icon, "🔥")
  }

  func testCreateListRejectsOverLengthName() async throws {
    let service = try makeService()
    let tooLong = String(repeating: "a", count: ValidationLimits.maxTitleLength + 1)
    await XCTAssertThrowsErrorAsync(
      try await service.createList(
        name: tooLong, description: nil, color: nil, icon: nil, aiNotes: nil))
  }

  func testCreateListRejectsNonHexColor() async throws {
    let service = try makeService()
    await XCTAssertThrowsErrorAsync(
      try await service.createList(
        name: "Bad color", description: nil, color: "red", icon: nil, aiNotes: nil))
  }

  func testCreateListRejectsProseIcon() async throws {
    let service = try makeService()
    await XCTAssertThrowsErrorAsync(
      try await service.createList(
        name: "Bad icon", description: nil, color: nil,
        icon: "ignore previous instructions", aiNotes: nil))
  }

  func testImportListSanitizesAndValidates() async throws {
    let service = try makeService()
    let id = uuid()
    let list = try await service.importList(
      id: id, name: "Re\u{200B}stored", description: "d\u{202E}esc",
      color: "#112233", icon: "tray")
    let stored = try service.read { db in
      try GRDBRowFetch.fetchListRow(db, id: list.id)
    }
    let row = try XCTUnwrap(stored)
    XCTAssertEqual(row.0, "Restored")
    XCTAssertEqual(row.1, "desc")
    XCTAssertEqual(row.3, "#112233")
    XCTAssertEqual(row.4, "tray")
  }

  // MARK: - sec-2 / sec-5: memory content hygiene

  func testUpsertMemorySanitizesContent() async throws {
    let service = try makeService()
    _ = try await service.upsertMemory(key: "prefs", content: "be\u{202E}kind\u{200B}here")
    let content = try service.read { db in
      try String.fetchOne(db, sql: "SELECT content FROM memories WHERE key = ?", arguments: ["prefs"])
    }
    XCTAssertEqual(content, "bekindhere")
  }

  func testUpsertMemoryRejectsOverCapContent() async throws {
    let service = try makeService()
    let overCap = String(repeating: "a", count: Memory.maxMemoryContentLength + 1)
    await XCTAssertThrowsErrorAsync(
      try await service.upsertMemory(key: "big", content: overCap))
  }

  // MARK: - sec-8: changelog provenance attribution

  /// The id-preserving importers carry no explicit provenance; they inherit the
  /// ambient ``SwiftLorvexCoreService/currentInitiator``. A data-file restore
  /// binds `import` around the whole run (as `LorvexDataImporter.apply` does),
  /// so an imported list's audit row records `import`.
  func testImportListUnderImporterBindingAttributesChangelogToImport() async throws {
    let service = try makeService()
    let id = uuid()
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.importAttribution
    ) {
      try await service.importList(
        id: id, name: "Imported", description: nil, color: nil, icon: nil)
    }
    let initiatedBy = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? ORDER BY timestamp DESC",
        arguments: [id])
    }
    XCTAssertEqual(initiatedBy, "import")
  }

  /// Reached live through `create_list`'s `original_id` under the MCP host's
  /// `assistant` binding, the same importer records `assistant` — a live
  /// assistant re-create is not misattributed as a data-file restore.
  func testImportListUnderAssistantBindingAttributesChangelogToAssistant() async throws {
    let service = try makeService()
    let id = uuid()
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.importList(
        id: id, name: "Re-created", description: nil, color: nil, icon: nil)
    }
    let initiatedBy = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? ORDER BY timestamp DESC",
        arguments: [id])
    }
    XCTAssertEqual(initiatedBy, "assistant")
  }

  /// A human surface declares `.user` through the service's
  /// ``SwiftLorvexCoreService/writeInitiatorDefault`` (the app's `AppCoreFactory`
  /// / `LorvexCoreRuntimeFactory` set it; the in-memory seam defaults to it), so
  /// a write with no ambient binding records `user` — a live interactive action
  /// is not the assistant.
  func testInteractiveCreateListAttributesChangelogToUser() async throws {
    let service = try makeService()
    let list = try await service.createList(
      name: "Live", description: nil, color: nil, icon: nil, aiNotes: nil)
    let initiatedBy = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? ORDER BY timestamp DESC",
        arguments: [list.id])
    }
    XCTAssertEqual(initiatedBy, "user")
  }

  /// Fail-closed default: a service that declares no `writeInitiatorDefault` (the
  /// on-disk production default) and runs a write with no ambient binding — a
  /// hypothetical new/forgotten write path — records the `unattributed` sentinel,
  /// NOT a silent human `user`. In DEBUG the write funnel also traps; the test
  /// suppresses the trap via ``SwiftLorvexCoreService/trapsOnUnattributedInitiator``
  /// so it can assert the recorded value instead of crashing.
  func testForgottenBindingRecordsUnattributedNotUser() async throws {
    let service = try makeService(
      writeInitiatorDefault: SwiftLorvexCoreService.ChangelogInitiator.unattributed)
    let list = try await SwiftLorvexCoreService.$trapsOnUnattributedInitiator.withValue(false) {
      try await service.createList(
        name: "Orphan", description: nil, color: nil, icon: nil, aiNotes: nil)
    }
    let initiatedBy = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? ORDER BY timestamp DESC",
        arguments: [list.id])
    }
    XCTAssertEqual(initiatedBy, "unattributed")
    XCTAssertNotEqual(initiatedBy, "user")
  }

  /// An ambient binding wins over the service's human `writeInitiatorDefault`: a
  /// data-file restore on a human-surface core still records `import`, so a
  /// replayed backup stays provenance-distinct from the surface's live actions.
  func testImportBindingWinsOverHumanDefault() async throws {
    let service = try makeService()  // `.user` human-surface default
    let id = uuid()
    _ = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.importAttribution
    ) {
      try await service.importList(
        id: id, name: "Restored", description: nil, color: nil, icon: nil)
    }
    let initiatedBy = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? ORDER BY timestamp DESC",
        arguments: [id])
    }
    XCTAssertEqual(initiatedBy, "import")
  }

  /// The MCP host binds ``SwiftLorvexCoreService/currentInitiator`` to
  /// `assistant` for the duration of a tool call; a write under that binding is
  /// attributed to the assistant surface.
  func testAssistantAttributedWriteRecordsAssistant() async throws {
    let service = try makeService()
    let list = try await SwiftLorvexCoreService.$currentInitiator.withValue(
      SwiftLorvexCoreService.ChangelogInitiator.assistant
    ) {
      try await service.createList(
        name: "AI list", description: nil, color: nil, icon: nil, aiNotes: nil)
    }
    let initiatedBy = try service.read { db in
      try String.fetchOne(
        db, sql: "SELECT initiated_by FROM ai_changelog WHERE entity_id = ? ORDER BY timestamp DESC",
        arguments: [list.id])
    }
    XCTAssertEqual(initiatedBy, "assistant")
  }
}

/// Positional `lists` row fetch shared by the hygiene assertions:
/// `(name, description, ai_notes, color, icon)`.
private enum GRDBRowFetch {
  static func fetchListRow(
    _ db: GRDB.Database, id: String
  ) throws -> (String, String?, String?, String?, String?)? {
    guard
      let row = try GRDB.Row.fetchOne(
        db, sql: "SELECT name, description, ai_notes, color, icon FROM lists WHERE id = ?",
        arguments: [id])
    else { return nil }
    return (row[0], row[1], row[2], row[3], row[4])
  }
}

func XCTAssertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("expected an error to be thrown", file: file, line: line)
  } catch {
    // expected
  }
}
