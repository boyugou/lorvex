import GRDB
import LorvexDomain
import XCTest

@testable import LorvexStore
@testable import LorvexSync

/// Ports `lorvex-sync/src/payload_build/aggregate/tests.rs`. Each of the four
/// aggregate roots embeds its materialized child collection; non-aggregate
/// kinds and missing rows return `nil`; every registered aggregate resolves
/// through a builder arm (never the missing-arm invariant error).
final class PayloadBuildAggregateTests: XCTestCase {
  private func seedScheduleHeader(_ db: Database, date: String) throws {
    try db.execute(
      sql: """
        INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at) \
        VALUES (?, 'rationale', 'UTC', '0000000000000_0000_0000000000000000', \
                '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
        """,
      arguments: [date])
  }

  private func seedList(_ db: Database, id: String) throws {
    try db.execute(
      sql: """
        INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at) \
        VALUES (?, 'L', '0000000000000_0000_0000000000000000', '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
        """,
      arguments: [id])
  }

  private func seedTask(_ db: Database, id: String, listId: String) throws {
    try db.execute(
      sql: """
        INSERT INTO tasks (id, title, list_id, version, created_at, updated_at) \
        VALUES (?, 'T', ?, '0000000000000_0000_0000000000000000', '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
        """,
      arguments: [id, listId])
  }

