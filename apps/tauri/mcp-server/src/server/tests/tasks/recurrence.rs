use super::*;
use crate::tasks::recurrence::{calculate_next_occurrence_date, inject_bymonthday, recurs_on_date};

#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_rejects_invalid_until_dates() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-00000000010b",
        "Recurrence Until Test",
        "open",
        None,
        None,
        None,
        0,
    );

    let err = server
        .set_recurrence(Parameters(SetRecurrenceArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000010b".to_string(),
            rule: crate::contract::RecurrenceRuleArgs {
                freq: RecurrenceFreq::Weekly,
                interval: Some(1),
                byday: Some(vec!["MO".to_string()]),
                bymonth: None,
                bymonthday: None,
                bysetpos: None,
                wkst: None,
                until: Some("2026-02-30".to_string()),
                count: None,
            },
            idempotency_key: None,
        }))
        .expect_err("invalid until should be rejected");

    // #2182: validation failures surface as structured JSON so the
    // assistant knows to reshape its args instead of retrying.
    let payload: serde_json::Value =
        serde_json::from_str(&err).expect("error must be a structured JSON payload");
    assert_eq!(payload["code"], "validation");
    assert_eq!(payload["retryable"], false);
    // post-consolidation the canonical
    // `validate_date_format` error wraps the offending value in
    // double-quotes (`\"2026-02-30\"`) and tags the field as
    // `date`. Both shapes carry the bad input so the assistant can
    // reshape its args; we just match on the raw value.
    assert!(
        payload["message"].as_str().unwrap().contains("2026-02-30"),
        "message must preserve human-readable detail: {payload}"
    );
}

// ──────────────────────────────────────────────────────────────────────
// F3 (#3006-M18 follow-up): pin the structured-validation envelope on
// every shape gate `set_recurrence` now delegates to. Pre-fix the
// `set_recurrence` rejection coverage had collapsed to a single UNTIL
// case after the M18 typed-args migration absorbed the boundary's
// hand-written guards into `normalize_task_recurrence`. These tests
// re-establish the policy that EVERY range/cardinality/shape failure
// surfaces as the assistant-facing `{kind: "validation", retryable: false,
// message: ...}` payload, with the message preserving enough detail
// for the AI to reshape its args without retrying.
// ──────────────────────────────────────────────────────────────────────

/// Build a default `RecurrenceRuleArgs` suitable for a happy-path
/// rule, then apply the test-specific tweak via `f`. Keeps each
/// rejection test focused on the field under test instead of
/// repeating ten None lines per case.
fn make_rule(
    freq: RecurrenceFreq,
    f: impl FnOnce(&mut crate::contract::RecurrenceRuleArgs),
) -> crate::contract::RecurrenceRuleArgs {
    let mut rule = crate::contract::RecurrenceRuleArgs {
        freq,
        interval: Some(1),
        byday: None,
        bymonth: None,
        bymonthday: None,
        bysetpos: None,
        wkst: None,
        until: None,
        count: None,
    };
    f(&mut rule);
    rule
}

/// Drive `set_recurrence` and parse the resulting error as a
/// structured validation envelope. Returns the payload so each test
/// can spell out a per-case message-content assertion.
fn drive_set_recurrence_rejection(
    rule: crate::contract::RecurrenceRuleArgs,
    seed_id: &str,
) -> serde_json::Value {
    let server = make_server();
    seed_task(
        &server,
        seed_id,
        "F3 rejection test",
        "open",
        None,
        None,
        None,
        0,
    );

    let err = server
        .set_recurrence(Parameters(SetRecurrenceArgs {
            id: seed_id.to_string(),
            rule,
            idempotency_key: None,
        }))
        .expect_err("rule should be rejected at the validation boundary");

    let payload: serde_json::Value =
        serde_json::from_str(&err).expect("error must be a structured JSON payload");
    assert_eq!(payload["code"], "validation", "payload: {payload}");
    assert_eq!(payload["retryable"], false, "payload: {payload}");
    payload
}

