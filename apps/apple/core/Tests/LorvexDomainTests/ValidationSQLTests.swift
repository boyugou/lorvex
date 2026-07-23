import XCTest

@testable import LorvexDomain

/// The Rust `assert_safe_sql_identifier` panics on invalid input. Swift's
/// `precondition` aborts uncatchably, so the rejection cases are asserted
/// against ``ValidationSQL/isSafeSQLIdentifier(_:)`` (the predicate the abort
/// wraps) rather than via `XCTAssertThrowsError`.
final class ValidationSQLTests: XCTestCase {
  func testValidSimple() { XCTAssertTrue(ValidationSQL.isSafeSQLIdentifier("tasks")) }
  func testValidWithUnderscores() { XCTAssertTrue(ValidationSQL.isSafeSQLIdentifier("ai_changelog")) }
  func testValidWithDigits() { XCTAssertTrue(ValidationSQL.isSafeSQLIdentifier("table_2")) }

  func testRejectsEmpty() { XCTAssertFalse(ValidationSQL.isSafeSQLIdentifier("")) }
  func testRejectsSemicolon() {
    XCTAssertFalse(ValidationSQL.isSafeSQLIdentifier("tasks; DROP TABLE tasks"))
  }
  func testRejectsSpaces() { XCTAssertFalse(ValidationSQL.isSafeSQLIdentifier("my table")) }
  func testRejectsQuotes() { XCTAssertFalse(ValidationSQL.isSafeSQLIdentifier("tasks'")) }
  func testRejectsParens() { XCTAssertFalse(ValidationSQL.isSafeSQLIdentifier("tasks()")) }
  func testRejectsDash() { XCTAssertFalse(ValidationSQL.isSafeSQLIdentifier("my-table")) }
}
