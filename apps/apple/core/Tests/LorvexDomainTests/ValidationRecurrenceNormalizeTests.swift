import XCTest

@testable import LorvexDomain

/// Ports the normalizer-exercising recurrence tests:
/// `validation/tests/recurrence_core.rs`, `recurrence_byday.rs`, and
/// `recurrence_bymonth_warnings.rs`. Output strings and warning sets are
/// asserted against the same expectations as the Rust suites.
final class ValidationRecurrenceNormalizeTests: XCTestCase {

  // MARK: - helpers

  private func normalize(_ input: String) -> String {
    switch ValidationRecurrence.normalizeTaskRecurrence(input) {
    case let .success(opt):
      guard let value = opt else {
        XCTFail("expected canonical, got nil")
        return ""
      }
      return value
    case let .failure(e):
      XCTFail("expected success, got error: \(e)")
      return ""
    }
  }

  private func errorMessage(_ input: String) -> String {
    switch ValidationRecurrence.normalizeTaskRecurrence(input) {
    case .success:
      XCTFail("expected error, got success")
      return ""
    case let .failure(e):
      return e.description
    }
  }

  private func normalizeWithWarnings(_ input: String) -> (String, [RecurrenceWarning]) {
    switch ValidationRecurrence.normalizeTaskRecurrenceWithWarnings(input) {
    case let .success(opt):
      guard let value = opt else {
        XCTFail("expected canonical, got nil")
        return ("", [])
      }
      return (value.canonical, value.warnings)
    case let .failure(e):
      XCTFail("expected success, got error: \(e)")
      return ("", [])
    }
  }

  private func field(_ canonical: String, _ key: String) -> JSONValue? {
    JSONValue.parse(canonical)?.asObject?[key]
  }

  // MARK: - recurrence_core.rs

  func testCountAndUntilMutuallyExclusive() {
    let err = errorMessage(#"{"FREQ":"DAILY","COUNT":3,"UNTIL":"2026-04-10"}"#)
    XCTAssertTrue(err.contains("COUNT and UNTIL are mutually exclusive"), err)
  }

  func testBydayOnlyValidForWeekly() {
    let err = errorMessage(#"{"FREQ":"DAILY","BYDAY":["MO","WE"]}"#)
    XCTAssertTrue(err.contains("BYDAY is only valid for WEEKLY"), err)
  }

  func testBymonthdayOnlyValidForMonthlyYearly() {
    let err = errorMessage(#"{"FREQ":"WEEKLY","BYMONTHDAY":15}"#)
    XCTAssertTrue(err.contains("BYMONTHDAY is only valid for MONTHLY/YEARLY"), err)
  }

  func testCanonicalKeyOrderPreserved() {
    let canonical = normalize(#"{"INTERVAL":2,"BYDAY":["MO","FR"],"FREQ":"WEEKLY"}"#)
    let obj = JSONValue.parse(canonical)?.asObject
    XCTAssertEqual(obj?.keys.sorted(), ["BYDAY", "FREQ", "INTERVAL"])
    XCTAssertEqual(field(canonical, "FREQ"), .string("WEEKLY"))
    XCTAssertEqual(field(canonical, "INTERVAL"), .int(2))
    XCTAssertEqual(field(canonical, "BYDAY"), .array([.string("MO"), .string("FR")]))
    // Byte-exact canonical form (sorted keys, compact).
    XCTAssertEqual(canonical, #"{"BYDAY":["MO","FR"],"FREQ":"WEEKLY","INTERVAL":2}"#)

    let canonical2 = normalize(#"{"FREQ":"WEEKLY","BYDAY":["MO","FR"],"INTERVAL":2}"#)
    XCTAssertEqual(canonical, canonical2)
  }

  func testEmptyInputReturnsNone() {
    XCTAssertEqual(try? ValidationRecurrence.normalizeTaskRecurrence("").get(), .some(nil))
    XCTAssertEqual(try? ValidationRecurrence.normalizeTaskRecurrence("   ").get(), .some(nil))
  }

  func testUnknownKeyRejected() {
    let err = errorMessage(#"{"FREQ":"DAILY","FOOBAR":"MO"}"#)
    XCTAssertTrue(err.contains("unknown key"), err)
  }

  func testValidDailyNormalized() {
    let canonical = normalize(#"{"FREQ":"DAILY"}"#)
    XCTAssertEqual(field(canonical, "FREQ"), .string("DAILY"))
    XCTAssertEqual(field(canonical, "INTERVAL"), .int(1))
  }

  func testBymonthdayValidForMonthly() {
    // A scalar on input is accepted for back-compat and normalizes to a
    // one-element array.
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"MONTHLY","BYMONTHDAY":15}"#), "BYMONTHDAY"), .array([.int(15)]))
  }

  func testBymonthdayValidForYearly() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"YEARLY","BYMONTHDAY":1}"#), "BYMONTHDAY"), .array([.int(1)]))
  }

  // MARK: - C9: multi-day BYMONTHDAY arrays

  func testBymonthdayArrayNormalizes() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"MONTHLY","BYMONTHDAY":[1,15]}"#), "BYMONTHDAY"),
      .array([.int(1), .int(15)]))
  }

  func testBymonthdayArraySortedAndDeduped() {
    // Logically-identical rules must converge on byte-identical canonical JSON.
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"MONTHLY","BYMONTHDAY":[15,1,15,20]}"#), "BYMONTHDAY"),
      .array([.int(1), .int(15), .int(20)]))
    XCTAssertEqual(
      normalize(#"{"FREQ":"MONTHLY","BYMONTHDAY":[20,1,15]}"#),
      normalize(#"{"FREQ":"MONTHLY","BYMONTHDAY":[1,15,20]}"#))
  }

  func testBymonthdayArrayNegativeAndPositive() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"MONTHLY","BYMONTHDAY":[-1,15]}"#), "BYMONTHDAY"),
      .array([.int(-1), .int(15)]))
  }

