use super::*;

// -----------------------------------------------------------------------
// Issue #2996 (MAC-H6): VTIMEZONE block parsing.
// -----------------------------------------------------------------------
//
// Before this fix, an ICS feed that shipped a `BEGIN:VTIMEZONE` block
// with a non-IANA TZID (Outlook display names, self-hosted custom
// zone IDs, retired Olson aliases) silently fell back to UTC. The
// resulting events landed up to 12h off their wall-clock intent.
// These tests pin the behaviour described in #2996: with a VTIMEZONE
// block in the feed, the parser consults the block FIRST and converts
// wall-clock values to UTC using the per-feed offsets.

/// A standard Outlook-style Eastern Time VTIMEZONE block, reused by
/// several tests below.
const OUTLOOK_EASTERN_VTIMEZONE: &str = "BEGIN:VTIMEZONE\r\n\
    TZID:Eastern Standard Time\r\n\
    BEGIN:STANDARD\r\n\
    DTSTART:16011104T020000\r\n\
    TZOFFSETFROM:-0400\r\n\
    TZOFFSETTO:-0500\r\n\
    RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU\r\n\
    END:STANDARD\r\n\
    BEGIN:DAYLIGHT\r\n\
    DTSTART:16010311T020000\r\n\
    TZOFFSETFROM:-0500\r\n\
    TZOFFSETTO:-0400\r\n\
    RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU\r\n\
    END:DAYLIGHT\r\n\
    END:VTIMEZONE\r\n";

#[test]
fn vtimezone_block_drives_utc_conversion_for_summer_event() {
    // The TZID is a Windows display name (`Eastern Standard Time`)
    // and would resolve via the legacy Windows-shim path to
    // `America/New_York`. With a VTIMEZONE block present, the
    // registry takes precedence: 10:00 wall-clock on July 15 in
    // EDT (offset -0400) becomes 14:00 UTC.
    let feed = format!(
        "BEGIN:VCALENDAR\r\n\
         VERSION:2.0\r\n\
         {OUTLOOK_EASTERN_VTIMEZONE}\
         BEGIN:VEVENT\r\n\
         UID:summer-meeting\r\n\
         SUMMARY:Summer Meeting\r\n\
         DTSTART;TZID=Eastern Standard Time:20260715T100000\r\n\
         DTEND;TZID=Eastern Standard Time:20260715T110000\r\n\
         END:VEVENT\r\n\
         END:VCALENDAR\r\n"
    );
    let events = parse_ics_events(&feed).expect("feed must parse");
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    assert_eq!(ev.source_time_kind, "utc");
    assert!(ev.source_tzid.is_none());
    assert_eq!(ev.start_date, "2026-07-15");
    assert_eq!(ev.start_time.as_deref(), Some("14:00"));
    assert_eq!(ev.end_date.as_deref(), Some("2026-07-15"));
    assert_eq!(ev.end_time.as_deref(), Some("15:00"));
}

#[test]
fn vtimezone_block_drives_utc_conversion_for_winter_event() {
    // Same VTIMEZONE block, but a January date: STANDARD is active
    // (offset -0500), so 10:00 EST → 15:00 UTC.
    let feed = format!(
        "BEGIN:VCALENDAR\r\n\
         VERSION:2.0\r\n\
         {OUTLOOK_EASTERN_VTIMEZONE}\
         BEGIN:VEVENT\r\n\
         UID:winter-meeting\r\n\
         SUMMARY:Winter Meeting\r\n\
         DTSTART;TZID=Eastern Standard Time:20260115T100000\r\n\
         DTEND;TZID=Eastern Standard Time:20260115T110000\r\n\
         END:VEVENT\r\n\
         END:VCALENDAR\r\n"
    );
    let events = parse_ics_events(&feed).expect("feed must parse");
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    assert_eq!(ev.source_time_kind, "utc");
    assert_eq!(ev.start_date, "2026-01-15");
    assert_eq!(ev.start_time.as_deref(), Some("15:00"));
    assert_eq!(ev.end_time.as_deref(), Some("16:00"));
}

