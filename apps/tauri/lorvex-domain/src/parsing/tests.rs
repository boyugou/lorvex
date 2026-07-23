use super::*;

#[test]
fn parse_json_string_preference_accepts_canonical_json_string() {
    assert_eq!(
        parse_json_string_preference(Some(r#""America/Los_Angeles""#)),
        Some("America/Los_Angeles".to_string())
    );
}

#[test]
fn parse_json_string_preference_rejects_blank_json_string() {
    assert_eq!(parse_json_string_preference(Some(r#""   ""#)), None);
}

#[test]
fn parse_json_string_preference_rejects_non_json_raw_string() {
    assert_eq!(
        parse_json_string_preference(Some("America/Los_Angeles")),
        None
    );
}

#[test]
fn parse_json_string_preference_rejects_non_string_json() {
    assert_eq!(parse_json_string_preference(Some("true")), None);
}

#[test]
fn parse_json_string_preference_rejects_nested_json_string_layer() {
    assert_eq!(
        parse_json_string_preference(Some(r#""\"America/Los_Angeles\"""#)),
        None
    );
}

#[test]
fn parse_json_bool_preference_accepts_json_boolean() {
    assert_eq!(parse_json_bool_preference(Some("true")), Some(true));
    assert_eq!(parse_json_bool_preference(Some("false")), Some(false));
}

#[test]
fn parse_json_bool_preference_rejects_json_string() {
    assert_eq!(parse_json_bool_preference(Some(r#""true""#)), None);
}

#[test]
fn parse_json_bool_preference_rejects_non_boolean_json() {
    assert_eq!(parse_json_bool_preference(Some("1")), None);
}

#[test]
fn parse_positive_i64_preference_accepts_json_number() {
    assert_eq!(
        parse_positive_i64_preference("30", "retention_days").expect("parse number"),
        30
    );
}

#[test]
fn parse_positive_i64_preference_rejects_invalid_payloads() {
    // ValidationError flows through Display so substring assertions
    // still work; the typed carrier just gives consumers (`?` through
    // From<ValidationError>) the option to route by variant later.
    let non_numeric = parse_positive_i64_preference(r#""nope""#, "retention_days")
        .expect_err("JSON string should fail")
        .to_string();
    assert!(non_numeric.contains("retention_days"));

    let non_scalar = parse_positive_i64_preference("{}", "retention_days")
        .expect_err("non-scalar should fail")
        .to_string();
    assert!(non_scalar.contains("JSON integer"));
}

#[test]
fn parse_positive_i64_preference_rejects_non_positive_values() {
    let zero = parse_positive_i64_preference("0", "retention_days")
        .expect_err("zero should fail")
        .to_string();
    assert!(zero.contains("positive integer"));

    let negative = parse_positive_i64_preference("-5", "retention_days")
        .expect_err("negative should fail")
        .to_string();
    assert!(negative.contains("positive integer"));
}

#[test]
fn escape_like_no_specials() {
    assert_eq!(escape_like("hello"), "hello");
}

#[test]
fn escape_like_with_specials() {
    assert_eq!(escape_like("100%"), "100\\%");
    assert_eq!(escape_like("a_b"), "a\\_b");
    assert_eq!(escape_like("c\\d"), "c\\\\d");
}

#[test]
fn platform_default_sync_backend_kind_matches_target_family() {
    assert_eq!(
        SyncBackendKind::platform_default().as_str(),
        SYNC_BACKEND_FILESYSTEM_BRIDGE
    );
}

#[test]
fn parse_sync_backend_preference_tracks_valid_unset_and_malformed_states() {
    assert_eq!(
        parse_sync_backend_preference(None),
        SyncBackendPreference::Unset
    );
    assert_eq!(
        parse_sync_backend_preference(Some(r#""filesystem_bridge""#)),
        SyncBackendPreference::Valid(SyncBackendKind::FilesystemBridge)
    );
    assert_eq!(
        parse_sync_backend_preference(Some(r#""remote_provider""#)),
        SyncBackendPreference::Malformed(MalformedPreferenceReason::UnknownBackendKind)
    );
    assert_eq!(
        parse_sync_backend_preference(Some("filesystem_bridge")),
        SyncBackendPreference::Malformed(MalformedPreferenceReason::InvalidJson)
    );
    assert_eq!(
        parse_sync_backend_preference(Some(r#""definitely_invalid""#)),
        SyncBackendPreference::Malformed(MalformedPreferenceReason::UnknownBackendKind)
    );
}

// -- parse_hhmm_to_minutes round-trip safety --------------------
//
// previously the parser accepted leading sign,
// whitespace, and full-width digits — `parse_hhmm_to_minutes("+9:00")`
// returned `Some(540)` and `format_minutes_hhmm(540)` returned
// `"09:00"`, breaking round-trip. The new byte-level digit
// check rejects every non-canonical 5-byte input.

#[test]
fn parse_hhmm_accepts_canonical_input() {
    assert_eq!(parse_hhmm_to_minutes("00:00"), Some(0));
    assert_eq!(parse_hhmm_to_minutes("09:30"), Some(570));
    assert_eq!(parse_hhmm_to_minutes("23:59"), Some(1439));
}

#[test]
fn parse_hhmm_rejects_leading_sign() {
    assert_eq!(parse_hhmm_to_minutes("+9:00"), None);
    assert_eq!(parse_hhmm_to_minutes("-1:30"), None);
}

#[test]
fn parse_hhmm_rejects_whitespace() {
    assert_eq!(parse_hhmm_to_minutes(" 9:00"), None);
    assert_eq!(parse_hhmm_to_minutes("9 :00"), None);
}

#[test]
fn parse_hhmm_rejects_non_ascii_digits() {
    // Full-width digits would parse as i64 but are 3 bytes each.
    assert_eq!(parse_hhmm_to_minutes("１２:３０"), None);
}

#[test]
fn parse_hhmm_rejects_wrong_separator() {
    assert_eq!(parse_hhmm_to_minutes("12-30"), None);
    assert_eq!(parse_hhmm_to_minutes("1230 "), None);
}

#[test]
fn parse_hhmm_rejects_out_of_range_components() {
    assert_eq!(parse_hhmm_to_minutes("24:00"), None);
    assert_eq!(parse_hhmm_to_minutes("23:60"), None);
}

#[test]
fn parse_hhmm_round_trips_for_every_minute_of_day() {
    for minute in 0..1440 {
        let formatted = format_minutes_hhmm(minute).expect("format every minute");
        let parsed = parse_hhmm_to_minutes(&formatted).unwrap_or_else(|| {
            panic!("round-trip failed at minute={minute} formatted={formatted}")
        });
        assert_eq!(parsed, minute);
    }
}

#[test]
fn parse_optional_rfc3339_state_reports_reason() {
    assert_eq!(
        parse_optional_rfc3339_state(Some("")),
        (None, true, Some("empty_timestamp"))
    );
    assert_eq!(
        parse_optional_rfc3339_state(Some("not-a-date")),
        (None, true, Some("invalid_rfc3339"))
    );
}

#[test]
fn parse_optional_i64_state_reports_reason() {
    assert_eq!(
        parse_optional_i64_state(Some("")),
        (0, true, Some("empty_i64"))
    );
    assert_eq!(
        parse_optional_i64_state(Some("nan")),
        (0, true, Some("invalid_i64"))
    );
}

#[test]
fn parse_optional_bool_state_reports_reason_and_trims() {
    assert_eq!(parse_optional_bool_state(None), (false, false, None));
    assert_eq!(
        parse_optional_bool_state(Some("")),
        (false, true, Some("empty_bool"))
    );
    assert_eq!(
        parse_optional_bool_state(Some("   ")),
        (false, true, Some("empty_bool"))
    );
    assert_eq!(parse_optional_bool_state(Some("true")), (true, false, None));
    assert_eq!(
        parse_optional_bool_state(Some(" true ")),
        (true, false, None)
    );
    assert_eq!(
        parse_optional_bool_state(Some("false")),
        (false, false, None)
    );
    assert_eq!(
        parse_optional_bool_state(Some("yes")),
        (false, true, Some("invalid_bool"))
    );
}

#[test]
fn decode_hlc_cursor_projection_tracks_validation_reasons() {
    assert_eq!(
        decode_hlc_cursor_projection(r#"{"updated_at":"","device_id":"dev","event_id":"evt"}"#),
        Err("empty_updated_at")
    );
    assert_eq!(
        decode_hlc_cursor_projection(
            r#"{"updated_at":"2026-01-01T00:00:00Z","device_id":"dev","event_id":"evt"}"#
        ),
        Err("invalid_updated_at_hlc")
    );
}
