import LorvexDomain
import XCTest

@testable import LorvexWorkflow

/// Planner-level recurrence-config tests. The DB applier has separate coverage
/// in `RecurrenceConfigApplyTests`.
final class RecurrenceConfigTests: XCTestCase {
  private func state(
    recurrence: String? = nil, groupId: String? = nil,
    anchor: String? = nil, due: String? = nil, planned: String? = nil
  ) -> RecurrenceConfig.State {
    RecurrenceConfig.State(
      recurrence: recurrence, recurrenceGroupId: groupId,
      canonicalOccurrenceDate: anchor, dueDate: due, plannedDate: planned)
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

  func testEnableWithoutDueDateStartsOnTheDayTheTaskIsPlannedFor() {
    for planned in ["2026-04-01", "2026-04-09"] {
      let (_, actions) = RecurrenceConfig.planRecurrenceTransition(
        old: state(planned: planned), newRecurrence: "{\"FREQ\":\"DAILY\"}", today: "2026-04-01")
      XCTAssertEqual(actions.setDueDate, planned)
      XCTAssertEqual(actions.setCanonicalOccurrenceDate, .set(planned))
      XCTAssertNil(actions.setPlannedDate)
    }
  }

  func testEnableWithoutDueDateStartsTodayAndMovesAPlanThatHasPassed() {
    let (_, actions) = RecurrenceConfig.planRecurrenceTransition(
      old: state(planned: "2026-03-20"), newRecurrence: "{\"FREQ\":\"DAILY\"}", today: "2026-04-01")
    XCTAssertEqual(actions.setDueDate, "2026-04-01")
    XCTAssertEqual(actions.setCanonicalOccurrenceDate, .set("2026-04-01"))
    XCTAssertEqual(actions.setPlannedDate, "2026-04-01")
  }

  func testEnableKeepsTheDueDateWhateverThePlannedDay() {
    let (_, actions) = RecurrenceConfig.planRecurrenceTransition(
      old: state(due: "2026-04-15", planned: "2026-04-09"),
      newRecurrence: "{\"FREQ\":\"DAILY\"}", today: "2026-04-01")
    XCTAssertNil(actions.setDueDate)
    XCTAssertNil(actions.setPlannedDate, "a plan before a real deadline is the user's own")
    XCTAssertEqual(actions.setCanonicalOccurrenceDate, .set("2026-04-15"))
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
    XCTAssertTrue(actions.clearRecurrenceInstanceKey)
  }

}
