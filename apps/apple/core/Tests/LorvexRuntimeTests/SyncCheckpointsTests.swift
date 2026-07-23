import GRDB
import XCTest

@testable import LorvexRuntime

/// Ports `lorvex-runtime/src/sync_checkpoints/tests.rs`. The CRUD primitives
/// are the authoritative `LorvexStore.SyncCheckpoints` re-export; these pin the
/// runtime surface's parity (well-known keys + the typed `clear`).
final class SyncCheckpointsTests: XCTestCase {
  func testGetAfterSetReturnsValue() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyLastError, value: "boom")
      XCTAssertEqual(try SyncCheckpoints.get(db, key: SyncCheckpoints.keyLastError), "boom")
    }
  }

  func testGetMissingKeyReturnsNil() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.read { db in
      XCTAssertNil(try SyncCheckpoints.get(db, key: "absent"))
    }
  }

  func testSetIsIdempotentForSameValue() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyLastSuccessAt, value: "2026-04-26T00:00:00Z")
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyLastSuccessAt, value: "2026-04-26T00:00:00Z")
      XCTAssertEqual(
        try SyncCheckpoints.get(db, key: SyncCheckpoints.keyLastSuccessAt), "2026-04-26T00:00:00Z")
    }
  }

  func testSetOverwritesPreviousValue() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyLastError, value: "first")
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyLastError, value: "second")
      XCTAssertEqual(try SyncCheckpoints.get(db, key: SyncCheckpoints.keyLastError), "second")
    }
  }

  func testClearRemovesRowAndReportsDeletion() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      try SyncCheckpoints.set(db, key: SyncCheckpoints.keyLastError, value: "boom")
      XCTAssertTrue(try SyncCheckpoints.clear(db, key: SyncCheckpoints.keyLastError))
      XCTAssertNil(try SyncCheckpoints.get(db, key: SyncCheckpoints.keyLastError))
      XCTAssertFalse(try SyncCheckpoints.clear(db, key: SyncCheckpoints.keyLastError))
    }
  }

  func testSetIfAbsentOnlyInsertsWhenAbsent() throws {
    let store = try RuntimeTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertTrue(try SyncCheckpoints.setIfAbsent(db, key: SyncCheckpoints.keyDeviceId, value: "first"))
      XCTAssertEqual(try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId), "first")
      XCTAssertFalse(try SyncCheckpoints.setIfAbsent(db, key: SyncCheckpoints.keyDeviceId, value: "second"))
      XCTAssertEqual(try SyncCheckpoints.get(db, key: SyncCheckpoints.keyDeviceId), "first")
    }
  }

  func testGetOrCreateDatabaseInstanceIdIsStableWithinADatabaseAndFreshPerDatabase() throws {
    // The invariant SYNC-HIGH-2 leans on: the instance id is created once per
    // physical database and stable across opens, but a freshly-created
    // (replacement) database mints a DISTINCT id. Traversal state and its token
    // live in that database; the identity additionally fences restored/cloned
    // lineage from reusing the source install's generation authority.
    let store1 = try RuntimeTestSupport.freshStore()
    let first = try store1.writer.write { try SyncCheckpoints.getOrCreateDatabaseInstanceId($0) }
    let second = try store1.writer.write { try SyncCheckpoints.getOrCreateDatabaseInstanceId($0) }
    XCTAssertEqual(first, second, "the instance id is stable across opens of the same database")
    XCTAssertFalse(first.trimmingCharacters(in: .whitespaces).isEmpty)

    let store2 = try RuntimeTestSupport.freshStore()
    let other = try store2.writer.write { try SyncCheckpoints.getOrCreateDatabaseInstanceId($0) }
    XCTAssertNotEqual(first, other, "a replacement database gets a new instance id")
  }
}
