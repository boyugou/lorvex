import Foundation
import LorvexDomain
import XCTest

@testable import LorvexStore

/// Shared recurrence-contract tests derived from `calendar_timeline::recurrence`
/// (date_math, count_end, recurs_on_date, first_occurrence, next_occurrence,
/// weekly, validation). Assertions pin exact dates, sequences, and termination.
final class CalendarRecurrenceTests: XCTestCase {
  // Convenience constructors mirroring `NaiveDate::from_ymd_opt(...).unwrap()`.
  private func d(_ y: Int, _ m: UInt32, _ day: UInt32) -> RDate {
    RDate.fromYMD(y, m, day)!
  }

  // Test-only wrappers mirroring `tests/helpers.rs` (panic-on-error form).
  private func recursOnDate(_ rule: String, _ base: String, _ target: String) -> Bool {
    try! CalendarRecurrence.recursOnDate(
      recurrenceJson: rule, baseDateYmd: base, targetDateYmd: target)
  }
  private func firstOccurrence(_ rule: String, _ base: RDate, _ target: RDate) -> RDate? {
    try! CalendarRecurrence.firstOccurrenceOnOrAfter(rule, base, target)
  }
  private func nextOccurrence(_ rule: String, _ base: String) -> String? {
    try! CalendarRecurrence.calculateNextOccurrenceDate(recurrenceJson: rule, baseDateYmd: base)
  }
  private func nextStrictlyAfter(_ rule: String, _ base: String, _ today: String) -> String? {
    try! CalendarRecurrence.nextOccurrenceStrictlyAfter(
      recurrenceJson: rule, baseDateYmd: base, todayYmd: today)
  }
  private func countEnd(_ rule: String, _ base: String) -> String? {
    try! CalendarRecurrence.countEndDate(recurrenceJson: rule, baseDate: base)
  }

  // MARK: - Weekday-numbering parity pin (chrono num_days_from_sunday)

  func test_weekday_numbering_matches_chrono_num_days_from_sunday() {
    // 2026-03-02 is a Monday → num_days_from_sunday == 1.
    XCTAssertEqual(d(2026, 3, 2).numDaysFromSunday, 1)
    // 2026-03-01 is a Sunday → 0; 2026-03-07 is a Saturday → 6.
    XCTAssertEqual(d(2026, 3, 1).numDaysFromSunday, 0)
    XCTAssertEqual(d(2026, 3, 7).numDaysFromSunday, 6)
    // BYDAY codes use the same numbering.
    XCTAssertEqual(CalendarRecurrence.bydayCodeToNum("SU"), 0)
    XCTAssertEqual(CalendarRecurrence.bydayCodeToNum("MO"), 1)
    XCTAssertEqual(CalendarRecurrence.bydayCodeToNum("SA"), 6)
  }

  // MARK: - date_math.rs

  func test_add_months_clamped_basic() {
    XCTAssertEqual(CalendarRecurrence.addMonthsClamped(d(2026, 1, 15), 1, 15), d(2026, 2, 15))
  }

  func test_add_months_clamped_feb_clamp() {
    XCTAssertEqual(CalendarRecurrence.addMonthsClamped(d(2026, 1, 31), 1, 31), d(2026, 2, 28))
  }

  func test_add_months_clamped_target_day_anchor() {
    XCTAssertEqual(CalendarRecurrence.addMonthsClamped(d(2026, 2, 28), 1, 31), d(2026, 3, 31))
  }

  func test_overlaps_range_identical() {
    let from = d(2026, 3, 1)
    let to = d(2026, 3, 31)
    XCTAssertTrue(CalendarRecurrence.overlapsCalendarRange(from, to, from, to))
  }

  func test_overlaps_range_no_overlap() {
    let from = d(2026, 3, 1)
    let to = d(2026, 3, 31)
    XCTAssertFalse(
      CalendarRecurrence.overlapsCalendarRange(d(2026, 4, 1), d(2026, 4, 30), from, to))
  }

  func test_overlaps_range_single_day_boundary() {
    let from = d(2026, 3, 1)
    let to = d(2026, 3, 31)
    XCTAssertTrue(CalendarRecurrence.overlapsCalendarRange(d(2026, 2, 28), from, from, to))
    XCTAssertTrue(CalendarRecurrence.overlapsCalendarRange(to, to, from, to))
  }

  func test_overlaps_range_entirely_before() {
    let from = d(2026, 3, 1)
    let to = d(2026, 3, 31)
    XCTAssertFalse(
      CalendarRecurrence.overlapsCalendarRange(d(2026, 2, 1), d(2026, 2, 28), from, to))
  }

  // MARK: - weekly.rs (weekly_target_dows + byday occurrence)

