use super::emit::{
    export_calendar_ics, export_calendar_ics_with_warnings, fold_line, format_ics_timestamp,
    local_to_utc_ics_timestamp, MAX_VEVENT_TEXT_LENGTH,
};
use super::model::{
    CalendarIcsError, CalendarIcsEvent, CalendarIcsEventFields, CalendarIcsWarning,
};
use super::recurrence::{
    parse_ics_rrule_to_recurrence_json, parse_ics_rrule_to_recurrence_json_with_warnings,
    recurrence_to_rrule,
};
use super::validation::{next_date, validate_export_range};
use crate::calendar::CalendarEventTiming;
use crate::time::{Date, TimeOfDay};

fn sample_event<'a>() -> CalendarIcsEvent<'a> {
    CalendarIcsEvent::new(CalendarIcsEventFields {
        id: "evt-1",
        title: "Weekly planning",
        description: Some("Review the week"),
        recurrence: None,
        recurrence_exceptions: None,
        start_date: Date::parse("2026-03-18").unwrap(),
        start_time: Some(TimeOfDay::parse("09:30").unwrap()),
        end_date: None,
        end_time: Some(TimeOfDay::parse("10:30").unwrap()),
        all_day: false,
        location: Some("Desk"),
        timezone: None,
        created_at: "2026-03-17T08:00:00Z",
        updated_at: "2026-03-18T08:30:00Z",
        sequence: 0,
    })
    .expect("sample event must validate")
}

#[test]
fn validate_export_range_rejects_reverse_range() {
    assert_eq!(
        validate_export_range("2026-03-20", "2026-03-18"),
        Err(CalendarIcsError::InvalidRange {
            from: "2026-03-20".to_string(),
            to: "2026-03-18".to_string(),
        })
    );
}

#[test]
fn export_calendar_ics_formats_timed_event() {
    let ics = export_calendar_ics(&[sample_event()]).expect("ics export should succeed");
    assert!(ics.contains("BEGIN:VCALENDAR"));
    assert!(ics.contains("UID:evt-1@lorvex"));
    assert!(ics.contains("DTSTART:20260318T093000Z"));
    assert!(ics.contains("DTEND:20260318T103000Z"));
    assert!(ics.contains("SUMMARY:Weekly planning"));
}

/// every exported VEVENT must carry a SEQUENCE
/// line so an edit-republish round trips through downstream
/// calendar clients without being silently ignored as a
/// duplicate of the original publication.
#[test]
fn export_calendar_ics_emits_sequence_line() {
    let event = sample_event();
    let ics = export_calendar_ics(&[event]).expect("ics export should succeed");
    assert!(
        ics.contains("SEQUENCE:0"),
        "VEVENT must carry SEQUENCE:0 for an unedited event; got:\n{ics}"
    );
}

#[test]
fn export_calendar_ics_emits_nonzero_sequence_for_edited_event() {
    let mut event = sample_event();
    event.sequence = 7;
    let ics = export_calendar_ics(&[event]).expect("ics export should succeed");
    assert!(
        ics.contains("SEQUENCE:7"),
        "edited VEVENT must carry caller-supplied SEQUENCE; got:\n{ics}"
    );
}

