import LorvexDomain
import XCTest

@testable import LorvexWorkflow

/// Planner-level recurrence-config tests. The DB applier has separate coverage
/// in `RecurrenceConfigApplyTests`.
final class RecurrenceConfigTests: XCTestCase {
  private func state(
    recurrence: String? = nil, groupId: String? = nil,
    anchor: String? = nil, due: String? = nil
  ) -> RecurrenceConfig.State {
    RecurrenceConfig.State(
      recurrence: recurrence, recurrenceGroupId: groupId,
      canonicalOccurrenceDate: anchor, dueDate: due)
  }

  func testEnableGeneratesAllActiveSeriesFields() {
    let old = state(due: "2026-04-15")
    let (transition, actions) = RecurrenceConfig.planRecurrenceTransition(
      old: old, newRecurrence: "{\"FREQ\":\"DAILY\"}", today: "2026-04-01")
    XCTAssertEqual(transition, .enable)
    XCTAssertNotNil(actions.setRecurrenceGroupId)
    XCTAssertEqual(actions.setCanonicalOccurrenceDate, .set("2026-04-15"))
    XCTAssertNil(actions.setDueDate)
  }

  func testEnableWithoutDueDateAssignsToday() {
    let old = state()
    let (transition, actions) = RecurrenceConfig.planRecurrenceTransition(
      old: old, newRecurrence: "{\"FREQ\":\"DAILY\"}", today: "2026-04-01")
    XCTAssertEqual(transition, .enable)
    XCTAssertEqual(actions.setDueDate, "2026-04-01")
    XCTAssertEqual(actions.setCanonicalOccurrenceDate, .set("2026-04-01"))
  }

  func testUpdateRulePreservesSeriesIdentity() {
    let old = state(
      recurrence: "{\"FREQ\":\"DAILY\"}", groupId: "grp-1",
      anchor: "2026-04-15", due: "2026-04-15")
    let (transition, actions) = RecurrenceConfig.planRecurrenceTransition(
      old: old, newRecurrence: "{\"FREQ\":\"WEEKLY\"}", today: "2026-04-01")
    XCTAssertEqual(transition, .updateRule)
    XCTAssertNil(actions.setRecurrenceGroupId)
    XCTAssertTrue(actions.setCanonicalOccurrenceDate.isUnset)
  }

  func testDisableClearsActiveSeriesConfig() {
    let old = state(
      recurrence: "{\"FREQ\":\"DAILY\"}", groupId: "grp-1",
      anchor: "2026-04-15", due: "2026-04-15")
    let (transition, actions) = RecurrenceConfig.planRecurrenceTransition(
      old: old, newRecurrence: nil, today: "2026-04-01")
    XCTAssertEqual(transition, .disable)
    XCTAssertTrue(actions.clearRecurrenceGroupId)
    XCTAssertTrue(actions.clearCanonicalOccurrenceDate)
  }

}
