import XCTest

@testable import LorvexDomain

final class StatusTransitionTests: XCTestCase {
  func testCompleteFromOpen() {
    let actions = statusTransitionColumns(
      oldStatus: .open, newStatus: .completed, now: "2026-03-26T10:00:00Z")
    XCTAssertTrue(actions.contains(.setText(column: "completed_at", value: "2026-03-26T10:00:00Z")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_deferred_at")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_defer_reason")))
  }

  func testCancelFromOpen() {
    let actions = statusTransitionColumns(
      oldStatus: .open, newStatus: .cancelled, now: "2026-03-26T10:00:00Z")
    XCTAssertTrue(actions.contains(.setNull(column: "completed_at")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_deferred_at")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_defer_reason")))
  }

  func testReopenFromCompleted() {
    let actions = statusTransitionColumns(
      oldStatus: .completed, newStatus: .open, now: "2026-03-26T10:00:00Z")
    XCTAssertTrue(actions.contains(.setNull(column: "completed_at")))
    XCTAssertTrue(actions.contains(.setNull(column: "planned_date")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_deferred_at")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_defer_reason")))
    XCTAssertTrue(actions.contains(.setInt(column: "defer_count", value: 0)))
  }

  func testNoChangeSameStatus() {
    XCTAssertTrue(statusTransitionColumns(oldStatus: .open, newStatus: .open, now: "now").isEmpty)
    XCTAssertTrue(
      statusTransitionColumns(oldStatus: .completed, newStatus: .completed, now: "now").isEmpty)
    XCTAssertTrue(
      statusTransitionColumns(oldStatus: .someday, newStatus: .someday, now: "now").isEmpty)
  }

  func testOpenToSomedayNoMetadataChanges() {
    let actions = statusTransitionColumns(
      oldStatus: .open, newStatus: .someday, now: "2026-03-26T10:00:00Z")
    XCTAssertTrue(actions.isEmpty)
  }

  func testSomedayToOpenClearsDeferralAndPlannedDate() {
    let actions = statusTransitionColumns(
      oldStatus: .someday, newStatus: .open, now: "2026-03-26T10:00:00Z")
    XCTAssertTrue(actions.contains(.setNull(column: "completed_at")))
    XCTAssertTrue(actions.contains(.setNull(column: "planned_date")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_deferred_at")))
    XCTAssertTrue(actions.contains(.setNull(column: "last_defer_reason")))
    XCTAssertTrue(actions.contains(.setInt(column: "defer_count", value: 0)))
  }

  func testSomedayToCompletedSetsCompletedAt() {
    let actions = statusTransitionColumns(
      oldStatus: .someday, newStatus: .completed, now: "2026-03-26T10:00:00Z")
    XCTAssertTrue(actions.contains(.setText(column: "completed_at", value: "2026-03-26T10:00:00Z")))
  }

  func testCompletedToSomedayClearsCompletedAt() {
    let actions = statusTransitionColumns(
      oldStatus: .completed, newStatus: .someday, now: "2026-03-26T10:00:00Z")
    XCTAssertTrue(actions.contains(.setNull(column: "completed_at")))
    XCTAssertFalse(actions.contains(.setNull(column: "planned_date")))
  }

  func testTypedEntryPointCoversEveryStatusPair() {
    let all: [TaskStatus] = [.open, .completed, .cancelled, .someday]
    for old in all {
      for new in all {
        _ = statusTransitionColumns(oldStatus: old, newStatus: new, now: "ts")
      }
    }
  }
}
