import XCTest

@testable import LorvexDomain

/// The canonical status-classification predicates and their SQL-list twins are
/// one source of truth: `actionableStatusSqlList` / `activeStatusSqlList` derive
/// from `TaskStatus.isActionable` / `.isActive`, so the SQL membership and the
/// Swift predicate can never disagree.
final class StatusClassificationTests: XCTestCase {
  func testIsActionableIsOpenAndInProgress() {
    XCTAssertTrue(TaskStatus.open.isActionable)
    XCTAssertTrue(TaskStatus.inProgress.isActionable)
    XCTAssertFalse(TaskStatus.someday.isActionable)
    XCTAssertFalse(TaskStatus.completed.isActionable)
    XCTAssertFalse(TaskStatus.cancelled.isActionable)
  }

  func testIsActiveIsEveryNonTerminalStatus() {
    XCTAssertTrue(TaskStatus.open.isActive)
    XCTAssertTrue(TaskStatus.inProgress.isActive)
    XCTAssertTrue(TaskStatus.someday.isActive)
    XCTAssertFalse(TaskStatus.completed.isActive)
    XCTAssertFalse(TaskStatus.cancelled.isActive)
  }

  func testIsActiveIsComplementOfIsTerminal() {
    for status in TaskStatus.allCases {
      XCTAssertNotEqual(
        status.isActive, status.isTerminal,
        "isActive must be the exact complement of isTerminal for \(status)")
    }
  }

  func testActionableSupersetIsActive() {
    for status in TaskStatus.allCases where status.isActionable {
      XCTAssertTrue(
        status.isActive, "every actionable status must also be active: \(status)")
    }
  }

  /// The SQL lists render exactly the statuses satisfying the predicate, in
  /// `allCases` order — so the SQL fragment and the Swift filter select the same
  /// set. This is the derived-from-one-source guarantee.
  func testActionableSqlListMatchesPredicate() {
    let expected = TaskStatus.allCases
      .filter { $0.isActionable }
      .map { "'\($0.rawValue)'" }
      .joined(separator: ", ")
    XCTAssertEqual(StatusName.actionableStatusSqlList, expected)
    XCTAssertEqual(StatusName.actionableStatusSqlList, "'open', 'in_progress'")
  }

  func testActiveSqlListMatchesPredicate() {
    let expected = TaskStatus.allCases
      .filter { $0.isActive }
      .map { "'\($0.rawValue)'" }
      .joined(separator: ", ")
    XCTAssertEqual(StatusName.activeStatusSqlList, expected)
    XCTAssertEqual(StatusName.activeStatusSqlList, "'open', 'in_progress', 'someday'")
  }
}
