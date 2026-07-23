use super::*;

// -----------------------------------------------------------------------
// Issue #2996 (M batch): ATTACH / merge ordering / TZID round-trip
// (RDATE inclusion-list parsing was removed: the
// `provider_calendar_events` schema has no inclusion column and the
// parser-only field violated CLAUDE.md principle 12 — no
// preservation for future use.)
// -----------------------------------------------------------------------

/// EXDATE with TZID parameter must resolve the wall-clock value
/// through the IANA shim and emit the UTC date — not the local date.
/// `EXDATE;TZID=America/New_York:20260408T230000` is 2026-04-09 in UTC
/// (EDT is UTC-4, so 23:00 local → 03:00 UTC the next day).
#[test]
fn parse_exdate_with_tzid_resolves_to_utc_date() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:exdate-tzid\n\
         SUMMARY:Late evening\n\
         DTSTART;TZID=America/New_York:20260401T230000\n\
         RRULE:FREQ=WEEKLY\n\
         EXDATE;TZID=America/New_York:20260408T230000\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 1);
    let exdates: Vec<String> =
        serde_json::from_str(events[0].exdates_json.as_ref().expect("exdates JSON")).unwrap();
    // 2026-04-08 23:00 EDT (UTC-4) is 2026-04-09 03:00 UTC
    assert_eq!(
        exdates,
        vec!["2026-04-09"],
        "EXDATE with TZID must resolve to UTC date, not raw wall-clock date"
    );
}

/// EXDATE without TZID and with `Z` suffix: pure UTC, no shift.
#[test]
fn parse_exdate_with_z_suffix_keeps_utc_date() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:exdate-z\n\
         SUMMARY:UTC\n\
         DTSTART:20260401T090000Z\n\
         RRULE:FREQ=WEEKLY\n\
         EXDATE:20260408T090000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    let exdates: Vec<String> =
        serde_json::from_str(events[0].exdates_json.as_ref().expect("exdates JSON")).unwrap();
    assert_eq!(exdates, vec!["2026-04-08"]);
}

/// RECURRENCE-ID with TZID round-trips to a canonical UTC form. Two
/// feeds describing the same overridden occurrence — one with TZID
/// and one with `Z` suffix — must collapse to the same composite key.
#[test]
fn parse_recurrence_id_with_tzid_canonicalizes_to_utc() {
    let with_tzid = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:override-1\n\
         SUMMARY:Override A\n\
         DTSTART;TZID=America/New_York:20260408T090000\n\
         RECURRENCE-ID;TZID=America/New_York:20260408T090000\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(with_tzid.len(), 1);
    let normalized = with_tzid[0]
        .recurrence_id
        .as_deref()
        .expect("recurrence_id must be set");
    // 2026-04-08 09:00 EDT (UTC-4) → 2026-04-08 13:00 UTC
    assert_eq!(
        normalized, "20260408T130000Z",
        "RECURRENCE-ID with TZID must normalize to UTC wire form"
    );
}

/// Two feeds — one with TZID, one with `Z` suffix — describing the
/// same override land on the same composite key.
#[test]
fn parse_recurrence_id_tzid_and_z_form_collapse_to_same_key() {
    let tzid = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:same\n\
         SUMMARY:T\n\
         DTSTART;TZID=America/New_York:20260408T090000\n\
         RECURRENCE-ID;TZID=America/New_York:20260408T090000\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    let zform = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:same\n\
         SUMMARY:Z\n\
         DTSTART:20260408T130000Z\n\
         RECURRENCE-ID:20260408T130000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(
        tzid[0].recurrence_id, zform[0].recurrence_id,
        "TZID and Z forms of the same instant must produce identical RECURRENCE-ID"
    );
}

/// All-day RECURRENCE-ID stays in the bare YYYYMMDD wire form.
#[test]
fn parse_recurrence_id_all_day_keeps_date_form() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:override-day\n\
         SUMMARY:All Day Override\n\
         DTSTART;VALUE=DATE:20260408\n\
         RECURRENCE-ID;VALUE=DATE:20260408\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events[0].recurrence_id.as_deref(), Some("20260408"));
}
