use super::super::*;

/// the canonical normalizer accepts `BYMONTH` (RFC
/// 5545's most common YEARLY modifier). Pre-fix the allowlist
/// silently rejected it, so Apple/Google calendar imports of
/// legitimate `FREQ=YEARLY;BYMONTH=*` rules failed at the validator
/// boundary.
#[test]
fn recurrence_yearly_bymonth_accepted_and_canonicalized() {
    let input = r#"{"FREQ":"YEARLY","BYMONTH":[2]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("YEARLY;BYMONTH must normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYMONTH"], serde_json::json!([2]));
}

#[test]
fn recurrence_leap_year_birthday_accepted_with_dedicated_warning() {
    // The canonical leap-year birthday idiom — issue #2978-H2 emits
    // a `LeapYearBirthday` warning instead of the generic
    // `BymonthdaySkipsMonths` so the diagnostic surface can spell
    // out the every-four-years cadence.
    let input = r#"{"FREQ":"YEARLY","BYMONTH":[2],"BYMONTHDAY":29}"#;
    let (canonical, warnings) = normalize_task_recurrence_with_warnings(input)
        .unwrap()
        .unwrap();
    assert!(canonical.contains(r#""BYMONTH":[2]"#));
    assert!(canonical.contains(r#""BYMONTHDAY":[29]"#));
    assert_eq!(warnings, vec![RecurrenceWarning::LeapYearBirthday]);
}

#[test]
fn recurrence_bymonth_rejects_zero_and_thirteen() {
    for raw in [
        r#"{"FREQ":"YEARLY","BYMONTH":[0]}"#,
        r#"{"FREQ":"YEARLY","BYMONTH":[13]}"#,
        r#"{"FREQ":"YEARLY","BYMONTH":[-1]}"#,
    ] {
        let err = normalize_task_recurrence(raw).unwrap_err();
        assert!(
            err.to_string().contains("BYMONTH"),
            "expected BYMONTH error, got: {err}"
        );
    }
}

#[test]
fn recurrence_daily_rejects_bymonth() {
    // RFC 5545 §3.3.10: BYMONTH has no defined semantics on
    // FREQ=DAILY (the daily expansion has no month boundary to
    // filter against).
    let input = r#"{"FREQ":"DAILY","BYMONTH":[2]}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.contains("BYMONTH") && msg.contains("DAILY"),
        "expected BYMONTH-on-DAILY rejection, got: {err}"
    );
}

#[test]
fn recurrence_weekly_bymonth_accepted() {
    // BYMONTH is meaningful on WEEKLY too — "every Monday in
    // February and August" is a legal RRULE.
    let input = r#"{"FREQ":"WEEKLY","BYDAY":["MO"],"BYMONTH":[2,8]}"#;
    let canonical = normalize_task_recurrence(input)
        .unwrap()
        .expect("WEEKLY;BYMONTH must normalize");
    let parsed: serde_json::Value = serde_json::from_str(&canonical).unwrap();
    assert_eq!(parsed["BYMONTH"], serde_json::json!([2, 8]));
}

#[test]
fn recurrence_byhour_byminute_rejected_until_time_expansion_is_supported() {
    let input = r#"{"FREQ":"DAILY","BYHOUR":[9,17],"BYMINUTE":[0,30]}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.contains("BYHOUR") || msg.contains("BYMINUTE"),
        "expected BYHOUR/BYMINUTE rejection, got: {err}"
    );
}

#[test]
fn recurrence_byhour_rejects_out_of_range() {
    let input = r#"{"FREQ":"DAILY","BYHOUR":[24]}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(err.to_string().contains("BYHOUR"), "got: {err}");
}

#[test]
fn recurrence_byminute_rejects_out_of_range() {
    let input = r#"{"FREQ":"DAILY","BYMINUTE":[60]}"#;
    let err = normalize_task_recurrence(input).unwrap_err();
    assert!(err.to_string().contains("BYMINUTE"), "got: {err}");
}

/// `MONTHLY;BYMONTHDAY=31` skips the months whose
/// last day is < 31. The validator returns `Ok(canonical)` so the
/// rule stores; the warning must fire so the apply / export path can
/// surface it.
#[test]
fn recurrence_bymonthday_31_emits_skip_warning() {
    let input = r#"{"FREQ":"MONTHLY","BYMONTHDAY":31}"#;
    let (canonical, warnings) = normalize_task_recurrence_with_warnings(input)
        .unwrap()
        .unwrap();
    assert!(canonical.contains(r#""BYMONTHDAY":[31]"#));
    assert_eq!(
        warnings,
        vec![RecurrenceWarning::BymonthdaySkipsMonths { day: 31 }]
    );
}

#[test]
fn recurrence_bymonthday_29_30_31_emit_warning() {
    for day in [29, 30, 31] {
        let raw = format!(r#"{{"FREQ":"MONTHLY","BYMONTHDAY":{day}}}"#);
        let (_, warnings) = normalize_task_recurrence_with_warnings(&raw)
            .unwrap()
            .unwrap();
        assert_eq!(
            warnings,
            vec![RecurrenceWarning::BymonthdaySkipsMonths { day }],
            "day={day} must emit skip warning"
        );
    }
}

#[test]
fn recurrence_bymonthday_28_does_not_warn() {
    // Every month has at least 28 days — the rule never skips.
    let input = r#"{"FREQ":"MONTHLY","BYMONTHDAY":28}"#;
    let (_, warnings) = normalize_task_recurrence_with_warnings(input)
        .unwrap()
        .unwrap();
    assert!(warnings.is_empty(), "BYMONTHDAY=28 must not warn");
}

#[test]
fn recurrence_bymonthday_negative_does_not_warn() {
    // Negative BYMONTHDAY counts from end-of-month — never skips.
    let input = r#"{"FREQ":"MONTHLY","BYMONTHDAY":-1}"#;
    let (_, warnings) = normalize_task_recurrence_with_warnings(input)
        .unwrap()
        .unwrap();
    assert!(warnings.is_empty(), "negative BYMONTHDAY must not warn");
}

#[test]
fn recurrence_bymonthday_31_on_yearly_also_warns() {
    let input = r#"{"FREQ":"YEARLY","BYMONTHDAY":31}"#;
    let (_, warnings) = normalize_task_recurrence_with_warnings(input)
        .unwrap()
        .unwrap();
    assert_eq!(
        warnings,
        vec![RecurrenceWarning::BymonthdaySkipsMonths { day: 31 }]
    );
}

/// pre-fix `BYMONTH/BYSETPOS/BYDAY`
/// arrays were emitted in input order without sort + dedup, so two
/// devices that author logically-identical rules in different input
/// orders produced divergent canonical JSON. The version-stamp /
/// outbox payload / peer apply path then diverged across devices for
/// the same logical rule, defeating LWW. Pin canonicalization here.
#[test]
fn recurrence_by_arrays_canonicalized_sort_dedup() {
    // BYMONTH
    let scrambled = r#"{"FREQ":"YEARLY","BYMONTH":[12,1,6,1]}"#;
    let canonical = normalize_task_recurrence(scrambled).unwrap().unwrap();
    assert!(canonical.contains(r#""BYMONTH":[1,6,12]"#));

    // BYSETPOS — negatives precede positives under default i64 ordering.
    let scrambled = r#"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[3,-1,1,1]}"#;
    let canonical = normalize_task_recurrence(scrambled).unwrap().unwrap();
    assert!(canonical.contains(r#""BYSETPOS":[-1,1,3]"#));

    // BYDAY — weekday ordering MO=0..SU=6, dedup.
    let scrambled = r#"{"FREQ":"WEEKLY","BYDAY":["FR","MO","FR","WE"]}"#;
    let canonical = normalize_task_recurrence(scrambled).unwrap().unwrap();
    assert!(canonical.contains(r#""BYDAY":["MO","WE","FR"]"#));

    // BYDAY with ordinal prefixes (MONTHLY): negative ordinals precede
    // unsigned, then by weekday.
    let scrambled = r#"{"FREQ":"MONTHLY","BYDAY":["1FR","-1MO","1MO"]}"#;
    let canonical = normalize_task_recurrence(scrambled).unwrap().unwrap();
    assert!(canonical.contains(r#""BYDAY":["-1MO","1MO","1FR"]"#));
}
