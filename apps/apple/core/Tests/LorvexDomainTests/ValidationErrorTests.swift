import XCTest

@testable import LorvexDomain

/// The `description` strings are the wire wording surfaced to AI clients and
/// must stay byte-identical to the Rust `Display` impls.
final class ValidationErrorTests: XCTestCase {
  func testEmptyWording() {
    XCTAssertEqual(ValidationError.empty("title").description, "title must not be empty")
  }

  func testTooLongWording() {
    XCTAssertEqual(
      ValidationError.tooLong(field: "title", max: 100, actual: 150).description,
      "title exceeds maximum length (150 chars, limit 100)")
  }

  func testOutOfRangeWording() {
    XCTAssertEqual(
      ValidationError.outOfRange(field: "priority", min: 1, max: 5, actual: 9).description,
      "priority is out of range (9, must be 1..=5)")
  }

  func testInvalidFormatWording() {
    XCTAssertEqual(
      ValidationError.invalidFormat(field: "entity_id", expected: "UUID", actual: "foo")
        .description,
      "entity_id has invalid format (got \"foo\", expected UUID)")
  }

  func testMessagePassesThrough() {
    XCTAssertEqual(ValidationError.message("custom failure").description, "custom failure")
    XCTAssertEqual(ValidationError(message: "custom failure"), .message("custom failure"))
  }

  func testEquatable() {
    XCTAssertEqual(ValidationError.empty("a"), ValidationError.empty("a"))
    XCTAssertNotEqual(ValidationError.empty("a"), ValidationError.empty("b"))
  }
}