  func testBymonthdayEmptyArrayDropped() {
    // An empty array carries no day-of-month constraint and is omitted.
    XCTAssertNil(field(normalize(#"{"FREQ":"MONTHLY","BYMONTHDAY":[]}"#), "BYMONTHDAY"))
  }

  func testBymonthdayArrayRejectsOutOfRangeElement() {
    for bad in ["[15,0]", "[1,32]", "[-32,1]", #"[1,"x"]"#] {
      let err = errorMessage(#"{"FREQ":"MONTHLY","BYMONTHDAY":\#(bad)}"#)
      XCTAssertTrue(err.contains("BYMONTHDAY"), "\(bad): \(err)")
    }
  }

  func testBymonthdayArrayOnlyValidForMonthlyYearly() {
    let err = errorMessage(#"{"FREQ":"WEEKLY","BYMONTHDAY":[1,15]}"#)
    XCTAssertTrue(err.contains("BYMONTHDAY is only valid for MONTHLY/YEARLY"), err)
  }

  func testBymonthdayMultidaySkipWarningsPerDay() {
    let (_, warnings) = normalizeWithWarnings(#"{"FREQ":"MONTHLY","BYMONTHDAY":[15,30,31]}"#)
    XCTAssertEqual(
      warnings, [.bymonthdaySkipsMonths(day: 30), .bymonthdaySkipsMonths(day: 31)])
  }

  func testBymonthdayMultidayYearlyFebDoesNotCollapseToLeapBirthday() {
    // The leap-birthday collapse is reserved for the single-day [29] shape; a
    // multi-day February rule keeps the per-day skip warning for 29.
    let (_, warnings) = normalizeWithWarnings(
      #"{"FREQ":"YEARLY","BYMONTH":[2],"BYMONTHDAY":[28,29]}"#)
    XCTAssertEqual(warnings, [.bymonthdaySkipsMonths(day: 29)])
  }

  func testCountValid() {
    XCTAssertEqual(field(normalize(#"{"FREQ":"DAILY","COUNT":5}"#), "COUNT"), .int(5))
  }

  func testUntilValid() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"WEEKLY","UNTIL":"2026-12-31"}"#), "UNTIL"), .string("2026-12-31"))
  }

  func testUntilAcceptsRfc5545DateTime() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"WEEKLY","UNTIL":"20261231T235959Z"}"#), "UNTIL"),
      .string("2026-12-31"))
  }

  func testUntilAcceptsRfc5545Date() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"WEEKLY","UNTIL":"20261231"}"#), "UNTIL"), .string("2026-12-31"))
  }

  func testUntilRejectsGarbage() {
    let err = errorMessage(#"{"FREQ":"WEEKLY","UNTIL":"not-a-date"}"#)
    XCTAssertTrue(err.contains("UNTIL"), err)
  }

  func testInvalidFreqRejected() {
    let err = errorMessage(#"{"FREQ":"HOURLY"}"#)
    XCTAssertTrue(err.contains("FREQ must be"), err)
  }

  func testNegativeIntervalRejected() {
    let err = errorMessage(#"{"FREQ":"DAILY","INTERVAL":-1}"#)
    XCTAssertTrue(err.contains("INTERVAL must be a positive integer"), err)
  }

  func testZeroCountRejected() {
    let err = errorMessage(#"{"FREQ":"DAILY","COUNT":0}"#)
    XCTAssertTrue(err.contains("COUNT must be a positive integer"), err)
  }

  /// serde `as_i64()` returns nil for a float literal even when integral; a
  /// fractional INTERVAL must reject.
  func testFractionalIntervalRejected() {
    let err = errorMessage(#"{"FREQ":"DAILY","INTERVAL":2.5}"#)
    XCTAssertTrue(err.contains("INTERVAL must be a positive integer"), err)
  }

  // MARK: - recurrence_byday.rs (normalizer cases)

  func testMonthlyBydayWithOrdinalAccepted() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"MONTHLY","BYDAY":["1MO"]}"#), "BYDAY"), .array([.string("1MO")]))
  }

  func testYearlyBydayWithNegativeOrdinalAccepted() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"YEARLY","BYDAY":["-1FR"]}"#), "BYDAY"), .array([.string("-1FR")]))
  }

  func testWeeklyRejectsBydayOrdinalPrefix() {
    let msg = errorMessage(#"{"FREQ":"WEEKLY","BYDAY":["1MO"]}"#)
    XCTAssertTrue(msg.contains("WEEKLY") && msg.contains("ordinal prefixes"), msg)
  }

  func testMonthlyRejectsBydayOrdinalAboveFive() {
    let msg = errorMessage(#"{"FREQ":"MONTHLY","BYDAY":["10MO"]}"#)
    XCTAssertTrue(msg.contains("MONTHLY") && msg.contains("1..=5"), msg)
  }

  func testYearlyAcceptsBydayOrdinalAtFullRange() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"YEARLY","BYDAY":["53SU"]}"#), "BYDAY"), .array([.string("53SU")]))
  }

  func testWkstAcceptedAndCanonicalized() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"WEEKLY","INTERVAL":2,"WKST":"MO"}"#), "WKST"), .string("MO"))
  }

  func testWkstRejectsInvalidCode() {
    XCTAssertTrue(errorMessage(#"{"FREQ":"WEEKLY","WKST":"XX"}"#).contains("WKST"))
  }

  func testBysetposArrayAccepted() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[1]}"#), "BYSETPOS"),
      .array([.int(1)]))
  }

  func testBysetposRejectedForDailyAndWeekly() {
    for raw in [
      #"{"FREQ":"DAILY","BYSETPOS":[1]}"#,
      #"{"FREQ":"WEEKLY","BYDAY":["MO"],"BYSETPOS":[1]}"#,
    ] {
      XCTAssertTrue(errorMessage(raw).contains("BYSETPOS"), raw)
    }
  }

  func testBysetposRejectsZeroAndOutOfRange() {
    for raw in [
      #"{"FREQ":"MONTHLY","BYSETPOS":[0]}"#,
      #"{"FREQ":"MONTHLY","BYSETPOS":[367]}"#,
      #"{"FREQ":"MONTHLY","BYSETPOS":[-367]}"#,
    ] {
      XCTAssertTrue(errorMessage(raw).contains("BYSETPOS"), raw)
    }
  }

  // MARK: - recurrence_bymonth_warnings.rs

  func testYearlyBymonthAcceptedAndCanonicalized() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"YEARLY","BYMONTH":[2]}"#), "BYMONTH"), .array([.int(2)]))
  }

  func testLeapYearBirthdayAcceptedWithDedicatedWarning() {
    let (canonical, warnings) = normalizeWithWarnings(
      #"{"FREQ":"YEARLY","BYMONTH":[2],"BYMONTHDAY":29}"#)
    XCTAssertTrue(canonical.contains(#""BYMONTH":[2]"#))
    XCTAssertTrue(canonical.contains(#""BYMONTHDAY":[29]"#))
    XCTAssertEqual(warnings, [.leapYearBirthday])
  }

  func testBymonthRejectsZeroAndThirteen() {
    for raw in [
      #"{"FREQ":"YEARLY","BYMONTH":[0]}"#,
      #"{"FREQ":"YEARLY","BYMONTH":[13]}"#,
      #"{"FREQ":"YEARLY","BYMONTH":[-1]}"#,
    ] {
      XCTAssertTrue(errorMessage(raw).contains("BYMONTH"), raw)
    }
  }

  func testDailyRejectsBymonth() {
    let msg = errorMessage(#"{"FREQ":"DAILY","BYMONTH":[2]}"#)
    XCTAssertTrue(msg.contains("BYMONTH") && msg.contains("DAILY"), msg)
  }

  func testWeeklyBymonthAccepted() {
    XCTAssertEqual(
      field(normalize(#"{"FREQ":"WEEKLY","BYDAY":["MO"],"BYMONTH":[2,8]}"#), "BYMONTH"),
      .array([.int(2), .int(8)]))
  }

  func testByhourByminuteRejected() {
    let msg = errorMessage(#"{"FREQ":"DAILY","BYHOUR":[9,17],"BYMINUTE":[0,30]}"#)
    XCTAssertTrue(msg.contains("BYHOUR") || msg.contains("BYMINUTE"), msg)
  }

  func testByhourRejectsOutOfRange() {
    XCTAssertTrue(errorMessage(#"{"FREQ":"DAILY","BYHOUR":[24]}"#).contains("BYHOUR"))
  }

  func testByminuteRejectsOutOfRange() {
    XCTAssertTrue(errorMessage(#"{"FREQ":"DAILY","BYMINUTE":[60]}"#).contains("BYMINUTE"))
  }

  func testBymonthday31EmitsSkipWarning() {
    let (canonical, warnings) = normalizeWithWarnings(#"{"FREQ":"MONTHLY","BYMONTHDAY":31}"#)
    XCTAssertTrue(canonical.contains(#""BYMONTHDAY":[31]"#))
    XCTAssertEqual(warnings, [.bymonthdaySkipsMonths(day: 31)])
  }

  func testBymonthday29_30_31EmitWarning() {
    for day in [29, 30, 31] {
      let (_, warnings) = normalizeWithWarnings(#"{"FREQ":"MONTHLY","BYMONTHDAY":\#(day)}"#)
      XCTAssertEqual(warnings, [.bymonthdaySkipsMonths(day: Int64(day))], "day=\(day)")
    }
  }

  func testBymonthday28DoesNotWarn() {
    let (_, warnings) = normalizeWithWarnings(#"{"FREQ":"MONTHLY","BYMONTHDAY":28}"#)
    XCTAssertTrue(warnings.isEmpty)
  }

  func testBymonthdayNegativeDoesNotWarn() {
    let (_, warnings) = normalizeWithWarnings(#"{"FREQ":"MONTHLY","BYMONTHDAY":-1}"#)
    XCTAssertTrue(warnings.isEmpty)
  }

  func testBymonthday31OnYearlyAlsoWarns() {
    let (_, warnings) = normalizeWithWarnings(#"{"FREQ":"YEARLY","BYMONTHDAY":31}"#)
    XCTAssertEqual(warnings, [.bymonthdaySkipsMonths(day: 31)])
  }

  func testByArraysCanonicalizedSortDedup() {
    XCTAssertTrue(
      normalize(#"{"FREQ":"YEARLY","BYMONTH":[12,1,6,1]}"#).contains(#""BYMONTH":[1,6,12]"#))
    XCTAssertTrue(
      normalize(#"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[3,-1,1,1]}"#)
        .contains(#""BYSETPOS":[-1,1,3]"#))
    XCTAssertTrue(
      normalize(#"{"FREQ":"WEEKLY","BYDAY":["FR","MO","FR","WE"]}"#)
        .contains(#""BYDAY":["MO","WE","FR"]"#))
    XCTAssertTrue(
      normalize(#"{"FREQ":"MONTHLY","BYDAY":["1FR","-1MO","1MO"]}"#)
        .contains(#""BYDAY":["-1MO","1MO","1FR"]"#))
  }

  // MARK: - calendar normalizer (calendar.rs)

  func testCalendarNilAndEmptyReturnNil() {
    XCTAssertEqual(try? ValidationRecurrence.normalizeCalendarRecurrence(nil).get(), .some(nil))
    XCTAssertEqual(try? ValidationRecurrence.normalizeCalendarRecurrence("").get(), .some(nil))
    XCTAssertEqual(try? ValidationRecurrence.normalizeCalendarRecurrence("   ").get(), .some(nil))
  }

  func testCalendarShorthandWrap() {
    let result = try? ValidationRecurrence.normalizeCalendarRecurrence("WEEKLY").get()
    XCTAssertEqual(result, .some(#"{"FREQ":"WEEKLY","INTERVAL":1}"#))
  }

  func testCalendarCountCapEnforced() {
    switch ValidationRecurrence.normalizeCalendarRecurrence(#"{"FREQ":"DAILY","COUNT":366}"#) {
    case .success:
      XCTFail("expected COUNT cap rejection")
    case let .failure(e):
      XCTAssertEqual(e, .outOfRange(field: "recurrence.COUNT", min: 1, max: 365, actual: 366))
    }
    // At the cap is accepted.
    XCTAssertNoThrow(
      try ValidationRecurrence.normalizeCalendarRecurrence(#"{"FREQ":"DAILY","COUNT":365}"#).get())
  }

  func testIntervalCapEnforced() {
    // Layer 2 (write path): an INTERVAL far above any real cadence — such as the
    // crash-report poison value — is rejected with a clean validation error so
    // MCP returns {code,message} instead of storing/syncing a row that would
    // trap every device rendering a timeline touching it.
    switch ValidationRecurrence.normalizeTaskRecurrence(
      #"{"FREQ":"WEEKLY","INTERVAL":1600000000000000000}"#)
    {
    case .success:
      XCTFail("expected INTERVAL cap rejection")
    case let .failure(e):
      XCTAssertEqual(
        e,
        .outOfRange(
          field: "recurrence", min: 1, max: 10_000, actual: 1_600_000_000_000_000_000))
    }
    // Just over the cap is rejected too.
    switch ValidationRecurrence.normalizeTaskRecurrence(#"{"FREQ":"WEEKLY","INTERVAL":10001}"#) {
    case .success:
      XCTFail("expected rejection just over the cap")
    case let .failure(e):
      XCTAssertEqual(e, .outOfRange(field: "recurrence", min: 1, max: 10_000, actual: 10_001))
    }
    // At the cap is accepted (task and calendar paths share the parser).
    XCTAssertNoThrow(
      try ValidationRecurrence.normalizeTaskRecurrence(#"{"FREQ":"WEEKLY","INTERVAL":10000}"#).get())
    XCTAssertNoThrow(
      try ValidationRecurrence.normalizeCalendarRecurrence(#"{"FREQ":"WEEKLY","INTERVAL":10000}"#)
        .get())
  }

  func testCalendarBareBydayRejectedOnMonthly() {
    let msg = errorMessage_calendar(#"{"FREQ":"MONTHLY","BYDAY":["MO"]}"#)
    XCTAssertTrue(msg.contains("only valid for WEEKLY") && msg.contains("MONTHLY"), msg)
  }

  func testCalendarOrdinalBydayAcceptedOnMonthly() {
    let result = try? ValidationRecurrence.normalizeCalendarRecurrence(
      #"{"FREQ":"MONTHLY","BYDAY":["1MO"]}"#
    ).get()
    XCTAssertEqual(result, .some(#"{"BYDAY":["1MO"],"FREQ":"MONTHLY","INTERVAL":1}"#))
  }

  func testCalendarBareBydayAcceptedWithBysetpos() {
    XCTAssertNoThrow(
      try ValidationRecurrence.normalizeCalendarRecurrence(
        #"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[1]}"#
      ).get())
  }

  // MARK: - ANCHOR (Lorvex completion-anchor extension)

  func testAnchorCompletionPreservedInCanonical() {
    XCTAssertEqual(
      normalize(#"{"FREQ":"DAILY","INTERVAL":2,"ANCHOR":"completion"}"#),
      #"{"ANCHOR":"completion","FREQ":"DAILY","INTERVAL":2}"#)
  }

  func testAnchorScheduleOmittedForByteCompatibility() {
    // The default anchor must produce the identical canonical string as a rule
    // with no ANCHOR key at all, so existing fixed-cadence rules never churn.
    XCTAssertEqual(
      normalize(#"{"FREQ":"DAILY","ANCHOR":"schedule"}"#),
      normalize(#"{"FREQ":"DAILY"}"#))
    XCTAssertFalse(normalize(#"{"FREQ":"DAILY","ANCHOR":"schedule"}"#).contains("ANCHOR"))
  }

  func testAnchorCompletionRejectsPositionalKeys() {
    XCTAssertTrue(
      errorMessage(#"{"FREQ":"WEEKLY","BYDAY":["MO"],"ANCHOR":"completion"}"#)
        .contains("positional"))
  }

  func testAnchorInvalidValueRejected() {
    XCTAssertTrue(
      errorMessage(#"{"FREQ":"DAILY","ANCHOR":"whenever"}"#).contains("ANCHOR"))
  }

  func testCalendarRecurrenceRejectsAnchor() {
    XCTAssertTrue(
      errorMessage_calendar(#"{"FREQ":"WEEKLY","ANCHOR":"completion"}"#)
        .contains("completion"))
  }

  /// An untrusted recurrence string nested thousands of levels deep is rejected
  /// as a plain format error by the parser's depth guard, rather than
  /// overflowing the stack and crashing the process.
  func testDeeplyNestedRecurrenceRejectedGracefully() {
    let deep = String(repeating: "[", count: 80_000) + "0" + String(repeating: "]", count: 80_000)
    switch ValidationRecurrence.normalizeTaskRecurrence(deep) {
    case .success:
      XCTFail("deeply nested recurrence must be rejected")
    case let .failure(e):
      XCTAssertTrue(e.description.contains("recurrence"))
    }
  }

  private func errorMessage_calendar(_ input: String) -> String {
    switch ValidationRecurrence.normalizeCalendarRecurrence(input) {
    case .success:
      XCTFail("expected error, got success")
      return ""
    case let .failure(e):
      return e.description
    }
  }
}