  func testCurrentFocusPayloadEmbedsTaskIdsInPositionOrder() throws {
    let store = try SyncTestSupport.freshStore()
    let date = "2026-04-01"
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at) \
          VALUES (?, 'brief', 'UTC', '0000000000000_0000_0000000000000000', \
                  '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')
          """,
        arguments: [date])
      try seedList(db, id: "list-default")
      for tid in ["t-2", "t-1"] {
        try seedTask(db, id: tid, listId: "list-default")
      }
      try CurrentFocusItemsRepo.materializeFocusItems(db, date: date, taskIds: ["t-2", "t-1"])

      let payload = try PayloadBuild.buildAggregatePayload(
        db, entityType: EntityName.currentFocus, entityId: date)
      guard case .object(let obj) = payload, case .array(let taskIds) = obj["task_ids"] else {
        return XCTFail("expected task_ids array")
      }
      XCTAssertEqual(taskIds, [.string("t-2"), .string("t-1")])
    }
  }

  func testFocusSchedulePayloadEmbedsBlocks() throws {
    let store = try SyncTestSupport.freshStore()
    let date = "2026-04-02"
    try store.writer.write { db in
      try seedScheduleHeader(db, date: date)
      try db.execute(
        sql: """
          INSERT INTO focus_schedule_blocks \
              (date, position, block_type, start_minutes, end_minutes, title) \
          VALUES (?, 0, 'buffer', 540, 600, 'Warm up'), (?, 1, 'buffer', 600, 660, 'Plan')
          """,
        arguments: [date, date])

      let payload = try PayloadBuild.buildAggregatePayload(
        db, entityType: EntityName.focusSchedule, entityId: date)
      guard case .object(let obj) = payload, case .array(let blocks) = obj["blocks"] else {
        return XCTFail("expected blocks array")
      }
      XCTAssertEqual(blocks.count, 2)
      guard case .object(let b0) = blocks[0], case .object(let b1) = blocks[1] else {
        return XCTFail("expected block objects")
      }
      XCTAssertEqual(b0["start_minutes"], .int(540))
      XCTAssertEqual(b1["title"], .string("Plan"))
    }
  }

  func testDailyReviewPayloadEmbedsLinks() throws {
    let store = try SyncTestSupport.freshStore()
    let date = "2026-04-03"
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO daily_reviews (date, summary, version, created_at, updated_at) \
          VALUES (?, 'summary', '0000000000000_0000_0000000000000000', \
                  '2026-04-03T00:00:00.000Z', '2026-04-03T00:00:00.000Z')
          """,
        arguments: [date])
      try seedList(db, id: "list-x")
      try seedTask(db, id: "t-x", listId: "list-x")
      try DailyReviewOpsRepo.materializeReviewTaskLinks(db, date: date, taskIds: ["t-x"])
      try DailyReviewOpsRepo.materializeReviewListLinks(db, date: date, listIds: ["list-x"])

      let payload = try PayloadBuild.buildAggregatePayload(
        db, entityType: EntityName.dailyReview, entityId: date)
      guard case .object(let obj) = payload,
        case .array(let taskIds) = obj["linked_task_ids"],
        case .array(let listIds) = obj["linked_list_ids"]
      else {
        return XCTFail("expected linked arrays")
      }
      XCTAssertEqual(taskIds, [.string("t-x")])
      XCTAssertEqual(listIds, [.string("list-x")])
    }
  }

  func testDailyReviewPayloadCanonicalizesSetValuedLinkOrder() throws {
    let store = try SyncTestSupport.freshStore()
    let date = "2026-04-03"
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO daily_reviews (date, summary, version, created_at, updated_at)
          VALUES (?, 'summary', '0000000000000_0000_0000000000000000',
                  '2026-04-03T00:00:00.000Z', '2026-04-03T00:00:00.000Z')
          """,
        arguments: [date])
      try seedList(db, id: "list-z")
      try seedList(db, id: "list-a")
      try seedTask(db, id: "task-z", listId: "list-z")
      try seedTask(db, id: "task-a", listId: "list-a")
      try DailyReviewOpsRepo.materializeReviewTaskLinks(
        db, date: date, taskIds: ["task-z", "task-a", "task-z"])
      try DailyReviewOpsRepo.materializeReviewListLinks(
        db, date: date, listIds: ["list-z", "list-a", "list-z"])

      let payload = try PayloadBuild.buildAggregatePayload(
        db, entityType: EntityName.dailyReview, entityId: date)
      guard case .object(let object) = payload else {
        return XCTFail("expected daily-review payload object")
      }
      XCTAssertEqual(
        object["linked_task_ids"],
        .array([.string("task-a"), .string("task-z")]))
      XCTAssertEqual(
        object["linked_list_ids"],
        .array([.string("list-a"), .string("list-z")]))
    }
  }

  func testCalendarEventPayloadEmbedsAttendees() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      try db.execute(
        sql: """
          INSERT INTO calendar_events \
              (id, title, start_date, start_time, all_day, event_type, attendees,
               content_version, recurrence_topology_version, version, created_at, updated_at) \
          VALUES ('evt-1', 'Standup', '2026-04-04', '09:00', 0, 'event', \
                  '[{"email":"a@example.com","name":"A"}]', \
                  '0000000000000_0000_0000000000000000', \
                  '0000000000000_0000_0000000000000000', \
                  '0000000000000_0000_0000000000000000', \
                  '2026-04-04T00:00:00.000Z', '2026-04-04T00:00:00.000Z')
          """)

      let payload = try PayloadBuild.buildAggregatePayload(
        db, entityType: EntityName.calendarEvent, entityId: "evt-1")
      guard case .object(let obj) = payload, case .array(let attendees) = obj["attendees"] else {
        return XCTFail("expected attendees array")
      }
      XCTAssertEqual(attendees.count, 1)
      guard case .object(let a0) = attendees[0] else { return XCTFail("expected attendee object") }
      XCTAssertEqual(a0["email"], .string("a@example.com"))
      XCTAssertEqual(obj["all_day"], .bool(false))
    }
  }

  func testNonAggregateTypesReturnNil() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      XCTAssertNil(try PayloadBuild.buildAggregatePayload(db, entityType: "task", entityId: "task-x"))
      XCTAssertNil(try PayloadBuild.buildAggregatePayload(db, entityType: "list", entityId: "list-x"))
      XCTAssertNil(try PayloadBuild.buildAggregatePayload(db, entityType: "habit", entityId: "h-x"))
    }
  }

  func testKnownAggregatesReturnNilWhenRowMissing() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      for kind in PayloadBuild.aggregateRootKindsWithDedicatedComposition {
        XCTAssertNil(
          try PayloadBuild.buildAggregatePayload(
            db, entityType: kind.asString, entityId: "missing-id"),
          "expected nil for missing \(kind.asString)")
      }
    }
  }

  func testEveryRegisteredAggregateResolvesThroughABuilderArm() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      for kind in PayloadBuild.aggregateRootKindsWithDedicatedComposition {
        XCTAssertNoThrow(
          try PayloadBuild.buildAggregatePayload(
            db, entityType: kind.asString, entityId: "missing-id"),
          "registered aggregate \(kind.asString) reached the missing-arm branch")
      }
    }
  }
}
