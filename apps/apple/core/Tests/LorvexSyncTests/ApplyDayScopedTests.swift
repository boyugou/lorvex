import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// The day-scoped appliers, driven end to end: `daily_briefing` (one scrubbed,
/// non-blank text per day) and `daily_review` (a review plus its task and list
/// link tables), and the drift guard that those link tables are not
/// independently synced.
final class ApplyDayScopedTests: XCTestCase {

  private let vMid = "1711234568000_0000_dec0000100000001"
  private let taskA = "01943a6d-b5c8-7e1f-9a12-3456789abcde"
  private let taskB = "550e8400-e29b-41d4-a716-446655440000"
  private let listA = "01943a6d-b5c8-7e1f-9a12-3456789abcdf"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  // MARK: - drift guard

  func testMaterializationTablesAreNotIndependentlySynced() {
    let forbidden = ["daily_review_task_links", "daily_review_list_links"]
    for child in forbidden {
      XCTAssertFalse(
        EntityKind.allSyncableTypes.contains(child),
        "\(child) was promoted to allSyncableTypes — migrate the parent day-scoped delete onto "
          + "the cascading-tombstone helper before enabling sync")
    }
  }

  // MARK: - daily_briefing

  private func briefingPayload(_ text: String, timezone: String = "UTC") throws -> String {
    try SyncCanonicalize.canonicalizeJSON(
      .object([
        "briefing": .string(text), "timezone": .string(timezone),
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
      ]))
  }

  private func storedBriefing(_ db: Database, _ date: String) throws -> String? {
    try String.fetchOne(
      db, sql: "SELECT briefing FROM daily_briefings WHERE date = ?", arguments: [date])
  }

