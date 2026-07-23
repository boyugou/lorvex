import XCTest

@testable import LorvexDomain

final class AttendeeStatusTests: XCTestCase {
  func testAllowlistContainsEveryCanonicalValue() {
    for value in ["accepted", "declined", "tentative", "needs-action"] {
      XCTAssertNotNil(
        AttendeeStatus.parseStrict(value),
        "\(value) must be parseable as a canonical AttendeeStatus")
    }
  }

  func testAllowlistRejectsUnderscoreForm() {
    XCTAssertNil(AttendeeStatus.parseStrict("needs_action"))
  }

  func testParseStrictRejectsUnderscoreForm() {
    XCTAssertNil(AttendeeStatus.parseStrict("needs_action"))
    XCTAssertEqual(AttendeeStatus.parseStrict("needs-action"), .needsAction)
  }

  func testParseStrictRejectsUnknownValues() {
    for bad in ["", "Accepted", "MAYBE", "delegated", "completed"] {
      XCTAssertNil(AttendeeStatus.parseStrict(bad), "\(bad) must not normalize")
    }
  }

  func testFromStrReturnsTypedErrorForUnknown() {
    do {
      _ = try AttendeeStatus.fromString("definitely-not-a-partstat")
      XCTFail("expected throw")
    } catch let err as UnknownAttendeeStatus {
      XCTAssertTrue(err.description.contains("definitely-not-a-partstat"))
    } catch {
      XCTFail("unexpected error type: \(error)")
    }
  }

  func testDisplayListsCanonicalValuesInStableOrder() {
    XCTAssertEqual(
      attendeeStatusAllowlistDisplay(),
      "accepted, declined, tentative, needs-action")
  }
}