#[test]
fn vtimezone_block_resolves_iana_tzid_via_registry_first() {
    // Even when the TZID *is* a valid IANA identifier, a feed that
    // ships a custom VTIMEZONE block for it should be honoured —
    // the feed author explicitly told us their offsets, and the
    // Olson DB cannot capture every legitimate edge case (e.g.,
    // historical pre-1970 transitions, or zones that have diverged
    // from upstream IANA but are still labelled with the old name).
    let body = "BEGIN:VCALENDAR\r\n\
         VERSION:2.0\r\n\
         BEGIN:VTIMEZONE\r\n\
         TZID:America/New_York\r\n\
         BEGIN:STANDARD\r\n\
         DTSTART:16011104T020000\r\n\
         TZOFFSETFROM:-0400\r\n\
         TZOFFSETTO:-0500\r\n\
         RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=1SU\r\n\
         END:STANDARD\r\n\
         BEGIN:DAYLIGHT\r\n\
         DTSTART:16010311T020000\r\n\
         TZOFFSETFROM:-0500\r\n\
         TZOFFSETTO:-0400\r\n\
         RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=2SU\r\n\
         END:DAYLIGHT\r\n\
         END:VTIMEZONE\r\n\
         BEGIN:VEVENT\r\n\
         UID:dst-edge\r\n\
         SUMMARY:DST Edge\r\n\
         DTSTART;TZID=America/New_York:20260715T100000\r\n\
         DTEND;TZID=America/New_York:20260715T110000\r\n\
         END:VEVENT\r\n\
         END:VCALENDAR\r\n"
        .to_string();
    let events = parse_ics_events(&body).expect("feed must parse");
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    // Registry takes precedence → emitted as UTC, not as a tzid
    // pointer. 10:00 EDT becomes 14:00 UTC.
    assert_eq!(ev.source_time_kind, "utc");
    assert!(ev.source_tzid.is_none());
    assert_eq!(ev.start_time.as_deref(), Some("14:00"));
}

#[test]
fn missing_vtimezone_falls_back_to_chrono_tz_iana_path() {
    // No VTIMEZONE block in this feed, but the TZID is a valid IANA
    // identifier — the Windows-shim / chrono-tz path must still
    // engage. The result is `source_time_kind="tzid"` (the
    // projection layer converts at render time using chrono-tz),
    // not `"utc"`. This locks in the "VTIMEZONE absent → no
    // behaviour change" half of the contract.
    let feed = "BEGIN:VCALENDAR\r\n\
                VERSION:2.0\r\n\
                BEGIN:VEVENT\r\n\
                UID:no-vtimezone\r\n\
                SUMMARY:No VTIMEZONE\r\n\
                DTSTART;TZID=America/New_York:20260715T100000\r\n\
                DTEND;TZID=America/New_York:20260715T110000\r\n\
                END:VEVENT\r\n\
                END:VCALENDAR\r\n";
    let events = parse_ics_events(feed).expect("feed must parse");
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    assert_eq!(ev.source_time_kind, "tzid");
    assert_eq!(ev.source_tzid.as_deref(), Some("America/New_York"));
    assert_eq!(ev.start_time.as_deref(), Some("10:00"));
}

