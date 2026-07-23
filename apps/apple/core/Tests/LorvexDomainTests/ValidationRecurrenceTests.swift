import XCTest

@testable import LorvexDomain

/// Covers the recurrence membership helpers. Normalizer-exercising cases live
/// in `ValidationRecurrenceNormalizeTests.swift`.
final class ValidationRecurrenceTests: XCTestCase {
  func testFreqMembership() {
    for f in ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"] {
      XCTAssertTrue(ValidationRecurrence.isValidRecurrenceFreq(f))
    }
    XCTAssertFalse(ValidationRecurrence.isValidRecurrenceFreq("HOURLY"))
    XCTAssertFalse(ValidationRecurrence.isValidRecurrenceFreq("weekly"))
  }

  func testBydayCodeMembership() {
    for c in ["MO", "TU", "WE", "TH", "FR", "SA", "SU"] {
      XCTAssertTrue(ValidationRecurrence.isValidBydayCode(c))
    }
    XCTAssertFalse(ValidationRecurrence.isValidBydayCode("XX"))
    XCTAssertFalse(ValidationRecurrence.isValidBydayCode("mo"))
  }

  func testBydayTokenAcceptsBareCodesForEveryFreq() {
    for code in ["MO", "TU", "WE", "TH", "FR", "SA", "SU"] {
      for freq in ["WEEKLY", "MONTHLY", "YEARLY"] {
        XCTAssertTrue(
          ValidationRecurrence.isValidBydayTokenForFreq(code, freq: freq),
          "bare \(code) under \(freq)")
      }
    }
  }

  func testBydayTokenYearlyAcceptsFullOrdinalRange() {
    for token in ["1MO", "+2WE", "-1FR", "53SU", "-53SU"] {
      XCTAssertTrue(
        ValidationRecurrence.isValidBydayTokenForFreq(token, freq: "YEARLY"),
        "prefixed \(token) under YEARLY")
    }
  }

  func testBydayTokenMonthlyCapsOrdinalAtFive() {
    for token in ["1MO", "+5WE", "-5FR"] {
      XCTAssertTrue(
        ValidationRecurrence.isValidBydayTokenForFreq(token, freq: "MONTHLY"),
        "in-range MONTHLY \(token)")
    }
    for token in ["6MO", "+10WE", "-7FR", "53SU"] {
      XCTAssertFalse(
        ValidationRecurrence.isValidBydayTokenForFreq(token, freq: "MONTHLY"),
        "out-of-range MONTHLY \(token)")
    }
  }

  func testBydayTokenWeeklyRejectsEveryOrdinal() {
    for token in ["1MO", "+2WE", "-1FR", "5SU"] {
      XCTAssertFalse(
        ValidationRecurrence.isValidBydayTokenForFreq(token, freq: "WEEKLY"),
        "WEEKLY ordinal \(token)")
    }
    XCTAssertTrue(ValidationRecurrence.isValidBydayTokenForFreq("MO", freq: "WEEKLY"))
  }

  func testBydayTokenRejectsGarbageAndOutOfRange() {
    for token in ["", "X", "MX", "1XX", "0MO", "54MO", "-54MO", "+0FR", "+-1MO", "01MO"] {
      XCTAssertFalse(
        ValidationRecurrence.isValidBydayTokenForFreq(token, freq: "YEARLY"),
        "\(token) must reject")
    }
  }

  func testMaxCalendarRecurrenceCount() {
    XCTAssertEqual(ValidationRecurrence.maxCalendarRecurrenceCount, 365)
  }

  func testRecurrenceWarningEquatable() {
    XCTAssertEqual(
      RecurrenceWarning.bymonthdaySkipsMonths(day: 31),
      RecurrenceWarning.bymonthdaySkipsMonths(day: 31))
    XCTAssertNotEqual(
      RecurrenceWarning.bymonthdaySkipsMonths(day: 31), RecurrenceWarning.leapYearBirthday)
  }
}
