use super::*;

#[test]
fn rrule_to_json_weekly_with_byday() {
    let json = rrule_to_json("FREQ=WEEKLY;BYDAY=MO,WE,FR").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed["FREQ"], "WEEKLY");
    // BYDAY must be a JSON array for the recurrence engine
    assert_eq!(parsed["BYDAY"], serde_json::json!(["MO", "WE", "FR"]));
}

#[test]
fn rrule_to_json_daily_with_interval_and_count() {
    let json = rrule_to_json("FREQ=DAILY;INTERVAL=2;COUNT=10").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed["FREQ"], "DAILY");
    assert_eq!(parsed["INTERVAL"], 2);
    assert_eq!(parsed["COUNT"], 10);
}

#[test]
fn rrule_to_json_with_until() {
    let json = rrule_to_json("FREQ=MONTHLY;UNTIL=20261231T000000Z").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed["FREQ"], "MONTHLY");
    // UNTIL must be YYYY-MM-DD for the recurrence engine
    assert_eq!(parsed["UNTIL"], "2026-12-31");
}

#[test]
fn rrule_to_json_with_until_date_only() {
    let json = rrule_to_json("FREQ=WEEKLY;UNTIL=20261015").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed["UNTIL"], "2026-10-15");
}

#[test]
fn rrule_to_json_rejects_malformed_until() {
    assert!(rrule_to_json("FREQ=DAILY;UNTIL=garbage").is_none());
    assert!(rrule_to_json("FREQ=DAILY;UNTIL=20261231garbage").is_none());
}

#[test]
fn rrule_to_json_bymonthday_is_array() {
    // BYMONTHDAY is canonically an array (RFC 5545 allows a comma list,
    // e.g. `BYMONTHDAY=1,15`); a single day parses to a one-element array.
    let json = rrule_to_json("FREQ=MONTHLY;BYMONTHDAY=15").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed["BYMONTHDAY"], serde_json::json!([15]));
}

#[test]
fn rrule_to_json_bymonth_and_bysetpos_are_numeric_arrays() {
    let json = rrule_to_json("FREQ=MONTHLY;BYMONTH=2,8;BYDAY=MO;BYSETPOS=1,-1").unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(parsed["BYMONTH"], serde_json::json!([2, 8]));
    assert_eq!(parsed["BYSETPOS"], serde_json::json!([-1, 1]));
}

#[test]
fn rrule_to_json_rejects_malformed_numeric_recurrence_lists() {
    assert!(rrule_to_json("FREQ=YEARLY;BYMONTH=2,13;BYMONTHDAY=1").is_none());
    assert!(rrule_to_json("FREQ=MONTHLY;BYDAY=MO;BYSETPOS=0,1").is_none());
    assert!(rrule_to_json("FREQ=YEARLY;BYMONTH=2,x;BYMONTHDAY=1").is_none());
}

#[test]
fn rrule_to_json_rejects_time_expansion_fields() {
    assert!(rrule_to_json("FREQ=DAILY;BYHOUR=9,17").is_none());
    assert!(rrule_to_json("FREQ=DAILY;BYMINUTE=0,30").is_none());
}

#[test]
fn rrule_to_json_missing_freq_returns_none() {
    assert!(rrule_to_json("INTERVAL=2;BYDAY=MO").is_none());
}

#[test]
fn rrule_to_json_empty_returns_none() {
    assert!(rrule_to_json("").is_none());
}

#[test]
fn parse_exdate_single_date() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:exdate-1\n\
         SUMMARY:Weekly\n\
         DTSTART:20260401T090000Z\n\
         RRULE:FREQ=WEEKLY\n\
         EXDATE:20260408T090000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    let exdates: Vec<String> =
        serde_json::from_str(events[0].exdates_json.as_ref().unwrap()).unwrap();
    assert_eq!(exdates, vec!["2026-04-08"]);
}

#[test]
fn parse_exdate_multiple_lines_and_comma_separated() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:exdate-2\n\
         SUMMARY:Daily\n\
         DTSTART:20260401T090000Z\n\
         RRULE:FREQ=DAILY\n\
         EXDATE:20260405T090000Z,20260406T090000Z\n\
         EXDATE:20260410\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    let exdates: Vec<String> =
        serde_json::from_str(events[0].exdates_json.as_ref().unwrap()).unwrap();
    assert_eq!(exdates, vec!["2026-04-05", "2026-04-06", "2026-04-10"]);
}

#[test]
fn parse_exdate_date_only_format() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:exdate-3\n\
         SUMMARY:All Day\n\
         DTSTART;VALUE=DATE:20260401\n\
         RRULE:FREQ=WEEKLY\n\
         EXDATE;VALUE=DATE:20260408\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    let exdates: Vec<String> =
        serde_json::from_str(events[0].exdates_json.as_ref().unwrap()).unwrap();
    assert_eq!(exdates, vec!["2026-04-08"]);
}

