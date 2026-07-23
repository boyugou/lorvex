use super::super::tzid::{parse_ics_datetime, resolve_tzid_to_iana};

// -----------------------------------------------------------------------
// Windows → IANA TZID normalization
// -----------------------------------------------------------------------

#[test]
fn parse_ics_datetime_maps_pacific_standard_time_to_iana() {
    // The canonical Outlook/Exchange failure: the TZID parameter is
    // a Windows display name, not an IANA identifier. Before the
    // fix, `source_tzid` was stored verbatim and chrono-tz failed to
    // resolve it at projection time, silently dropping the event.
    let parsed = parse_ics_datetime("DTSTART;TZID=Pacific Standard Time", "20260318T100000")
        .expect("Windows TZID must still produce a valid IcsDateTime");
    assert_eq!(parsed.source_time_kind, "tzid");
    assert_eq!(parsed.source_tzid.as_deref(), Some("America/Los_Angeles"));
    assert_eq!(parsed.date.as_deref(), Some("2026-03-18"));
    assert_eq!(parsed.time.as_deref(), Some("10:00"));
    assert!(!parsed.all_day);
}

#[test]
fn parse_ics_datetime_keeps_iana_names_unchanged() {
    // IANA identifiers are already resolvable by chrono-tz and must
    // pass through verbatim — otherwise we'd churn stored values on
    // every sync and potentially round-trip to a non-canonical alias.
    let parsed = parse_ics_datetime("DTSTART;TZID=America/New_York", "20260318T100000")
        .expect("IANA TZID must parse");
    assert_eq!(parsed.source_time_kind, "tzid");
    assert_eq!(parsed.source_tzid.as_deref(), Some("America/New_York"));
}

#[test]
fn parse_ics_datetime_falls_back_to_utc_for_unknown_tzid() {
    // An unknown TZID (neither IANA nor in the Windows table) is
    // logged as a warning and normalized to UTC so the event still
    // appears in the calendar — just at a possibly-shifted wall
    // clock time. Prior behaviour dropped the event entirely.
    let parsed = parse_ics_datetime("DTSTART;TZID=Completely Invented Zone", "20260318T100000")
        .expect("Unknown TZID must not error, just fall back to UTC");
    assert_eq!(parsed.source_time_kind, "utc");
    assert!(parsed.source_tzid.is_none());
}

#[test]
fn windows_to_iana_covers_common_zones() {
    // Spot-check that the canonical CLDR mapping is wired correctly
    // for the zones that cover the majority of Outlook users worldwide.
    let cases: &[(&str, &str)] = &[
        ("Pacific Standard Time", "America/Los_Angeles"),
        ("Mountain Standard Time", "America/Denver"),
        ("Central Standard Time", "America/Chicago"),
        ("Eastern Standard Time", "America/New_York"),
        ("GMT Standard Time", "Europe/London"),
        ("W. Europe Standard Time", "Europe/Berlin"),
        ("Central European Standard Time", "Europe/Warsaw"),
        ("China Standard Time", "Asia/Shanghai"),
        ("Tokyo Standard Time", "Asia/Tokyo"),
        ("India Standard Time", "Asia/Kolkata"),
        ("AUS Eastern Standard Time", "Australia/Sydney"),
        ("New Zealand Standard Time", "Pacific/Auckland"),
        ("UTC", "UTC"),
    ];
    for (windows, iana) in cases {
        let resolved = resolve_tzid_to_iana(windows)
            .unwrap_or_else(|| panic!("Windows zone `{windows}` must map to an IANA identifier"));
        assert_eq!(
            resolved, *iana,
            "`{windows}` expected to map to `{iana}`, got `{resolved}`"
        );
    }
}

#[test]
fn resolve_tzid_to_iana_returns_none_for_unknown_name() {
    // Guard against future accidental "resolve everything to UTC"
    // regressions: truly unknown names must surface as `None` so the
    // caller knows to log a warning.
    assert!(resolve_tzid_to_iana("Not A Real Zone Name").is_none());
}
