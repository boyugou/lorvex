use super::*;
use chrono::{Local, TimeZone, Utc};

#[test]
fn parse_timezone_name_accepts_valid_iana_timezone() {
    assert_eq!(
        parse_timezone_name("America/Los_Angeles")
            .expect("parse valid timezone")
            .to_string(),
        "America/Los_Angeles"
    );
}

#[test]
fn normalize_timezone_name_rejects_blank_or_invalid_values() {
    assert_eq!(normalize_timezone_name(Some("   ")), None);
    assert_eq!(normalize_timezone_name(Some("Not/AZone")), None);
    assert_eq!(
        normalize_timezone_name(Some("  America/Los_Angeles  ")),
        Some("America/Los_Angeles".to_string())
    );
}

#[test]
fn parse_json_timezone_preference_accepts_canonical_json_timezone_string() {
    assert_eq!(
        parse_json_timezone_preference(Some(r#""America/Los_Angeles""#)),
        Some("America/Los_Angeles".to_string())
    );
}

#[test]
fn parse_json_timezone_preference_rejects_non_json_or_invalid_timezone() {
    assert_eq!(
        parse_json_timezone_preference(Some("America/Los_Angeles")),
        None
    );
    assert_eq!(parse_json_timezone_preference(Some(r#""Not/AZone""#)), None);
}

#[test]
fn parse_required_timezone_preference_accepts_canonical_timezone_string() {
    assert_eq!(
        parse_required_timezone_preference(r#""America/Los_Angeles""#, "timezone")
            .expect("parse timezone preference"),
        "America/Los_Angeles".to_string()
    );
}

#[test]
fn parse_required_timezone_preference_rejects_non_json_or_invalid_timezone() {
    // ValidationError flows through Display so substring assertions
    // still work post-typing.
    let malformed = parse_required_timezone_preference("America/Los_Angeles", "timezone")
        .expect_err("raw timezone should fail")
        .to_string();
    assert!(malformed.contains("canonical JSON timezone string"));

    let invalid = parse_required_timezone_preference(r#""Not/AZone""#, "timezone")
        .expect_err("invalid timezone should fail")
        .to_string();
    assert!(invalid.contains("unknown timezone"));
}

/// In release builds the corrupt-preference path silently falls back
/// to system-local (see #2925-M10 contract on `today_ymd_for_timezone_name`).
#[test]
#[cfg(not(debug_assertions))]
fn today_ymd_for_timezone_name_falls_back_to_local_for_invalid_timezone_in_release() {
    let now = Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");

    assert_eq!(
        today_ymd_for_timezone_name(now, Some("Not/AZone")),
        now.with_timezone(&Local).format("%Y-%m-%d").to_string()
    );
}

/// In dev builds the same input panics so a corrupt timezone preference
/// is surfaced at the failure site rather than rounding silently.
#[test]
#[cfg(debug_assertions)]
#[should_panic(expected = "invalid IANA timezone 'Not/AZone'")]
fn today_ymd_for_timezone_name_panics_on_invalid_timezone_in_dev() {
    let now = Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");
    let _ = today_ymd_for_timezone_name(now, Some("Not/AZone"));
}

/// `None` is the legitimate "no preference" path and never panics.
#[test]
fn today_ymd_for_timezone_name_uses_local_when_preference_is_none() {
    let now = Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");
    assert_eq!(
        today_ymd_for_timezone_name(now, None),
        now.with_timezone(&Local).format("%Y-%m-%d").to_string()
    );
}

#[test]
#[cfg(debug_assertions)]
#[should_panic(expected = "invalid IANA timezone 'Not/AZone'")]
fn date_plus_days_ymd_for_timezone_name_panics_on_invalid_timezone_in_dev() {
    let now = Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");
    let _ = date_plus_days_ymd_for_timezone_name(now, Some("Not/AZone"), 1);
}

#[test]
fn resolve_anchored_timezone_name_prefers_active_timezone() {
    assert_eq!(
        resolve_anchored_timezone_name(
            Some("America/Los_Angeles".to_string()),
            Err("lookup should not be needed".to_string()),
        )
        .expect("prefer active timezone"),
        "America/Los_Angeles"
    );
}

#[test]
fn resolve_anchored_timezone_name_uses_system_timezone_when_active_missing() {
    assert_eq!(
        resolve_anchored_timezone_name(None, Ok("America/New_York".to_string()))
            .expect("resolve system timezone"),
        "America/New_York"
    );
}

#[test]
fn resolve_anchored_timezone_name_rejects_lookup_failure_without_active_timezone() {
    let error = resolve_anchored_timezone_name(None, Err("timezone lookup failed".to_string()))
        .expect_err("lookup failure should fail");
    assert!(error.contains("resolvable system IANA timezone"));
}

#[test]
fn resolve_anchored_timezone_name_rejects_invalid_system_timezone() {
    let error = resolve_anchored_timezone_name(None, Ok("Mars/Phobos".to_string()))
        .expect_err("invalid timezone should fail");
    assert!(error.contains("valid IANA timezone"));
}

// enforce the canonical millisecond sync-timestamp
// format so lex comparisons against SQLite-produced timestamps
// stay correct.

#[test]
fn sync_timestamp_now_has_millisecond_precision() {
    let s = sync_timestamp_now();
    // `YYYY-MM-DDTHH:MM:SS.mmmZ` — exactly 24 characters.
    assert_eq!(s.len(), 24, "unexpected timestamp width: {s:?}");
    assert!(s.ends_with('Z'));
    let dot = s.find('.').expect("dot separator required");
    let frac = &s[dot + 1..s.len() - 1];
    assert_eq!(frac.len(), 3, "fraction must be 3 digits, got {frac:?}");
}

#[test]
fn sync_timestamp_now_is_lex_comparable_across_1000_samples() {
    let mut last: Option<String> = None;
    for _ in 0..1_000 {
        let s = sync_timestamp_now();
        assert_eq!(s.len(), 24);
        if let Some(prev) = &last {
            assert!(
                prev.as_str() <= s.as_str(),
                "timestamps must be monotonic lex: {prev} > {s}"
            );
        }
        last = Some(s);
    }
}

#[test]
fn normalize_sync_timestamp_accepts_microsecond_input() {
    // An older peer emitting 6-digit fraction must normalize to 3.
    let input = "2026-03-20T15:30:00.123456Z";
    let out = normalize_sync_timestamp(input).expect("parse micros");
    assert_eq!(out, "2026-03-20T15:30:00.123Z");
}

#[test]
fn normalize_sync_timestamp_is_idempotent_on_millisecond_input() {
    let input = "2026-03-20T15:30:00.123Z";
    let out = normalize_sync_timestamp(input).expect("parse millis");
    assert_eq!(out, input);
}

#[test]
fn normalize_sync_timestamp_pads_second_precision_input() {
    // A peer emitting `SecondsFormat::Secs` produces no fraction.
    let input = "2026-03-20T15:30:00Z";
    let out = normalize_sync_timestamp(input).expect("parse secs");
    assert_eq!(out, "2026-03-20T15:30:00.000Z");
}

#[test]
fn normalize_sync_timestamp_rejects_malformed_input() {
    assert!(normalize_sync_timestamp("not-a-timestamp").is_none());
    assert!(normalize_sync_timestamp("").is_none());
}

/// previously the function silently converted
/// non-UTC offsets into UTC, breaking callers that compare raw
/// stored strings against post-normalized ones. The Lorvex
/// schema only stores UTC timestamps in `Z` form, so the
/// strict check matches the invariant the doc comment already
/// advertises.
#[test]
fn normalize_sync_timestamp_rejects_non_utc_offsets() {
    assert!(normalize_sync_timestamp("2026-03-20T15:30:00.123+05:30").is_none());
    assert!(normalize_sync_timestamp("2026-03-20T15:30:00.123-08:00").is_none());
    assert!(normalize_sync_timestamp("2026-03-20T15:30:00.123+00:01").is_none());
}

/// `+00:00` IS UTC — explicit zero-offset must still be accepted
/// since it round-trips to the same UTC instant as `Z`.
#[test]
fn normalize_sync_timestamp_accepts_explicit_zero_offset() {
    let out =
        normalize_sync_timestamp("2026-03-20T15:30:00.123+00:00").expect("zero offset is UTC");
    assert_eq!(out, "2026-03-20T15:30:00.123Z");
}

#[test]
fn canonicalize_rfc3339_instant_converts_non_utc_offsets() {
    let out = canonicalize_rfc3339_instant("2026-12-01T09:00:00-05:00")
        .expect("offset instant should parse");
    assert_eq!(out, "2026-12-01T14:00:00.000Z");
}

#[test]
fn canonicalize_rfc3339_instant_rejects_malformed_input() {
    assert!(canonicalize_rfc3339_instant("not-a-timestamp").is_none());
    assert!(canonicalize_rfc3339_instant("").is_none());
}

// -----------------------------------------------------------------
// SyncTimestamp newtype
// -----------------------------------------------------------------

#[test]
fn sync_timestamp_display_round_trips_through_canonical_form() {
    let dt = Utc.with_ymd_and_hms(2026, 4, 19, 8, 30, 0).unwrap();
    let ts = SyncTimestamp::from(dt);
    assert_eq!(ts.to_string(), "2026-04-19T08:30:00.000Z");
    assert_eq!(ts.as_string(), "2026-04-19T08:30:00.000Z");
    // FromStr parses the canonical form back to the same instant.
    let parsed: SyncTimestamp = ts.to_string().parse().unwrap();
    assert_eq!(parsed, ts);
}

#[test]
fn sync_timestamp_serde_round_trips_through_canonical_form() {
    let dt = Utc.with_ymd_and_hms(2026, 4, 19, 8, 30, 0).unwrap();
    let ts = SyncTimestamp::from(dt);
    let json = serde_json::to_string(&ts).unwrap();
    assert_eq!(json, "\"2026-04-19T08:30:00.000Z\"");
    let back: SyncTimestamp = serde_json::from_str(&json).unwrap();
    assert_eq!(back, ts);
}

#[test]
fn sync_timestamp_ord_matches_datetime_ord() {
    let earlier = SyncTimestamp::from(Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap());
    let later = SyncTimestamp::from(Utc.with_ymd_and_hms(2026, 6, 15, 12, 0, 0).unwrap());
    assert!(earlier < later);
    assert_eq!(earlier.cmp(&later), std::cmp::Ordering::Less);
}

#[test]
fn sync_timestamp_parse_accepts_microsecond_precision_input() {
    // Older peers may emit microsecond strings — they normalise to
    // the same UTC instant on parse, even though the rendered form
    // truncates to millisecond precision.
    let ts = SyncTimestamp::parse("2026-03-20T15:30:00.123456Z").expect("parse");
    assert_eq!(ts.as_string(), "2026-03-20T15:30:00.123Z");
}

#[test]
fn sync_timestamp_parse_rejects_non_utc_offsets() {
    assert_eq!(SyncTimestamp::parse("2026-03-20T15:30:00.123+05:30"), None);
    assert_eq!(SyncTimestamp::parse("not-a-timestamp"), None);
}

#[test]
fn sync_timestamp_parse_accepts_explicit_zero_offset() {
    let ts = SyncTimestamp::parse("2026-03-20T15:30:00.123+00:00").expect("zero offset is UTC");
    assert_eq!(ts.as_string(), "2026-03-20T15:30:00.123Z");
}

#[test]
fn sync_timestamp_now_renders_as_24_char_canonical_form() {
    let s = SyncTimestamp::now().as_string();
    assert_eq!(s.len(), 24);
    assert!(s.ends_with('Z'));
}

#[test]
fn today_ymd_for_timezone_name_uses_configured_timezone_calendar_day() {
    // 2026-03-08T01:00:00Z is 2026-03-07 17:00 in Los Angeles (PST,
    // pre-DST-spring-forward); the calendar day is 2026-03-07.
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");
    assert_eq!(
        today_ymd_for_timezone_name(now, Some("America/Los_Angeles")),
        "2026-03-07"
    );
}

#[test]
fn date_plus_days_ymd_for_timezone_name_uses_configured_timezone_calendar_day() {
    // Same instant; +1 day in LA tz is 2026-03-08 (the local day was
    // 2026-03-07).
    let now = chrono::Utc
        .with_ymd_and_hms(2026, 3, 8, 1, 0, 0)
        .single()
        .expect("construct UTC instant");
    assert_eq!(
        date_plus_days_ymd_for_timezone_name(now, Some("America/Los_Angeles"), 1),
        "2026-03-08"
    );
}

// ── Date / TimeOfDay newtypes (#3286) ────────────────────────────────

#[test]
fn date_parse_accepts_canonical_iso_form() {
    let d = Date::parse("2026-04-19").expect("parse canonical ISO date");
    assert_eq!(d.as_string(), "2026-04-19");
    assert_eq!(d.to_string(), "2026-04-19");
    assert_eq!(d.as_naive_date().to_string(), "2026-04-19");
}

#[test]
fn date_parse_rejects_non_iso_form() {
    assert!(Date::parse("19/04/2026").is_err());
    assert!(Date::parse("2026-13-01").is_err());
    assert!(Date::parse("").is_err());
}

#[test]
fn date_serde_round_trips_as_bare_string() {
    let d = Date::parse("2026-04-19").expect("parse");
    let json = serde_json::to_string(&d).expect("serialize");
    assert_eq!(json, "\"2026-04-19\"");
    let round: Date = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(round, d);
}

#[test]
fn date_from_naive_date_round_trips() {
    let nd = chrono::NaiveDate::from_ymd_opt(2026, 4, 19).expect("valid date");
    let d: Date = nd.into();
    let nd2: chrono::NaiveDate = d.into();
    assert_eq!(nd, nd2);
}

#[test]
fn time_of_day_parse_accepts_canonical_hhmm_form() {
    let t = TimeOfDay::parse("09:30").expect("parse canonical HH:MM");
    assert_eq!(t.as_string(), "09:30");
    assert_eq!(t.to_string(), "09:30");
}

#[test]
fn time_of_day_parse_rejects_invalid_inputs() {
    assert!(TimeOfDay::parse("24:00").is_err());
    assert!(TimeOfDay::parse("09:60").is_err());
    assert!(TimeOfDay::parse("9-30").is_err());
    assert!(TimeOfDay::parse("").is_err());
    assert!(TimeOfDay::parse("not-a-time").is_err());
}

#[test]
fn time_of_day_serde_round_trips_as_bare_string() {
    let t = TimeOfDay::parse("17:45").expect("parse");
    let json = serde_json::to_string(&t).expect("serialize");
    assert_eq!(json, "\"17:45\"");
    let round: TimeOfDay = serde_json::from_str(&json).expect("deserialize");
    assert_eq!(round, t);
}

#[test]
fn time_of_day_orders_by_minute_not_lex() {
    let early = TimeOfDay::parse("09:00").expect("parse");
    let later = TimeOfDay::parse("17:00").expect("parse");
    assert!(early < later);
}

#[test]
fn due_at_from_optional_pair_accepts_three_valid_shapes() {
    let unscheduled = DueAt::from_optional_pair(None, None).expect("ok");
    assert_eq!(unscheduled, DueAt::Unscheduled);

    let date = Date::parse("2026-05-04").unwrap();
    let on_day = DueAt::from_optional_pair(Some(date), None).expect("ok");
    assert_eq!(on_day, DueAt::OnDay(date));

    let time = TimeOfDay::parse("09:30").unwrap();
    let at_moment = DueAt::from_optional_pair(Some(date), Some(time)).expect("ok");
    assert_eq!(at_moment, DueAt::AtMoment { date, time });
}

#[test]
fn due_at_from_optional_pair_rejects_time_without_date() {
    let time = TimeOfDay::parse("09:30").unwrap();
    let err = DueAt::from_optional_pair(None, Some(time)).expect_err("must reject");
    assert!(format!("{err}").contains("due_time without due_date"));
}

#[test]
fn due_at_round_trips_through_optional_pair() {
    let date = Date::parse("2026-05-04").unwrap();
    let time = TimeOfDay::parse("09:30").unwrap();
    for d in [
        DueAt::Unscheduled,
        DueAt::OnDay(date),
        DueAt::AtMoment { date, time },
    ] {
        let (dt, tm) = d.into_optional_pair();
        let round = DueAt::from_optional_pair(dt, tm).unwrap();
        assert_eq!(round, d);
    }
}

#[test]
fn due_at_flat_serializes_byte_stable_with_legacy_two_key_shape() {
    // Wire format byte-stability test #1: typed `DueAtFlat` serializes
    // identically to the historic `{due_date, due_time}` legacy shape.
    let flat = DueAtFlat::from(DueAt::AtMoment {
        date: Date::parse("2026-05-04").unwrap(),
        time: TimeOfDay::parse("09:30").unwrap(),
    });
    let json = serde_json::to_string(&flat).unwrap();
    assert_eq!(json, r#"{"due_date":"2026-05-04","due_time":"09:30"}"#);

    // OnDay carries only `due_date`; the absent `due_time` key MUST
    // be omitted (skip_serializing_if) so the JSON matches the
    // pre-typed legacy shape produced by `serde_json::to_string` of
    // `(Some(Date), None)`.
    let flat_day = DueAtFlat::from(DueAt::OnDay(Date::parse("2026-05-04").unwrap()));
    assert_eq!(
        serde_json::to_string(&flat_day).unwrap(),
        r#"{"due_date":"2026-05-04"}"#
    );

    // Unscheduled emits an empty object — same as the legacy struct
    // when both fields are `None`.
    let flat_none = DueAtFlat::from(DueAt::Unscheduled);
    assert_eq!(serde_json::to_string(&flat_none).unwrap(), "{}");
}

#[test]
fn due_at_flat_deserializes_from_legacy_json_shape() {
    // Wire format byte-stability test #2: legacy JSON parses back
    // into `DueAtFlat` and converts into a typed `DueAt`.
    let json = r#"{"due_date":"2026-05-04","due_time":"09:30"}"#;
    let flat: DueAtFlat = serde_json::from_str(json).unwrap();
    let due: DueAt = flat.try_into().unwrap();
    assert_eq!(
        due,
        DueAt::AtMoment {
            date: Date::parse("2026-05-04").unwrap(),
            time: TimeOfDay::parse("09:30").unwrap(),
        }
    );

    // Empty JSON object → Unscheduled.
    let flat_empty: DueAtFlat = serde_json::from_str("{}").unwrap();
    let due_empty: DueAt = flat_empty.try_into().unwrap();
    assert_eq!(due_empty, DueAt::Unscheduled);

    // `null` for either field deserializes the same as omitting it
    // (typed `Option<Date>` / `Option<TimeOfDay>` both accept null).
    let flat_null: DueAtFlat =
        serde_json::from_str(r#"{"due_date":null,"due_time":null}"#).unwrap();
    assert_eq!(DueAt::try_from(flat_null).unwrap(), DueAt::Unscheduled);
}
