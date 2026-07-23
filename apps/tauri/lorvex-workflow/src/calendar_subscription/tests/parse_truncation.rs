use super::*;

// -----------------------------------------------------------------------
// Truncated-response detection
// -----------------------------------------------------------------------

#[test]
fn fetch_ics_rejects_body_without_end_vcalendar() {
    // A feed that starts with BEGIN:VCALENDAR and terminates
    // cleanly at an END:VEVENT but never emits END:VCALENDAR
    // must be rejected — the HTTP connection closed after the
    // last event but before the calendar wrapper closed. The
    // size-cap reader would otherwise hand this to the parser,
    // which would happily emit the events and the diff-delete
    // pass would clobber whatever *wasn't* in the truncated
    // prefix.
    let body = "BEGIN:VCALENDAR\r\n\
                VERSION:2.0\r\n\
                BEGIN:VEVENT\r\n\
                UID:first\r\n\
                SUMMARY:Good\r\n\
                DTSTART:20260401T090000Z\r\n\
                DTEND:20260401T100000Z\r\n\
                END:VEVENT\r\n";
    let reason = detect_ics_truncation(body)
        .expect_err("missing END:VCALENDAR must be classified as truncation");
    assert_eq!(reason, IcsTruncationReason::MissingCalendarTerminator);
}

#[test]
fn parse_ics_rejects_mismatched_begin_end_vevent_count() {
    // Truncation mid-VEVENT: the parser used to silently drop
    // the unclosed block (its `END:VEVENT` gate never fires),
    // so every event following the truncation point vanished
    // without the subscription noticing. Now the parser refuses
    // to process a body whose VEVENT bracket counts disagree.
    let truncated = "BEGIN:VCALENDAR\n\
                     BEGIN:VEVENT\nUID:a\nSUMMARY:First\nDTSTART:20260401T090000Z\nEND:VEVENT\n\
                     BEGIN:VEVENT\nUID:b\nSUMMARY:Second cut off\nDTSTART:20260402";
    let err = parse_ics_events(truncated).expect_err("mismatched VEVENT counts must be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("truncated"),
        "diagnostic should name the truncation condition, got: {msg}"
    );
    assert!(
        msg.contains("BEGIN:VEVENT") && msg.contains("END:VEVENT"),
        "diagnostic should cite the unbalanced counts, got: {msg}"
    );
}

#[test]
fn fetch_ics_accepts_well_formed_feed() {
    // A complete, balanced feed — both truncation signals pass.
    // Validates that the new checks don't regress the happy path
    // for a multi-event feed with an RRULE and EXDATE, which are
    // the property shapes most likely to interact with the
    // line-count heuristic.
    let body = "BEGIN:VCALENDAR\r\n\
                VERSION:2.0\r\n\
                BEGIN:VEVENT\r\n\
                UID:a\r\n\
                SUMMARY:Alpha\r\n\
                DTSTART:20260401T090000Z\r\n\
                DTEND:20260401T100000Z\r\n\
                RRULE:FREQ=WEEKLY\r\n\
                END:VEVENT\r\n\
                BEGIN:VEVENT\r\n\
                UID:b\r\n\
                SUMMARY:Beta\r\n\
                DTSTART:20260402T110000Z\r\n\
                DTEND:20260402T120000Z\r\n\
                EXDATE:20260409T110000Z\r\n\
                END:VEVENT\r\n\
                END:VCALENDAR\r\n";
    detect_ics_truncation(body).expect("well-formed feed must pass truncation checks");
    let events = parse_ics_events(body).expect("well-formed feed must parse");
    assert_eq!(events.len(), 2);
}
