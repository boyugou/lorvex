use chrono::NaiveDate;

fn first_recurrence_on_or_after(
    recurrence_json: &str,
    base: NaiveDate,
    target: NaiveDate,
) -> Option<NaiveDate> {
    lorvex_store::calendar_timeline::recurrence::first_occurrence_on_or_after(
        recurrence_json,
        base,
        target,
    )
    .expect("recurrence rule should parse")
}

fn d(s: &str) -> NaiveDate {
    NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
}

#[test]
#[serial_test::serial(hlc)]
fn daily_base_is_first_occurrence() {
    let base = d("2026-03-10");
    let result = first_recurrence_on_or_after(r#"{"FREQ":"DAILY","INTERVAL":1}"#, base, base);
    assert_eq!(result, Some(base));
}

#[test]
#[serial_test::serial(hlc)]
fn daily_skips_to_exact_occurrence() {
    let base = d("2026-03-10");
    let result =
        first_recurrence_on_or_after(r#"{"FREQ":"DAILY","INTERVAL":1}"#, base, d("2026-03-12"));
    assert_eq!(result, Some(d("2026-03-12")));
}

#[test]
#[serial_test::serial(hlc)]
fn daily_non_occurrence_advances_to_next() {
    let base = d("2026-03-10");
    let result =
        first_recurrence_on_or_after(r#"{"FREQ":"DAILY","INTERVAL":2}"#, base, d("2026-03-11"));
    assert_eq!(result, Some(d("2026-03-12")));
}

#[test]
#[serial_test::serial(hlc)]
fn weekly_non_occurrence_is_detected() {
    let base = d("2026-03-09");
    let result =
        first_recurrence_on_or_after(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#, base, d("2026-03-10"));
    assert_eq!(result, Some(d("2026-03-16")));
}

#[test]
#[serial_test::serial(hlc)]
fn weekly_byday_valid_occurrence() {
    let base = d("2026-03-09");
    let result = first_recurrence_on_or_after(
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO","WE"]}"#,
        base,
        d("2026-03-11"),
    );
    assert_eq!(result, Some(d("2026-03-11")));
}

#[test]
#[serial_test::serial(hlc)]
fn yearly_leap_day_clamps_in_non_leap_year() {
    let base = d("2024-02-29");
    let result =
        first_recurrence_on_or_after(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, base, d("2025-01-01"));
    assert_eq!(result, Some(d("2025-02-28")));
}

#[test]
#[serial_test::serial(hlc)]
fn until_bound_prevents_occurrence() {
    let base = d("2026-03-09");
    let result = first_recurrence_on_or_after(
        r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-03-11"}"#,
        base,
        d("2026-03-15"),
    );
    assert_eq!(result, None);
}
