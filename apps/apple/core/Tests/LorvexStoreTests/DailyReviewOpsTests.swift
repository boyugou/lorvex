import Foundation
import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore

final class DailyReviewOpsTests: XCTestCase {

  private static let taskA = "01900000-0000-7000-8000-00000000da01"
  private static let taskB = "01900000-0000-7000-8000-00000000da02"
  private static let listA = "list-daily-read"

  private func makeParams(
    date: String, summary: String, timezone: String, version: String, now: String
  ) -> UpsertDailyReviewParams {
    UpsertDailyReviewParams(
      date: date, summary: summary, timezone: timezone, version: version, now: now)
  }

  private func seedReviewRow(_ db: Database, date: String, summary: String) throws {
    let p = UpsertDailyReviewParams(
      date: date, summary: summary,
      mood: 4, energyLevel: 3,
      wins: "Shipped", blockers: "None",
      learnings: "Use shared projections",
      timezone: "UTC",
      version: "0000000000001_0000_0000000000000000",
      now: "2026-04-01T00:00:00Z")
    let ok = try DailyReviewOpsRepo.upsertDailyReview(db, params: p)
    XCTAssertTrue(ok)
  }

  private func seedFixtureRows(_ db: Database, date: String) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES (?, 'Daily Review', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """,
      arguments: [Self.listA])
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES ('inbox', 'Inbox', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
        """)
    for tid in [Self.taskA, Self.taskB] {
      try db.execute(
        sql: """
          INSERT INTO tasks (id, title, list_id, version, created_at, updated_at) \
          VALUES (?, 'Read model task', ?, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """,
        arguments: [tid, Self.listA])
    }
    try DailyReviewOpsRepo.materializeReviewTaskLinks(
      db, date: date, taskIds: [Self.taskA, Self.taskB])
    try DailyReviewOpsRepo.materializeReviewListLinks(
      db, date: date, listIds: [Self.listA])
  }

  func testUpsertAndAmendSanitizeReviewFreeText() throws {
    // Bidi override + zero-width chars in review free-text must be stripped
    // before storage (they render to the assistant in the weekly brief).
    let store = try TestSupport.freshStore()
    let (upserted, amended) = try store.writer.write { db -> (DailyReviewRow, DailyReviewRow) in
      let upsertParams = UpsertDailyReviewParams(
        date: "2026-04-02",
        summary: "Good\u{202E}day",
        wins: "ship\u{200B}ped",
        blockers: "none",
        learnings: "learn\u{200D}ed",
        timezone: "UTC",
        version: "0000000000001_0000_0000000000000000",
        now: "2026-04-02T00:00:00Z")
      XCTAssertTrue(try DailyReviewOpsRepo.upsertDailyReview(db, params: upsertParams))
      let afterUpsert = try XCTUnwrap(
        try DailyReviewOpsRepo.getDailyReviewRow(db, date: "2026-04-02"))

      let amendParams = AmendDailyReviewParams(
        date: "2026-04-02",
        summary: "Re\u{200B}vised",
        wins: "win\u{202D}s",
        version: "0000000000002_0000_0000000000000000",
        now: "2026-04-02T01:00:00Z")
      XCTAssertTrue(try DailyReviewOpsRepo.amendDailyReview(db, params: amendParams))
      let afterAmend = try XCTUnwrap(
        try DailyReviewOpsRepo.getDailyReviewRow(db, date: "2026-04-02"))
      return (afterUpsert, afterAmend)
    }

    XCTAssertEqual(upserted.summary, "Goodday")
    XCTAssertEqual(upserted.wins, "shipped")
    XCTAssertEqual(upserted.learnings, "learned")

    XCTAssertEqual(amended.summary, "Revised")
    XCTAssertEqual(amended.wins, "wins")
  }

  func testGetDailyReviewRowMapsExplicitProjectionAndEmbedsLinks() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db -> DailyReviewRow? in
      try self.seedReviewRow(db, date: "2026-04-01", summary: "Shared row")
      try self.seedFixtureRows(db, date: "2026-04-01")
      return try DailyReviewOpsRepo.getDailyReviewRow(db, date: "2026-04-01")
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r.date, "2026-04-01")
    XCTAssertEqual(r.summary, "Shared row")
    XCTAssertEqual(r.mood, 4)
    XCTAssertEqual(r.energyLevel, 3)
    XCTAssertEqual(r.wins, "Shipped")
    XCTAssertEqual(r.blockers, "None")
    XCTAssertEqual(r.learnings, "Use shared projections")
    XCTAssertEqual(r.timezone, "UTC")
    XCTAssertEqual(r.version, "0000000000001_0000_0000000000000000")
    XCTAssertEqual(r.createdAt, "2026-04-01T00:00:00Z")
    XCTAssertEqual(r.updatedAt, "2026-04-01T00:00:00Z")
    XCTAssertEqual(r.linkedTaskIds, [Self.taskA, Self.taskB])
    XCTAssertEqual(r.linkedListIds, [Self.listA])
  }

  func testReviewLinksAreCanonicalSetsIndependentOfInputOrderAndDuplicates() throws {
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db -> DailyReviewRow? in
      try self.seedReviewRow(db, date: "2026-04-01", summary: "Canonical links")
      try self.seedFixtureRows(db, date: "2026-04-01")
      try DailyReviewOpsRepo.materializeReviewTaskLinks(
        db, date: "2026-04-01",
        taskIds: [Self.taskB, Self.taskA, Self.taskB])
      return try DailyReviewOpsRepo.getDailyReviewRow(db, date: "2026-04-01")
    }

    XCTAssertEqual(try XCTUnwrap(row).linkedTaskIds, [Self.taskA, Self.taskB])
  }

  func testGetDailyReviewRowHidesLinksToPermanentlyDeletedTaskAndList() throws {
    let orphanList = "list-daily-orphan"
    let store = try TestSupport.freshStore()
    let row = try store.writer.write { db -> DailyReviewRow? in
      try self.seedReviewRow(db, date: "2026-04-01", summary: "With dangling links")
      try self.seedFixtureRows(db, date: "2026-04-01")
      // Link a second list that no task references, so it can be permanently
      // deleted without tripping the tasks.list_id ON DELETE RESTRICT guard.
      try db.execute(
        sql: """
          INSERT INTO lists (id, name, version, created_at, updated_at) \
          VALUES (?, 'Orphan', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
          """,
        arguments: [orphanList])
      try DailyReviewOpsRepo.materializeReviewListLinks(
        db, date: "2026-04-01", listIds: [Self.listA, orphanList])
      // Permanently delete one linked task and the orphan list. The link rows
      // survive (task_id / list_id carry no FK, only review_date cascades), so
      // the read must EXISTS-filter the now-dangling ids.
      try db.execute(sql: "DELETE FROM tasks WHERE id = ?", arguments: [Self.taskA])
      try db.execute(sql: "DELETE FROM lists WHERE id = ?", arguments: [orphanList])
      return try DailyReviewOpsRepo.getDailyReviewRow(db, date: "2026-04-01")
    }
    let r = try XCTUnwrap(row)
    XCTAssertEqual(r.linkedTaskIds, [Self.taskB])
    XCTAssertEqual(r.linkedListIds, [Self.listA])
  }

  func testListDailyReviewRowsPagesHistoryWithTotalCount() throws {
    let store = try TestSupport.freshStore()
    let page = try store.writer.write { db -> DailyReviewHistoryPage in
      try self.seedReviewRow(db, date: "2026-04-01", summary: "Older")
      try self.seedReviewRow(db, date: "2026-04-02", summary: "Middle")
      try self.seedReviewRow(db, date: "2026-04-03", summary: "Newest")
      try self.seedFixtureRows(db, date: "2026-04-03")
      return try DailyReviewOpsRepo.listDailyReviewRows(
        db,
        query: DailyReviewHistoryQuery(since: "2026-04-02", limit: 1, offset: 0))
    }
    XCTAssertEqual(page.totalMatching, 2)
    XCTAssertEqual(page.rows.count, 1)
    XCTAssertEqual(page.rows[0].date, "2026-04-03")
    XCTAssertEqual(page.rows[0].linkedTaskIds, [Self.taskA, Self.taskB])
  }

  func testListDailyReviewRowsAppliesUpperBoundBeforeLimit() throws {
    let store = try TestSupport.freshStore()
    let page = try store.writer.write { db -> DailyReviewHistoryPage in
      try self.seedReviewRow(db, date: "2026-04-01", summary: "In range")
      try self.seedReviewRow(db, date: "2026-04-02", summary: "Too new")
      try self.seedReviewRow(db, date: "2026-04-03", summary: "Also too new")
      return try DailyReviewOpsRepo.listDailyReviewRows(
        db,
        query: DailyReviewHistoryQuery(until: "2026-04-01", limit: 1, offset: 0))
    }
    XCTAssertEqual(page.totalMatching, 1)
    XCTAssertEqual(page.rows.map(\.date), ["2026-04-01"])
  }

  func testSetsTimezoneOnCreate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      var p = makeParams(
        date: "2026-03-27", summary: "Good day",
        timezone: "America/New_York", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T20:00:00Z")
      p = UpsertDailyReviewParams(
        date: p.date, summary: p.summary, mood: 4,
        timezone: "America/New_York", version: p.version, now: p.now)
      _ = try DailyReviewOpsRepo.upsertDailyReview(db, params: p)
      let row = try Row.fetchOne(
        db, sql: "SELECT timezone, mood FROM daily_reviews WHERE date = '2026-03-27'")!
      XCTAssertEqual(row[0] as String?, "America/New_York")
      XCTAssertEqual(row[1] as Int64?, 4)
    }
  }

  func testPreservesTimezoneOnUpdate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let p1 = makeParams(
        date: "2026-03-27", summary: "Morning review",
        timezone: "America/New_York", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T08:00:00Z")
      _ = try DailyReviewOpsRepo.upsertDailyReview(db, params: p1)
      let p2 = UpsertDailyReviewParams(
        date: "2026-03-27", summary: "Evening update",
        timezone: "Asia/Tokyo", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T20:00:00Z")
      _ = try DailyReviewOpsRepo.upsertDailyReview(db, params: p2)
      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT timezone, summary, version FROM daily_reviews WHERE date = '2026-03-27'")!
      XCTAssertEqual(row[0] as String?, "America/New_York")
      XCTAssertEqual(row[1] as String, "Evening update")
      XCTAssertEqual(row[2] as String, "0000000000002_0000_0000000000000002")
    }
  }

  func testUpsertFullyReplacesAndClearsOmittedOptionalValues() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let p1 = UpsertDailyReviewParams(
        date: "2026-03-27", summary: "First entry",
        mood: 4, energyLevel: 3,
        wins: "Shipped feature", blockers: "CI flaky",
        timezone: "UTC", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-27T08:00:00Z")
      _ = try DailyReviewOpsRepo.upsertDailyReview(db, params: p1)
      let p2 = UpsertDailyReviewParams(
        date: "2026-03-27", summary: "Updated summary",
        learnings: "Learned testing",
        timezone: "UTC", version: "0000000000002_0000_0000000000000002",
        now: "2026-03-27T12:00:00Z")
      _ = try DailyReviewOpsRepo.upsertDailyReview(db, params: p2)
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT summary, mood, energy_level, wins, blockers, learnings \
          FROM daily_reviews WHERE date = '2026-03-27'
          """)!
      XCTAssertEqual(row[0] as String, "Updated summary")
      XCTAssertNil(row[1] as Int64?)
      XCTAssertNil(row[2] as Int64?)
      XCTAssertNil(row[3] as String?)
      XCTAssertNil(row[4] as String?)
      XCTAssertEqual(row[5] as String?, "Learned testing")
    }
  }

  func testAmendDailyReviewUpdatesSpecifiedFieldsOnly() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let create = UpsertDailyReviewParams(
        date: "2026-03-28", summary: "Initial review",
        mood: 3, energyLevel: 4, wins: "Shipped CLI",
        timezone: "America/Los_Angeles", version: "0000000000001_0000_0000000000000001",
        now: "2026-03-28T08:00:00Z")
      _ = try DailyReviewOpsRepo.upsertDailyReview(db, params: create)

      let amend = AmendDailyReviewParams(
        date: "2026-03-28",
        learnings: "Batching keeps the afternoon open",
        version: "0000000000002_0000_0000000000000002",
        now: "2026-03-28T20:00:00Z")
      let amended = try DailyReviewOpsRepo.amendDailyReview(db, params: amend)
      XCTAssertTrue(amended)

      let row = try Row.fetchOne(
        db,
        sql:
          "SELECT summary, mood, learnings, version FROM daily_reviews WHERE date = '2026-03-28'"
      )!
      XCTAssertEqual(row[0] as String, "Initial review")
      XCTAssertEqual(row[1] as Int64?, 3)
      XCTAssertEqual(row[2] as String?, "Batching keeps the afternoon open")
      XCTAssertEqual(row[3] as String, "0000000000002_0000_0000000000000002")
    }
  }

  func testUpsertDailyReviewLwwGateRejectsStaleVersion() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let p1 = UpsertDailyReviewParams(
        date: "2026-04-26", summary: "winning version",
        mood: 5, energyLevel: 4,
        timezone: "UTC",
        version: "0002000000000_0001_a000000000000001",
        now: "2026-04-26T08:00:00Z")
      let applied1 = try DailyReviewOpsRepo.upsertDailyReview(db, params: p1)
      XCTAssertTrue(applied1)

      let p2 = UpsertDailyReviewParams(
        date: "2026-04-26", summary: "stale version",
        mood: 1, energyLevel: 1,
        timezone: "UTC",
        version: "0001000000000_0001_b000000000000001",
        now: "2026-04-26T09:00:00Z")
      let applied2 = try DailyReviewOpsRepo.upsertDailyReview(db, params: p2)
      XCTAssertFalse(applied2)

      let row = try Row.fetchOne(
        db,
        sql: "SELECT summary, mood, version FROM daily_reviews WHERE date = '2026-04-26'")!
      XCTAssertEqual(row[0] as String, "winning version")
      XCTAssertEqual(row[1] as Int64?, 5)
      XCTAssertEqual(row[2] as String, "0002000000000_0001_a000000000000001")
    }
  }

  func testAmendDailyReviewReturnsFalseForNonexistentDate() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let amend = AmendDailyReviewParams(
        date: "2099-12-31",
        summary: "Should not exist",
        version: "0000000000001_0000_0000000000000001",
        now: "2099-12-31T00:00:00Z")
      let amended = try DailyReviewOpsRepo.amendDailyReview(db, params: amend)
      XCTAssertFalse(amended)
    }
  }

  // MARK: - SB7: mood / energy_level scale enforced in the core writer

  private func expectMoodEnergyValidation(
    _ op: () throws -> Void, field: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    do {
      try op()
      XCTFail("expected StoreError.validation for out-of-range \(field)", file: file, line: line)
    } catch let e as StoreError {
      guard case let .validation(msg) = e else {
        return XCTFail("expected .validation, got \(e)", file: file, line: line)
      }
      XCTAssertTrue(msg.contains(field), "reason '\(msg)' should mention '\(field)'", file: file, line: line)
    } catch {
      XCTFail("expected StoreError.validation, got \(error)", file: file, line: line)
    }
  }

  /// The 1…5 scale is enforced in `upsertDailyReview` (the local write path
  /// every daily-review caller — interactive upsert AND `importDailyReview` —
  /// funnels through), so no caller reaches the raw `CHECK (mood BETWEEN 1 AND 5)`.
  func testUpsertDailyReviewRejectsOutOfRangeMoodAndEnergy() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      self.expectMoodEnergyValidation(
        {
          _ = try DailyReviewOpsRepo.upsertDailyReview(
            db,
            params: UpsertDailyReviewParams(
              date: "2026-04-01", summary: "s", mood: 6, timezone: "UTC", version: "0000000000001_0000_0000000000000001",
              now: "2026-04-01T00:00:00Z"))
        }, field: "mood")
      self.expectMoodEnergyValidation(
        {
          _ = try DailyReviewOpsRepo.upsertDailyReview(
            db,
            params: UpsertDailyReviewParams(
              date: "2026-04-01", summary: "s", energyLevel: 0, timezone: "UTC", version: "0000000000001_0000_0000000000000001",
              now: "2026-04-01T00:00:00Z"))
        }, field: "energy_level")
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_reviews"), 0,
        "no rejected review should have landed")
    }
  }

  func testAmendDailyReviewRejectsOutOfRangeMood() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      try self.seedReviewRow(db, date: "2026-04-01", summary: "seed")
      self.expectMoodEnergyValidation(
        {
          _ = try DailyReviewOpsRepo.amendDailyReview(
            db,
            params: AmendDailyReviewParams(
              date: "2026-04-01", mood: 7, version: "0000000000002_0000_0000000000000000",
              now: "2026-04-01T01:00:00Z"))
        }, field: "mood")
    }
  }

  func testUpsertDailyReviewAcceptsBoundaryScaleValues() throws {
    let store = try TestSupport.freshStore()
    try store.writer.write { db in
      let ok = try DailyReviewOpsRepo.upsertDailyReview(
        db,
        params: UpsertDailyReviewParams(
          date: "2026-04-02", summary: "s", mood: 5, energyLevel: 1, timezone: "UTC",
          version: "0000000000001_0000_0000000000000001", now: "2026-04-02T00:00:00Z"))
      XCTAssertTrue(ok)
      let row = try Row.fetchOne(
        db, sql: "SELECT mood, energy_level FROM daily_reviews WHERE date = '2026-04-02'")
      XCTAssertEqual(row?["mood"] as Int64?, 5)
      XCTAssertEqual(row?["energy_level"] as Int64?, 1)
    }
  }
}
