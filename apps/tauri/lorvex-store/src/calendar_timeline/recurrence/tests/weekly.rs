use super::helpers::{first_weekly_byday_occurrence_on_or_after, weekly_target_dows};
use super::{NaiveDate, Value};

#[test]
fn weekly_target_dows_returns_sorted() {
    let rule: Value = serde_json::from_str(r#"{"BYDAY":["FR","MO","WE"]}"#).unwrap();
    assert_eq!(weekly_target_dows(&rule), Some(vec![1, 3, 5]));
}

#[test]
fn weekly_target_dows_empty_returns_none() {
    let rule: Value = serde_json::from_str(r#"{"BYDAY":[]}"#).unwrap();
    assert_eq!(weekly_target_dows(&rule), None);
}

#[test]
fn weekly_target_dows_absent_returns_none() {
    let rule: Value = serde_json::from_str(r#"{"FREQ":"WEEKLY"}"#).unwrap();
    assert_eq!(weekly_target_dows(&rule), None);
}

#[test]
fn byday_occurrence_same_week() {
    // 2026-03-02 is Monday. Target Wed 2026-03-04. BYDAY MO,WE.
    let rule: Value =
        serde_json::from_str(r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE"]}"#).unwrap();
    let base = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 4).unwrap();
    assert_eq!(
        first_weekly_byday_occurrence_on_or_after(&rule, base, target, 1),
        Some(NaiveDate::from_ymd_opt(2026, 3, 4).unwrap())
    );
}

#[test]
fn byday_occurrence_next_interval() {
    // 2026-03-02 is Monday. Interval 2. Target 2026-03-10 (next Mon).
    // Next aligned week starts 2026-03-16.
    let rule: Value =
        serde_json::from_str(r#"{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO"]}"#).unwrap();
    let base = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 10).unwrap();
    assert_eq!(
        first_weekly_byday_occurrence_on_or_after(&rule, base, target, 2),
        Some(NaiveDate::from_ymd_opt(2026, 3, 16).unwrap())
    );
}