  func test_weekly_target_dows_returns_sorted() {
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"BYDAY":["FR","MO","WE"]}"#)
    XCTAssertEqual(try! CalendarRecurrence.weeklyTargetDows(rule), [1, 3, 5])
  }

  func test_weekly_target_dows_empty_returns_none() {
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"BYDAY":[]}"#)
    XCTAssertNil(try! CalendarRecurrence.weeklyTargetDows(rule))
  }

  func test_weekly_target_dows_absent_returns_none() {
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"FREQ":"WEEKLY"}"#)
    XCTAssertNil(try! CalendarRecurrence.weeklyTargetDows(rule))
  }

  func test_byday_occurrence_same_week() {
    let rule = try! CalendarRecurrence.parseRuleObject(
      #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE"]}"#)
    let r = try! CalendarRecurrence.firstWeeklyBydayOccurrenceOnOrAfter(
      rule, d(2026, 3, 2), d(2026, 3, 4), 1)
    XCTAssertEqual(r, d(2026, 3, 4))
  }

  func test_byday_occurrence_next_interval() {
    let rule = try! CalendarRecurrence.parseRuleObject(
      #"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO"]}"#)
    let r = try! CalendarRecurrence.firstWeeklyBydayOccurrenceOnOrAfter(
      rule, d(2026, 3, 2), d(2026, 3, 10), 2)
    XCTAssertEqual(r, d(2026, 3, 16))
  }

  // MARK: - case-insensitive rule keys / codes (Apple superset)

  /// The calendar recurrence reader accepts the lowercase structured form
  /// (`set_task_recurrence`'s `freq`/`byday`) by normalizing keys and weekday
  /// codes to uppercase on parse, so a lowercase rule behaves identically to
  /// the uppercase canonical form.
  func test_lowercase_rule_keys_normalize_to_uppercase() {
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"freq":"weekly","byday":["mo"]}"#)
    XCTAssertEqual(Set(rule.keys), ["FREQ", "BYDAY"])
    XCTAssertEqual(try! CalendarRecurrence.parseFreq(rule), "WEEKLY")
    XCTAssertEqual(try! CalendarRecurrence.weeklyTargetDows(rule), [1])
  }

  func test_lowercase_rule_matches_uppercase_occurrence() {
    let lower = #"{"freq":"weekly","byday":["mo","we","fr"]}"#
    let upper = #"{"FREQ":"WEEKLY","BYDAY":["MO","WE","FR"]}"#
    // 2026-03-02 is a Monday (base); 2026-03-04 is the Wednesday in BYDAY.
    XCTAssertEqual(
      recursOnDate(lower, "2026-03-02", "2026-03-04"),
      recursOnDate(upper, "2026-03-02", "2026-03-04"))
    XCTAssertTrue(recursOnDate(lower, "2026-03-02", "2026-03-04"))
    // 2026-03-05 is a Thursday (not in BYDAY) → no occurrence for either form.
    XCTAssertEqual(
      recursOnDate(lower, "2026-03-02", "2026-03-05"),
      recursOnDate(upper, "2026-03-02", "2026-03-05"))
    XCTAssertFalse(recursOnDate(lower, "2026-03-02", "2026-03-05"))
  }

  // MARK: - R-1: MONTHLY month-end anchoring (no BYMONTHDAY drift)

  func test_monthly_no_bymonthday_count_anchors_to_original_day() {
    // R-3 (B): an *implicit* MONTHLY anchored on the month-end (Jan-31) injects
    // BYMONTHDAY=-1, so the chained COUNT loop tracks each month's last day
    // (Feb-28, Mar-31, Apr-30) — the friendly series, now RFC-faithful — instead
    // of drifting to the 28th after February.
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"COUNT":6}"#
    XCTAssertTrue(recursOnDate(rule, "2026-01-31", "2026-02-28"))
    XCTAssertTrue(recursOnDate(rule, "2026-01-31", "2026-03-31"))
    XCTAssertTrue(recursOnDate(rule, "2026-01-31", "2026-04-30"))
    // The drift artifact — every later month on the 28th — must NOT be reported.
    XCTAssertFalse(recursOnDate(rule, "2026-01-31", "2026-03-28"))
    XCTAssertFalse(recursOnDate(rule, "2026-01-31", "2026-04-28"))
  }

  func test_monthly_explicit_bymonthday_31_skips_short_months() {
    // R-3 (A): an *explicit* positive BYMONTHDAY skips months that lack the day
    // per RFC 5545 §3.3.10 — no clamp. Jan-31 → (Feb skipped) → Mar-31 →
    // (Apr skipped) → May-31. A clamped Feb-28 would be un-exportable.
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#
    XCTAssertFalse(recursOnDate(rule, "2026-01-31", "2026-02-28"))  // skipped, not clamped
    XCTAssertTrue(recursOnDate(rule, "2026-01-31", "2026-03-31"))
    XCTAssertFalse(recursOnDate(rule, "2026-01-31", "2026-04-30"))  // April has no 31st
    XCTAssertTrue(recursOnDate(rule, "2026-01-31", "2026-05-31"))
  }

  // MARK: - count_end.rs

  func test_count_end_daily_count_3() {
    XCTAssertEqual(
      countEnd(#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#, "2026-01-01"), "2026-01-03")
  }

  func test_count_end_weekly_count_2() {
    XCTAssertEqual(
      countEnd(#"{"FREQ":"WEEKLY","INTERVAL":1,"COUNT":2}"#, "2026-01-06"), "2026-01-13")
  }

  func test_count_end_no_count_returns_none() {
    XCTAssertNil(countEnd(#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-01-01"))
  }

  func test_count_end_count_1_returns_base() {
    XCTAssertEqual(
      countEnd(#"{"FREQ":"MONTHLY","INTERVAL":1,"COUNT":1}"#, "2026-03-15"), "2026-03-15")
  }

  func test_count_end_yearly_from_leap_day_clamps() {
    XCTAssertEqual(
      countEnd(#"{"FREQ":"YEARLY","INTERVAL":1,"COUNT":3}"#, "2024-02-29"), "2026-02-28")
  }

  func test_count_end_yearly_bymonth_bymonthday_counts_leap_day_occurrences() {
    XCTAssertEqual(
      countEnd(
        #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29,"COUNT":2}"#, "2024-02-29"),
      "2028-02-29")
  }

  func test_count_end_monthly_byday_bysetpos_counts_first_mondays() {
    XCTAssertEqual(
      countEnd(
        #"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1],"COUNT":3}"#, "2026-01-05"),
      "2026-03-02")
  }

  func test_count_end_rejects_excessive_count() {
    XCTAssertThrowsError(
      try CalendarRecurrence.countEndDate(
        recurrenceJson: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":9999}"#, baseDate: "2026-01-01")
    ) { error in
      guard case let StoreError.validation(msg) = error else {
        return XCTFail("expected .validation, got \(error)")
      }
      XCTAssertTrue(msg.contains("9999") && msg.contains("exceeds maximum"))
    }
  }

  func test_count_end_accepts_count_at_cap() {
    XCTAssertEqual(
      countEnd(#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1000}"#, "2026-01-01"), "2028-09-26")
  }

  // MARK: - recurs_on_date.rs

  func test_recurs_on_date_daily() {
    let rule = #"{"FREQ":"DAILY","INTERVAL":2}"#
    XCTAssertTrue(recursOnDate(rule, "2026-03-01", "2026-03-03"))
    XCTAssertFalse(recursOnDate(rule, "2026-03-01", "2026-03-02"))
  }

  func test_recurs_on_date_weekly() {
    let rule = #"{"FREQ":"WEEKLY","INTERVAL":1}"#
    XCTAssertTrue(recursOnDate(rule, "2026-03-01", "2026-03-08"))
    XCTAssertFalse(recursOnDate(rule, "2026-03-01", "2026-03-09"))
  }

  func test_recurs_on_date_monthly() {
    XCTAssertTrue(recursOnDate(#"{"FREQ":"MONTHLY","INTERVAL":1}"#, "2026-01-15", "2026-03-15"))
  }

  func test_recurs_on_date_yearly() {
    XCTAssertTrue(recursOnDate(#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2025-06-15", "2026-06-15"))
  }

  func test_recurs_on_date_yearly_bymonth_bymonthday_only_matches_leap_day() {
    let rule = #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#
    XCTAssertTrue(recursOnDate(rule, "2024-02-29", "2028-02-29"))
    XCTAssertFalse(recursOnDate(rule, "2024-02-29", "2025-02-28"))
  }

  func test_recurs_on_date_monthly_byday_bysetpos_matches_first_monday() {
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#
    XCTAssertTrue(recursOnDate(rule, "2026-01-05", "2026-02-02"))
    XCTAssertFalse(recursOnDate(rule, "2026-01-05", "2026-02-09"))
  }

  func test_recurs_on_date_base_is_match() {
    XCTAssertTrue(recursOnDate(#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-03-15", "2026-03-15"))
  }

  func test_recurs_on_date_before_base() {
    XCTAssertFalse(recursOnDate(#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-03-15", "2026-03-14"))
  }

  func test_recurs_on_date_until_exceeded() {
    XCTAssertFalse(
      recursOnDate(
        #"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-03-16"}"#, "2026-03-15", "2026-03-17"))
  }

  func test_recurs_on_date_count_daily() {
    let rule = #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#
    XCTAssertTrue(recursOnDate(rule, "2026-03-01", "2026-03-02"))
    XCTAssertTrue(recursOnDate(rule, "2026-03-01", "2026-03-03"))
    XCTAssertFalse(recursOnDate(rule, "2026-03-01", "2026-03-04"))
  }

  func test_recurs_on_date_rejects_invalid_count_zero() {
    XCTAssertThrowsError(
      try CalendarRecurrence.recursOnDate(
        recurrenceJson: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":0}"#,
        baseDateYmd: "2026-03-01", targetDateYmd: "2026-03-02")
    ) { error in
      guard case StoreError.validation = error else {
        return XCTFail("expected .validation, got \(error)")
      }
    }
  }

  func test_recurs_on_date_rejects_excessive_count_for_expansion_budget() {
    XCTAssertThrowsError(
      try CalendarRecurrence.recursOnDate(
        recurrenceJson: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1001}"#,
        baseDateYmd: "2026-03-01", targetDateYmd: "2026-03-02")
    ) { error in
      guard case let StoreError.validation(msg) = error else {
        return XCTFail("expected .validation, got \(error)")
      }
      XCTAssertTrue(msg.contains("1001") && msg.contains("exceeds maximum"))
    }
  }

  // MARK: - first_occurrence.rs

  func test_first_occurrence_daily_before_base() {
    let base = d(2026, 3, 10)
    XCTAssertEqual(
      firstOccurrence(#"{"FREQ":"DAILY","INTERVAL":1}"#, base, d(2026, 3, 5)), base)
  }

  func test_first_occurrence_daily_with_interval() {
    XCTAssertEqual(
      firstOccurrence(#"{"FREQ":"DAILY","INTERVAL":3}"#, d(2026, 3, 1), d(2026, 3, 4)),
      d(2026, 3, 4))
  }

  func test_first_occurrence_weekly_no_byday() {
    XCTAssertEqual(
      firstOccurrence(#"{"FREQ":"WEEKLY","INTERVAL":1}"#, d(2026, 3, 1), d(2026, 3, 10)),
      d(2026, 3, 15))
  }

  func test_first_occurrence_weekly_with_byday() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE","FR"]}"#, d(2026, 3, 2), d(2026, 3, 5)),
      d(2026, 3, 6))
  }

  func test_first_occurrence_weekly_bymonth_filters_out_other_months() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"BYMONTH":[2]}"#, d(2026, 1, 5),
        d(2026, 1, 6)),
      d(2026, 2, 2))
  }

  func test_first_occurrence_weekly_interval_respects_wkst() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO"],"WKST":"MO"}"#, d(2026, 3, 1),
        d(2026, 3, 2)),
      d(2026, 3, 9))
  }

  func test_first_occurrence_weekly_byday_order_respects_wkst() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","SU"],"WKST":"MO"}"#, d(2026, 3, 2),
        d(2026, 3, 2)),
      d(2026, 3, 2))
  }

  func test_first_occurrence_monthly_bymonthday_skips_to_next_long_month() {
    // Explicit BYMONTHDAY=31 skips February (no 31st) rather than clamping to
    // the 28th; the first occurrence on/after Feb-1 is Mar-31.
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#, d(2026, 1, 31), d(2026, 2, 1)),
      d(2026, 3, 31))
  }

  func test_first_occurrence_yearly_clamps_leap_day() {
    XCTAssertEqual(
      firstOccurrence(#"{"FREQ":"YEARLY","INTERVAL":1}"#, d(2024, 2, 29), d(2025, 1, 1)),
      d(2025, 2, 28))
  }

  func test_first_occurrence_yearly_preserves_leap_day() {
    XCTAssertEqual(
      firstOccurrence(#"{"FREQ":"YEARLY","INTERVAL":4}"#, d(2024, 2, 29), d(2028, 1, 1)),
      d(2028, 2, 29))
  }

  func test_first_occurrence_yearly_bymonth_bymonthday_skips_to_leap_day() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#, d(2023, 1, 1),
        d(2023, 1, 1)),
      d(2024, 2, 29))
  }

  func test_first_occurrence_yearly_bymonth_without_bymonthday_uses_base_day_in_target_month() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2]}"#, d(2026, 1, 10), d(2026, 1, 11)),
      d(2026, 2, 10))
  }

  func test_first_occurrence_yearly_ordinal_byday_scans_whole_year() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["-1FR"]}"#, d(2026, 1, 1), d(2026, 1, 1)),
      d(2026, 12, 25))
  }

  func test_first_occurrence_monthly_byday_bysetpos_picks_first_monday() {
    XCTAssertEqual(
      firstOccurrence(
        #"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#, d(2026, 1, 5),
        d(2026, 2, 1)),
      d(2026, 2, 2))
  }

  func test_first_occurrence_until_exceeded() {
    XCTAssertNil(
      firstOccurrence(
        #"{"FREQ":"MONTHLY","INTERVAL":1,"UNTIL":"2026-03-31"}"#, d(2026, 1, 1), d(2026, 4, 1)))
  }

  // MARK: - next_occurrence.rs (calculate_next_occurrence_date)

  func test_next_occurrence_daily_basic() {
    XCTAssertEqual(nextOccurrence(#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-03-15"), "2026-03-16")
  }

  func test_next_occurrence_weekly_basic() {
    XCTAssertEqual(nextOccurrence(#"{"FREQ":"WEEKLY","INTERVAL":1}"#, "2026-03-15"), "2026-03-22")
  }

  func test_next_occurrence_weekly_bymonth_filters_out_other_months() {
    XCTAssertEqual(
      nextOccurrence(
        #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"BYMONTH":[2]}"#, "2026-01-05"),
      "2026-02-02")
  }

  func test_next_occurrence_weekly_interval_respects_wkst() {
    XCTAssertEqual(
      nextOccurrence(
        #"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO"],"WKST":"MO"}"#, "2026-03-01"),
      "2026-03-09")
  }

  func test_next_occurrence_weekly_byday_order_respects_wkst() {
    XCTAssertEqual(
      nextOccurrence(
        #"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","SU"],"WKST":"MO"}"#, "2026-03-02"),
      "2026-03-08")
  }

  func test_next_occurrence_monthly_bymonthday_31_skips_feb() {
    // Explicit BYMONTHDAY=31 skips February entirely (RFC 5545 §3.3.10): the
    // occurrence after Jan-31 is Mar-31, never a clamped Feb-28.
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#, "2026-01-31"),
      "2026-03-31")
  }

  func test_next_occurrence_monthly_bymonthday_31_finds_next_31_day_month() {
    // From a non-occurrence base (Feb-28) the next BYMONTHDAY=31 instance is the
    // next month that actually has a 31st — March.
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#, "2026-02-28"),
      "2026-03-31")
  }

  func test_yearly_recurrence_clamps_leap_day_to_feb_28() {
    XCTAssertEqual(nextOccurrence(#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2024-02-29"), "2025-02-28")
  }

  func test_monthly_bymonthday_negative_one_resolves_to_last_day_of_month() {
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":-1}"#, "2026-01-31"),
      "2026-02-28")
  }

  func test_monthly_bymonthday_negative_two_resolves_to_penultimate_day() {
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":-2}"#, "2026-01-30"),
      "2026-02-27")
  }

  func test_monthly_bymonthday_rejects_zero_and_out_of_range_values() {
    for invalid in ["0", "32", "-32", "-33", "\"x\""] {
      let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":\#(invalid)}"#
      XCTAssertThrowsError(
        try CalendarRecurrence.calculateNextOccurrenceDate(
          recurrenceJson: rule, baseDateYmd: "2026-01-15")
      ) { error in
        let msg: String
        switch error {
        case let StoreError.validation(m): msg = m
        case let StoreError.serialization(m): msg = m
        case let StoreError.invariant(m): msg = m
        default: msg = "\(error)"
        }
        XCTAssertTrue(msg.contains("BYMONTHDAY"), "unexpected error for \(invalid): \(msg)")
      }
    }
  }

  func test_yearly_recurrence_preserves_leap_day_in_leap_year() {
    XCTAssertEqual(nextOccurrence(#"{"FREQ":"YEARLY","INTERVAL":4}"#, "2024-02-29"), "2028-02-29")
  }

  func test_next_occurrence_yearly_bymonth_bymonthday_skips_non_leap_years() {
    XCTAssertEqual(
      nextOccurrence(
        #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#, "2024-02-29"),
      "2028-02-29")
  }

  func test_next_occurrence_yearly_bymonth_without_bymonthday_uses_base_day_in_target_month() {
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2]}"#, "2026-01-10"),
      "2026-02-10")
  }

  func test_next_occurrence_yearly_byday_bysetpos_scans_whole_year() {
    XCTAssertEqual(
      nextOccurrence(
        #"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#, "2026-01-05"),
      "2027-01-04")
  }

  func test_next_occurrence_monthly_ordinal_byday_picks_first_monday() {
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["1MO"]}"#, "2026-01-05"),
      "2026-02-02")
  }

  func test_yearly_recurrence_normal_date() {
    XCTAssertEqual(nextOccurrence(#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2026-03-15"), "2027-03-15")
  }

  func test_yearly_bymonthday_29_skips_non_leap_februaries_with_or_without_bymonth() {
    // R-3 (C): explicit YEARLY BYMONTHDAY=29 anchored in February skips non-leap
    // years to the next Feb-29 — identically whether or not BYMONTH=[2] is
    // present. Previously the no-BYMONTH form clamped (clamp = !hasBymonth),
    // diverging from the BYMONTH form; both now skip.
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTHDAY":29}"#, "2025-02-28"),
      "2028-02-29")
    XCTAssertEqual(
      nextOccurrence(#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#, "2025-02-28"),
      "2028-02-29")
  }

  // MARK: - C9: multi-day BYMONTHDAY arrays

  func test_multiday_bymonthday_single_element_matches_legacy_scalar() {
    // Back-compat: [15] expands identically to the old scalar 15.
    let array = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[15]}"#
    let scalar = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":15}"#
    for base in ["2026-01-01", "2026-01-15", "2026-02-15", "2026-01-31"] {
      XCTAssertEqual(nextOccurrence(array, base), nextOccurrence(scalar, base), "base=\(base)")
    }
  }

  func test_multiday_bymonthday_1_and_15_alternates_within_month() {
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[1,15]}"#
    XCTAssertEqual(nextOccurrence(rule, "2026-01-01"), "2026-01-15")
    XCTAssertEqual(nextOccurrence(rule, "2026-01-15"), "2026-02-01")
    XCTAssertEqual(nextOccurrence(rule, "2026-02-01"), "2026-02-15")
    XCTAssertEqual(firstOccurrence(rule, d(2026, 1, 1), d(2026, 1, 1)), d(2026, 1, 1))
    XCTAssertTrue(recursOnDate(rule, "2026-01-01", "2026-02-15"))
    XCTAssertFalse(recursOnDate(rule, "2026-01-01", "2026-02-10"))
  }

  func test_multiday_bymonthday_sorted_regardless_of_input_order() {
    // Input order does not change expansion order; the engine sorts per period.
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[20,1,10]}"#
    XCTAssertEqual(nextOccurrence(rule, "2026-01-01"), "2026-01-10")
    XCTAssertEqual(nextOccurrence(rule, "2026-01-10"), "2026-01-20")
    XCTAssertEqual(nextOccurrence(rule, "2026-01-20"), "2026-02-01")
  }

  func test_multiday_bymonthday_31_skips_short_months_but_keeps_low_days() {
    // [1,10,20,31]: February lacks the 31st, so only 1/10/20 fire; the 31st
    // resumes in the next 31-day month (March).
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[1,10,20,31]}"#
    XCTAssertEqual(nextOccurrence(rule, "2026-01-31"), "2026-02-01")
    XCTAssertEqual(nextOccurrence(rule, "2026-02-20"), "2026-03-01")
    XCTAssertEqual(nextOccurrence(rule, "2026-03-20"), "2026-03-31")
  }

  func test_multiday_bymonthday_all_high_days_skip_february_entirely() {
    // [29,30,31] has no occurrence in a 28-day February: it jumps to March.
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[29,30,31]}"#
    XCTAssertEqual(nextOccurrence(rule, "2026-01-31"), "2026-03-29")
    XCTAssertFalse(recursOnDate(rule, "2026-01-29", "2026-02-15"))
  }

  func test_multiday_bymonthday_month_end_and_31_dedupe_in_long_months() {
    // -1 (last day) and 31 coincide in 31-day months (deduped to one date) and
    // diverge in February, where only -1 (→ 28) survives.
    let rule = #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[-1,31]}"#
    XCTAssertEqual(nextOccurrence(rule, "2026-01-31"), "2026-02-28")
    XCTAssertEqual(nextOccurrence(rule, "2026-02-28"), "2026-03-31")
  }

  func test_multiday_bymonthday_yearly_feb_28_and_29_leap_behavior() {
    // YEARLY BYMONTH=[2], BYMONTHDAY=[28,29]: both fire in leap years, only 28
    // in common years.
    let rule = #"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":[28,29]}"#
    XCTAssertEqual(nextOccurrence(rule, "2024-02-28"), "2024-02-29")
    XCTAssertEqual(nextOccurrence(rule, "2024-02-29"), "2025-02-28")
    XCTAssertEqual(nextOccurrence(rule, "2025-02-28"), "2026-02-28")
  }

  func test_multiday_bymonthday_engine_rejects_out_of_range_element() {
    for rule in [
      #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[15,0]}"#,
      #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[1,32]}"#,
      #"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[1,"x"]}"#,
    ] {
      XCTAssertThrowsError(
        try CalendarRecurrence.calculateNextOccurrenceDate(
          recurrenceJson: rule, baseDateYmd: "2026-01-15")
      ) { error in
        let msg: String
        switch error {
        case let StoreError.validation(m): msg = m
        default: msg = "\(error)"
        }
        XCTAssertTrue(msg.contains("BYMONTHDAY"), "unexpected error for \(rule): \(msg)")
      }
    }
  }

  func test_until_date_prevents_next_occurrence() {
    XCTAssertNil(
      nextOccurrence(#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-03-15"}"#, "2026-03-15"))
  }

  // MARK: - next_occurrence.rs (next_occurrence_strictly_after)

  func test_strictly_after_today_wins() {
    XCTAssertEqual(
      nextStrictlyAfter(#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-03-10", "2026-03-15"),
      "2026-03-16")
  }

  func test_strictly_after_base_wins() {
    XCTAssertEqual(
      nextStrictlyAfter(#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-03-20", "2026-03-15"),
      "2026-03-21")
  }

  // MARK: - validation.rs (parse + error paths + mutation helpers)

  func test_parse_ymd_valid() {
    XCTAssertEqual(try! CalendarRecurrence.parseYmd("2026-03-15"), d(2026, 3, 15))
  }

  func test_parse_ymd_invalid_returns_validation_error() {
    XCTAssertThrowsError(try CalendarRecurrence.parseYmd("not-a-date")) { error in
      guard case StoreError.validation = error else {
        return XCTFail("expected .validation, got \(error)")
      }
    }
  }

  func test_first_occurrence_rejects_malformed_rule_json() {
    XCTAssertThrowsError(
      try CalendarRecurrence.firstOccurrenceOnOrAfter(
        recurrenceJson: #"{"FREQ":"DAILY""#, baseDateYmd: "2026-03-01",
        targetDateYmd: "2026-03-02")
    ) { error in
      guard case StoreError.serialization = error else {
        return XCTFail("expected .serialization, got \(error)")
      }
    }
  }

  func test_next_occurrence_rejects_invalid_until_date() {
    XCTAssertThrowsError(
      try CalendarRecurrence.calculateNextOccurrenceDate(
        recurrenceJson: #"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-02-30"}"#,
        baseDateYmd: "2026-02-28")
    ) { error in
      guard case StoreError.validation = error else {
        return XCTFail("expected .validation, got \(error)")
      }
    }
  }

  func test_inject_bymonthday_rejects_invalid_due_date() {
    XCTAssertThrowsError(
      try CalendarRecurrence.injectBymonthday(
        recurrenceJson: #"{"FREQ":"MONTHLY","INTERVAL":1}"#, dueDateYmd: "2026-02-30")
    ) { error in
      guard case StoreError.validation = error else {
        return XCTFail("expected .validation, got \(error)")
      }
    }
  }

  func test_inject_bymonthday_skips_positional_rules() {
    XCTAssertNil(
      try! CalendarRecurrence.injectBymonthday(
        recurrenceJson: #"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#,
        dueDateYmd: "2026-01-05"))
    XCTAssertNil(
      try! CalendarRecurrence.injectBymonthday(
        recurrenceJson: #"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["1MO"],"BYMONTH":[2]}"#,
        dueDateYmd: "2026-02-02"))
  }

  func test_inject_bymonthday_injects_day_for_plain_monthly() {
    let injected = try! CalendarRecurrence.injectBymonthday(
      recurrenceJson: #"{"FREQ":"MONTHLY","INTERVAL":1}"#, dueDateYmd: "2026-01-15")
    let parsed = JSONValue.parse(injected!)!
    guard case let .object(rule) = parsed else { return XCTFail("expected object") }
    XCTAssertEqual(rule["BYMONTHDAY"]?.rcArray?.compactMap(\.rcI64), [15])
  }

  func test_inject_bymonthday_uses_negative_one_for_month_end_anchor() {
    // An anchor that is INVARIANTLY its month's last day across every year
    // injects BYMONTHDAY=-1 so the series tracks each month's last day rather
    // than skipping. This is year-independent: a 30/31-day month is unambiguous
    // (Jan-31, Apr-30) and February qualifies only on the leap-year 29th, its
    // invariant month-end. Holds for MONTHLY and YEARLY.
    let cases: [(String, String)] = [
      ("2026-01-31", "MONTHLY"), ("2026-04-30", "MONTHLY"),
      ("2024-02-29", "MONTHLY"), ("2024-02-29", "YEARLY"), ("2026-01-31", "YEARLY"),
    ]
    for (due, freq) in cases {
      let injected = try! CalendarRecurrence.injectBymonthday(
        recurrenceJson: "{\"FREQ\":\"\(freq)\",\"INTERVAL\":1}", dueDateYmd: due)
      let parsed = JSONValue.parse(injected!)!
      guard case let .object(rule) = parsed else { return XCTFail("expected object") }
      XCTAssertEqual(
        rule["BYMONTHDAY"]?.rcArray?.compactMap(\.rcI64), [-1], "due=\(due) freq=\(freq)")
    }
  }

  func test_inject_bymonthday_common_year_feb28_is_literal_28() {
    // L7 regression: a Feb-28 anchor in a COMMON year is the literal 28th, not a
    // month-end. February's invariant last day is the 29th (leap), so the 28th
    // does not collapse to -1 — otherwise the series would drift to Mar-31,
    // Apr-30, … and be persisted onto every spawned successor. A Feb-28 in a
    // LEAP year is likewise the literal 28th (that February's last day is 29).
    for (due, freq) in [("2025-02-28", "MONTHLY"), ("2026-02-28", "YEARLY"), ("2024-02-28", "MONTHLY")] {
      let injected = try! CalendarRecurrence.injectBymonthday(
        recurrenceJson: "{\"FREQ\":\"\(freq)\",\"INTERVAL\":1}", dueDateYmd: due)
      let parsed = JSONValue.parse(injected!)!
      guard case let .object(rule) = parsed else { return XCTFail("expected object") }
      XCTAssertEqual(
        rule["BYMONTHDAY"]?.rcArray?.compactMap(\.rcI64), [28], "due=\(due) freq=\(freq)")
    }
  }

  func test_inject_bymonthday_common_year_feb28_successors_stay_on_28th() {
    // L7: with BYMONTHDAY=[28] the series recurs on the 28th every month (the
    // 28th exists in every month, so it never skips or drifts to last-day).
    let rule = try! CalendarRecurrence.injectBymonthday(
      recurrenceJson: #"{"FREQ":"MONTHLY","INTERVAL":1}"#, dueDateYmd: "2025-02-28")!
    XCTAssertEqual(nextOccurrence(rule, "2025-02-28"), "2025-03-28")
    XCTAssertEqual(nextOccurrence(rule, "2025-03-28"), "2025-04-28")
    XCTAssertTrue(recursOnDate(rule, "2025-02-28", "2025-12-28"))
    XCTAssertFalse(recursOnDate(rule, "2025-02-28", "2025-03-31"))
  }

  func test_inject_bymonthday_uses_exact_day_for_non_month_end_anchor() {
    // Sub-case (decided): an implicit anchor on day 29/30 that is NOT the last
    // day of its start month injects the exact day, so expansion SKIPS short
    // months (RFC-consistent) instead of clamping to the 28th.
    let injected = try! CalendarRecurrence.injectBymonthday(
      recurrenceJson: #"{"FREQ":"MONTHLY","INTERVAL":1}"#, dueDateYmd: "2026-01-30")
    let parsed = JSONValue.parse(injected!)!
    guard case let .object(rule) = parsed else { return XCTFail("expected object") }
    XCTAssertEqual(rule["BYMONTHDAY"]?.rcArray?.compactMap(\.rcI64), [30])
  }

  // MARK: - reanchorBymonthday (start_date move re-derives an auto-injected day)

  private func reanchorBymonthday(_ rule: String, _ old: String, _ new: String) -> [Int64]? {
    let out = try! CalendarRecurrence.reanchorBymonthday(
      recurrenceJson: rule, oldAnchorYmd: old, newAnchorYmd: new)
    guard case let .object(obj)? = JSONValue.parse(out) else { return nil }
    return obj["BYMONTHDAY"]?.rcArray?.compactMap(\.rcI64)
  }

  func test_reanchor_common_feb28_to_month_end_rederives_negative_one() {
    // L8: a bare-monthly series auto-injected to [28] from Feb-28 (common),
    // moved to Jan-31, re-derives to [-1] — identical to creating it at Jan-31.
    XCTAssertEqual(
      reanchorBymonthday(
        #"{"BYMONTHDAY":[28],"FREQ":"MONTHLY","INTERVAL":1}"#, "2025-02-28", "2026-01-31"),
      [-1])
  }

  func test_reanchor_month_end_to_plain_day_rederives_literal_day() {
    // L8: [-1] auto-injected from Jan-31, moved to the 15th, re-derives to [15].
    XCTAssertEqual(
      reanchorBymonthday(
        #"{"BYMONTHDAY":[-1],"FREQ":"MONTHLY","INTERVAL":1}"#, "2026-01-31", "2026-03-15"),
      [15])
  }

  func test_reanchor_preserves_explicit_non_anchor_day() {
    // The stored [1] does not match the old anchor's auto-injected value (the
    // 5th → [5]), so it was chosen explicitly and is preserved on a move.
    XCTAssertEqual(
      reanchorBymonthday(
        #"{"BYMONTHDAY":[1],"FREQ":"MONTHLY","INTERVAL":1}"#, "2026-01-05", "2026-02-10"),
      [1])
  }

  func test_reanchor_leaves_positional_and_weekly_rules_untouched() {
    // MONTHLY BYDAY/BYSETPOS never receives injection, and WEEKLY has no
    // day-of-month; both pass through verbatim.
    let monthlyByday = #"{"BYDAY":["MO"],"BYSETPOS":[1],"FREQ":"MONTHLY","INTERVAL":1}"#
    XCTAssertEqual(
      try! CalendarRecurrence.reanchorBymonthday(
        recurrenceJson: monthlyByday, oldAnchorYmd: "2026-01-05", newAnchorYmd: "2026-02-02"),
      monthlyByday)
    let weekly = #"{"BYDAY":["MO"],"FREQ":"WEEKLY","INTERVAL":1}"#
    XCTAssertEqual(
      try! CalendarRecurrence.reanchorBymonthday(
        recurrenceJson: weekly, oldAnchorYmd: "2026-01-05", newAnchorYmd: "2026-01-12"),
      weekly)
  }

  func test_reanchor_noop_when_derived_day_unchanged() {
    // Moving between two anchors that derive the same day is a no-op: [15] from
    // the 15th, moved to another 15th, returns the rule unchanged.
    let rule = #"{"BYMONTHDAY":[15],"FREQ":"MONTHLY","INTERVAL":1}"#
    XCTAssertEqual(
      try! CalendarRecurrence.reanchorBymonthday(
        recurrenceJson: rule, oldAnchorYmd: "2026-01-15", newAnchorYmd: "2026-03-15"),
      rule)
  }

  func test_decrement_recurrence_count_accepts_uncapped_positive_count() {
    let decremented = try! CalendarRecurrence.decrementRecurrenceCount(
      recurrenceJson: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1001}"#)!
    let parsed = JSONValue.parse(decremented)!
    guard case let .object(rule) = parsed else { return XCTFail("expected object") }
    XCTAssertEqual(rule["COUNT"]?.rcI64, 1000)
    XCTAssertEqual(rule["FREQ"]?.rcStr, "DAILY")
    XCTAssertEqual(rule["INTERVAL"]?.rcI64, 1)
  }

  func test_decrement_recurrence_count_one_clears() {
    XCTAssertNil(
      try! CalendarRecurrence.decrementRecurrenceCount(
        recurrenceJson: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1}"#))
  }

  func test_decrement_recurrence_count_rejects_below_one() {
    XCTAssertThrowsError(
      try CalendarRecurrence.decrementRecurrenceCount(
        recurrenceJson: #"{"FREQ":"DAILY","INTERVAL":1,"COUNT":0}"#)
    ) { error in
      guard case StoreError.invariant = error else {
        return XCTFail("expected .invariant, got \(error)")
      }
    }
  }

  // MARK: - INTERVAL overflow crash-safety (poison recurrence rules)
  //
  // A recurrence rule with an enormous INTERVAL (e.g. Int64.max) can reach the
  // expansion engine through a synced peer whose write bypassed our normalizer.
  // Layer 1 requires the render/expansion path to be crash-proof regardless of
  // stored data: `interval * 7`, `steps * interval`, `delta + interval`, and the
  // day/month/year shifts all fail soft, so the series yields a bounded (here
  // empty) occurrence set. Each direct-helper call below drives the arithmetic
  // with Int64.max — bypassing the interval cap in `parseInterval` — and would
  // TRAP (checked-overflow or force-unwrap) without the overflow-safe arithmetic
  // and the fail-soft `RDate.addingDays`.

  func test_addingDays_does_not_trap_on_extreme_offset() {
    // The force-unwrap that trapped on out-of-range shifts is gone. Foundation
    // clamps rather than nils an astronomically large shift, so the result is
    // unspecified — the load-bearing guarantee is only that neither call traps.
    _ = d(2000, 1, 1).addingDays(Int64.max)
    _ = d(2000, 1, 1).addingDays(Int64.min)
    // A representable shift still computes correctly (2000 is a leap year).
    XCTAssertEqual(d(2000, 1, 1).addingDays(366), d(2001, 1, 1))
  }

  func test_weekly_nonbyday_interval_int64max_does_not_crash() {
    // Traps at `let intervalDays = interval * 7` (checked Int64 multiply) without
    // Layer 1. The next occurrence is astronomically far out → nil.
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"FREQ":"WEEKLY"}"#)
    XCTAssertNil(
      try! CalendarRecurrence.firstWeeklyCandidateOnOrAfter(
        rule, d(2026, 1, 5), d(2026, 6, 1), Int64.max))
  }

  func test_weekly_byday_interval_int64max_does_not_crash() {
    // Traps at `currentWeekStart.addingDays(interval * 7)` without Layer 1.
    let rule = try! CalendarRecurrence.parseRuleObject(
      #"{"FREQ":"WEEKLY","BYDAY":["MO","WE"]}"#)
    XCTAssertNil(
      try! CalendarRecurrence.firstWeeklyCandidateOnOrAfter(
        rule, d(2026, 1, 5), d(2026, 6, 1), Int64.max))
  }

  func test_daily_interval_int64max_does_not_crash() {
    // Traps at `delta + interval - 1` / `steps * interval` / the day-shift force
    // unwrap without Layer 1.
    XCTAssertNil(
      CalendarRecurrence.firstDailyCandidateOnOrAfter(
        d(2026, 1, 5), d(2026, 6, 1), Int64.max))
  }

  func test_monthly_interval_int64max_does_not_crash() {
    // Traps at `Int64(year) * 12 + Int64(month0) + steps*interval` (Int64
    // addition) inside `addMonthsWithAnchor` without the overflow-safe fix. The
    // target month is unrepresentably far out, surfaced as a caught `.invariant`
    // (skips the row) rather than a runtime trap.
    let rule = try! CalendarRecurrence.parseRuleObject(
      #"{"FREQ":"MONTHLY","BYMONTHDAY":[15]}"#)
    XCTAssertThrowsError(
      try CalendarRecurrence.firstMonthlyCandidateOnOrAfter(
        rule, d(2026, 1, 15), d(2026, 6, 1), Int64.max)
    ) { error in
      guard case StoreError.invariant = error else {
        return XCTFail("expected .invariant, got \(error)")
      }
    }
  }

  func test_yearly_interval_int64max_does_not_crash() {
    // Traps at `steps * interval` without the overflow-safe fix.
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"FREQ":"YEARLY"}"#)
    XCTAssertNil(
      try! CalendarRecurrence.firstYearlyCandidateOnOrAfter(
        rule, d(2026, 3, 3), d(2027, 1, 1), Int64.max))
  }

  func test_first_occurrence_poison_interval_throws_validation_not_crash() {
    // The exact poison from the crash report, driven through the rule-shaped
    // entry point. `parseInterval` rejects it (> cap), surfacing a clean
    // `.validation` (caught upstream by `extendWithTolerantExpansion`) — never a
    // crash — for every FREQ.
    for freq in ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"] {
      let json = #"{"FREQ":"\#(freq)","INTERVAL":1600000000000000000}"#
      XCTAssertThrowsError(
        try CalendarRecurrence.firstOccurrenceOnOrAfter(json, d(2026, 1, 5), d(2026, 6, 1)),
        "FREQ=\(freq)"
      ) { error in
        guard case StoreError.validation = error else {
          return XCTFail("expected .validation for FREQ=\(freq), got \(error)")
        }
      }
    }
  }

  // MARK: - INTERVAL upper-bound (Layer 2: expansion-engine parser)

  func test_parse_interval_rejects_over_cap() {
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"FREQ":"DAILY","INTERVAL":10001}"#)
    XCTAssertThrowsError(try CalendarRecurrence.parseInterval(rule)) { error in
      guard case let StoreError.validation(msg) = error else {
        return XCTFail("expected .validation, got \(error)")
      }
      XCTAssertTrue(msg.contains("10001") && msg.contains("exceeds maximum"), msg)
    }
  }

  func test_parse_interval_accepts_at_cap() {
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"FREQ":"DAILY","INTERVAL":10000}"#)
    XCTAssertEqual(try! CalendarRecurrence.parseInterval(rule), 10_000)
  }

  // MARK: - Small-interval regression (no behavior change from overflow-safe math)

  func test_daily_small_interval_expands_exact_occurrences() {
    // target == base → base itself.
    XCTAssertEqual(
      CalendarRecurrence.firstDailyCandidateOnOrAfter(d(2026, 1, 1), d(2026, 1, 1), 2),
      d(2026, 1, 1))
    // interval 2 (Jan 1,3,5,…): first on/after Jan 2 is Jan 3.
    XCTAssertEqual(
      CalendarRecurrence.firstDailyCandidateOnOrAfter(d(2026, 1, 1), d(2026, 1, 2), 2),
      d(2026, 1, 3))
    // interval 3 (Jan 1,4,7,…): first on/after Jan 6 is Jan 7.
    XCTAssertEqual(
      CalendarRecurrence.firstDailyCandidateOnOrAfter(d(2026, 1, 1), d(2026, 1, 6), 3),
      d(2026, 1, 7))
  }

  func test_weekly_small_interval_expands_exact_occurrences() {
    let rule = try! CalendarRecurrence.parseRuleObject(#"{"FREQ":"WEEKLY"}"#)
    // interval 1 (weekly from Jan 5): first on/after Jan 12 is Jan 12.
    XCTAssertEqual(
      try! CalendarRecurrence.firstWeeklyCandidateOnOrAfter(
        rule, d(2026, 1, 5), d(2026, 1, 12), 1),
      d(2026, 1, 12))
    // interval 2 (Jan 5, 19, Feb 2, …): first on/after Jan 12 is Jan 19.
    XCTAssertEqual(
      try! CalendarRecurrence.firstWeeklyCandidateOnOrAfter(
        rule, d(2026, 1, 5), d(2026, 1, 12), 2),
      d(2026, 1, 19))
  }
}
