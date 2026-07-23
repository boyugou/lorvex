import XCTest

@testable import LorvexDomain

/// Parse/serialize contract for ``ChangelogRetentionPolicy``: the tolerant
/// stored-JSON parser, canonical integer day values, and the
/// serialize → re-parse identity of ``ChangelogRetentionPolicy/wireValue``.
final class ChangelogRetentionPolicyTests: XCTestCase {

  // MARK: - Tolerant parse

  func testAbsentAndBlankInputParseToMaximum() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse(nil), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse(""), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("   "), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("null"), .maximum)
  }

  func testMalformedAndUnknownInputParseToMaximum() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse("{ not json"), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("\"someday\""), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("true"), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("[30]"), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("{\"days\":30}"), .maximum)
  }

  func testStringTokensParse() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse("\"maximum\""), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("\"off\""), .off)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("\"MAXIMUM\""), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("\"Off\""), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("\"never\""), .maximum)
  }

  func testPositiveIntegerParsesToDays() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse("7"), .days(7))
    XCTAssertEqual(ChangelogRetentionPolicy.parse("30"), .days(30))
    XCTAssertEqual(ChangelogRetentionPolicy.parse("90"), .days(90))
    XCTAssertEqual(ChangelogRetentionPolicy.parse("365"), .days(365))
  }

  func testZeroParsesToMaximum() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse("0"), .maximum)
  }

  func testNegativeParsesToMaximum() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse("-1"), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("-90"), .maximum)
  }

  func testOutOfRangeIntegerParsesToMaximum() {
    // Exceeds UInt32.max (4_294_967_295) but fits Int64.
    XCTAssertEqual(ChangelogRetentionPolicy.parse("4294967296"), .maximum)
    // Exceeds Int64.max — parsed as an unsigned literal, still too large.
    XCTAssertEqual(ChangelogRetentionPolicy.parse("99999999999999999999"), .maximum)
  }

  func testUInt32MaxBoundaryParsesToDays() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse("4294967295"), .days(UInt32.max))
  }

  func testWholeAndFractionalNumbersParse() {
    XCTAssertEqual(ChangelogRetentionPolicy.parse("30.0"), .days(30))
    XCTAssertEqual(ChangelogRetentionPolicy.parse("0.0"), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parse("-5.0"), .maximum)
    // A fractional day count degrades to maximum rather than rounding.
    XCTAssertEqual(ChangelogRetentionPolicy.parse("30.5"), .maximum)
  }

  func testStrictParseDistinguishesValidMaximumFromInvalidInput() {
    XCTAssertEqual(ChangelogRetentionPolicy.parseStrict("\"maximum\""), .maximum)
    XCTAssertEqual(ChangelogRetentionPolicy.parseStrict("\"off\""), .off)
    XCTAssertEqual(ChangelogRetentionPolicy.parseStrict("30"), .days(30))
    XCTAssertEqual(ChangelogRetentionPolicy.parseStrict("30.0"), .days(30))

    XCTAssertNil(ChangelogRetentionPolicy.parseStrict(nil))
    XCTAssertNil(ChangelogRetentionPolicy.parseStrict("\"someday\""))
    XCTAssertNil(ChangelogRetentionPolicy.parseStrict("0"))
    XCTAssertNil(ChangelogRetentionPolicy.parseStrict("-1"))
    XCTAssertNil(ChangelogRetentionPolicy.parseStrict("30.5"))
    XCTAssertNil(ChangelogRetentionPolicy.parseStrict("4294967296"))
    XCTAssertNil(ChangelogRetentionPolicy.parseStrict("null"))
  }

  // MARK: - Canonical serialization

  func testWireValueIsCanonicalJSON() {
    XCTAssertEqual(ChangelogRetentionPolicy.maximum.wireValue, "\"maximum\"")
    XCTAssertEqual(ChangelogRetentionPolicy.off.wireValue, "\"off\"")
    XCTAssertEqual(ChangelogRetentionPolicy.days(30).wireValue, "30")
  }

  func testSerializeThenParseIsIdentity() {
    let cases: [ChangelogRetentionPolicy] = [
      .maximum, .off, .days(1), .days(7), .days(30), .days(90), .days(365),
      .days(UInt32.max),
    ]
    for policy in cases {
      XCTAssertEqual(
        ChangelogRetentionPolicy.parse(policy.wireValue), policy,
        "wireValue must round-trip through parse for \(policy)")
    }
  }

  func testConservativeCollisionWinnerIsADataPreservingSemilattice() {
    let policies: [ChangelogRetentionPolicy] = [
      .off, .days(7), .days(30), .days(365), .maximum,
    ]
    for lhs in policies {
      XCTAssertEqual(
        ChangelogRetentionPolicy.conservativeCollisionWinner(lhs, lhs), lhs)
      for rhs in policies {
        XCTAssertEqual(
          ChangelogRetentionPolicy.conservativeCollisionWinner(lhs, rhs),
          ChangelogRetentionPolicy.conservativeCollisionWinner(rhs, lhs))
      }
    }
    XCTAssertEqual(
      ChangelogRetentionPolicy.conservativeCollisionWinner(.off, .days(30)),
      .days(30))
    XCTAssertEqual(
      ChangelogRetentionPolicy.conservativeCollisionWinner(.days(30), .days(365)),
      .days(365))
    XCTAssertEqual(
      ChangelogRetentionPolicy.conservativeCollisionWinner(.days(365), .maximum),
      .maximum)
  }
}