  func testDailyBriefingUpsertStoresScrubbedText() throws {
    try withDB { db in
      try ApplyDayScoped.applyDailyBriefingUpsert(
        db, entityId: "2026-04-01", payload: try self.briefingPayload("Two\u{202E} meetings"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.storedBriefing(db, "2026-04-01"), "Two meetings")
    }
  }

  func testDailyBriefingRejectsBlankTextAsInvalidPayload() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try ApplyDayScoped.applyDailyBriefingUpsert(
          db, entityId: "2026-04-01", payload: try self.briefingPayload("\u{200B} \n"),
          version: self.vMid, tieBreak: .rejectEqual)
      ) { error in
        guard case ApplyError.invalidPayload = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
      }
      XCTAssertNil(try self.storedBriefing(db, "2026-04-01"))
    }
  }

  func testDailyBriefingEqualVersionFollowsTheTieBreak() throws {
    try withDB { db in
      try ApplyDayScoped.applyDailyBriefingUpsert(
        db, entityId: "2026-04-01", payload: try self.briefingPayload("First"),
        version: self.vMid, tieBreak: .rejectEqual)
      try ApplyDayScoped.applyDailyBriefingUpsert(
        db, entityId: "2026-04-01", payload: try self.briefingPayload("Equal, rejected"),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(try self.storedBriefing(db, "2026-04-01"), "First")
      try ApplyDayScoped.applyDailyBriefingUpsert(
        db, entityId: "2026-04-01", payload: try self.briefingPayload("Equal, accepted"),
        version: self.vMid, tieBreak: .allowEqual)
      XCTAssertEqual(try self.storedBriefing(db, "2026-04-01"), "Equal, accepted")
    }
  }

  func testDailyBriefingDeleteIsVersionGated() throws {
    try withDB { db in
      try ApplyDayScoped.applyDailyBriefingUpsert(
        db, entityId: "2026-04-01", payload: try self.briefingPayload("Keep"),
        version: self.vMid, tieBreak: .rejectEqual)
      try? ApplyDayScoped.applyDailyBriefingDelete(
        db, entityId: "2026-04-01", version: "1711234567000_0000_dec0000100000001")
      XCTAssertEqual(try self.storedBriefing(db, "2026-04-01"), "Keep", "an older delete loses")
      try ApplyDayScoped.applyDailyBriefingDelete(
        db, entityId: "2026-04-01", version: "1711234569000_0000_dec0000100000001")
      XCTAssertNil(try self.storedBriefing(db, "2026-04-01"))
    }
  }

  // MARK: - daily_review

  func testDailyReviewUpsertMaterializesLinks() throws {
    try withDB { db in
      let date = "2026-04-01"
      let payload: JSONValue = .object([
        "summary": .string("good day"),
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "linked_task_ids": .array([.string(self.taskA), .string(self.taskB)]),
        "linked_list_ids": .array([.string("inbox"), .string(self.listA)]),
      ])
      try ApplyDayScoped.applyDailyReviewUpsert(
        db, entityId: date, payload: try SyncCanonicalize.canonicalizeJSON(payload),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?",
          arguments: [date]), 2)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM daily_review_list_links WHERE review_date = ?",
          arguments: [date]), 2)
    }
  }

  /// SYNC-MED-2: a daily_review upsert that OMITS `linked_task_ids` /
  /// `linked_list_ids` must PRESERVE the existing links, not wipe them.
  func testDailyReviewOmittingLinkedIdsPreservesLinks() throws {
    try withDB { db in
      let date = "2026-04-01"
      try ApplyDayScoped.applyDailyReviewUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "summary": .string("good day"),
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:00:00Z"),
            "linked_task_ids": .array([.string(self.taskA), .string(self.taskB)]),
            "linked_list_ids": .array([.string("inbox")]),
          ])), version: self.vMid, tieBreak: .rejectEqual)

      // Newer envelope revises the summary but omits both link arrays.
      try ApplyDayScoped.applyDailyReviewUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "summary": .string("revised"),
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:10:00Z"),
          ])), version: "1711234569000_0000_dec0000100000001", tieBreak: .rejectEqual)

      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?",
          arguments: [date]), 2, "omitting linked_task_ids must preserve the task links")
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM daily_review_list_links WHERE review_date = ?",
          arguments: [date]), 1, "omitting linked_list_ids must preserve the list links")
    }
  }

  func testDailyReviewDeleteCascadesLinks() throws {
    try withDB { db in
      let date = "2026-04-01"
      try ApplyDayScoped.applyDailyReviewUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "summary": .string("s"), "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:00:00Z"),
            "linked_task_ids": .array([.string(self.taskA)]),
          ])), version: self.vMid, tieBreak: .rejectEqual)
      try ApplyDayScoped.applyDailyReviewDelete(
        db, entityId: date, version: "1711234569000_0000_dec0000100000001")
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM daily_reviews WHERE date = ?", arguments: [date]),
        0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM daily_review_task_links WHERE review_date = ?",
          arguments: [date]), 0)
    }
  }

  func testDailyReviewRejectsNonCanonicalLinkedTaskIdentity() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try ApplyDayScoped.applyDailyReviewUpsert(
          db, entityId: "2026-04-01",
          payload: try SyncCanonicalize.canonicalizeJSON(
            .object([
              "summary": .string("s"),
              "created_at": .string("2026-04-01T00:00:00Z"),
              "updated_at": .string("2026-04-01T00:00:00Z"),
              "linked_task_ids": .array([.string("task-not-a-uuid")]),
            ])), version: self.vMid, tieBreak: .rejectEqual)
      ) { error in
        guard case let ApplyError.invalidPayload(message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("linked_task_ids[0]"))
      }
    }
  }

  func testDailyReviewRejectsNonCanonicalLinkedListIdentity() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try ApplyDayScoped.applyDailyReviewUpsert(
          db, entityId: "2026-04-01",
          payload: try SyncCanonicalize.canonicalizeJSON(
            .object([
              "summary": .string("s"),
              "created_at": .string("2026-04-01T00:00:00Z"),
              "updated_at": .string("2026-04-01T00:00:00Z"),
              "linked_list_ids": .array([.string("list-not-a-uuid")]),
            ])), version: self.vMid, tieBreak: .rejectEqual)
      ) { error in
        guard case let ApplyError.invalidPayload(message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("linked_list_ids[0]"))
      }
    }
  }

  /// D4: `mood` / `energy_level` are pre-validated against the schema's 1…5
  /// scale at the trust boundary, so an out-of-range value drops as
  /// InvalidPayload rather than tripping `CHECK (mood BETWEEN 1 AND 5)` (which
  /// the batch loop would treat as batch-fatal and wedge inbound sync).
  func testDailyReviewMoodOutOfRangeRejectedAtApplyBoundary() throws {
    try withDB { db in
      let date = "2026-04-01"
      XCTAssertThrowsError(
        try ApplyDayScoped.applyDailyReviewUpsert(
          db, entityId: date,
          payload: try SyncCanonicalize.canonicalizeJSON(
            .object([
              "summary": .string("s"), "mood": .int(9),
              "created_at": .string("2026-04-01T00:00:00Z"),
              "updated_at": .string("2026-04-01T00:00:00Z"),
            ])), version: self.vMid, tieBreak: .rejectEqual)
      ) { err in
        guard case let ApplyError.invalidPayload(msg) = err else {
          return XCTFail("expected invalidPayload, got \(err)")
        }
        XCTAssertTrue(msg.contains("mood"), "got: \(msg)")
      }
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM daily_reviews WHERE date = ?", arguments: [date]),
        0, "the rejected review must not have landed")
    }
  }

  /// An in-range `mood` / `energy_level` (and NULL) satisfies the CHECK and
  /// applies unchanged.
  func testDailyReviewValidScaleApplies() throws {
    try withDB { db in
      let date = "2026-04-02"
      try ApplyDayScoped.applyDailyReviewUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "summary": .string("s"), "mood": .int(5), "energy_level": .int(1),
            "created_at": .string("2026-04-02T00:00:00Z"),
            "updated_at": .string("2026-04-02T00:00:00Z"),
          ])), version: self.vMid, tieBreak: .rejectEqual)
      let row = try Row.fetchOne(
        db, sql: "SELECT mood, energy_level FROM daily_reviews WHERE date = ?", arguments: [date])
      XCTAssertEqual(row?["mood"], 5)
      XCTAssertEqual(row?["energy_level"], 1)
    }
  }
}
