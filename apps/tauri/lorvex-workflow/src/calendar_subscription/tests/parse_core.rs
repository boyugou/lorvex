use super::*;

#[test]
fn parse_ics_events_skips_malformed_vevent_datetime() {
    // Malformed VEVENTs are now skipped (not fatal) so one bad event
    // doesn't prevent importing hundreds of valid ones.
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:test-1\nSUMMARY:Broken\nDTSTART:not-a-date\nEND:VEVENT\nEND:VCALENDAR\n",
    )
    .expect("malformed VEVENTs should be skipped, not fatal");
    assert!(
        events.is_empty(),
        "malformed event should be skipped, not included"
    );
}

#[test]
fn parse_ics_events_keeps_valid_events_when_one_is_malformed() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\nUID:good\nSUMMARY:Valid\nDTSTART:20260401T090000Z\nDTEND:20260401T100000Z\nEND:VEVENT\n\
         BEGIN:VEVENT\nUID:bad\nSUMMARY:Broken\nDTSTART:not-a-date\nEND:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("should succeed with partial results");
    assert_eq!(events.len(), 1, "only the valid event should be returned");
    assert_eq!(events[0].uid, "good");
}

#[test]
fn parse_ics_events_with_diagnostics_reports_malformed_vevent() {
    let report = parse_ics_events_with_diagnostics(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\nUID:good\nSUMMARY:Valid\nDTSTART:20260401T090000Z\nDTEND:20260401T100000Z\nEND:VEVENT\n\
         BEGIN:VEVENT\nUID:bad\nSUMMARY:Broken\nDTSTART:not-a-date\nEND:VEVENT\n\
         END:VCALENDAR\n",
        &noop_unknown_tzid_sink,
    )
    .expect("should succeed with partial results");

    assert_eq!(report.events.len(), 1);
    assert_eq!(report.warnings.len(), 1);
    assert_eq!(report.warnings[0].source, "sync.ics.parser_warning");
    assert!(
        report.warnings[0].message.contains("malformed VEVENT"),
        "warning should classify the skipped VEVENT"
    );
}

#[test]
fn parse_ics_events_with_diagnostics_reports_vevent_cap_once() {
    let mut feed = String::from("BEGIN:VCALENDAR\n");
    for i in 0..5_001 {
        feed.push_str(&format!(
            "BEGIN:VEVENT\nUID:event-{i}\nSUMMARY:Event {i}\nDTSTART:20260401T090000Z\nDTEND:20260401T100000Z\nEND:VEVENT\n"
        ));
    }
    feed.push_str("END:VCALENDAR\n");

    let report = parse_ics_events_with_diagnostics(&feed, &noop_unknown_tzid_sink)
        .expect("oversize feed should parse");

    assert_eq!(report.events.len(), 5_000);
    assert_eq!(
        report
            .warnings
            .iter()
            .filter(|warning| warning.message.contains("VEVENT cap reached"))
            .count(),
        1,
        "VEVENT cap warning should be emitted once"
    );
}

// over-length VEVENT fields must be skipped like
// other per-event malformations. A hostile ICS feed cannot smuggle
// in a 1 MB SUMMARY or 100k ATTENDEE lines.

#[test]
fn parse_ics_events_skips_vevent_with_oversized_summary() {
    let giant = "a".repeat(1_001);
    let feed = format!(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\nUID:bad\nSUMMARY:{giant}\nDTSTART:20260401T090000Z\nDTEND:20260401T100000Z\nEND:VEVENT\n\
         END:VCALENDAR\n"
    );
    let events = parse_ics_events(&feed).expect("oversize summary should be skipped, not fatal");
    assert!(
        events.is_empty(),
        "VEVENT with oversized SUMMARY must be skipped"
    );
}

#[test]
fn parse_ics_events_skips_vevent_with_too_many_attendees() {
    let mut feed = String::from("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:bad\nSUMMARY:ok\nDTSTART:20260401T090000Z\nDTEND:20260401T100000Z\n");
    for i in 0..=MAX_ATTENDEES_PER_EVENT {
        feed.push_str(&format!("ATTENDEE:mailto:user{i}@example.com\n"));
    }
    feed.push_str("END:VEVENT\nEND:VCALENDAR\n");
    let events =
        parse_ics_events(&feed).expect("oversize attendee list should be skipped, not fatal");
    assert!(
        events.is_empty(),
        "VEVENT with {}+ ATTENDEEs must be skipped",
        MAX_ATTENDEES_PER_EVENT + 1
    );
}

