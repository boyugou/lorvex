import Foundation
import GRDB
import XCTest

@testable import LorvexCore

final class WholeDataExportSnapshotTests: XCTestCase {
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

  private func withSharedServices(
    _ body: (SwiftLorvexCoreService, SwiftLorvexCoreService) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "lorvex-whole-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("lorvex.sqlite").path
    let schema = try schemaSQL()
    let source = SwiftLorvexCoreService(databasePath: path, schemaSQL: schema)
    let peer = SwiftLorvexCoreService(databasePath: path, schemaSQL: schema)
    _ = try await source.getSessionContext()
    _ = try await peer.getSessionContext()
    try await body(source, peer)
  }

  func testWholeExportCannotDuplicateOrOmitListAcrossArchiveBoundary() async throws {
    try await withSharedServices { source, peer in
      let list = try await source.createList(name: "Snapshot list", description: nil)
      let hookEntered = expectation(description: "active export partition read")
      let continueExport = DispatchSemaphore(value: 0)
      let exportTask = Task {
        try await SwiftLorvexCoreService.$afterActiveListsExportReadForTesting.withValue({
          hookEntered.fulfill()
          _ = continueExport.wait(timeout: .now() + 5)
        }) {
          try await source.exportData(entities: ["lists"], format: "json")
        }
      }

      await fulfillment(of: [hookEntered], timeout: 5)
      do {
        _ = try await peer.archiveList(id: list.id)
      } catch {
        continueExport.signal()
        throw error
      }
      continueExport.signal()

      let json = try await exportTask.value
      let payload = try JSONDecoder().decode(
        LorvexDataExportPayload.self, from: Data(json.utf8))
      let matching = try XCTUnwrap(payload.lists?.filter { $0.id == list.id })
      XCTAssertEqual(matching.count, 1)
      XCTAssertNil(matching[0].archivedAt)

      let freshJSON = try await source.exportData(entities: ["lists"], format: "json")
      let fresh = try JSONDecoder().decode(
        LorvexDataExportPayload.self, from: Data(freshJSON.utf8))
      XCTAssertNotNil(fresh.lists?.first { $0.id == list.id }?.archivedAt)
    }
  }

  func testWholeExportKeepsTaskAndParentListInSameSnapshot() async throws {
    try await withSharedServices { source, peer in
      let oldList = try await source.createList(name: "Old parent", description: nil)
      let newList = try await source.createList(name: "New parent", description: nil)
      let task = try await source.createTask(
        TaskCreateDraft(title: "Snapshot child", listID: oldList.id))
      let hookEntered = expectation(description: "native task roots read")
      let continueExport = DispatchSemaphore(value: 0)
      let exportTask = Task {
        try await SwiftLorvexCoreService.$afterNativeTaskRowsExportReadForTesting.withValue({
          hookEntered.fulfill()
          _ = continueExport.wait(timeout: .now() + 5)
        }) {
          try await source.exportData(entities: ["tasks", "lists"], format: "json")
        }
      }

      await fulfillment(of: [hookEntered], timeout: 5)
      do {
        try peer.write { db in
          try db.execute(
            sql: "UPDATE tasks SET list_id = ? WHERE id = ?",
            arguments: [newList.id, task.id])
          try db.execute(sql: "DELETE FROM lists WHERE id = ?", arguments: [oldList.id])
        }
      } catch {
        continueExport.signal()
        throw error
      }
      continueExport.signal()

      let json = try await exportTask.value
      let payload = try JSONDecoder().decode(
        LorvexDataExportPayload.self, from: Data(json.utf8))
      XCTAssertEqual(payload.tasks?.first { $0.id == task.id }?.listID, oldList.id)
      XCTAssertTrue(payload.lists?.contains { $0.id == oldList.id } == true)

      let freshJSON = try await source.exportData(
        entities: ["tasks", "lists"], format: "json")
      let fresh = try JSONDecoder().decode(
        LorvexDataExportPayload.self, from: Data(freshJSON.utf8))
      XCTAssertEqual(fresh.tasks?.first { $0.id == task.id }?.listID, newList.id)
      XCTAssertFalse(fresh.lists?.contains { $0.id == oldList.id } == true)
    }
  }
}
