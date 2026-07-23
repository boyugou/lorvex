import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class CurrentFocusItemsTests: XCTestCase {

  private func seedHeader(_ db: Database, date: String, version: String = "0000000000000_0000_a0a0a0a0a0a0a0a0") throws {
    try db.execute(
      sql: """
        INSERT INTO current_focus (date, timezone, version, created_at, updated_at) \
        VALUES (?, 'UTC', ?, '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')
        """,
      arguments: [date, version])
  }

  // -- materialize_focus_items --

  func testMaterializeDeduplicatesTaskIds() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> [String] in
      try self.seedHeader(db, date: "2026-03-27")
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-03-27", taskIds: ["a", "b", "a", "c"])
      return try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: "2026-03-27")
    }
    XCTAssertEqual(result, ["a", "b", "c"])
  }

  func testMaterializeReplacesExisting() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> [String] in
      try self.seedHeader(db, date: "2026-03-27")
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-03-27", taskIds: ["x", "y"])
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-03-27", taskIds: ["p", "q", "r"])
      return try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: "2026-03-27")
    }
    XCTAssertEqual(result, ["p", "q", "r"])
  }

  func testMaterializeEmptyClearsAll() throws {
    let store = try TestSupport.freshStore()
    let result = try store.writer.write { db -> [String] in
      try self.seedHeader(db, date: "2026-03-27")
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-03-27", taskIds: ["a"])
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-03-27", taskIds: [])
      return try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: "2026-03-27")
    }
    XCTAssertTrue(result.isEmpty)
  }

  // -- upsert_current_focus_header --

  func testUpsertCreatesNewRow() throws {
    let store = try TestSupport.freshStore()
    let outcome = try store.writer.write { db in
      try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-03-27", briefing: "morning briefing",
        timezone: "America/New_York", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T08:00:00Z")
    }
    XCTAssertEqual(outcome, .created)
    let (briefing, tz) = try store.writer.read { db -> (String?, String?) in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT briefing, timezone FROM current_focus WHERE date = '2026-03-27'")!
      return (row[0], row[1])
    }
    XCTAssertEqual(briefing, "morning briefing")
    XCTAssertEqual(tz, "America/New_York")
  }

  func testUpsertUpdatePreservesTimezone() throws {
    let store = try TestSupport.freshStore()
    let outcome = try store.writer.write { db -> UpsertOutcome in
      _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-03-27", briefing: "v1 briefing",
        timezone: "America/New_York", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T08:00:00Z")
      return try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-03-27", briefing: "v2 briefing",
        timezone: "Europe/London", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T09:00:00Z")
    }
    XCTAssertEqual(outcome, .updated)
    let (briefing, tz, version) = try store.writer.read { db -> (String?, String?, String) in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT briefing, timezone, version FROM current_focus WHERE date = '2026-03-27'")!
      return (row[0], row[1], row[2])
    }
    XCTAssertEqual(briefing, "v2 briefing")
    XCTAssertEqual(tz, "America/New_York")
    XCTAssertEqual(version, "0000000000002_0000_0000000000000002")
  }

  func testUpsertLwwGateRejectsStaleVersion() throws {
    let store = try TestSupport.freshStore()
    let outcome = try store.writer.write { db -> UpsertOutcome in
      _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-04-26", briefing: "winning briefing",
        timezone: "America/New_York",
        version: "0002000000000_0001_a000000000000001",
        now: "2026-04-26T08:00:00Z")
      return try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-04-26", briefing: "stale briefing",
        timezone: "America/New_York",
        version: "0001000000000_0001_b000000000000001",
        now: "2026-04-26T09:00:00Z")
    }
    XCTAssertEqual(outcome, .lwwRejected)
    let (briefing, version, updatedAt) = try store.writer.read {
      db -> (String?, String, String) in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT briefing, version, updated_at FROM current_focus WHERE date = '2026-04-26'")!
      return (row[0], row[1], row[2])
    }
    XCTAssertEqual(briefing, "winning briefing")
    XCTAssertEqual(version, "0002000000000_0001_a000000000000001")
    XCTAssertEqual(updatedAt, "2026-04-26T08:00:00Z")
  }

  func testDeleteCurrentFocusRemovesRowAndChildren() throws {
    let store = try TestSupport.freshStore()
    let (childCount, parentCount, deleted) =
      try store.writer.write { db -> (Int64, Int64, Bool) in
        _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
          db, date: "2026-03-27", briefing: nil, timezone: "UTC",
          version: "0000000000001_0000_0000000000000001", now: "2026-03-27T08:00:00Z")
        try CurrentFocusItemsRepo.materializeFocusItems(
          db, date: "2026-03-27", taskIds: ["a", "b"])
        let d = try CurrentFocusItemsRepo.deleteCurrentFocus(
          db, date: "2026-03-27")
        let p =
          try Int64.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM current_focus WHERE date = '2026-03-27'") ?? -1
        let c =
          try Int64.fetchOne(
            db,
            sql:
              "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-27'")
          ?? -1
        return (c, p, d)
      }
    XCTAssertTrue(deleted)
    XCTAssertEqual(parentCount, 0)
    XCTAssertEqual(childCount, 0)
  }

  func testDeleteNonexistentReturnsFalse() throws {
    let store = try TestSupport.freshStore()
    let deleted = try store.writer.write { db in
      try CurrentFocusItemsRepo.deleteCurrentFocus(db, date: "2099-01-01")
    }
    XCTAssertFalse(deleted)
  }

  func testMaterializeWithHeaderBumpAdvancesParent() throws {
    let store = try TestSupport.freshStore()
    let newVersion = "0001000000999_0000_de1cea0de1cea000"
    let newUpdatedAt = "2026-04-26T09:00:00Z"
    let (version, updatedAt, ids) = try store.writer.write {
      db -> (String, String, [String]) in
      _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-04-26", briefing: "seed", timezone: "UTC",
        version: "0001000000000_0000_a0a0a0a0a0a0a0a0",
        now: "2026-04-26T08:00:00Z")
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-04-26", taskIds: ["a", "b"])
      try CurrentFocusItemsRepo.materializeFocusItemsWithHeaderBump(
        db, date: "2026-04-26", taskIds: ["c", "d"],
        version: newVersion, now: newUpdatedAt)
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'")!
      let v: String = row[0]
      let u: String = row[1]
      let i = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: "2026-04-26")
      return (v, u, i)
    }
    XCTAssertEqual(version, newVersion)
    XCTAssertEqual(updatedAt, newUpdatedAt)
    XCTAssertEqual(ids, ["c", "d"])
  }

  func testMaterializeWithHeaderBumpRejectsStaleVersion() throws {
    let store = try TestSupport.freshStore()
    let winner = "0002000000000_0001_a000000000000001"
    try store.writer.write { db in
      _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-04-26", briefing: "seed", timezone: "UTC",
        version: winner, now: "2026-04-26T08:00:00Z")
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-04-26", taskIds: ["winner-a", "winner-b"])
    }
    let stale = "0001000000000_0001_b000000000000001"
    XCTAssertThrowsError(
      try store.writer.write { db in
        try CurrentFocusItemsRepo.materializeFocusItemsWithHeaderBump(
          db, date: "2026-04-26", taskIds: ["loser-x"],
          version: stale, now: "2026-04-26T09:00:00Z")
      }
    ) { err in
      guard case StoreError.staleVersion(let entity, let id) = err else {
        return XCTFail("expected .staleVersion, got \(err)")
      }
      XCTAssertEqual(entity, "current_focus")
      XCTAssertEqual(id, "2026-04-26")
    }
    let (version, updatedAt, ids) = try store.writer.read {
      db -> (String, String, [String]) in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'")!
      let v: String = row[0]
      let u: String = row[1]
      let i = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: "2026-04-26")
      return (v, u, i)
    }
    XCTAssertEqual(version, winner)
    XCTAssertEqual(updatedAt, "2026-04-26T08:00:00Z")
    XCTAssertEqual(ids, ["winner-a", "winner-b"])
  }

  func testMaterializeWithHeaderBumpAcceptsEqualVersionRestamp() throws {
    let store = try TestSupport.freshStore()
    let v = "0001000000000_0001_a0a0a0a0a0a0a0a0"
    try store.writer.write { db in
      _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-04-26", briefing: "seed", timezone: "UTC",
        version: v, now: "2026-04-26T08:00:00Z")
      try CurrentFocusItemsRepo.materializeFocusItemsWithHeaderBump(
        db, date: "2026-04-26", taskIds: ["a", "b"],
        version: v, now: "2026-04-26T09:00:00Z")
    }
    let (version, updatedAt, ids) = try store.writer.read {
      db -> (String, String, [String]) in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'")!
      let vv: String = row[0]
      let u: String = row[1]
      let i = try CurrentFocusItemsRepo.queryFocusTaskIds(db, date: "2026-04-26")
      return (vv, u, i)
    }
    XCTAssertEqual(version, v)
    XCTAssertEqual(updatedAt, "2026-04-26T09:00:00Z")
    XCTAssertEqual(ids, ["a", "b"])
  }

  func testMaterializeWithHeaderBumpRejectsMissingParent() throws {
    let store = try TestSupport.freshStore()
    XCTAssertThrowsError(
      try store.writer.write { db in
        try CurrentFocusItemsRepo.materializeFocusItemsWithHeaderBump(
          db, date: "2099-01-01", taskIds: ["a"],
          version: "0000000000000_0000_a0a0a0a0a0a0a0a0",
          now: "2099-01-01T00:00:00Z")
      }
    ) { err in
      guard case StoreError.staleVersion = err else {
        return XCTFail("expected .staleVersion, got \(err)")
      }
    }
    let count = try store.writer.read { db in
      try Int64.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM current_focus_items WHERE date = '2099-01-01'")
        ?? -1
    }
    XCTAssertEqual(count, 0)
  }

  func testSyncApplyPathPreservesEnvelopeVersionAfterRebuild() throws {
    let store = try TestSupport.freshStore()
    let envelopeVersion = "0002000000000_0000_0e007e0000000000"
    let envelopeUpdatedAt = "2026-04-26T10:30:00Z"
    let wrote = try store.writer.write { db -> Bool in
      _ = try CurrentFocusItemsRepo.upsertCurrentFocusHeader(
        db, date: "2026-04-26", briefing: "baseline", timezone: "UTC",
        version: "0001000000000_0000_a0a0a0a0a0a0a0a0",
        now: "2026-04-26T08:00:00Z")
      let r = try CurrentFocusItemsRepo.syncUpsertCurrentFocus(
        db, date: "2026-04-26", briefing: "remote-briefing",
        timezone: "Europe/London", version: envelopeVersion,
        createdAt: "2026-04-26T08:00:00Z", updatedAt: envelopeUpdatedAt,
        versionCmp: ">")
      try CurrentFocusItemsRepo.materializeFocusItems(
        db, date: "2026-04-26", taskIds: ["x", "y"])
      return r
    }
    XCTAssertTrue(wrote)
    let (version, updatedAt) = try store.writer.read { db -> (String, String) in
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT version, updated_at FROM current_focus WHERE date = '2026-04-26'")!
      return (row[0], row[1])
    }
    XCTAssertEqual(version, envelopeVersion)
    XCTAssertEqual(updatedAt, envelopeUpdatedAt)
  }
}
