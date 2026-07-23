use super::*;

#[test]
fn parse_ymd_valid() {
    assert_eq!(
        parse_ymd("2026-03-15").expect("valid YMD"),
        NaiveDate::from_ymd_opt(2026, 3, 15).unwrap()
    );
}

#[test]
fn parse_ymd_invalid_returns_validation_error() {
    // corrupt-DB-row signals must propagate, not
    // silently disappear into a `None`. The error variant is the
    // typed `StoreError::Validation` so callers can re-classify
    // (DB-row vs user-input) at their own boundary.
    let err = parse_ymd("not-a-date").expect_err("invalid YMD must error");
    assert!(matches!(err, StoreError::Validation(_)));
}

#[test]
fn first_occurrence_rejects_malformed_rule_json() {
    let base = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
    let target = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
    let err = super::first_occurrence_on_or_after(r#"{"FREQ":"DAILY""#, base, target)
        .expect_err("malformed recurrence JSON should fail");
    assert!(matches!(err, StoreError::Serialization(_)));
}

#[test]
fn next_occurrence_rejects_invalid_until_date() {
    let err = super::calculate_next_occurrence_date(
        r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-02-30"}"#,
        "2026-02-28",
    )
    .expect_err("invalid UNTIL should fail");
    assert!(matches!(err, StoreError::Validation(_)));
}

#[test]
fn inject_bymonthday_rejects_invalid_due_date() {
    let err = super::inject_bymonthday(r#"{"FREQ":"MONTHLY","INTERVAL":1}"#, "2026-02-30")
        .expect_err("invalid due date should fail");
    assert!(matches!(err, StoreError::Validation(_)));
}

#[test]
fn inject_bymonthday_skips_positional_rules() {
    assert_eq!(
        super::inject_bymonthday(
            r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#,
            "2026-01-05",
        )
        .expect("valid positional monthly recurrence"),
        None
    );
    assert_eq!(
        super::inject_bymonthday(
            r#"{"FREQ":"YEARLY","INTERVAL":1,"BYDAY":["1MO"],"BYMONTH":[2]}"#,
            "2026-02-02",
        )
        .expect("valid ordinal yearly recurrence"),
        None
    );
}

#[test]
fn decrement_recurrence_count_accepts_uncapped_positive_count() {
    let decremented =
        super::decrement_recurrence_count(r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1001}"#)
            .expect("task recurrence countdown must accept uncapped positive COUNT")
            .expect("COUNT > 1 should keep recurrence");

    let rule: Value = serde_json::from_str(&decremented).expect("canonical recurrence JSON");
    assert_eq!(rule["COUNT"], 1000);
    assert_eq!(rule["FREQ"], "DAILY");
    assert_eq!(rule["INTERVAL"], 1);
}