#[test]
fn parse_ics_events_keeps_valid_event_when_hostile_event_has_oversized_summary() {
    let giant = "a".repeat(1_001);
    let feed = format!(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\nUID:good\nSUMMARY:Valid\nDTSTART:20260401T090000Z\nDTEND:20260401T100000Z\nEND:VEVENT\n\
         BEGIN:VEVENT\nUID:bad\nSUMMARY:{giant}\nDTSTART:20260401T090000Z\nDTEND:20260401T100000Z\nEND:VEVENT\n\
         END:VCALENDAR\n"
    );
    let events = parse_ics_events(&feed).expect("one valid + one oversize should succeed partial");
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].uid, "good");
}

#[test]
fn parse_ics_handles_mixed_line_endings() {
    // RFC 5545 §3.1 mandates CRLF, but real-world feeds emit LF or
    // mixed endings (hand-edited `.ics` files, pipelines that
    // round-trip through Unix tooling). `unfold_lines` delegates to
    // `str::lines()` which strips both `\n` and the preceding `\r` if
    // present, so a single feed mixing `\r\n` and `\n` line
    // terminators must produce the same parse result as either pure
    // form.
    let mixed = "BEGIN:VCALENDAR\r\n\
                 VERSION:2.0\n\
                 BEGIN:VEVENT\r\n\
                 UID:mixed\n\
                 SUMMARY:Mixed Endings\r\n\
                 DTSTART:20260401T090000Z\n\
                 DTEND:20260401T100000Z\r\n\
                 END:VEVENT\n\
                 END:VCALENDAR\r\n";
    let events = parse_ics_events(mixed).expect("mixed line endings must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].uid, "mixed");
    assert_eq!(events[0].summary, "Mixed Endings");
}

// -----------------------------------------------------------------------
// ICS edge-case parser coverage
// -----------------------------------------------------------------------

/// a feed shipped with `METHOD:CANCEL` is an
/// iTIP cancellation payload — the entire VEVENT set is being
/// retracted. The parser must return zero events so the
/// diff-delete pass in `sync_subscription_content_inner` clears the
/// affected scope from the cache rather than upserting the
/// cancelled rows as fresh events.
#[test]
fn parse_ics_events_drops_all_when_method_is_cancel() {
    let body = "BEGIN:VCALENDAR\r\n\
        VERSION:2.0\r\n\
        METHOD:CANCEL\r\n\
        BEGIN:VEVENT\r\n\
        UID:cancelled-1@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART:20260315T100000Z\r\n\
        SUMMARY:Cancelled meeting\r\n\
        END:VEVENT\r\n\
        END:VCALENDAR\r\n";
    let events = parse_ics_events(body).expect("METHOD:CANCEL feed must parse");
    assert!(events.is_empty(), "METHOD:CANCEL must drop every event");
}

/// a single VEVENT with `STATUS:CANCELLED`
/// (e.g. a detached override removing one occurrence of a series)
/// must drop just that VEVENT — not poison the rest of the feed.
#[test]
fn parse_ics_events_skips_individual_cancelled_event() {
    let body = "BEGIN:VCALENDAR\r\n\
        VERSION:2.0\r\n\
        METHOD:PUBLISH\r\n\
        BEGIN:VEVENT\r\n\
        UID:keeper@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART:20260315T100000Z\r\n\
        SUMMARY:Active meeting\r\n\
        END:VEVENT\r\n\
        BEGIN:VEVENT\r\n\
        UID:dropped@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART:20260316T100000Z\r\n\
        STATUS:CANCELLED\r\n\
        SUMMARY:Cancelled occurrence\r\n\
        END:VEVENT\r\n\
        END:VCALENDAR\r\n";
    let events = parse_ics_events(body).expect("mixed feed must parse");
    assert_eq!(events.len(), 1, "STATUS:CANCELLED row must drop");
    assert_eq!(events[0].uid, "keeper@example.com");
}

/// Google Calendar exports a calendar-level
/// `X-WR-TIMEZONE:` and omits per-event `DTSTART;TZID=`. Without
/// applying it as a fallback every event lands as `floating`, which
/// the projection layer renders in the viewer's local zone.
#[test]
fn parse_ics_events_applies_x_wr_timezone_fallback_to_floating_events() {
    let body = "BEGIN:VCALENDAR\r\n\
        VERSION:2.0\r\n\
        X-WR-TIMEZONE:America/Los_Angeles\r\n\
        BEGIN:VEVENT\r\n\
        UID:google-1@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART:20260318T093000\r\n\
        DTEND:20260318T103000\r\n\
        SUMMARY:Standup\r\n\
        END:VEVENT\r\n\
        END:VCALENDAR\r\n";
    let events = parse_ics_events(body).expect("Google-style feed must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(
        events[0].source_time_kind, "tzid",
        "floating event without TZID must inherit X-WR-TIMEZONE",
    );
    assert_eq!(
        events[0].source_tzid.as_deref(),
        Some("America/Los_Angeles"),
        "X-WR-TIMEZONE value must propagate as the source_tzid",
    );
}

/// an explicit `DTSTART;TZID=` must take
/// precedence over `X-WR-TIMEZONE`. The calendar-level value is
/// only a fallback for events that have no zone of their own.
#[test]
fn parse_ics_events_x_wr_timezone_does_not_override_explicit_tzid() {
    let body = "BEGIN:VCALENDAR\r\n\
        VERSION:2.0\r\n\
        X-WR-TIMEZONE:America/Los_Angeles\r\n\
        BEGIN:VEVENT\r\n\
        UID:explicit-tz@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART;TZID=America/New_York:20260318T093000\r\n\
        DTEND;TZID=America/New_York:20260318T103000\r\n\
        SUMMARY:Standup\r\n\
        END:VEVENT\r\n\
        END:VCALENDAR\r\n";
    let events = parse_ics_events(body).expect("must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].source_time_kind, "tzid");
    assert_eq!(
        events[0].source_tzid.as_deref(),
        Some("America/New_York"),
        "explicit DTSTART;TZID must win over X-WR-TIMEZONE",
    );
}

/// `X-WR-TIMEZONE` must NOT be applied to a
/// `Z`-suffixed DTSTART (already UTC) or to an all-day DATE value.
#[test]
fn parse_ics_events_x_wr_timezone_does_not_override_utc_or_all_day() {
    let body = "BEGIN:VCALENDAR\r\n\
        VERSION:2.0\r\n\
        X-WR-TIMEZONE:America/Los_Angeles\r\n\
        BEGIN:VEVENT\r\n\
        UID:utc@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART:20260318T093000Z\r\n\
        DTEND:20260318T103000Z\r\n\
        SUMMARY:UTC event\r\n\
        END:VEVENT\r\n\
        BEGIN:VEVENT\r\n\
        UID:all-day@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART;VALUE=DATE:20260318\r\n\
        DTEND;VALUE=DATE:20260319\r\n\
        SUMMARY:All-day event\r\n\
        END:VEVENT\r\n\
        END:VCALENDAR\r\n";
    let events = parse_ics_events(body).expect("must parse");
    assert_eq!(events.len(), 2);

    let utc_event = events.iter().find(|e| e.uid == "utc@example.com").unwrap();
    assert_eq!(utc_event.source_time_kind, "utc");
    assert!(utc_event.source_tzid.is_none());

    let all_day = events
        .iter()
        .find(|e| e.uid == "all-day@example.com")
        .unwrap();
    assert!(all_day.all_day);
    assert!(
        all_day.source_tzid.is_none(),
        "X-WR-TIMEZONE must not coerce all-day events into a zone",
    );
}

/// RFC 5545 §3.3.3 declares URI scheme names
/// case-insensitive, but the previous prefix-match accepted only
/// lowercase `mailto:`. Exchange and Lotus emit `MAILTO:`; the
/// stored organizer ended up keeping the scheme prefix.
#[test]
fn parse_ics_events_strips_uppercase_mailto_scheme_from_organizer() {
    let body = "BEGIN:VCALENDAR\r\n\
        VERSION:2.0\r\n\
        BEGIN:VEVENT\r\n\
        UID:mailto-case@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART:20260318T093000Z\r\n\
        ORGANIZER;CN=Pat:MAILTO:pat@example.com\r\n\
        SUMMARY:Mixed-case mailto\r\n\
        END:VEVENT\r\n\
        END:VCALENDAR\r\n";
    let events = parse_ics_events(body).expect("must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(
        events[0].organizer.as_deref(),
        Some("pat@example.com"),
        "uppercase MAILTO: must be stripped from ORGANIZER",
    );
}

/// ATTENDEE values share the same scheme
/// case-insensitivity as ORGANIZER.
#[test]
fn parse_ics_events_strips_uppercase_mailto_scheme_from_attendees() {
    let body = "BEGIN:VCALENDAR\r\n\
        VERSION:2.0\r\n\
        BEGIN:VEVENT\r\n\
        UID:attendee-case@example.com\r\n\
        DTSTAMP:20260301T120000Z\r\n\
        DTSTART:20260318T093000Z\r\n\
        SUMMARY:Mixed-case mailto\r\n\
        ATTENDEE;CN=Sam;PARTSTAT=ACCEPTED:MAILTO:sam@example.com\r\n\
        END:VEVENT\r\n\
        END:VCALENDAR\r\n";
    let events = parse_ics_events(body).expect("must parse");
    assert_eq!(events.len(), 1);
    let attendees_json = events[0]
        .attendees_json
        .as_deref()
        .expect("attendees JSON must be present");
    assert!(
        attendees_json.contains("\"email\":\"sam@example.com\""),
        "uppercase MAILTO: must be stripped from ATTENDEE; got {attendees_json}"
    );
}

/// Multi-VEVENT same-UID merge ordering: SEQUENCE wins regardless of
/// document order. Pre-fix, "last occurrence in the feed wins" was a
/// coincidence of the upsert loop — a feed that emitted SEQUENCE=2
/// after SEQUENCE=5 silently downgraded the persisted record.
#[test]
fn parse_duplicate_uid_higher_sequence_wins() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:dup-seq\n\
         SUMMARY:Old\n\
         DTSTART:20260401T090000Z\n\
         SEQUENCE:5\n\
         DTSTAMP:20260301T100000Z\n\
         END:VEVENT\n\
         BEGIN:VEVENT\n\
         UID:dup-seq\n\
         SUMMARY:Stale\n\
         DTSTART:20260401T090000Z\n\
         SEQUENCE:2\n\
         DTSTAMP:20260315T100000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 1, "duplicates must collapse to one event");
    assert_eq!(
        events[0].summary, "Old",
        "higher SEQUENCE wins over later document position"
    );
}