#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_rejects_byday_on_daily_freq() {
    // RFC 5545 §3.3.10: BYDAY is meaningful only for WEEKLY/MONTHLY/YEARLY.
    // The canonical normalizer pins this so a "DAILY on Mondays" rule
    // can't silently degrade into a daily-without-filter expansion.
    let payload = drive_set_recurrence_rejection(
        make_rule(RecurrenceFreq::Daily, |r| {
            r.byday = Some(vec!["MO".to_string()]);
        }),
        "01966a3f-7c8b-7d4e-8f3a-000000000106",
    );
    let message = payload["message"].as_str().unwrap();
    assert!(
        message.contains("BYDAY") && message.contains("WEEKLY"),
        "message should call out the BYDAY/freq mismatch: {payload}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_rejects_interval_zero() {
    // INTERVAL=0 has no defined RFC meaning. Pre-fix the typed schema
    // declared `interval: Option<u32>` so 0 *parsed* successfully —
    // the canonical normalizer is the only thing that catches it.
    let payload = drive_set_recurrence_rejection(
        make_rule(RecurrenceFreq::Weekly, |r| {
            r.interval = Some(0);
        }),
        "01966a3f-7c8b-7d4e-8f3a-00000000010a",
    );
    let message = payload["message"].as_str().unwrap();
    assert!(
        message.contains("INTERVAL") && message.contains("positive integer"),
        "message should explain INTERVAL must be positive: {payload}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_rejects_count_and_until_together() {
    // RFC 5545 §3.3.10: COUNT and UNTIL are mutually exclusive.
    // The two together would otherwise produce ambiguous "stop on N
    // occurrences vs. stop on date" semantics that the apply pipeline
    // can't reconcile.
    let payload = drive_set_recurrence_rejection(
        make_rule(RecurrenceFreq::Daily, |r| {
            r.count = Some(5);
            r.until = Some("2026-12-31".to_string());
        }),
        "01966a3f-7c8b-7d4e-8f3a-000000000108",
    );
    let message = payload["message"].as_str().unwrap();
    assert!(
        message.contains("COUNT") && message.contains("UNTIL"),
        "message should call out the COUNT/UNTIL exclusivity: {payload}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_rejects_bymonthday_out_of_range() {
    // BYMONTHDAY range per RFC 5545 §3.3.10: -31..=-1 ∪ 1..=31. 32
    // is out of band; the canonical normalizer is the single gate.
    let payload = drive_set_recurrence_rejection(
        make_rule(RecurrenceFreq::Monthly, |r| {
            r.bymonthday = Some(vec![32]);
        }),
        "01966a3f-7c8b-7d4e-8f3a-000000000107",
    );
    let message = payload["message"].as_str().unwrap();
    assert!(
        message.contains("BYMONTHDAY") && message.contains("32"),
        "message must echo the offending BYMONTHDAY value: {payload}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_rejects_unknown_byday_codes() {
    // the canonical BYDAY allowlist is MO/TU/WE/TH/FR/SA/SU.
    // "XX" is not a weekday code; a typo here would otherwise round-trip
    // through the wire envelope and surface as a confusing apply-time
    // parse error far from the bug site.
    let payload = drive_set_recurrence_rejection(
        make_rule(RecurrenceFreq::Weekly, |r| {
            r.byday = Some(vec!["XX".to_string()]);
        }),
        "01966a3f-7c8b-7d4e-8f3a-00000000010c",
    );
    let message = payload["message"].as_str().unwrap();
    assert!(
        message.contains("XX") || message.contains("BYDAY"),
        "message should preserve the bad BYDAY code: {payload}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn set_recurrence_rejects_empty_byday_array() {
    // F3 (#3006-M18 follow-up): a literal `byday: []` patch can't
    // round-trip through `normalize_task_recurrence` (the typed
    // serializer drops empty arrays before the normalizer ever sees
    // them), so `set_recurrence` owns the typed-boundary check —
    // pinning the assistant on a structured error rather than a
    // silent no-op.
    let payload = drive_set_recurrence_rejection(
        make_rule(RecurrenceFreq::Weekly, |r| {
            r.byday = Some(Vec::new());
        }),
        "01966a3f-7c8b-7d4e-8f3a-000000000109",
    );
    let message = payload["message"].as_str().unwrap();
    assert!(
        message.contains("BYDAY"),
        "message must call out BYDAY: {payload}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn monthly_recurrence_helpers_preserve_anchor_day_before_spawning_next_occurrence() {
    let recurrence = inject_bymonthday(r#"{"FREQ":"MONTHLY","INTERVAL":1}"#, "2026-01-31")
        .expect("recurrence rule should parse")
        .expect("monthly recurrence should gain BYMONTHDAY anchor");

    let next = calculate_next_occurrence_date(&recurrence, "2026-01-31")
        .expect("recurrence rule should parse")
        .expect("anchored monthly recurrence should produce a next date");

    assert_eq!(next, "2026-02-28");
}

#[test]
#[serial_test::serial(hlc)]
fn recurrence_helpers_honor_until_cutoffs() {
    let next = calculate_next_occurrence_date(
        r#"{"FREQ":"WEEKLY","INTERVAL":1,"BYDAY":["MO"],"UNTIL":"2026-03-02"}"#,
        "2026-03-02",
    )
    .expect("recurrence rule should parse");

    assert_eq!(next, None);
}

#[test]
#[serial_test::serial(hlc)]
fn yearly_recurrence_clamps_leap_day_to_feb_28() {
    let next = calculate_next_occurrence_date(r#"{"FREQ":"YEARLY","INTERVAL":1}"#, "2024-02-29")
        .expect("recurrence rule should parse");
    assert_eq!(next.as_deref(), Some("2025-02-28"));
}

#[test]
#[serial_test::serial(hlc)]
fn yearly_recurrence_recurs_on_clamped_feb_28_in_non_leap_year() {
    // recurs_on_date must find a yearly event from Feb 29 on Feb 28 in non-leap years
    assert!(recurs_on_date(
        r#"{"FREQ":"YEARLY","INTERVAL":1}"#,
        "2024-02-29",
        "2025-02-28",
    )
    .expect("recurrence rule should parse"));
}

#[test]
#[serial_test::serial(hlc)]
fn yearly_recurrence_rejects_invalid_target_date() {
    let err = recurs_on_date(
        r#"{"FREQ":"YEARLY","INTERVAL":1}"#,
        "2024-02-29",
        "2025-02-29",
    )
    .expect_err("invalid target date should fail");

    assert!(matches!(
        err,
        lorvex_store::StoreError::Validation(message)
            if message.contains("invalid target_date")
    ));
}
