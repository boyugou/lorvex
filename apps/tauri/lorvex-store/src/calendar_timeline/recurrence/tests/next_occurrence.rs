use super::helpers::{calculate_next_occurrence_date, next_occurrence_strictly_after};

#[test]
fn next_occurrence_daily_basic() {
    let result = calculate_next_occurrence_date(r#"{"FREQ":"DAILY","INTERVAL":1}"#, "2026-03-15");
    assert_eq!(result.as_deref(), Some("2026-03-16"));
}

#[test]
fn next_occurrence_weekly_basic() {
    let result = calculate_next_occurrence_date(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#, "2026-03-15");
    assert_eq!(result.as_deref(), Some("2026-03-22"));
}

#[test]
fn next_occurrence_weekly_bymonth_filters_out_other_months() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"BYMONTH":[2]}"#,
        "2026-01-05",
    );
    assert_eq!(result.as_deref(), Some("2026-02-02"));
}

#[test]
fn next_occurrence_weekly_interval_respects_wkst() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO"],"WKST":"MO"}"#,
        "2026-03-01",
    );
    assert_eq!(result.as_deref(), Some("2026-03-09"));
}

#[test]
fn next_occurrence_weekly_byday_order_respects_wkst() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","SU"],"WKST":"MO"}"#,
        "2026-03-02",
    );
    assert_eq!(result.as_deref(), Some("2026-03-08"));
}

#[test]
fn next_occurrence_monthly_bymonthday_31_skips_feb() {
    // RFC 5545 §3.3.10: explicit BYMONTHDAY=31 skips February (no 31st)
    // rather than clamping to the 28th — the next occurrence after
    // Jan 31 is Mar 31.
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#,
        "2026-01-31",
    );
    assert_eq!(result.as_deref(), Some("2026-03-31"));
}

#[test]
fn monthly_bymonthday_31_lands_on_next_month_with_31_days() {
    // From Feb 28 the next BYMONTHDAY=31 occurrence is Mar 31 (Feb is
    // skipped; March has a 31st).
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#,
        "2026-02-28",
    );
    assert_eq!(result.as_deref(), Some("2026-03-31"));
}

#[test]
fn yearly_recurrence_clamps_leap_day_to_feb_28() {
    let result = calculate_next_occurrence_date(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2024-02-29");
    assert_eq!(result.as_deref(), Some("2025-02-28"));
}

#[test]
fn monthly_bymonthday_negative_one_resolves_to_last_day_of_month() {
    // RFC 5545 BYMONTHDAY=-1 is "last day of month" — common in
    // subscribed ICS feeds (rent, payroll, month-end reports).
    // previously rejected by `as_u64()` → whole
    // expansion aborted → event silently absent from the app.
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":-1}"#,
        "2026-01-31",
    );
    assert_eq!(result.as_deref(), Some("2026-02-28"));
}

#[test]
fn monthly_bymonthday_negative_two_resolves_to_penultimate_day() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":-2}"#,
        "2026-01-30",
    );
    assert_eq!(result.as_deref(), Some("2026-02-27"));
}

#[test]
fn monthly_bymonthday_rejects_zero_and_out_of_range_values() {
    for invalid in ["0", "32", "-32", "-33", "\"x\""] {
        let rule = format!(r#"{{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":{invalid}}}"#);
        let err = super::calculate_next_occurrence_date(&rule, "2026-01-15")
            .expect_err("invalid BYMONTHDAY should error");
        assert!(
            err.to_string().contains("BYMONTHDAY"),
            "unexpected error for {invalid}: {err}"
        );
    }
}

#[test]
fn yearly_recurrence_preserves_leap_day_in_leap_year() {
    let result = calculate_next_occurrence_date(r#"{"FREQ":"YEARLY","INTERVAL":4}"#, "2024-02-29");
    assert_eq!(result.as_deref(), Some("2028-02-29"));
}

#[test]
fn next_occurrence_yearly_bymonth_bymonthday_skips_non_leap_years() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#,
        "2024-02-29",
    );
    assert_eq!(result.as_deref(), Some("2028-02-29"));
}

