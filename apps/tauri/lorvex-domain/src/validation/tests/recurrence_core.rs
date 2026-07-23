use super::super::*;

#[test]
fn recurrence_count_and_until_mutually_exclusive() {
    let input = r#"{"FREQ":"DAILY","COUNT":3,"UNTIL":"2026-04-10"}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string()
            .contains("COUNT and UNTIL are mutually exclusive"),
        "expected mutual exclusion error, got: {err}"
    );
}

#[test]
fn recurrence_byday_only_valid_for_weekly() {
    let input = r#"{"FREQ":"DAILY","BYDAY":["MO","WE"]}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string().contains("BYDAY is only valid for WEEKLY"),
        "expected BYDAY/WEEKLY error, got: {err}"
    );
}

#[test]
fn recurrence_bymonthday_only_valid_for_monthly_yearly() {
    let input = r#"{"FREQ":"WEEKLY","BYMONTHDAY":15}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string()
            .contains("BYMONTHDAY is only valid for MONTHLY/YEARLY"),
        "expected BYMONTHDAY restriction error, got: {err}"
    );
}

#[test]
fn recurrence_canonical_key_order_preserved() {
    // Input has keys in a non-canonical order; output must have stable, deterministic order.
    let input = r#"{"INTERVAL":2,"BYDAY":["MO","FR"],"FREQ":"WEEKLY"}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should produce canonical JSON");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    let obj = parsed.as_object().unwrap();

    // serde_json::Map uses BTreeMap by default, so keys are sorted alphabetically.
    // The key point is that the output is deterministic regardless of input key order.
    let keys: Vec<&String> = obj.keys().collect();
    assert_eq!(keys, vec!["BYDAY", "FREQ", "INTERVAL"]);
    assert_eq!(parsed["FREQ"], "WEEKLY");
    assert_eq!(parsed["INTERVAL"], 2);
    assert_eq!(parsed["BYDAY"], serde_json::json!(["MO", "FR"]));

    // Verify stability: same input in different order produces identical output.
    let input2 = r#"{"FREQ":"WEEKLY","BYDAY":["MO","FR"],"INTERVAL":2}"#;
    let canonical2 = normalize_task_recurrence(input2)
        .unwrap()
        .expect("should produce canonical JSON");
    assert_eq!(
        canonical, canonical2,
        "canonical output must be identical regardless of input key order"
    );
}

#[test]
fn recurrence_empty_input_returns_none() {
    assert_eq!(normalize_task_recurrence("").unwrap(), None);
    assert_eq!(normalize_task_recurrence("   ").unwrap(), None);
}

#[test]
fn recurrence_unknown_key_rejected() {
    // WKST/BYSETPOS/BYMONTH were promoted
    // into the known-keys allowlist alongside the existing FREQ /
    // INTERVAL / BYDAY / BYMONTHDAY / UNTIL / COUNT, so this test
    // pivots to a still-undefined key.
    let input = r#"{"FREQ":"DAILY","FOOBAR":"MO"}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string().contains("unknown key"),
        "expected unknown key error, got: {err}"
    );
}

#[test]
fn recurrence_valid_daily_normalized() {
    let input = r#"{"FREQ":"DAILY"}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["FREQ"], "DAILY");
    assert_eq!(parsed["INTERVAL"], 1, "INTERVAL should default to 1");
}

#[test]
fn recurrence_bymonthday_valid_for_monthly() {
    let input = r#"{"FREQ":"MONTHLY","BYMONTHDAY":15}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYMONTHDAY"], serde_json::json!([15]));
}

#[test]
fn recurrence_bymonthday_valid_for_yearly() {
    let input = r#"{"FREQ":"YEARLY","BYMONTHDAY":1}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYMONTHDAY"], serde_json::json!([1]));
}

#[test]
fn recurrence_bymonthday_array_sorts_and_dedupes() {
    // Multi-day rule: "1st and 15th" plus a duplicate and a negative
    // anchor. Canonical output is the sorted, deduped array.
    let input = r#"{"FREQ":"MONTHLY","BYMONTHDAY":[15,1,15,-1]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    assert!(
        canonical.contains(r#""BYMONTHDAY":[-1,1,15]"#),
        "expected sorted+deduped array, got: {canonical}"
    );
}

#[test]
fn recurrence_bymonthday_empty_array_drops_the_key() {
    // An empty BYMONTHDAY array is treated as absent.
    let input = r#"{"FREQ":"MONTHLY","BYMONTHDAY":[]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    assert!(
        !canonical.contains("BYMONTHDAY"),
        "empty BYMONTHDAY array must drop the key, got: {canonical}"
    );
}

#[test]
fn recurrence_bymonthday_array_rejects_out_of_range_entry() {
    // A single out-of-range entry rejects the whole array.
    for input in [
        r#"{"FREQ":"MONTHLY","BYMONTHDAY":[1,32]}"#,
        r#"{"FREQ":"MONTHLY","BYMONTHDAY":[0]}"#,
        r#"{"FREQ":"MONTHLY","BYMONTHDAY":[-32,5]}"#,
    ] {
        let err = normalize_task_recurrence(input).unwrap_err();
        assert!(
            err.to_string().contains("BYMONTHDAY"),
            "expected BYMONTHDAY range error for {input}, got: {err}"
        );
    }
}

#[test]
fn recurrence_count_valid() {
    let input = r#"{"FREQ":"DAILY","COUNT":5}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["COUNT"], 5);
}

#[test]
fn recurrence_until_valid() {
    let input = r#"{"FREQ":"WEEKLY","UNTIL":"2026-12-31"}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["UNTIL"], "2026-12-31");
}

/// RFC 5545 DATE-TIME form `YYYYMMDDTHHMMSSZ`
/// must be accepted (and normalized to canonical YYYY-MM-DD).
/// Pre-fix imported feeds with the legitimate DATE-TIME variant
/// were rejected at sync apply.
#[test]
fn recurrence_until_accepts_rfc5545_date_time() {
    let input = r#"{"FREQ":"WEEKLY","UNTIL":"20261231T235959Z"}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(
        parsed["UNTIL"], "2026-12-31",
        "UNTIL must normalize to canonical YYYY-MM-DD"
    );
}

/// RFC 5545 DATE form `YYYYMMDD` must be accepted
/// (and normalized to canonical YYYY-MM-DD).
#[test]
fn recurrence_until_accepts_rfc5545_date() {
    let input = r#"{"FREQ":"WEEKLY","UNTIL":"20261231"}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["UNTIL"], "2026-12-31");
}

#[test]
fn recurrence_until_rejects_garbage() {
    let input = r#"{"FREQ":"WEEKLY","UNTIL":"not-a-date"}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(err.to_string().contains("UNTIL"), "got: {err}");
}

#[test]
fn recurrence_invalid_freq_rejected() {
    let input = r#"{"FREQ":"HOURLY"}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string().contains("FREQ must be"),
        "expected FREQ error, got: {err}"
    );
}

#[test]
fn recurrence_negative_interval_rejected() {
    let input = r#"{"FREQ":"DAILY","INTERVAL":-1}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string()
            .contains("INTERVAL must be a positive integer"),
        "expected INTERVAL error, got: {err}"
    );
}

#[test]
fn recurrence_zero_count_rejected() {
    let input = r#"{"FREQ":"DAILY","COUNT":0}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string().contains("COUNT must be a positive integer"),
        "expected COUNT error, got: {err}"
    );
}
