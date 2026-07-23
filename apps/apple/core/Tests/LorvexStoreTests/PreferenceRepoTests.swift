import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class PreferenceRepoTests: XCTestCase {
  func testSetPreferenceInsertsNewKey() throws {
    let store = try TestSupport.freshStore()
    let wrote = try store.writer.write { db -> Bool in
      try PreferenceRepo.setPreference(
        db, key: "theme", value: "\"dark\"", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T00:00:00.000Z")
    }
    XCTAssertTrue(wrote, "fresh insert should report wrote=true")

    let value = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?",
        arguments: ["theme"])
    }
    XCTAssertEqual(value, "\"dark\"")
  }

  func testSetPreferenceUpsertsExistingKey() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try PreferenceRepo.setPreference(
        db, key: "theme", value: "\"dark\"", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T00:00:00.000Z")
    }
    let wrote = try store.writer.write { db -> Bool in
      try PreferenceRepo.setPreference(
        db, key: "theme", value: "\"light\"", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T01:00:00.000Z")
    }
    XCTAssertTrue(wrote, "newer-version upsert should report wrote=true")

    let value = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?",
        arguments: ["theme"])
    }
    XCTAssertEqual(value, "\"light\"")
  }

  func testSetPreferenceRejectsStaleVersionWrite() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try PreferenceRepo.setPreference(
        db, key: "theme", value: "\"dark\"", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T00:00:00.000Z")
    }
    let wrote = try store.writer.write { db -> Bool in
      try PreferenceRepo.setPreference(
        db, key: "theme", value: "\"light\"", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-26T00:00:00.000Z")
    }
    XCTAssertFalse(wrote, "stale-version upsert must report wrote=false")

    let (value, version) = try store.writer.read { db -> (String?, String?) in
      let row = try Row.fetchOne(
        db, sql: "SELECT value, version FROM preferences WHERE key = ?",
        arguments: ["theme"])
      return (row?[0], row?[1])
    }
    XCTAssertEqual(value, "\"dark\"")
    XCTAssertEqual(version, "0000000000002_0000_0000000000000002")
  }

  func testClearPreferenceDeletesWhenVersionStrictlyNewer() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try PreferenceRepo.setPreference(
        db, key: "key1", value: "val1", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T00:00:00.000Z")
    }
    let deleted = try store.writer.write { db -> Int in
      try PreferenceRepo.clearPreference(db, key: "key1", version: "0000000000002_0000_0000000000000002")
    }
    XCTAssertEqual(deleted, 1)
  }

  func testClearPreferenceReturnsZeroForMissing() throws {
    let store = try TestSupport.freshStore()
    let deleted = try store.writer.write { db -> Int in
      try PreferenceRepo.clearPreference(db, key: "nonexistent", version: "0000000000009_0000_0000000000000009")
    }
    XCTAssertEqual(deleted, 0)
  }

  func testClearPreferenceThrowsStaleVersionOnRefusedRow() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try PreferenceRepo.setPreference(
        db, key: "theme", value: "\"dark\"", version: "0000000000003_0000_0000000000000003",
        now: "2026-03-27T00:00:00.000Z")
    }
    // A present-but-refused row (stored version newer than the clear stamp)
    // throws so the write-surface retry can advance the clock past it, rather
    // than silently no-opping and leaving the row un-deletable.
    XCTAssertThrowsError(
      try store.writer.write { db in
        try PreferenceRepo.clearPreference(db, key: "theme", version: "0000000000002_0000_0000000000000002")
      }
    ) { error in
      guard case StoreError.staleVersion = error else {
        return XCTFail("expected staleVersion, got \(error)")
      }
    }

    let value = try store.writer.read { db in
      try String.fetchOne(
        db, sql: "SELECT value FROM preferences WHERE key = ?",
        arguments: ["theme"])
    }
    XCTAssertEqual(value, "\"dark\"")
  }

  func testClearPreferenceThrowsStaleVersionOnEqualVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      _ = try PreferenceRepo.setPreference(
        db, key: "theme", value: "\"dark\"", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T00:00:00.000Z")
    }
    XCTAssertThrowsError(
      try store.writer.write { db in
        try PreferenceRepo.clearPreference(db, key: "theme", version: "0000000000002_0000_0000000000000002")
      }
    ) { error in
      guard case StoreError.staleVersion = error else {
        return XCTFail("expected staleVersion, got \(error)")
      }
    }
  }
}
