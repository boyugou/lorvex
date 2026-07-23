use super::helpers::recurs_on_date;
use super::StoreError;

#[test]
fn recurs_on_date_daily() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":2}"#;
    assert!(recurs_on_date(rule, "2026-03-01", "2026-03-03"));
    assert!(!recurs_on_date(rule, "2026-03-01", "2026-03-02"));
}

#[test]
fn recurs_on_date_weekly() {
    let rule = r#"{"FREQ":"WEEKLY","INTERVAL":1}"#;
    assert!(recurs_on_date(rule, "2026-03-01", "2026-03-08"));
    assert!(!recurs_on_date(rule, "2026-03-01", "2026-03-09"));
}

#[test]
fn recurs_on_date_monthly() {
    let rule = r#"{"FREQ":"MONTHLY","INTERVAL":1}"#;
    assert!(recurs_on_date(rule, "2026-01-15", "2026-03-15"));
}

#[test]
fn recurs_on_date_yearly() {
    let rule = r#"{"FREQ":"YEARLY","INTERVAL":1}"#;
    assert!(recurs_on_date(rule, "2025-06-15", "2026-06-15"));
}

#[test]
fn recurs_on_date_yearly_bymonth_bymonthday_only_matches_leap_day() {
    let rule = r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#;
    assert!(recurs_on_date(rule, "2024-02-29", "2028-02-29"));
    assert!(!recurs_on_date(rule, "2024-02-29", "2025-02-28"));
}

#[test]
fn recurs_on_date_monthly_byday_bysetpos_matches_first_monday() {
    let rule = r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#;
    assert!(recurs_on_date(rule, "2026-01-05", "2026-02-02"));
    assert!(!recurs_on_date(rule, "2026-01-05", "2026-02-09"));
}

#[test]
fn recurs_on_date_base_is_match() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1}"#;
    assert!(recurs_on_date(rule, "2026-03-15", "2026-03-15"));
}

#[test]
fn recurs_on_date_before_base() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1}"#;
    assert!(!recurs_on_date(rule, "2026-03-15", "2026-03-14"));
}

#[test]
fn recurs_on_date_until_exceeded() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-03-16"}"#;
    assert!(!recurs_on_date(rule, "2026-03-15", "2026-03-17"));
}

#[test]
fn recurs_on_date_count_daily() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#;
    assert!(recurs_on_date(rule, "2026-03-01", "2026-03-02"));
    assert!(recurs_on_date(rule, "2026-03-01", "2026-03-03"));
    assert!(!recurs_on_date(rule, "2026-03-01", "2026-03-04"));
}

#[test]
fn recurs_on_date_rejects_invalid_count_zero() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":0}"#;
    let err = super::recurs_on_date(rule, "2026-03-01", "2026-03-02")
        .expect_err("COUNT=0 should be rejected");
    assert!(matches!(err, StoreError::Validation(_)));
}

#[test]
fn recurs_on_date_rejects_excessive_count_for_expansion_budget() {
    let rule = r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1001}"#;
    let err = super::recurs_on_date(rule, "2026-03-01", "2026-03-02")
        .expect_err("timeline recurrence checks must keep COUNT expansion bounded");
    assert!(
        matches!(err, StoreError::Validation(ref msg) if msg.contains("1001")
                && msg.contains("exceeds maximum")),
        "expected validation error mentioning 1001 and max, got: {err:?}"
    );
}

// -----------------------------------------------------------------------
// first_occurrence_on_or_after
// -----------------------------------------------------------------------
