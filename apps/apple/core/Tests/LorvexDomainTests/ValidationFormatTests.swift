import XCTest

@testable import LorvexDomain

final class ValidationFormatTests: XCTestCase {
  func okURL(_ r: Result<String, ValidationError>, line: UInt = #line) {
    if case .failure(let e) = r { XCTFail("expected ok: \(e)", line: line) }
  }
  func errURL(_ r: Result<String, ValidationError>, line: UInt = #line) {
    if case .success(let v) = r { XCTFail("expected error, got \(v)", line: line) }
  }
  func okVoid(_ r: Result<Void, ValidationError>, line: UInt = #line) {
    if case .failure(let e) = r { XCTFail("expected ok: \(e)", line: line) }
  }
  func errVoid(_ r: Result<Void, ValidationError>, line: UInt = #line) {
    if case .success = r { XCTFail("expected error", line: line) }
  }
  func canonical(_ r: Result<String, ValidationError>, line: UInt = #line) -> String? {
    if case .success(let v) = r { return v }
    XCTFail("expected ok", line: line)
    return nil
  }

  // -- validateUserURL --

  func testURLAllowsHttps() { okURL(ValidationFormat.validateUserURL("https://example.com/path?x=1")) }
  func testURLAllowsHttp() { okURL(ValidationFormat.validateUserURL("http://example.com")) }
  func testURLAllowsMailto() { okURL(ValidationFormat.validateUserURL("mailto:user@example.com")) }
  func testURLAllowsTel() { okURL(ValidationFormat.validateUserURL("tel:+15555555555")) }
  func testURLRejectsJavascriptScheme() { errURL(ValidationFormat.validateUserURL("javascript:alert(1)")) }
  func testURLRejectsJavascriptCaseInsensitive() {
    errURL(ValidationFormat.validateUserURL("JaVaScRiPt:alert(1)"))
  }
  func testURLRejectsDataScheme() {
    errURL(ValidationFormat.validateUserURL("data:text/html;base64,PHNjcmlwdD4="))
  }
  func testURLRejectsFileScheme() { errURL(ValidationFormat.validateUserURL("file:///etc/passwd")) }
  func testURLRejectsEmpty() { errURL(ValidationFormat.validateUserURL("")) }
  func testURLRejectsWhitespaceOnly() { errURL(ValidationFormat.validateUserURL("   ")) }
  func testURLRejectsNoScheme() { errURL(ValidationFormat.validateUserURL("example.com/path")) }

  func testURLLowercasesSchemeInCanonicalForm() {
    XCTAssertEqual(canonical(ValidationFormat.validateUserURL("MAILTO:foo@example.com")), "mailto:foo@example.com")
    XCTAssertEqual(
      canonical(ValidationFormat.validateUserURL("HTTPS://Example.com/Path")),
      "https://Example.com/Path")
    XCTAssertEqual(canonical(ValidationFormat.validateUserURL("Tel:+15555555555")), "tel:+15555555555")
    XCTAssertEqual(
      canonical(ValidationFormat.validateCalendarURL("WEBCAL://Example.com/feed.ics")),
      "webcal://Example.com/feed.ics")
  }

  func testURLRejectsControlCharacters() {
    errURL(ValidationFormat.validateUserURL("https://example.com/\npath"))
    errURL(ValidationFormat.validateUserURL("https://example.com/\rpath"))
    errURL(ValidationFormat.validateUserURL("https://example.com/\tpath"))
  }

  func testURLRejectsJavascriptWithLeadingZeroWidth() {
    errURL(ValidationFormat.validateUserURL("\u{200B}javascript:alert(1)"))
    errURL(ValidationFormat.validateUserURL("\u{FEFF}javascript:alert(1)"))
    errURL(ValidationFormat.validateUserURL("\u{202E}javascript:alert(1)"))
  }

  func testURLStripsLeadingZeroWidthForLegitimateScheme() {
    okURL(ValidationFormat.validateUserURL("\u{200B}https://example.com/path"))
    okURL(ValidationFormat.validateUserURL("\u{FEFF}https://example.com/path"))
  }

  func testCalendarURLRejectsJavascriptWithLeadingZeroWidth() {
    errURL(ValidationFormat.validateCalendarURL("\u{200B}javascript:alert(1)"))
    errURL(ValidationFormat.validateCalendarURL("\u{202E}javascript:alert(1)"))
  }

  func testURLValidatorsReturnSanitizedCanonicalFormForBidiZeroWidth() {
    let dirtyUser = "  \u{202E}\u{200B}\u{FEFF}https://example.com/path?x=1  "
    XCTAssertEqual(canonical(ValidationFormat.validateUserURL(dirtyUser)), "https://example.com/path?x=1")

    let dirtyCalendar = "\u{202E}\u{200B}webcal://example.com/feed.ics\u{FEFF}"
    XCTAssertEqual(
      canonical(ValidationFormat.validateCalendarURL(dirtyCalendar)), "webcal://example.com/feed.ics")
  }

  // -- validateCalendarDateRange --

  func testCalendarDateRangeNilEnd() {
    guard case .success(let v) = ValidationFormat.validateCalendarDateRange(startDate: "2026-01-01", endDate: nil)
    else { return XCTFail() }
    XCTAssertNil(v)
  }

  func testCalendarDateRangeEndAfterStart() {
    guard
      case .success(let v) = ValidationFormat.validateCalendarDateRange(
        startDate: "2026-01-01", endDate: "2026-02-01")
    else { return XCTFail() }
    XCTAssertEqual(v, "2026-02-01")
  }

  func testCalendarDateRangeEndEqualsStart() {
    guard
      case .success(let v) = ValidationFormat.validateCalendarDateRange(
        startDate: "2026-01-01", endDate: "2026-01-01")
    else { return XCTFail() }
    XCTAssertEqual(v, "2026-01-01")
  }

  func testCalendarDateRangeEndBeforeStart() {
    XCTAssertEqual(
      ValidationFormat.validateCalendarDateRange(startDate: "2026-02-01", endDate: "2026-01-01"),
      .failure(
        .invalidFormat(
          field: "end_date", expected: "end_date must be on or after start_date",
          actual: "end_date=2026-01-01, start_date=2026-02-01")))
  }

  // -- validateHexColor --

  func testHexColorSixDigit() { okVoid(ValidationFormat.validateHexColor("#aabbcc")) }
  func testHexColorThreeDigit() { okVoid(ValidationFormat.validateHexColor("#abc")) }
  func testHexColorUppercase() { okVoid(ValidationFormat.validateHexColor("#AABBCC")) }
  func testHexColorNoHash() { errVoid(ValidationFormat.validateHexColor("aabbcc")) }
  func testHexColorBadLength() { errVoid(ValidationFormat.validateHexColor("#aabb")) }
  func testHexColorNonHex() { errVoid(ValidationFormat.validateHexColor("#gggggg")) }

  func testHexColorErrorShape() {
    assertFailure(
      ValidationFormat.validateHexColor("xyz"),
      .invalidFormat(field: "hex_color", expected: "#RGB or #RRGGBB", actual: "xyz"))
  }

  func testHexColorFieldCustomLabel() {
    assertFailure(
      ValidationFormat.validateHexColorField("xyz", field: "color"),
      .invalidFormat(field: "color", expected: "#RGB or #RRGGBB", actual: "xyz"))
  }
}