#[test]
fn next_occurrence_yearly_bymonth_without_bymonthday_uses_base_day_in_target_month() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2]}"#,
        "2026-01-10",
    );
    assert_eq!(result.as_deref(), Some("2026-02-10"));
}

#[test]
fn next_occurrence_yearly_byday_bysetpos_scans_whole_year() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#,
        "2026-01-05",
    );
    assert_eq!(result.as_deref(), Some("2027-01-04"));
}

#[test]
fn next_occurrence_monthly_ordinal_byday_picks_first_monday() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["1MO"]}"#,
        "2026-01-05",
    );
    assert_eq!(result.as_deref(), Some("2026-02-02"));
}

#[test]
fn yearly_recurrence_normal_date() {
    let result = calculate_next_occurrence_date(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2026-03-15");
    assert_eq!(result.as_deref(), Some("2027-03-15"));
}

#[test]
fn next_occurrence_monthly_multi_day_visits_each_day_in_order() {
    // BYMONTHDAY=[1,15]: from the 1st the next occurrence is the 15th;
    // from the 15th it rolls to the next month's 1st.
    let from_first = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[1,15]}"#,
        "2026-01-01",
    );
    assert_eq!(from_first.as_deref(), Some("2026-01-15"));
    let from_fifteenth = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[1,15]}"#,
        "2026-01-15",
    );
    assert_eq!(from_fifteenth.as_deref(), Some("2026-02-01"));
}

#[test]
fn next_occurrence_monthly_bymonthday_29_30_31_skips_february_entirely() {
    // February has none of 29/30/31, so the whole month is skipped (not
    // clamped to the 28th); the next occurrence after Jan 31 is Mar 29 —
    // the earliest of the set in a month that has all three days.
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[29,30,31]}"#,
        "2026-01-31",
    );
    assert_eq!(result.as_deref(), Some("2026-03-29"));
}

#[test]
fn next_occurrence_monthly_minus_one_and_31_dedupe_in_31_day_month() {
    // In a 31-day month -1 and 31 coincide and dedupe to a single 31st.
    // Advancing from Mar 31 lands on Apr 30: April lacks a 31st (that
    // anchor skips) while -1 resolves to the 30th.
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":[-1,31]}"#,
        "2026-03-31",
    );
    assert_eq!(result.as_deref(), Some("2026-04-30"));
}

#[test]
fn yearly_bymonthday_29_skips_to_next_leap_year() {
    // Explicit BYMONTHDAY=29 (no BYMONTH) skips non-leap Februaries per
    // RFC 5545 — from Feb 28 2025 the next Feb-29 is in leap year 2028.
    // Matches the BYMONTH=[2];BYMONTHDAY=29 behavior (both skip).
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTHDAY":29}"#,
        "2025-02-28",
    );
    assert_eq!(result.as_deref(), Some("2028-02-29"));
}

#[test]
fn until_date_prevents_next_occurrence() {
    let result = calculate_next_occurrence_date(
        r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-03-15"}"#,
        "2026-03-15",
    );
    assert_eq!(result, None);
}

// -----------------------------------------------------------------------
// next_occurrence_strictly_after
// -----------------------------------------------------------------------

#[test]
fn strictly_after_today_wins() {
    let result = next_occurrence_strictly_after(
        r#"{"FREQ":"DAILY","INTERVAL":1}"#,
        "2026-03-10",
        "2026-03-15",
    );
    assert_eq!(result.as_deref(), Some("2026-03-16"));
}

#[test]
fn strictly_after_base_wins() {
    let result = next_occurrence_strictly_after(
        r#"{"FREQ":"DAILY","INTERVAL":1}"#,
        "2026-03-20",
        "2026-03-15",
    );
    assert_eq!(result.as_deref(), Some("2026-03-21"));
}

// -----------------------------------------------------------------------
// count_end_date
// -----------------------------------------------------------------------
