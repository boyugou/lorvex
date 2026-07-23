import GRDB
import XCTest

@testable import LorvexStore
@testable import LorvexSync

final class ApplyTaskCalendarEventLinkTests: XCTestCase {
  func testDecisionEndpointIsRejectedAsTypedInvalidPayload() throws {
    let store = try SyncTestSupport.freshStore()
    try store.writer.write { db in
      let taskID = "00000000-0000-7000-8000-000000000101"
      let masterID = "00000000-0000-7000-8000-000000000102"
      let decisionID = "00000000-0000-8000-8000-000000000103"
      let version = "1760000000000_0000_dec0000100000001"
      let timestamp = "2026-10-01T00:00:00.000Z"
      try db.execute(
        sql: """
          INSERT INTO tasks (
            id, title, status, priority, defer_count,
            version, created_at, updated_at
          ) VALUES (?, 'Task', 'open', 1, 0, ?, ?, ?)
          """,
        arguments: [taskID, version, timestamp, timestamp])
      try db.execute(
        sql: """
          INSERT INTO calendar_events (
            id, title, recurrence, start_date, start_time, end_time, all_day,
            recurrence_generation, content_version, recurrence_topology_version,
            version, created_at, updated_at
          ) VALUES (?, 'Series', '{"FREQ":"DAILY"}', '2026-10-01', '09:00', '09:30', 0,
                    ?, ?, ?, ?, ?, ?)
          """,
        arguments: [masterID, version, version, version, version, timestamp, timestamp])
      try db.execute(
        sql: """
          INSERT INTO calendar_events (
            id, title, start_date, start_time, end_time, all_day,
            series_id, recurrence_instance_date, occurrence_state,
            recurrence_generation, content_version, recurrence_topology_version,
            version, created_at, updated_at
          ) VALUES (?, 'Replacement', '2026-10-02', '10:00', '10:30', 0,
                    ?, '2026-10-02', 'replacement', ?, NULL, NULL, ?, ?, ?)
          """,
        arguments: [decisionID, masterID, version, version, timestamp, timestamp])
      let payload = try SyncCanonicalize.canonicalizeJSON(
        .object([
          "task_id": .string(taskID),
          "calendar_event_id": .string(decisionID),
          "created_at": .string(timestamp),
          "updated_at": .string(timestamp),
        ]))

      XCTAssertThrowsError(
        try ApplyEdge.applyTaskCalendarEventLinkUpsert(
          db, entityId: "\(taskID):\(decisionID)", payload: payload,
          version: version, tieBreak: .rejectEqual)
      ) { error in
        guard case ApplyError.invalidPayload(let message) = error else {
          return XCTFail("Expected invalidPayload, got \(error)")
        }
        XCTAssertTrue(message.contains("must reference a base event"))
      }
      XCTAssertNil(
        try Int.fetchOne(
          db,
          sql: "SELECT 1 FROM task_calendar_event_links WHERE task_id = ? AND calendar_event_id = ?",
          arguments: [taskID, decisionID]))
    }
  }
}
