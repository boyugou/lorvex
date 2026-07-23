use super::helpers::count_end_date;
use super::StoreError;

#[test]
fn count_end_daily_count_3() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#;
    assert_eq!(
        count_end_date(rule, "2026-01-01"),
        Some("2026-01-03".to_string())
    );
}

#[test]
fn count_end_weekly_count_2() {
    let rule = r#"{"FREQ":"WEEKLY","INTERVAL":1,"COUNT":2}"#;
    assert_eq!(
        count_end_date(rule, "2026-01-06"),
        Some("2026-01-13".to_string())
    );
}

#[test]
fn count_end_no_count_returns_none() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1}"#;
    assert_eq!(count_end_date(rule, "2026-01-01"), None);
}

#[test]
fn count_end_count_1_returns_base() {
    let rule = r#"{"FREQ":"MONTHLY","INTERVAL":1,"COUNT":1}"#;
    assert_eq!(
        count_end_date(rule, "2026-03-15"),
        Some("2026-03-15".to_string())
    );
}

#[test]
fn count_end_yearly_from_leap_day_clamps() {
    let rule = r#"{"FREQ":"YEARLY","INTERVAL":1,"COUNT":3}"#;
    assert_eq!(
        count_end_date(rule, "2024-02-29"),
        Some("2026-02-28".to_string())
    );
}

#[test]
fn count_end_yearly_bymonth_bymonthday_counts_leap_day_occurrences() {
    let rule = r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29,"COUNT":2}"#;
    assert_eq!(
        count_end_date(rule, "2024-02-29"),
        Some("2028-02-29".to_string())
    );
}

#[test]
fn count_end_monthly_byday_bysetpos_counts_first_mondays() {
    let rule = r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1],"COUNT":3}"#;
    assert_eq!(
        count_end_date(rule, "2026-01-05"),
        Some("2026-03-02".to_string())
    );
}

#[test]
fn count_end_rejects_excessive_count() {
    // A malicious sync payload with COUNT=9999 must be rejected at parse
    // time rather than spinning `count_end_date` for thousands of iterations.
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":9999}"#;
    let err =
        super::count_end_date(rule, "2026-01-01").expect_err("excessive COUNT should be rejected");
    assert!(
        matches!(err, StoreError::Validation(ref msg) if msg.contains("9999")
                && msg.contains("exceeds maximum")),
        "expected validation error mentioning 9999 and max, got: {err:?}"
    );
}

#[test]
fn count_end_accepts_count_at_cap() {
    // COUNT exactly at MAX_RECURRENCE_COUNT must still be accepted.
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1000}"#;
    // 2026-01-01 + 999 days (index 1..1000) = 2028-09-26.
    assert_eq!(
        count_end_date(rule, "2026-01-01"),
        Some("2028-09-26".to_string())
    );
}

// -----------------------------------------------------------------------
// first_weekly_byday_occurrence_on_or_after
// -----------------------------------------------------------------------