/// SEQUENCE tie → later DTSTAMP wins.
#[test]
fn parse_duplicate_uid_dtstamp_breaks_sequence_tie() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:dup-stamp\n\
         SUMMARY:Earlier\n\
         DTSTART:20260401T090000Z\n\
         SEQUENCE:1\n\
         DTSTAMP:20260301T100000Z\n\
         END:VEVENT\n\
         BEGIN:VEVENT\n\
         UID:dup-stamp\n\
         SUMMARY:Later\n\
         DTSTART:20260401T090000Z\n\
         SEQUENCE:1\n\
         DTSTAMP:20260315T100000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].summary, "Later");
}

/// SEQUENCE tie + DTSTAMP tie → later document position wins.
#[test]
fn parse_duplicate_uid_position_breaks_dtstamp_tie() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:dup-pos\n\
         SUMMARY:First\n\
         DTSTART:20260401T090000Z\n\
         SEQUENCE:0\n\
         DTSTAMP:20260301T100000Z\n\
         END:VEVENT\n\
         BEGIN:VEVENT\n\
         UID:dup-pos\n\
         SUMMARY:Second\n\
         DTSTART:20260401T090000Z\n\
         SEQUENCE:0\n\
         DTSTAMP:20260301T100000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(events[0].summary, "Second");
}