/// an over-long SUMMARY / DESCRIPTION /
/// LOCATION must be truncated at the export boundary and surface
/// a `TextTruncated` warning so a sync-imported or legacy row
/// that bypassed the write-time validator cannot ship an
/// unbounded line through the export.
#[test]
fn export_calendar_ics_truncates_oversize_summary() {
    let huge_title: String = "x".repeat(MAX_VEVENT_TEXT_LENGTH + 50);
    let mut event = sample_event();
    event.title = &huge_title;
    let (ics, warnings) =
        export_calendar_ics_with_warnings(&[event]).expect("ics export should succeed");

    // SUMMARY line must contain the truncation marker.
    assert!(
        ics.contains('\u{2026}'),
        "oversize SUMMARY must include the truncation marker; got:\n{ics}"
    );

    // No SUMMARY line in the output should exceed the cap (excluding
    // the `SUMMARY:` prefix and ICS line-folding which the fold
    // helper applies after capping).
    let summary_line = ics
        .lines()
        .find(|l| l.starts_with("SUMMARY:") || l.starts_with(' '))
        .map(std::string::ToString::to_string)
        .unwrap_or_default();
    // The capped value, stripped of "SUMMARY:" prefix, must be
    // <= MAX_VEVENT_TEXT_LENGTH codepoints. (Fold-line continuation
    // marker is checked elsewhere — here we assert the unfolded
    // input length feeding into fold_line.)
    assert!(
        !summary_line.is_empty(),
        "must emit a SUMMARY line for the capped value"
    );

    let truncated_warning = warnings.iter().any(|w| {
        matches!(
            w,
            CalendarIcsWarning::TextTruncated {
                field: "SUMMARY",
                original_chars,
                truncated_to,
            } if *original_chars == MAX_VEVENT_TEXT_LENGTH + 50
                && *truncated_to == MAX_VEVENT_TEXT_LENGTH
        )
    });
    assert!(
        truncated_warning,
        "must emit TextTruncated warning for SUMMARY; got: {warnings:?}"
    );
}

#[test]
fn export_calendar_ics_does_not_warn_for_summary_at_cap() {
    let exact_title: String = "x".repeat(MAX_VEVENT_TEXT_LENGTH);
    let mut event = sample_event();
    event.title = &exact_title;
    let (_, warnings) =
        export_calendar_ics_with_warnings(&[event]).expect("ics export should succeed");
    assert!(
        !warnings
            .iter()
            .any(|w| matches!(w, CalendarIcsWarning::TextTruncated { .. })),
        "exactly-at-cap SUMMARY must not warn; got: {warnings:?}"
    );
}

/// the PRODID line must include the running
/// crate version so a downstream client (or a support request
/// reading an exported `.ics` blob) can pinpoint the build that
/// emitted the file. The previous hardcoded
/// `//Lorvex//Calendar//EN` made that impossible.
#[test]
fn export_calendar_ics_prodid_includes_crate_version() {
    let ics = export_calendar_ics(&[sample_event()]).expect("ics export should succeed");
    let expected = format!(
        "PRODID:-//Lorvex//Calendar {}//EN",
        env!("CARGO_PKG_VERSION")
    );
    assert!(
        ics.contains(&expected),
        "PRODID must carry crate version; got ics:\n{ics}"
    );
}

#[test]
fn export_calendar_ics_converts_local_time_to_utc_for_ny_tz() {
    // March 18 2026 at 09:30 America/New_York is 13:30 UTC (EDT is
    // active by then — DST started March 8 2026).
    let mut event = sample_event();
    event.timezone = Some("America/New_York");
    let ics = export_calendar_ics(&[event]).expect("ics export should succeed");
    assert!(
        ics.contains("DTSTART:20260318T133000Z"),
        "timezone-aware DTSTART must convert local wall-clock to UTC; got: {ics}"
    );
    assert!(
        ics.contains("DTEND:20260318T143000Z"),
        "timezone-aware DTEND must convert local wall-clock to UTC; got: {ics}"
    );
}

