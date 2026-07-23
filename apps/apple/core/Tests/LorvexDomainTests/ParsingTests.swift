import XCTest

@testable import LorvexDomain

/// Ports the self-contained subset of `parsing/tests.rs`:
/// `parse_json_string_preference`, the `parse_hhmm_to_minutes` /
/// `format_minutes_hhmm` round-trip family, and `escape_like`. The
/// `serde_json::Value`/HLC-backed preference-state helpers are not ported (their
/// dependencies are not yet available in Swift).
final class ParsingTests: XCTestCase {
  // ── parseJsonStringPreference ────────────────────────────────────────

  func testJsonStringPrefAcceptsCanonical() {
    XCTAssertEqual(
      Parsing.parseJsonStringPreference("\"America/Los_Angeles\""), "America/Los_Angeles")
  }

  func testJsonStringPrefRejectsBlank() {
    XCTAssertNil(Parsing.parseJsonStringPreference("\"   \""))
  }

  func testJsonStringPrefRejectsNonJsonRaw() {
    XCTAssertNil(Parsing.parseJsonStringPreference("America/Los_Angeles"))
  }

  func testJsonStringPrefRejectsNonStringJson() {
    XCTAssertNil(Parsing.parseJsonStringPreference("true"))
  }

  func testJsonStringPrefRejectsNestedJsonStringLayer() {
    XCTAssertNil(Parsing.parseJsonStringPreference(#""\"America/Los_Angeles\"""#))
  }

  // ── parseHhmmToMinutes / formatMinutesHhmm ───────────────────────────

  func testParseHhmmAcceptsCanonical() {
    XCTAssertEqual(Parsing.parseHhmmToMinutes("00:00"), 0)
    XCTAssertEqual(Parsing.parseHhmmToMinutes("09:30"), 570)
    XCTAssertEqual(Parsing.parseHhmmToMinutes("23:59"), 1439)
  }

  func testParseHhmmRejectsLeadingSign() {
    XCTAssertNil(Parsing.parseHhmmToMinutes("+9:00"))
    XCTAssertNil(Parsing.parseHhmmToMinutes("-1:30"))
  }

  func testParseHhmmRejectsWhitespace() {
    XCTAssertNil(Parsing.parseHhmmToMinutes(" 9:00"))
    XCTAssertNil(Parsing.parseHhmmToMinutes("9 :00"))
  }

  func testParseHhmmRejectsNonAsciiDigits() {
    XCTAssertNil(Parsing.parseHhmmToMinutes("１２:３０"))
  }

  func testParseHhmmRejectsWrongSeparator() {
    XCTAssertNil(Parsing.parseHhmmToMinutes("12-30"))
    XCTAssertNil(Parsing.parseHhmmToMinutes("1230 "))
  }

  func testParseHhmmRejectsOutOfRange() {
    XCTAssertNil(Parsing.parseHhmmToMinutes("24:00"))
    XCTAssertNil(Parsing.parseHhmmToMinutes("23:60"))
  }

  func testParseHhmmRoundTripsForEveryMinuteOfDay() {
    for minute in Int64(0)..<1440 {
      guard let formatted = Parsing.formatMinutesHhmm(minute) else {
        return XCTFail("format failed at \(minute)")
      }
      XCTAssertEqual(Parsing.parseHhmmToMinutes(formatted), minute)
    }
  }

  // ── escapeLike ───────────────────────────────────────────────────────

  func testEscapeLikeNoSpecials() {
    XCTAssertEqual(Parsing.escapeLike("hello"), "hello")
  }

  func testEscapeLikeWithSpecials() {
    XCTAssertEqual(Parsing.escapeLike("100%"), "100\\%")
    XCTAssertEqual(Parsing.escapeLike("a_b"), "a\\_b")
    XCTAssertEqual(Parsing.escapeLike("c\\d"), "c\\\\d")
  }
}