#[test]
fn parse_no_exdate_returns_none() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:no-exdate\n\
         SUMMARY:Simple\n\
         DTSTART:20260401T090000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    assert!(events[0].exdates_json.is_none());
}

#[test]
fn parse_attendee_with_cn_and_partstat() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:attendee-1\n\
         SUMMARY:Meeting\n\
         DTSTART:20260401T090000Z\n\
         ATTENDEE;CN=Alice Smith;PARTSTAT=ACCEPTED:mailto:alice@example.com\n\
         ATTENDEE;CN=Bob Jones;PARTSTAT=TENTATIVE:mailto:bob@example.com\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    let attendees: Vec<serde_json::Value> =
        serde_json::from_str(events[0].attendees_json.as_ref().unwrap()).unwrap();
    assert_eq!(attendees.len(), 2);
    assert_eq!(attendees[0]["email"], "alice@example.com");
    assert_eq!(attendees[0]["name"], "Alice Smith");
    assert_eq!(attendees[0]["status"], "accepted");
    assert_eq!(attendees[1]["email"], "bob@example.com");
    assert_eq!(attendees[1]["status"], "tentative");
}

#[test]
fn parse_attendee_without_cn() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:attendee-2\n\
         SUMMARY:Quick\n\
         DTSTART:20260401T090000Z\n\
         ATTENDEE:mailto:noreply@example.com\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    let attendees: Vec<serde_json::Value> =
        serde_json::from_str(events[0].attendees_json.as_ref().unwrap()).unwrap();
    assert_eq!(attendees.len(), 1);
    assert_eq!(attendees[0]["email"], "noreply@example.com");
    assert!(attendees[0].get("name").is_none());
}

#[test]
fn parse_no_attendees_returns_none() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:no-att\n\
         SUMMARY:Solo\n\
         DTSTART:20260401T090000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    assert!(events[0].attendees_json.is_none());
}

#[test]
fn parse_url_property() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:url-1\n\
         SUMMARY:Conference\n\
         DTSTART:20260401T090000Z\n\
         URL:https://meet.example.com/room-42\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    assert_eq!(
        events[0].url.as_deref(),
        Some("https://meet.example.com/room-42")
    );
}

#[test]
fn parse_no_url_returns_none() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:no-url\n\
         SUMMARY:Local\n\
         DTSTART:20260401T090000Z\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    assert!(events[0].url.is_none());
}

#[test]
fn parse_all_new_fields_together() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:full-1\n\
         SUMMARY:All Fields\n\
         DTSTART:20260401T090000Z\n\
         DTEND:20260401T100000Z\n\
         RRULE:FREQ=WEEKLY;BYDAY=MO\n\
         EXDATE:20260408T090000Z\n\
         EXDATE:20260415T090000Z\n\
         ATTENDEE;CN=Alice;PARTSTAT=ACCEPTED:mailto:alice@example.com\n\
         URL:https://zoom.us/j/123\n\
         ORGANIZER;CN=Bob:mailto:bob@example.com\n\
         LOCATION:Room 101\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .unwrap();
    assert_eq!(events.len(), 1);
    let e = &events[0];
    assert_eq!(e.uid, "full-1");
    assert_eq!(e.rrule.as_deref(), Some("FREQ=WEEKLY;BYDAY=MO"));
    let exdates: Vec<String> = serde_json::from_str(e.exdates_json.as_ref().unwrap()).unwrap();
    assert_eq!(exdates, vec!["2026-04-08", "2026-04-15"]);
    let attendees: Vec<serde_json::Value> =
        serde_json::from_str(e.attendees_json.as_ref().unwrap()).unwrap();
    assert_eq!(attendees.len(), 1);
    assert_eq!(attendees[0]["email"], "alice@example.com");
    assert_eq!(e.url.as_deref(), Some("https://zoom.us/j/123"));
    assert_eq!(e.organizer.as_deref(), Some("bob@example.com"));
    assert_eq!(e.location.as_deref(), Some("Room 101"));
}

#[test]
fn extract_ics_param_basic() {
    assert_eq!(
        extract_ics_param("ATTENDEE;CN=Alice;PARTSTAT=ACCEPTED", "CN"),
        Some("Alice".to_string())
    );
    assert_eq!(
        extract_ics_param("ATTENDEE;CN=Alice;PARTSTAT=ACCEPTED", "PARTSTAT"),
        Some("ACCEPTED".to_string())
    );
    assert_eq!(extract_ics_param("ATTENDEE;CN=Alice", "PARTSTAT"), None);
}

#[test]
fn extract_ics_param_quoted_value() {
    assert_eq!(
        extract_ics_param("ATTENDEE;CN=\"John Doe\";PARTSTAT=TENTATIVE", "CN"),
        Some("John Doe".to_string())
    );
}

// -----------------------------------------------------------------------
// unescape_ics control/ANSI/bidi sanitization (issue #2425)
// -----------------------------------------------------------------------