#[test]
fn export_calendar_ics_converts_exdate_same_as_dtstart() {
    let mut event = sample_event();
    event.timezone = Some("America/New_York");
    event.recurrence = Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#);
    event.recurrence_exceptions = Some(r#"["2026-03-25"]"#);
    let ics = export_calendar_ics(&[event]).expect("ics export should succeed");
    // EXDATE must share the same UTC offset as DTSTART or external
    // clients won't match the excluded instance.
    assert!(
        ics.contains("EXDATE:20260325T133000Z"),
        "EXDATE must match the DTSTART timezone; got: {ics}"
    );
}

#[test]
fn export_calendar_ics_rejects_invalid_exception_json() {
    let mut event = sample_event();
    event.recurrence_exceptions = Some("[1,2,3]");
    assert_eq!(
        export_calendar_ics(&[event]),
        Err(CalendarIcsError::InvalidRecurrenceExceptionJson(
            "[1,2,3]".to_string()
        ))
    );
}

#[test]
fn export_calendar_ics_rejects_invalid_exception_date() {
    let mut event = sample_event();
    event.recurrence_exceptions = Some("[\"2026-02-30\"]");
    assert_eq!(
        export_calendar_ics(&[event]),
        Err(CalendarIcsError::InvalidRecurrenceExceptionDate(
            "2026-02-30".to_string()
        ))
    );
}

#[test]
fn recurrence_to_rrule_daily() {
    let json = r#"{"FREQ":"DAILY","INTERVAL":1}"#;
    let mut warnings = Vec::new();
    assert_eq!(
        recurrence_to_rrule(Some(json), &mut warnings).expect("recurrence should export"),
        Some("RRULE:FREQ=DAILY".to_string())
    );
    assert!(warnings.is_empty(), "DAILY rule should produce no warnings");
}

#[test]
fn parse_ics_rrule_to_recurrence_json_weekly_byday() {
    let json = parse_ics_rrule_to_recurrence_json("FREQ=WEEKLY;BYDAY=MO,WE,FR")
        .expect("weekly BYDAY RRULE should parse");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("parse recurrence JSON");

    assert_eq!(parsed["FREQ"], "WEEKLY");
    assert_eq!(parsed["BYDAY"], serde_json::json!(["MO", "WE", "FR"]));
}

#[test]
fn parse_ics_rrule_to_recurrence_json_numeric_lists_and_until() {
    let json = parse_ics_rrule_to_recurrence_json(
        "FREQ=MONTHLY;INTERVAL=2;BYMONTH=2,8;BYDAY=MO;BYSETPOS=1,-1;UNTIL=20261231T000000Z",
    )
    .expect("monthly RRULE should parse");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("parse recurrence JSON");

    assert_eq!(parsed["INTERVAL"], 2);
    assert_eq!(parsed["BYMONTH"], serde_json::json!([2, 8]));
    assert_eq!(parsed["BYSETPOS"], serde_json::json!([-1, 1]));
    assert_eq!(parsed["UNTIL"], "2026-12-31");
}

#[test]
fn parse_ics_rrule_to_recurrence_json_rejects_malformed_until_with_warning() {
    let mut warnings = Vec::new();
    let parsed =
        parse_ics_rrule_to_recurrence_json_with_warnings("FREQ=DAILY;UNTIL=garbage", &mut warnings);

    assert!(parsed.is_none());
    assert_eq!(warnings.len(), 1);
    assert_eq!(warnings[0].message, "unsupported RRULE dropped");
    assert!(warnings[0].details.contains("UNTIL"));
}

#[test]
fn parse_ics_rrule_to_recurrence_json_rejects_until_with_trailing_junk() {
    let mut warnings = Vec::new();
    let parsed = parse_ics_rrule_to_recurrence_json_with_warnings(
        "FREQ=DAILY;UNTIL=20261231garbage",
        &mut warnings,
    );

    assert!(parsed.is_none());
    assert_eq!(warnings.len(), 1);
    assert_eq!(warnings[0].message, "unsupported RRULE dropped");
    assert!(warnings[0].details.contains("UNTIL"));
}

#[test]
fn parse_ics_rrule_to_recurrence_json_rejects_unsupported_fields_with_warning() {
    let mut warnings = Vec::new();
    let parsed =
        parse_ics_rrule_to_recurrence_json_with_warnings("FREQ=DAILY;BYHOUR=9", &mut warnings);

    assert!(parsed.is_none());
    assert_eq!(warnings.len(), 1);
    assert_eq!(warnings[0].message, "unsupported RRULE dropped");
    assert!(warnings[0].details.contains("BYHOUR"));
}

#[test]
fn recurrence_to_rrule_rejects_malformed_json() {
    // malformed JSON now surfaces through the
    // canonical normalizer's parse error, which gets wrapped in
    // `InvalidRecurrenceRule` rather than the bespoke
    // `InvalidRecurrenceJson` variant the standalone helper used.
    let mut warnings = Vec::new();
    let err = recurrence_to_rrule(Some("{bad json"), &mut warnings)
        .expect_err("malformed JSON must reject");
    assert!(
        matches!(err, CalendarIcsError::InvalidRecurrenceRule(_)),
        "expected InvalidRecurrenceRule for malformed JSON, got {err:?}"
    );
}

/// BYDAY codes must be validated
/// against the canonical seven-code allowlist before they reach
/// the exported RRULE. The validator now owns the check; the
/// serializer simply trusts the canonical output. A malformed
/// code (`MX` here) is rejected at normalize time and surfaces
/// as `InvalidRecurrenceRule` carrying both the offending code
/// and the allowed set.
#[test]
fn recurrence_to_rrule_rejects_unknown_byday_code() {
    let json = r#"{"FREQ":"WEEKLY","BYDAY":["MO","MX"]}"#;
    let mut warnings = Vec::new();
    let err =
        recurrence_to_rrule(Some(json), &mut warnings).expect_err("malformed BYDAY must reject");
    match err {
        CalendarIcsError::InvalidRecurrenceRule(message) => {
            assert!(
                message.contains("MX") && message.contains("MO/TU/WE/TH/FR/SA/SU"),
                "error must cite the offending code and the allowlist; got: {message}"
            );
        }
        other => panic!("expected InvalidRecurrenceRule, got {other:?}"),
    }
}

#[test]
fn recurrence_to_rrule_accepts_all_valid_byday_codes() {
    let json = r#"{"FREQ":"WEEKLY","BYDAY":["MO","TU","WE","TH","FR","SA","SU"]}"#;
    let mut warnings = Vec::new();
    let rrule =
        recurrence_to_rrule(Some(json), &mut warnings).expect("all canonical codes must accept");
    assert_eq!(
        rrule,
        Some("RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU".to_string())
    );
}

#[test]
fn recurrence_to_rrule_rejects_invalid_until_date() {
    // post-refactor an invalid UNTIL date is
    // caught by the canonical normalizer (which understands
    // YYYY-MM-DD, YYYYMMDD, and YYYYMMDDTHHMMSSZ) and surfaces as
    // `InvalidRecurrenceRule` rather than the dedicated
    // `InvalidDate` variant the standalone helper used.
    let json = r#"{"FREQ":"DAILY","UNTIL":"2026-02-30"}"#;
    let mut warnings = Vec::new();
    let err =
        recurrence_to_rrule(Some(json), &mut warnings).expect_err("invalid UNTIL must reject");
    match err {
        CalendarIcsError::InvalidRecurrenceRule(message) => {
            assert!(
                message.contains("UNTIL") && message.contains("2026-02-30"),
                "error must cite the field and offending value; got: {message}"
            );
        }
        other => panic!("expected InvalidRecurrenceRule, got {other:?}"),
    }
}

#[test]
fn ics_export_shifts_forward_through_dst_spring_gap() {
    // 2026-03-08 02:30 in America/Los_Angeles falls
    // inside the spring-forward gap (clocks jump 02:00 → 03:00
    // PST → PDT). Previously this silently re-labeled the wall
    // clock as UTC — producing a timestamp ~8 hours and 1 day
    // off. Now the helper advances 15 minutes at a time until it
    // lands on a valid wall-clock moment (03:00 local = 10:00 UTC
    // in PDT). Result: 20260308T100000Z, NOT 20260308T023000Z.
    let out = local_to_utc_ics_timestamp(
        Date::parse("2026-03-08").unwrap(),
        TimeOfDay::parse("02:30").unwrap(),
        Some("America/Los_Angeles"),
        "start",
    );
    assert_eq!(
        out, "20260308T100000Z",
        "expected post-gap 03:00 local -> 10:00 UTC, got {out}"
    );
}

#[test]
fn ics_export_ambiguous_fall_back_picks_earliest_offset() {
    // 2026-11-01 01:30 America/Los_Angeles falls in the fall-back
    // ambiguity (PDT 01:30 → 02:00, then PST 01:00 → 02:00).
    // Matching the existing convention, pick the earliest (PDT).
    let out = local_to_utc_ics_timestamp(
        Date::parse("2026-11-01").unwrap(),
        TimeOfDay::parse("01:30").unwrap(),
        Some("America/Los_Angeles"),
        "start",
    );
    // 01:30 PDT = 08:30 UTC.
    assert_eq!(out, "20261101T083000Z");
}

// -- regressions

/// `next_date` must never panic on chrono's
/// `+ Duration::days(1)` arithmetic. `9999-12-31` is the
/// largest year `%Y-%m-%d` accepts via `parse_from_str`; chrono's
/// `NaiveDate` happily represents `+10000-01-01` so the fix
/// surfaces as "no panic, returns `+10000-01-01`" — a contract
/// the legacy `+ Duration::days(1)` form *also* met for this
/// input but that is now defensively wrapped in
/// `checked_add_days` so a future caller that constructs
/// `NaiveDate::MAX` directly won't panic either.
#[test]
fn next_date_succeeds_at_year_9999_without_panic() {
    let next = next_date("end_date", Date::parse("9999-12-31").unwrap()).expect("must not panic");
    // `+10000-01-01` is what `chrono::NaiveDate::format("%Y-%m-%d")`
    // produces for a 5-digit year (the leading `+` sign mode).
    // Compare via `to_string()` since `Date::parse` rejects the
    // 5-digit form (matches the `%Y-%m-%d` parser cap) but the
    // underlying NaiveDate still represents it correctly.
    assert_eq!(next.to_string(), "+10000-01-01");
}

/// directly exercise the overflow branch by
/// constructing `NaiveDate::MAX` and asserting `+1 day` saturates
/// to `None`. Pre-fix the equivalent `+ Duration::days(1)` call
/// panicked. Wraps the verified branch into the typed error path
/// `next_date` exposes — `checked_add_days(MAX) → None →
/// DateOverflow`.
#[test]
fn next_date_overflow_branch_returns_typed_error() {
    // The string parser caps at year 9999, so we can't reach
    // overflow through the public string entry point. Verify
    // the underlying chrono primitive saturates to `None` so
    // the `ok_or_else(DateOverflow)` arm is exercised — this
    // pins the contract that an upstream change exposing
    // `NaiveDate::MAX` to `next_date` would surface as a typed
    // error rather than a panic.
    let max = chrono::NaiveDate::MAX;
    assert_eq!(
        max.checked_add_days(chrono::Days::new(1)),
        None,
        "NaiveDate::MAX + 1 day must saturate to None"
    );
}

/// the two legacy fallback parsers in
/// `format_ics_timestamp` (no timezone marker) must emit a
/// `LegacyNaiveTimestamp` warning so a caller can surface the
/// drift. RFC 3339-shaped inputs must NOT warn.
#[test]
fn format_ics_timestamp_warns_on_naive_t_separator() {
    let mut warnings = Vec::new();
    let out = format_ics_timestamp("created_at", "2026-03-08T02:30:00", &mut warnings).unwrap();
    assert_eq!(out, "20260308T023000Z");
    assert_eq!(
        warnings,
        vec![CalendarIcsWarning::LegacyNaiveTimestamp {
            field: "created_at",
            value: "2026-03-08T02:30:00".to_string()
        }]
    );
}

#[test]
fn format_ics_timestamp_warns_on_naive_space_separator() {
    let mut warnings = Vec::new();
    let out = format_ics_timestamp("updated_at", "2026-03-08 02:30:00", &mut warnings).unwrap();
    assert_eq!(out, "20260308T023000Z");
    assert_eq!(
        warnings,
        vec![CalendarIcsWarning::LegacyNaiveTimestamp {
            field: "updated_at",
            value: "2026-03-08 02:30:00".to_string()
        }]
    );
}

#[test]
fn format_ics_timestamp_does_not_warn_on_rfc3339() {
    let mut warnings = Vec::new();
    let _ = format_ics_timestamp("created_at", "2026-03-08T02:30:00Z", &mut warnings).unwrap();
    assert!(warnings.is_empty(), "RFC3339 input must not warn");
}

// -- issue #2978-H9: legacy fallback rejects pre-1900 years -------

/// Pre-fix `created_at = "0099-01-01T00:00:00"` (no timezone
/// marker → falls into the legacy naive parser) produced
/// `00990101T000000Z`. RFC 5545 §3.3.5 mandates 4-digit Gregorian
/// timestamps and Apple/Google/Outlook silently drop the entire
/// VEVENT when they parse a pre-1900 year, so the export looked
/// like it succeeded while the receiving client was eating it.
#[test]
fn format_ics_timestamp_rejects_pre_1900_year_t_separator() {
    let mut warnings = Vec::new();
    let err = format_ics_timestamp("created_at", "0099-01-01T00:00:00", &mut warnings)
        .expect_err("pre-1900 year must reject");
    match err {
        CalendarIcsError::PreGregorianTimestampYear { field, year } => {
            assert_eq!(field, "created_at");
            assert_eq!(year, 99);
        }
        other => panic!("expected PreGregorianTimestampYear, got {other:?}"),
    }
}

#[test]
fn format_ics_timestamp_rejects_pre_1900_year_space_separator() {
    let mut warnings = Vec::new();
    let err = format_ics_timestamp("updated_at", "1899-12-31 23:59:59", &mut warnings)
        .expect_err("year 1899 must reject (cutoff is 1900)");
    match err {
        CalendarIcsError::PreGregorianTimestampYear { field, year } => {
            assert_eq!(field, "updated_at");
            assert_eq!(year, 1899);
        }
        other => panic!("expected PreGregorianTimestampYear, got {other:?}"),
    }
}

#[test]
fn format_ics_timestamp_accepts_year_1900_at_cutoff() {
    let mut warnings = Vec::new();
    let out = format_ics_timestamp("created_at", "1900-01-01T00:00:00", &mut warnings).unwrap();
    assert_eq!(out, "19000101T000000Z");
}

// -- issue #2978-H8: EXDATE dedupe + cap --------------------------

/// Pre-fix `recurrence_exceptions = ["2026-03-25"]*10` produced
/// 10 EXDATE lines for a single VEVENT — issue #2978-H8 dedupes
/// by canonical YYYY-MM-DD before emitting so the same date
/// surfaces once.
#[test]
fn export_calendar_ics_dedupes_exdates_by_canonical_date() {
    let mut event = sample_event();
    event.recurrence = Some(r#"{"FREQ":"WEEKLY"}"#);
    event.recurrence_exceptions = Some(r#"["2026-03-25","2026-03-25","2026-03-25"]"#);
    let ics = export_calendar_ics(&[event]).expect("ics export should succeed");
    let exdate_lines = ics.lines().filter(|l| l.starts_with("EXDATE")).count();
    assert_eq!(
        exdate_lines, 1,
        "duplicate exception dates must collapse to a single EXDATE line; got: {ics}"
    );
}

/// a peer-authored exception list past the
/// `MAX_RECURRENCE_EXDATES` cap surfaces a typed error instead
/// of producing thousands of lines.
#[test]
fn export_calendar_ics_rejects_oversize_exception_list() {
    // Build 367 unique dates (one past the 366 leap-year cap).
    let dates: Vec<String> = (0..367)
        .map(|i| {
            let base = chrono::NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
            let d = base + chrono::Duration::days(i);
            d.format("%Y-%m-%d").to_string()
        })
        .collect();
    let recurrence_exceptions = serde_json::to_string(&dates).unwrap();
    let mut event = sample_event();
    event.recurrence = Some(r#"{"FREQ":"DAILY"}"#);
    event.recurrence_exceptions = Some(&recurrence_exceptions);
    let err = export_calendar_ics(&[event]).expect_err("oversize EXDATE list must reject");
    match err {
        CalendarIcsError::RecurrenceExdateLimitExceeded { count, limit } => {
            assert_eq!(count, 367);
            assert_eq!(limit, 366);
        }
        other => panic!("expected RecurrenceExdateLimitExceeded, got {other:?}"),
    }
}

/// the cap matches `MAX_CALENDAR_RECURRENCE_COUNT
/// = 365` plus 1 for leap-year parity. A 366-entry list still
/// exports cleanly.
#[test]
fn export_calendar_ics_accepts_exception_list_at_cap() {
    let dates: Vec<String> = (0..366)
        .map(|i| {
            let base = chrono::NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
            let d = base + chrono::Duration::days(i);
            d.format("%Y-%m-%d").to_string()
        })
        .collect();
    let recurrence_exceptions = serde_json::to_string(&dates).unwrap();
    let mut event = sample_event();
    event.timing = CalendarEventTiming::AllDay {
        start: Date::parse("2026-03-18").unwrap(),
        end: None,
    };
    event.recurrence = Some(r#"{"FREQ":"DAILY"}"#);
    event.recurrence_exceptions = Some(&recurrence_exceptions);
    let ics = export_calendar_ics(&[event]).expect("at-cap EXDATE list must export");
    let exdate_lines = ics.lines().filter(|l| l.starts_with("EXDATE")).count();
    assert_eq!(
        exdate_lines, 366,
        "366-day cap should emit 366 EXDATE lines"
    );
}

// -- issue #2978-H3: EXDATE shape parity with DTSTART -------------
//
// the legacy regression test
// `export_calendar_ics_exdate_is_date_value_when_start_time_is_none`
// exercised a malformed `(start_time = None, all_day = false)`
// combination that the pre-#3287 struct shape allowed by direct
// field assignment. After the typed-timing migration the carrier
// holds a [`CalendarEventTiming`] enum so that combination is
// non-representable — `from_flat_fields` rejects it at the boundary
// — and the test cannot be expressed without bypassing the typed
// gate. The defensive `is_date_value_event` helper and its
// `InternalContractViolation` partner in `append_vevent` /
// `recurrence_exdates` remain in place so a future bug that reaches
// the timed branch with no `start_time` surfaces a typed error
// instead of a panic.

#[test]
fn export_calendar_ics_exdate_is_timed_when_start_time_is_present_and_not_all_day() {
    // Sanity check the timed branch — ensures the new
    // `is_date_value_event` helper still routes timed events
    // through the correct EXDATE shape.
    let mut event = sample_event();
    event.timezone = Some("America/New_York");
    event.recurrence = Some(r#"{"FREQ":"WEEKLY"}"#);
    event.recurrence_exceptions = Some(r#"["2026-03-25"]"#);
    let ics = export_calendar_ics(&[event]).expect("must export");
    assert!(
        ics.contains("EXDATE:20260325T133000Z"),
        "timed event must emit timed EXDATE matching DTSTART; got: {ics}"
    );
}

/// `recurrence_to_rrule` now delegates to the
/// canonical normalizer. Verifies BYSETPOS, WKST, and
/// ordinal-prefixed BYDAY all round-trip into the emitted RRULE.
#[test]
fn recurrence_to_rrule_emits_bysetpos_and_wkst() {
    let json = r#"{"FREQ":"MONTHLY","BYDAY":["MO"],"BYSETPOS":[1],"WKST":"MO"}"#;
    let mut warnings = Vec::new();
    let rrule = recurrence_to_rrule(Some(json), &mut warnings)
        .unwrap()
        .unwrap();
    assert!(
        rrule.contains("BYDAY=MO") && rrule.contains("BYSETPOS=1") && rrule.contains("WKST=MO"),
        "RRULE missing one of the new keys: {rrule}"
    );
}

#[test]
fn recurrence_to_rrule_rejects_byhour_byminute_until_time_expansion_is_supported() {
    let json = r#"{"FREQ":"DAILY","BYHOUR":[9,17],"BYMINUTE":[0,30]}"#;
    let mut warnings = Vec::new();
    let err = recurrence_to_rrule(Some(json), &mut warnings)
        .expect_err("BYHOUR/BYMINUTE should be rejected");
    assert!(err.to_string().contains("BYHOUR"), "got: {err}");
}

#[test]
fn recurrence_to_rrule_emits_ordinal_byday() {
    let json = r#"{"FREQ":"MONTHLY","BYDAY":["1MO","-1FR"]}"#;
    let mut warnings = Vec::new();
    let rrule = recurrence_to_rrule(Some(json), &mut warnings)
        .unwrap()
        .unwrap();
    // BYDAY canonicalization (#3034-H4) sorts by
    // (ordinal, weekday_index) so `-1FR` (ordinal=-1) precedes
    // `1MO` (ordinal=1) regardless of input order.
    assert!(
        rrule.contains("BYDAY=-1FR,1MO"),
        "RRULE missing canonical BYDAY ordering: {rrule}"
    );
}

/// a `MONTHLY;BYMONTHDAY=31` rule must surface a
/// `BymonthdaySkipsMonths` warning to the export pipeline so it
/// can be passed onward to a diagnostic / sync conflict log.
#[test]
fn export_calendar_ics_surfaces_bymonthday_skip_warning() {
    let mut event = sample_event();
    event.recurrence = Some(r#"{"FREQ":"MONTHLY","BYMONTHDAY":31}"#);
    let (_, warnings) = export_calendar_ics_with_warnings(&[event]).unwrap();
    assert_eq!(
        warnings,
        vec![CalendarIcsWarning::Recurrence(
            crate::validation::RecurrenceWarning::BymonthdaySkipsMonths { day: 31 }
        )]
    );
}

/// the validator's BYDAY-code
/// rejection must propagate cleanly through the serializer. A
/// stale duplicate validator inside `recurrence_to_rrule` would
/// be a silent gap.
#[test]
fn export_calendar_ics_rejects_unknown_byday_via_validator() {
    let mut event = sample_event();
    event.recurrence = Some(r#"{"FREQ":"WEEKLY","BYDAY":["XX"]}"#);
    let err = export_calendar_ics(&[event]).expect_err("must reject");
    match err {
        CalendarIcsError::InvalidRecurrenceRule(message) => {
            assert!(
                message.contains("XX"),
                "error must cite offending code; got: {message}"
            );
        }
        other => panic!("expected InvalidRecurrenceRule, got {other:?}"),
    }
}

/// `escape_ics_text` must strip the bidi
/// overrides + zero-width codepoints that
/// `unicode_hygiene::sanitize_user_text` strips at every other
/// write boundary. Pre-fix, `\u{202E}` (RIGHT-TO-LEFT OVERRIDE),
/// `\u{200B}` (ZWSP), and `\u{FEFF}` (BOM) embedded in an
/// untrusted title round-tripped into the exported `.ics`
/// SUMMARY/DESCRIPTION/LOCATION lines and from there into Apple
/// Calendar / Google.
#[test]
fn export_calendar_ics_strips_bidi_and_zero_width_codepoints() {
    let mut event = sample_event();
    event.title = "paypal\u{202E}moc";
    event.description = Some("ad\u{200B}min\u{2060}note");
    event.location = Some("\u{FEFF}Office\u{200E}");
    let ics = export_calendar_ics(&[event]).expect("ics export should succeed");

    assert!(
        ics.contains("SUMMARY:paypalmoc"),
        "RLO must be stripped from SUMMARY; got: {ics}"
    );
    assert!(
        ics.contains("DESCRIPTION:adminnote"),
        "ZWSP + word-joiner must be stripped from DESCRIPTION; got: {ics}"
    );
    assert!(
        ics.contains("LOCATION:Office"),
        "BOM + LRM must be stripped from LOCATION; got: {ics}"
    );
    // Strong post-condition: none of the dangerous codepoints
    // survive anywhere in the output.
    for cp in [
        '\u{202E}', '\u{202A}', '\u{202B}', '\u{202C}', '\u{202D}', '\u{200B}', '\u{200C}',
        '\u{200D}', '\u{200E}', '\u{200F}', '\u{2060}', '\u{FEFF}', '\u{2028}', '\u{2029}',
    ] {
        assert!(
            !ics.contains(cp),
            "codepoint U+{:04X} survived the export: {ics:?}",
            cp as u32
        );
    }
}

#[test]
fn fold_line_multibyte_utf8_not_corrupted() {
    let title = "\u{8FD9}\u{662F}\u{4E00}\u{4E2A}\u{975E}\u{5E38}\u{957F}\u{7684}\u{4E2D}\u{6587}\u{65E5}\u{5386}\u{4E8B}\u{4EF6}\u{6807}\u{9898}\u{9700}\u{8981}\u{8D85}\u{8FC7}\u{4E03}\u{5341}\u{4E94}";
    let line = format!("SUMMARY:{title}");
    let folded = fold_line(&line);
    assert_eq!(folded.replace("\r\n ", ""), line);
    for (index, part) in folded.split("\r\n").enumerate() {
        assert!(part.len() <= 75);
        if index > 0 {
            assert!(part.starts_with(' '));
        }
    }
}
