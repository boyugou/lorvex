import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports the parity `#[test]` cases for the day-scoped appliers (Rust
/// `day_scoped/tests.rs`): the `isCanonicalUUID` accept/reject set and the
/// drift guard that the materialization child tables are NOT independently
/// synced. Adds end-to-end upsert + child-materialization coverage for
/// current_focus / focus_schedule / daily_review driven through the appliers.
final class ApplyDayScopedTests: XCTestCase {

  private let vMid = "1711234568000_0000_dec0000100000001"
  private let taskA = "01943a6d-b5c8-7e1f-9a12-3456789abcde"
  private let taskB = "550e8400-e29b-41d4-a716-446655440000"
  private let listA = "01943a6d-b5c8-7e1f-9a12-3456789abcdf"

  private func withDB(_ body: (Database) throws -> Void) throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in try body(db) }
  }

  // MARK: - isCanonicalUUID unit

  func testAcceptsValidUUIDs() {
    XCTAssertTrue(ApplyDayScoped.isCanonicalUUID("01943a6d-b5c8-7e1f-9a12-3456789abcde"))
    XCTAssertTrue(ApplyDayScoped.isCanonicalUUID("550e8400-e29b-41d4-a716-446655440000"))
    XCTAssertTrue(ApplyDayScoped.isCanonicalUUID("00000000-0000-0000-0000-000000000000"))
  }

  func testRejectsProviderEventKeys() {
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID("550E8400-E29B-41D4-A716-446655440000"))
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID("3A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D6E7F"))
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID("uid-12345@example.com"))
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID("eventkit-cal-item-123"))
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID("550e8400-e29b-41d4"))
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID("550e8400e29b41d4a716446655440000xxxx"))
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID("550e84-00e29b-41d4a-716-446655440000"))
    XCTAssertFalse(ApplyDayScoped.isCanonicalUUID(""))
  }

  // MARK: - drift guard

  func testMaterializationTablesAreNotIndependentlySynced() {
    let forbidden = [
      "current_focus_items", "focus_schedule_blocks", "daily_review_task_links",
      "daily_review_list_links",
    ]
    for child in forbidden {
      XCTAssertFalse(
        EntityKind.allSyncableTypes.contains(child),
        "\(child) was promoted to allSyncableTypes — migrate the parent day-scoped delete onto "
          + "the cascading-tombstone helper before enabling sync")
    }
  }

  // MARK: - current_focus

  func testCurrentFocusUpsertMaterializesItems() throws {
    try withDB { db in
      let date = "2026-04-01"
      // The focus_schedule blocks need a real task to reference; current_focus
      // items are soft references (no FK to tasks).
      let payload: JSONValue = .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "task_ids": .array([.string(self.taskA), .string(self.taskB), .string(self.taskA)]),
      ])
      try ApplyDayScoped.applyCurrentFocusUpsert(
        db, entityId: date, payload: try SyncCanonicalize.canonicalizeJSON(payload),
        version: self.vMid, tieBreak: .rejectEqual)
      // Dedup: first-occurrence-wins, so 2 distinct items.
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?", arguments: [date]), 2)
      XCTAssertEqual(
        try String.fetchOne(
          db, sql: "SELECT task_id FROM current_focus_items WHERE date = ? AND position = 0",
          arguments: [date]), self.taskA)
    }
  }

  /// SYNC-MED-2: a current_focus upsert that OMITS `task_ids` must PRESERVE the
  /// existing focus items, not treat the absent array as `[]` and wipe them.
  func testCurrentFocusOmittingTaskIdsPreservesItems() throws {
    try withDB { db in
      let date = "2026-04-01"
      try ApplyDayScoped.applyCurrentFocusUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:00:00Z"),
            "task_ids": .array([.string(self.taskA), .string(self.taskB)]),
          ])), version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?", arguments: [date]), 2)

      // Newer envelope omits task_ids — the briefing changed, the item list did not.
      try ApplyDayScoped.applyCurrentFocusUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "briefing": .string("Refocused"),
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:05:00Z"),
          ])), version: "1711234569000_0000_dec0000100000001", tieBreak: .rejectEqual)

      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?", arguments: [date]), 2,
        "omitting task_ids must preserve the focus items, not wipe them")
    }
  }

  /// The complement: an explicit empty `task_ids: []` still CLEARS the items.
  func testCurrentFocusEmptyTaskIdsClearsItems() throws {
    try withDB { db in
      let date = "2026-04-01"
      try ApplyDayScoped.applyCurrentFocusUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:00:00Z"),
            "task_ids": .array([.string(self.taskA)]),
          ])), version: self.vMid, tieBreak: .rejectEqual)
      try ApplyDayScoped.applyCurrentFocusUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:05:00Z"),
            "task_ids": .array([]),
          ])), version: "1711234569000_0000_dec0000100000001", tieBreak: .rejectEqual)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?", arguments: [date]), 0,
        "an explicit empty task_ids array clears the items")
    }
  }

  func testCurrentFocusDeleteCascadesItems() throws {
    try withDB { db in
      let date = "2026-04-01"
      try ApplyDayScoped.applyCurrentFocusUpsert(
        db, entityId: date,
        payload: try SyncCanonicalize.canonicalizeJSON(
          .object([
            "created_at": .string("2026-04-01T00:00:00Z"),
            "updated_at": .string("2026-04-01T00:00:00Z"),
            "task_ids": .array([.string(self.taskA)]),
          ])), version: self.vMid, tieBreak: .rejectEqual)
      try ApplyDayScoped.applyCurrentFocusDelete(
        db, entityId: date, version: "1711234569000_0000_dec0000100000001")
      XCTAssertEqual(
        try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM current_focus WHERE date = ?", arguments: [date]),
        0)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM current_focus_items WHERE date = ?", arguments: [date]), 0)
    }
  }

  func testCurrentFocusRejectsNonCanonicalTaskIdentity() throws {
    try withDB { db in
      XCTAssertThrowsError(
        try ApplyDayScoped.applyCurrentFocusUpsert(
          db, entityId: "2026-04-01",
          payload: try SyncCanonicalize.canonicalizeJSON(
            .object([
              "created_at": .string("2026-04-01T00:00:00Z"),
              "updated_at": .string("2026-04-01T00:00:00Z"),
              "task_ids": .array([.string("task-not-a-uuid")]),
            ])), version: self.vMid, tieBreak: .rejectEqual)
      ) { error in
        guard case let ApplyError.invalidPayload(message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("task_ids[0]"))
      }
    }
  }

  // MARK: - focus_schedule

  func testFocusScheduleUpsertMaterializesBlocks() throws {
    try withDB { db in
      let date = "2026-04-01"
      let payload: JSONValue = .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "blocks": .array([
          .object([
            "block_type": .string("task"), "start_minutes": .int(540), "end_minutes": .int(570),
            "task_id": .string(self.taskA), "event_source": .null,
          ]),
          .object([
            "block_type": .string("buffer"), "start_minutes": .string("10:00"),
            "end_minutes": .string("10:30"), "event_source": .null,
          ]),
        ]),
      ])
      try ApplyDayScoped.applyFocusScheduleUpsert(
        db, entityId: date, payload: try SyncCanonicalize.canonicalizeJSON(payload),
        version: self.vMid, tieBreak: .rejectEqual)
      XCTAssertEqual(
        try Int64.fetchOne(
          db, sql: "SELECT COUNT(*) FROM focus_schedule_blocks WHERE date = ?",
          arguments: [date]), 2)
    }
  }

  func testFocusScheduleRejectsProviderEventId() throws {
    try withDB { db in
      let date = "2026-04-01"
      let payload: JSONValue = .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "blocks": .array([
          .object([
            "block_type": .string("event"), "start_minutes": .int(540), "end_minutes": .int(570),
            "calendar_event_id": .string("eventkit-cal-item-123"),
            "event_source": .string("canonical"),
          ])
        ]),
      ])
      XCTAssertThrowsError(
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: date, payload: try SyncCanonicalize.canonicalizeJSON(payload),
          version: self.vMid, tieBreak: .rejectEqual))
    }
  }

  func testFocusScheduleRejectsNonCanonicalTaskIdentity() throws {
    try withDB { db in
      let payload: JSONValue = .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "blocks": .array([
          .object([
            "block_type": .string("task"), "start_minutes": .int(540), "end_minutes": .int(570),
            "task_id": .string("task-not-a-uuid"), "event_source": .null,
          ])
        ]),
      ])
      XCTAssertThrowsError(
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: "2026-04-01",
          payload: try SyncCanonicalize.canonicalizeJSON(payload),
          version: self.vMid, tieBreak: .rejectEqual)
      ) { error in
        guard case let ApplyError.invalidPayload(message) = error else {
          return XCTFail("expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("task_id"))
      }
    }
  }

  func testFocusScheduleRejectsInvertedRange() throws {
    try withDB { db in
      let date = "2026-04-01"
      let payload: JSONValue = .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "blocks": .array([
          .object([
            "block_type": .string("task"), "start_minutes": .int(570), "end_minutes": .int(540),
            "event_source": .null,
          ])
        ]),
      ])
      XCTAssertThrowsError(
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: date, payload: try SyncCanonicalize.canonicalizeJSON(payload),
          version: self.vMid, tieBreak: .rejectEqual))
    }
  }

  func testFocusScheduleRejectsZeroLengthRange() throws {
    try withDB { db in
      let payload: JSONValue = .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "blocks": .array([
          .object([
            "block_type": .string("buffer"), "start_minutes": .int(570), "end_minutes": .int(570),
            "event_source": .null,
          ])
        ]),
      ])
      XCTAssertThrowsError(
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: "2026-04-01",
          payload: try SyncCanonicalize.canonicalizeJSON(payload),
          version: self.vMid, tieBreak: .rejectEqual))
    }
  }

  /// DE-2: an unknown `block_type` at the inner applier boundary must degrade
  /// to a single-envelope
  /// `invalidPayload` DROP, never a `SQLITE_CONSTRAINT` → `ApplyError.db` that
  /// aborts and WEDGES the whole inbound batch (re-fetching the poison page
  /// forever). The focus applier must pre-validate against the closed
  /// `FocusBlockType` set, matching the calendar / habit appliers.
  func testFocusScheduleRejectsUnknownBlockTypeAsInvalidPayloadNotDbWedge() throws {
    try withDB { db in
      let date = "2026-04-01"
      let payload: JSONValue = .object([
        "created_at": .string("2026-04-01T00:00:00Z"),
        "updated_at": .string("2026-04-01T00:00:00Z"),
        "blocks": .array([
          .object([
            "block_type": .string("meeting"), "start_minutes": .int(540), "end_minutes": .int(570),
            "event_source": .null,
          ])
        ]),
      ])
      XCTAssertThrowsError(
        try ApplyDayScoped.applyFocusScheduleUpsert(
          db, entityId: date, payload: try SyncCanonicalize.canonicalizeJSON(payload),
          version: self.vMid, tieBreak: .rejectEqual)
      ) { error in
        guard case ApplyError.invalidPayload = error else {
          return XCTFail(
            "unknown block_type must throw .invalidPayload (single-envelope drop), got \(error) "
              + "— a .db error would wedge the whole inbound batch")
        }
      }
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
