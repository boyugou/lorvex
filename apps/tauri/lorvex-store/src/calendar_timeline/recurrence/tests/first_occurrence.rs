use super::helpers::first_occurrence_on_or_after;
use super::NaiveDate;

#[test]
fn first_occurrence_daily_before_base() {
    let base = NaiveDate::from_ymd_opt(2026, 3, 10).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 5).unwrap();
    let result = first_occurrence_on_or_after(r#"{"FREQ":"DAILY","INTERVAL":1}"#, base, target);
    assert_eq!(result, Some(base));
}

#[test]
fn first_occurrence_daily_with_interval() {
    let base = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 4).unwrap();
    let result = first_occurrence_on_or_after(r#"{"FREQ":"DAILY","INTERVAL":3}"#, base, target);
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 3, 4).unwrap()));
}

#[test]
fn first_occurrence_weekly_no_byday() {
    let base = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 10).unwrap();
    let result = first_occurrence_on_or_after(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#, base, target);
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 3, 15).unwrap()));
}

#[test]
fn first_occurrence_weekly_with_byday() {
    // 2026-03-02 is a Monday. BYDAY MO,WE,FR. Target 2026-03-05 (Thu).
    // Next match should be 2026-03-06 (Fri).
    let base = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 5).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE","FR"]}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 3, 6).unwrap()));
}

#[test]
fn first_occurrence_weekly_bymonth_filters_out_other_months() {
    let base = NaiveDate::from_ymd_opt(2026, 1, 5).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 1, 6).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"BYMONTH":[2]}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 2, 2).unwrap()));
}

#[test]
fn first_occurrence_weekly_interval_respects_wkst() {
    let base = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO"],"WKST":"MO"}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 3, 9).unwrap()));
}

#[test]
fn first_occurrence_weekly_byday_order_respects_wkst() {
    let base = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","SU"],"WKST":"MO"}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 3, 2).unwrap()));
}

#[test]
fn first_occurrence_monthly_bymonthday_skips_short_month() {
    // Explicit BYMONTHDAY=31 follows RFC 5545 §3.3.10: February has no
    // 31st, so it is skipped (not clamped to the 28th) — the next
    // occurrence after Jan 31 is Mar 31.
    let base = NaiveDate::from_ymd_opt(2026, 1, 31).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 2, 1).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYMONTHDAY":31}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 3, 31).unwrap()));
}

#[test]
fn first_occurrence_yearly_clamps_leap_day() {
    let base = NaiveDate::from_ymd_opt(2024, 2, 29).unwrap();
    let target = NaiveDate::from_ymd_opt(2025, 1, 1).unwrap();
    let result = first_occurrence_on_or_after(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, base, target);
    assert_eq!(
        result,
        Some(NaiveDate::from_ymd_opt(2025, 2, 28).unwrap()),
        "Yearly recurrence from Feb 29 must clamp to Feb 28 in 2025"
    );
}

#[test]
fn first_occurrence_yearly_preserves_leap_day() {
    let base = NaiveDate::from_ymd_opt(2024, 2, 29).unwrap();
    let target = NaiveDate::from_ymd_opt(2028, 1, 1).unwrap();
    let result = first_occurrence_on_or_after(r#"{"FREQ":"YEARLY","INTERVAL":4}"#, base, target);
    assert_eq!(
        result,
        Some(NaiveDate::from_ymd_opt(2028, 2, 29).unwrap()),
        "Yearly recurrence with interval 4 should land on Feb 29 in leap year"
    );
}

#[test]
fn first_occurrence_yearly_bymonth_bymonthday_skips_to_leap_day() {
    let base = NaiveDate::from_ymd_opt(2023, 1, 1).unwrap();
    let target = NaiveDate::from_ymd_opt(2023, 1, 1).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2024, 2, 29).unwrap()));
}

#[test]
fn first_occurrence_yearly_bymonth_without_bymonthday_uses_base_day_in_target_month() {
    let base = NaiveDate::from_ymd_opt(2026, 1, 10).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 1, 11).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2]}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 2, 10).unwrap()));
}

#[test]
fn first_occurrence_yearly_ordinal_byday_scans_whole_year() {
    let base = NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["-1FR"]}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 12, 25).unwrap()));
}

#[test]
fn first_occurrence_monthly_byday_bysetpos_picks_first_monday() {
    let base = NaiveDate::from_ymd_opt(2026, 1, 5).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 2, 1).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#,
        base,
        target,
    );
    assert_eq!(result, Some(NaiveDate::from_ymd_opt(2026, 2, 2).unwrap()));
}

#[test]
fn first_occurrence_until_exceeded() {
    let base = NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 4, 1).unwrap();
    let result = first_occurrence_on_or_after(
        r#"{"FREQ":"MONTHLY","INTERVAL":1,"UNTIL":"2026-03-31"}"#,
        base,
        target,
    );
    assert_eq!(result, None);
}

// -----------------------------------------------------------------------
// calculate_next_occurrence_date