#[test]
fn unescape_ics_strips_ansi_escape_sequences() {
    // ESC (U+001B) is a C0 control and must be stripped; the surrounding
    // `[31m` / `[0m` are plain ASCII and pass through unchanged, which
    // is exactly what we want — the terminal no longer sees a CSI, but
    // the user sees the bracketed text as plain characters.
    let input = "A\u{001B}[31mRED\u{001B}[0m";
    assert_eq!(unescape_ics(input), "A[31mRED[0m");
}

#[test]
fn unescape_ics_strips_null_byte() {
    let input = "before\u{0000}after";
    assert_eq!(unescape_ics(input), "beforeafter");
}

#[test]
fn unescape_ics_strips_bidi_override() {
    // Right-to-left override (U+202E) is the classic filename-spoofing
    // character; calendar summaries have no use for directional controls.
    let input = "invoice\u{202E}gpj.exe";
    assert_eq!(unescape_ics(input), "invoicegpj.exe");
}

#[test]
fn unescape_ics_strips_zero_width_space() {
    let input = "foo\u{200B}bar\u{FEFF}baz";
    assert_eq!(unescape_ics(input), "foobarbaz");
}

#[test]
fn unescape_ics_preserves_newline_and_tab() {
    // `\n` -> LF via escape sequence, literal tab passes through.
    let input = "line1\\nline2\tindented";
    assert_eq!(unescape_ics(input), "line1\nline2\tindented");
}

#[test]
fn unescape_ics_preserves_emoji_and_cjk() {
    // 🗓️ = U+1F5D3 U+FE0F; 会议 = CJK unified ideographs.
    let input = "🗓️ 会议: 10:00";
    assert_eq!(unescape_ics(input), "🗓️ 会议: 10:00");
}

#[test]
fn unescape_ics_handles_mixed_escaped_and_control_chars() {
    // `\,` unescape must still work after the sanitizer is added, and
    // a CR embedded in the raw value must be dropped (CRLF canonicalized
    // to LF via the LF from `\n`).
    let input = "A\\, B\\nC\r\u{0007}D";
    assert_eq!(unescape_ics(input), "A, B\nCD");
}

#[test]
fn unescape_ics_strips_c1_control_range() {
    // C1 control (U+0080–U+009F) — sometimes emitted by broken encoders
    // that mishandle Latin-1 vs. UTF-8.
    let input = "ok\u{0085}still\u{009F}ok";
    assert_eq!(unescape_ics(input), "okstillok");
}

#[test]
fn unescape_ics_strips_bidi_isolates() {
    // U+2066–U+2069 isolate range, distinct from the override block.
    let input = "a\u{2066}b\u{2069}c";
    assert_eq!(unescape_ics(input), "abc");
}

/// ATTACH with `VALUE=BINARY;ENCODING=BASE64` carries an inline base64
/// payload that can run into megabytes. The parser must recognize and
/// drop it without surfacing the blob as `url`.
#[test]
fn parse_attach_inline_binary_is_dropped() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:attach-bin\n\
         SUMMARY:Inline\n\
         DTSTART:20260401T090000Z\n\
         ATTACH;VALUE=BINARY;ENCODING=BASE64:QUFBQUFBQUFBQUFBQUFBQUFB\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 1);
    assert!(
        events[0].url.is_none(),
        "binary ATTACH must not surface as URL; got {:?}",
        events[0].url
    );
}

/// URI-form ATTACH falls back as the URL when no explicit URL line
/// is present. This matters for Zoom/Teams invites that emit the
/// meeting link as `ATTACH;FMTTYPE=text/html:https://…`.
#[test]
fn parse_attach_uri_falls_back_to_url() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:attach-uri\n\
         SUMMARY:Invite\n\
         DTSTART:20260401T090000Z\n\
         ATTACH;FMTTYPE=text/html:https://meet.example.com/abc\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(
        events[0].url.as_deref(),
        Some("https://meet.example.com/abc"),
        "URI ATTACH must fall back to URL when no URL line is present"
    );
}

/// Explicit URL wins over ATTACH — feeds that emit both shouldn't see
/// the URL silently overwritten by an attachment URL.
#[test]
fn parse_explicit_url_wins_over_attach() {
    let events = parse_ics_events(
        "BEGIN:VCALENDAR\n\
         BEGIN:VEVENT\n\
         UID:url-vs-attach\n\
         SUMMARY:Both\n\
         DTSTART:20260401T090000Z\n\
         URL:https://primary.example.com/main\n\
         ATTACH;FMTTYPE=text/html:https://secondary.example.com/extra\n\
         END:VEVENT\n\
         END:VCALENDAR\n",
    )
    .expect("must parse");
    assert_eq!(events.len(), 1);
    assert_eq!(
        events[0].url.as_deref(),
        Some("https://primary.example.com/main"),
        "explicit URL must win over ATTACH"
    );
}