/// Master + override (different RECURRENCE-ID values) must NOT collapse.
#[test]
fn parse_master_and_override_with_same_uid_both_kept() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:series-1\n\
         SUMMARY:Master\n\
         DTSTART:20260401T090000Z\n\
         RRULE:FREQ=WEEKLY\n\
         END:VEVENT\n\
         BEGIN:VEVENT\n\
         UID:series-1\n\
         SUMMARY:Moved Override\n\
         DTSTART:20260408T100000Z\n\
         RECURRENCE-ID:20260408T090000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 2, "master + override must both survive merge");
}

/// EXDATE per-event cap: a hostile feed emitting tens of thousands of
/// EXDATE entries must be capped at parse time, not at storage. Use a
/// fresh epoch-base date so each generated EXDATE is unique (otherwise
/// the dedup pass collapses the duplicates and we can't observe the
/// raw entry-cap behaviour).
#[test]
fn parse_exdate_per_event_cap_enforced() {
    let mut body = String::from(
        "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:cap\nSUMMARY:Cap\nDTSTART:20200101T090000Z\nRRULE:FREQ=DAILY\n",
    );
    // Emit 10_000 EXDATE entries with a unique date each, walking
    // forward day-by-day from 2020-01-01. 10_000 days fits inside the
    // chrono `NaiveDate` range without overflow.
    let base = chrono::NaiveDate::from_ymd_opt(2020, 1, 1).unwrap();
    for i in 0..10_000i64 {
        let d = base + chrono::Duration::days(i);
        body.push_str(&format!("EXDATE:{}T090000Z\n", d.format("%Y%m%d")));
    }
    body.push_str("END:VEVENT\nEND:VCALENDAR\n");
    let events = parse_ics_events(&body).expect("must parse");
    assert_eq!(events.len(), 1);
    let exdates: Vec<String> =
        serde_json::from_str(events[0].exdates_json.as_ref().expect("exdates JSON")).unwrap();
    assert!(
        exdates.len() <= 5_000,
        "EXDATE list must be capped at MAX_EXDATES_PER_EVENT, got {}",
        exdates.len()
    );
    assert!(
        exdates.len() >= 4_000,
        "EXDATE cap should be near MAX_EXDATES_PER_EVENT, got {}",
        exdates.len()
    );
}
