import XCTest

@testable import LorvexCore

/// Pins the scope → core-operation mapping for cancelling a recurring task.
/// The operation order for `.all` is load-bearing: the recurrence rule must be
/// removed *before* cancelling so `cancelTask` spawns no successor.
final class RecurringTaskCancelScopeTests: XCTestCase {
  func testThisOccurrenceCancelsWithoutTouchingTheRule() {
    XCTAssertEqual(
      RecurringTaskCancelScope.thisOccurrence.coreOperations,
      [.cancelTask])
  }

  func testAllRemovesRecurrenceBeforeCancelling() {
    XCTAssertEqual(
      RecurringTaskCancelScope.all.coreOperations,
      [.removeRecurrence, .cancelTask])
  }

  func testAllRemovesRecurrenceStrictlyBeforeCancel() {
    let ops = RecurringTaskCancelScope.all.coreOperations
    guard
      let removeIndex = ops.firstIndex(of: .removeRecurrence),
      let cancelIndex = ops.firstIndex(of: .cancelTask)
    else {
      return XCTFail("expected both removeRecurrence and cancelTask in .all")
    }
    XCTAssertLessThan(
      removeIndex, cancelIndex,
      "removeRecurrence must run before cancelTask so no successor spawns")
  }

  func testEverySupportedScopeEndsWithCancel() {
    // Every cancel scope must ultimately cancel the current occurrence.
    for scope in RecurringTaskCancelScope.allCases {
      XCTAssertEqual(
        scope.coreOperations.last, .cancelTask,
        "scope \(scope.rawValue) must end by cancelling the task")
    }
  }

  func testThisAndFollowingIsNotOffered() {
    // "This and following" is deliberately absent: no single existing core op
    // drops the current occurrence and truncates the tail.
    XCTAssertEqual(
      Set(RecurringTaskCancelScope.allCases),
      [.thisOccurrence, .all])
  }
}