#[test]
fn vtimezone_block_resolves_completely_invented_tzid() {
    // The TZID is neither IANA nor in the Windows-shim table, but
    // the feed ships its own VTIMEZONE block defining a fixed
    // +05:00 offset. Without #2996, this would silently fall back
    // to UTC and shift the wall-clock time by 5 hours. With the
    // registry, 09:00 in `Custom Zone X` → 04:00 UTC.
    let feed = "BEGIN:VCALENDAR\r\n\
                VERSION:2.0\r\n\
                BEGIN:VTIMEZONE\r\n\
                TZID:Custom Zone X\r\n\
                BEGIN:STANDARD\r\n\
                DTSTART:20200101T000000\r\n\
                TZOFFSETFROM:+0500\r\n\
                TZOFFSETTO:+0500\r\n\
                END:STANDARD\r\n\
                END:VTIMEZONE\r\n\
                BEGIN:VEVENT\r\n\
                UID:invented\r\n\
                SUMMARY:Invented Zone Event\r\n\
                DTSTART;TZID=Custom Zone X:20260715T090000\r\n\
                DTEND;TZID=Custom Zone X:20260715T100000\r\n\
                END:VEVENT\r\n\
                END:VCALENDAR\r\n";
    let events = parse_ics_events(feed).expect("feed must parse");
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    assert_eq!(ev.source_time_kind, "utc");
    assert!(ev.source_tzid.is_none());
    assert_eq!(ev.start_date, "2026-07-15");
    assert_eq!(ev.start_time.as_deref(), Some("04:00"));
    assert_eq!(ev.end_time.as_deref(), Some("05:00"));
}

#[test]
fn vtimezone_block_does_not_override_z_suffixed_utc_value() {
    // A `Z`-suffixed value already declares itself UTC. Even if the
    // feed has a VTIMEZONE block, we must not double-shift it.
    let feed = format!(
        "BEGIN:VCALENDAR\r\n\
         VERSION:2.0\r\n\
         {OUTLOOK_EASTERN_VTIMEZONE}\
         BEGIN:VEVENT\r\n\
         UID:already-utc\r\n\
         SUMMARY:Already UTC\r\n\
         DTSTART:20260715T140000Z\r\n\
         DTEND:20260715T150000Z\r\n\
         END:VEVENT\r\n\
         END:VCALENDAR\r\n"
    );
    let events = parse_ics_events(&feed).expect("feed must parse");
    assert_eq!(events.len(), 1);
    let ev = &events[0];
    assert_eq!(ev.source_time_kind, "utc");
    assert_eq!(ev.start_time.as_deref(), Some("14:00"));
}

#[test]
fn vtimezone_block_only_applies_to_its_own_tzid() {
    // A feed can ship VTIMEZONE blocks for some TZIDs and still
    // reference others through the IANA name. The registry must
    // only intercept TZIDs it actually defined.
    let feed = format!(
        "BEGIN:VCALENDAR\r\n\
         VERSION:2.0\r\n\
         {OUTLOOK_EASTERN_VTIMEZONE}\
         BEGIN:VEVENT\r\n\
         UID:eastern-via-vtimezone\r\n\
         SUMMARY:Eastern via VTIMEZONE\r\n\
         DTSTART;TZID=Eastern Standard Time:20260715T100000\r\n\
         END:VEVENT\r\n\
         BEGIN:VEVENT\r\n\
         UID:tokyo-via-iana\r\n\
         SUMMARY:Tokyo via IANA\r\n\
         DTSTART;TZID=Asia/Tokyo:20260715T100000\r\n\
         END:VEVENT\r\n\
         END:VCALENDAR\r\n"
    );
    let events = parse_ics_events(&feed).expect("feed must parse");
    assert_eq!(events.len(), 2);
    let eastern = events
        .iter()
        .find(|e| e.uid == "eastern-via-vtimezone")
        .unwrap();
    let tokyo = events.iter().find(|e| e.uid == "tokyo-via-iana").unwrap();
    // Eastern: VTIMEZONE registry → UTC.
    assert_eq!(eastern.source_time_kind, "utc");
    assert_eq!(eastern.start_time.as_deref(), Some("14:00"));
    // Tokyo: no VTIMEZONE block, so chrono-tz/IANA path stays
    // untouched and the value is emitted as a `tzid` pointer.
    assert_eq!(tokyo.source_time_kind, "tzid");
    assert_eq!(tokyo.source_tzid.as_deref(), Some("Asia/Tokyo"));
    assert_eq!(tokyo.start_time.as_deref(), Some("10:00"));
}
