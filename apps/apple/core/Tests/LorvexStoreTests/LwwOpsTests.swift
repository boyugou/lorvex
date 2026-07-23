import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class LwwOpsTests: XCTestCase {
  private static let v1 = "0000000000001_0000_a0a0a0a0a0a0a0a0"
  private static let v2 = "0000000000002_0000_a0a0a0a0a0a0a0a0"
  private static let v3 = "0000000000003_0000_a0a0a0a0a0a0a0a0"
  private static let now1 = "2026-04-03T00:00:00.000Z"
  private static let now2 = "2026-04-03T00:00:01.000Z"

  private func seedList(_ store: LorvexStore, id: String = "l1") throws {
    try store.writer.write { db in
      _ = try ListRepo.createList(
        db, id: ListId(trusted: id), name: "Seed", version: Self.v1)
    }
  }

  func testExecuteUpdateCommitsAndAdvancesVersion() throws {
    let store = try TestSupport.freshStore()
    try seedList(store)
    try store.writer.write { db in
      try LwwOps.executeUpdate(
        db,
        table: "lists",
        entity: EntityKind.list.rawValue,
        id: "l1",
        version: Self.v2,
        setClauses: ["name = ?", "version = ?", "updated_at = ?"],
        bindings: ["Renamed", Self.v2, Self.now2])
    }
    let row = try store.writer.read { db in
      try ListRepo.getList(db, id: ListId(trusted: "l1"))
    }
    XCTAssertEqual(row?.name, "Renamed")
    XCTAssertEqual(row?.version, Self.v2)
  }

  func testExecuteUpdateThrowsStaleVersionWhenVersionNotNewer() throws {
    let store = try TestSupport.freshStore()
    try seedList(store)
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LwwOps.executeUpdate(
          db,
          table: "lists",
          entity: EntityKind.list.rawValue,
          id: "l1",
          version: Self.v1,
          setClauses: ["name = ?", "version = ?", "updated_at = ?"],
          bindings: ["Renamed", Self.v1, Self.now2])
      }
    ) { error in
      guard case StoreError.staleVersion(let entity, let id) = error else {
        return XCTFail("expected staleVersion, got \(error)")
      }
      XCTAssertEqual(entity, "list")
      XCTAssertEqual(id, "l1")
    }
  }

  func testExecuteUpdateThrowsStaleVersionWhenRowAbsent() throws {
    // Rust contract: absent row is indistinguishable from stale miss. Both
    // produce staleVersion. No existence probe.
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try LwwOps.executeUpdate(
          db,
          table: "lists",
          entity: EntityKind.list.rawValue,
          id: "missing",
          version: Self.v2,
          setClauses: ["name = ?", "version = ?", "updated_at = ?"],
          bindings: ["X", Self.v2, Self.now2])
      }
    ) { error in
      guard case StoreError.staleVersion = error else {
        return XCTFail("expected staleVersion, got \(error)")
      }
    }
  }

  func testExecuteDeleteByIdReturnsOneOnSuccess() throws {
    let store = try TestSupport.freshStore()
    try seedList(store)
    let n = try store.writer.write { db in
      try LwwOps.executeDeleteById(
        db,
        table: "lists",
        entity: EntityKind.list.rawValue,
        id: "l1",
        version: Self.v2)
    }
    XCTAssertEqual(n, 1)
    let row = try store.writer.read { db in
      try ListRepo.getList(db, id: ListId(trusted: "l1"))
    }
    XCTAssertNil(row)
  }

  func testExecuteDeleteByIdReturnsZeroWhenRowAbsent() throws {
    let store = try TestSupport.freshStore()
    let n = try store.writer.write { db in
      try LwwOps.executeDeleteById(
        db,
        table: "lists",
        entity: EntityKind.list.rawValue,
        id: "ghost",
        version: Self.v2)
    }
    XCTAssertEqual(n, 0)
  }

  func testExecuteDeleteByIdThrowsStaleVersionWhenLwwLoses() throws {
    let store = try TestSupport.freshStore()
    try seedList(store)
    XCTAssertThrowsError(
      try store.writer.write { db in
        _ = try LwwOps.executeDeleteById(
          db,
          table: "lists",
          entity: EntityKind.list.rawValue,
          id: "l1",
          version: Self.v1)
      }
    ) { error in
      guard case StoreError.staleVersion(let entity, let id) = error else {
        return XCTFail("expected staleVersion, got \(error)")
      }
      XCTAssertEqual(entity, "list")
      XCTAssertEqual(id, "l1")
    }
  }
}
