import XCTest

@testable import LorvexDomain

/// Ports the `validate_date_format` / `validate_time_format` cases from
/// `validation/tests/format.rs`, plus the RFC 5545 compact UNTIL parsers on
/// ``IsoDate`` (the accept/reject set the recurrence normalizer depends on).
final class ValidationDateTimeFormatTests: XCTestCase {
  private func ok(_ r: Result<Void, ValidationError>, line: UInt = #line) {
    if case .failure(let e) = r { XCTFail("expected ok: \(e)", line: line) }
  }
  private func err(_ r: Result<Void, ValidationError>, line: UInt = #line) {
    if case .success = r { XCTFail("expected error", line: line) }
  }

  // -- validateDateFormat --
  func testDateValid() { ok(ValidationFormat.validateDateFormat("2026-03-24")) }
  func testDateLeapDayValid() { ok(ValidationFormat.validateDateFormat("2024-02-29")) }
  func testDateLeapDayInvalid() { err(ValidationFormat.validateDateFormat("2023-02-29")) }
  func testDateWrongFormatSlash() { err(ValidationFormat.validateDateFormat("2026/03/24")) }
  func testDateWrongFormatDayMonth() { err(ValidationFormat.validateDateFormat("24-03-2026")) }
  func testDateEmpty() { err(ValidationFormat.validateDateFormat("")) }
  func testDateGarbage() { err(ValidationFormat.validateDateFormat("not-a-date")) }
  func testDateMonth13() { err(ValidationFormat.validateDateFormat("2026-13-01")) }
  func testDateDay32() { err(ValidationFormat.validateDateFormat("2026-01-32")) }

  func testDateErrorShape() {
    if case .failure(let e) = ValidationFormat.validateDateFormat("nope") {
      XCTAssertEqual(e, .invalidFormat(field: "date", expected: "YYYY-MM-DD", actual: "nope"))
    } else {
      XCTFail("expected error")
    }
  }

  // -- validateTimeFormat --
  func testTimeValid() { ok(ValidationFormat.validateTimeFormat("09:30")) }
  func testTimeMidnight() { ok(ValidationFormat.validateTimeFormat("00:00")) }
  func testTimeMax() { ok(ValidationFormat.validateTimeFormat("23:59")) }
  func testTimeHour24() { err(ValidationFormat.validateTimeFormat("24:00")) }
  func testTimeMinute60() { err(ValidationFormat.validateTimeFormat("12:60")) }
  func testTimeNoColon() { err(ValidationFormat.validateTimeFormat("0930")) }
  func testTimeWithSeconds() { err(ValidationFormat.validateTimeFormat("09:30:00")) }
  func testTimeEmpty() { err(ValidationFormat.validateTimeFormat("")) }
  func testTimeSingleDigitHour() { err(ValidationFormat.validateTimeFormat("9:30")) }
  func testTimeNonNumeric() { err(ValidationFormat.validateTimeFormat("ab:cd")) }

  func testTimeErrorShape() {
    if case .failure(let e) = ValidationFormat.validateTimeFormat("9:30") {
      XCTAssertEqual(
        e, .invalidFormat(field: "time", expected: "HH:MM (00:00-23:59)", actual: "9:30"))
    } else {
      XCTFail("expected error")
    }
  }

  // -- IsoDate.parseUntilToYmd (RFC 5545 compact forms) --
  func testUntilHyphenated() {
    XCTAssertEqual(IsoDate.parseUntilToYmd("2026-12-31"), "2026-12-31")
  }
  func testUntilCompactDate() {
    XCTAssertEqual(IsoDate.parseUntilToYmd("20261231"), "2026-12-31")
  }
  func testUntilCompactDateTimeZ() {
    XCTAssertEqual(IsoDate.parseUntilToYmd("20261231T235959Z"), "2026-12-31")
  }
  func testUntilCompactDateTimeRejectsMissingZ() {
    XCTAssertNil(IsoDate.parseUntilToYmd("20261231T235959"))
  }
  func testUntilCompactDateTimeRejectsLowercaseZ() {
    XCTAssertNil(IsoDate.parseUntilToYmd("20261231T235959z"))
  }
  func testUntilCompactDateRejectsBadDate() {
    XCTAssertNil(IsoDate.parseUntilToYmd("20260230"))  // Feb 30
    XCTAssertNil(IsoDate.parseUntilToYmd("20261301"))  // month 13
    XCTAssertNil(IsoDate.parseUntilToYmd("20250229"))  // non-leap Feb 29
  }
  func testUntilCompactDateTimeRejectsBadTime() {
    XCTAssertNil(IsoDate.parseUntilToYmd("20261231T240000Z"))  // hour 24
    XCTAssertNil(IsoDate.parseUntilToYmd("20261231T236000Z"))  // minute 60
  }
  func testUntilRejectsGarbage() {
    XCTAssertNil(IsoDate.parseUntilToYmd("not-a-date"))
    XCTAssertNil(IsoDate.parseUntilToYmd(""))
    XCTAssertNil(IsoDate.parseUntilToYmd("2026/12/31"))
    XCTAssertNil(IsoDate.parseUntilToYmd("202612"))  // too short
  }
}
