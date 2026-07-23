use super::super::*;

/// `is_valid_byday_token_for_freq` accepts bare codes for every FREQ.
/// The RFC 5545 ordinal-prefixed forms (`1MO`, `+2WE`, `-1FR`) are
/// only valid for MONTHLY/YEARLY — issue #2978-H5.
#[test]
fn byday_token_accepts_bare_codes_for_every_freq() {
    for code in ["MO", "TU", "WE", "TH", "FR", "SA", "SU"] {
        for freq in ["WEEKLY", "MONTHLY", "YEARLY"] {
            assert!(
                is_valid_byday_token_for_freq(code, freq),
                "bare {code} must accept under {freq}"
            );
        }
    }
}

#[test]
fn byday_token_yearly_accepts_full_ordinal_range() {
    // YEARLY is the broadest range — `1..=53` covers the maximum
    // count of same-weekdays in a Gregorian year.
    for token in ["1MO", "+2WE", "-1FR", "53SU", "-53SU"] {
        assert!(
            is_valid_byday_token_for_freq(token, "YEARLY"),
            "prefixed {token} must accept under YEARLY"
        );
    }
}

#[test]
fn byday_token_monthly_caps_ordinal_at_five() {
    // MONTHLY caps the ordinal absolute value at 5
    // because no calendar month has more than five same-weekdays.
    // Pre-fix the validator accepted up to 53, which produced
    // never-firing series like `MONTHLY;BYDAY=10MO`.
    for token in ["1MO", "+5WE", "-5FR"] {
        assert!(
            is_valid_byday_token_for_freq(token, "MONTHLY"),
            "in-range MONTHLY ordinal {token} must accept"
        );
    }
    for token in ["6MO", "+10WE", "-7FR", "53SU"] {
        assert!(
            !is_valid_byday_token_for_freq(token, "MONTHLY"),
            "out-of-range MONTHLY ordinal {token} must reject"
        );
    }
}

#[test]
fn byday_token_weekly_rejects_every_ordinal() {
    // RFC 5545 has no "first MO inside a week" notion — issue
    // #2978-H5 folds the FREQ-level rejection into the token helper
    // so the rule lives in one place.
    for token in ["1MO", "+2WE", "-1FR", "5SU"] {
        assert!(
            !is_valid_byday_token_for_freq(token, "WEEKLY"),
            "WEEKLY ordinal prefix {token} must reject"
        );
    }
    // Bare codes still pass.
    assert!(is_valid_byday_token_for_freq("MO", "WEEKLY"));
}

#[test]
fn byday_token_rejects_garbage_and_out_of_range() {
    for token in [
        "", "X", "MX", "1XX", "0MO", "54MO", "-54MO", "+0FR", "+-1MO", "01MO",
    ] {
        assert!(
            !is_valid_byday_token_for_freq(token, "YEARLY"),
            "{token} must reject"
        );
    }
}

#[test]
fn recurrence_monthly_byday_with_ordinal_accepted() {
    // "First Monday of every month" — the canonical RFC 5545 idiom
    // for "first weekday of the month". Pre-fix the validator
    // rejected the ordinal prefix.
    let input = r#"{"FREQ":"MONTHLY","BYDAY":["1MO"]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYDAY"], serde_json::json!(["1MO"]));
}

#[test]
fn recurrence_yearly_byday_with_negative_ordinal_accepted() {
    let input = r#"{"FREQ":"YEARLY","BYDAY":["-1FR"]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYDAY"], serde_json::json!(["-1FR"]));
}

#[test]
fn recurrence_weekly_rejects_byday_ordinal_prefix() {
    // RFC 5545 disallows ordinal-prefixed BYDAY on WEEKLY. Issue
    // #2978-H5: the rejection is now folded into the FREQ-aware
    // token helper, so the surfacing error cites the WEEKLY-specific
    // expectation copy rather than a generic "ordinal prefixes are
    // only valid for MONTHLY/YEARLY" message.
    let input = r#"{"FREQ":"WEEKLY","BYDAY":["1MO"]}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.contains("WEEKLY") && msg.contains("ordinal prefixes"),
        "expected WEEKLY ordinal-prefix rejection, got: {err}"
    );
}

#[test]
fn recurrence_monthly_rejects_byday_ordinal_above_five() {
    // MONTHLY ordinals are capped at `1..=5` because
    // no calendar month has more than five same-weekdays. Pre-fix
    // `MONTHLY;BYDAY=10MO` survived validation and produced a
    // never-firing series.
    let input = r#"{"FREQ":"MONTHLY","BYDAY":["10MO"]}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.contains("MONTHLY") && msg.contains("1..=5"),
        "expected MONTHLY ordinal-cap message, got: {err}"
    );
}

#[test]
fn recurrence_yearly_accepts_byday_ordinal_at_full_range() {
    // YEARLY's `1..=53` range is
    // preserved by the FREQ-aware helper.
    let input = r#"{"FREQ":"YEARLY","BYDAY":["53SU"]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("YEARLY accepts the full ordinal range");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYDAY"], serde_json::json!(["53SU"]));
}

#[test]
fn recurrence_wkst_accepted_and_canonicalized() {
    let input = r#"{"FREQ":"WEEKLY","INTERVAL":2,"WKST":"MO"}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["WKST"], "MO");
}

#[test]
fn recurrence_wkst_rejects_invalid_code() {
    let input = r#"{"FREQ":"WEEKLY","WKST":"XX"}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(
        err.to_string().contains("WKST"),
        "expected WKST error, got: {err}"
    );
}

#[test]
fn recurrence_bysetpos_array_accepted() {
    // "First Monday of the month" via BYDAY+BYSETPOS — the sample
    // pattern called out in the RFC 5545 text.
    let input = r#"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[1]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("should normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYSETPOS"], serde_json::json!([1]));
}

#[test]
fn recurrence_bysetpos_rejected_for_daily_and_weekly() {
    for raw in [
        r#"{"FREQ":"DAILY","BYSETPOS":[1]}"#,
        r#"{"FREQ":"WEEKLY","BYDAY":["MO"],"BYSETPOS":[1]}"#,
    ] {
        let err = normalize_task_recurrence(raw).unwrap_err();
        assert!(err.to_string().contains("BYSETPOS"), "got: {err}");
    }
}

#[test]
fn recurrence_bysetpos_rejects_zero_and_out_of_range() {
    for raw in [
        r#"{"FREQ":"MONTHLY","BYSETPOS":[0]}"#,
        r#"{"FREQ":"MONTHLY","BYSETPOS":[367]}"#,
        r#"{"FREQ":"MONTHLY","BYSETPOS":[-367]}"#,
    ] {
        let err = normalize_task_recurrence(raw).unwrap_err();
        assert!(err.to_string().contains("BYSETPOS"), "got: {err}");
    }
}
