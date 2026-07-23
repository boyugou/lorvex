import XCTest

@testable import LorvexStore

final class TaskRecurrenceSuccessorIDTests: XCTestCase {
  func testDeterministicUuidV8GoldenValue() {
    XCTAssertEqual(
      TaskRecurrenceSuccessorID.make(
        parentTaskId: "parent-1", recurrenceGroupId: "group-1"),
      "ca57af4d-28cc-850d-a7eb-404066244163")
  }

  func testBothInputsParticipateInIdentity() {
    let baseline = TaskRecurrenceSuccessorID.make(
      parentTaskId: "parent-1", recurrenceGroupId: "group-1")
    XCTAssertNotEqual(
      baseline,
      TaskRecurrenceSuccessorID.make(
        parentTaskId: "parent-2", recurrenceGroupId: "group-1"))
    XCTAssertNotEqual(
      baseline,
      TaskRecurrenceSuccessorID.make(
        parentTaskId: "parent-1", recurrenceGroupId: "group-2"))
  }
}
