import XCTest

@testable import LorvexStore

final class TaskRolloverPolicyTests: XCTestCase {
  private let before = "0000000000001_0000_1111111111111111"
  private let decision = "0000000000002_0000_1111111111111111"
  private let after = "0000000000003_0000_1111111111111111"

  func testDecisionDominatingEveryRegisterCancelsStableSuccessor() throws {
    let result = try TaskRolloverPolicy.resolveContradiction(
      decisionVersion: decision,
      childClocks: TaskRolloverRegisterClocks(
        content: before, schedule: decision, lifecycle: before, archive: before))
    XCTAssertEqual(result, .cancelStableSuccessor)
  }

  func testAnyRegisterAfterDecisionRerootsSuccessor() throws {
    for clocks in [
      TaskRolloverRegisterClocks(
        content: after, schedule: before, lifecycle: before, archive: before),
      TaskRolloverRegisterClocks(
        content: before, schedule: after, lifecycle: before, archive: before),
      TaskRolloverRegisterClocks(
        content: before, schedule: before, lifecycle: after, archive: before),
      TaskRolloverRegisterClocks(
        content: before, schedule: before, lifecycle: before, archive: after),
    ] {
      XCTAssertEqual(
        try TaskRolloverPolicy.resolveContradiction(
          decisionVersion: decision, childClocks: clocks),
        .rerootAdvancedSuccessor)
    }
  }
}
