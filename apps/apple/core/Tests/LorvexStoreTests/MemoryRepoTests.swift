import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class MemoryRepoTests: XCTestCase {
  func testGetMemoryEntryReturnsNilForMissing() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.read { db in
      try MemoryRepo.getMemoryEntry(db, key: "missing")
    }
    XCTAssertNil(result)
  }

  func testGetMemoryEntryReturnsInsertedRow() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO memories (id, key, content, version, updated_at) \
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "mem-1", "favorite_color", "blue", "0000000000000_0000_0000000000000000",
          "2026-01-01T00:00:00.000Z",
        ])
    }
    let entry = try store.writer.read { db in
      try MemoryRepo.getMemoryEntry(db, key: "favorite_color")
    }
    let unwrapped = try XCTUnwrap(entry)
    XCTAssertEqual(unwrapped.key, "favorite_color")
    XCTAssertEqual(unwrapped.content, "blue")
    XCTAssertEqual(unwrapped.version, "0000000000000_0000_0000000000000000")
    XCTAssertEqual(unwrapped.updatedAt.asString, "2026-01-01T00:00:00.000Z")
  }
}
