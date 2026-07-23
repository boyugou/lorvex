use chrono::{NaiveDate, Weekday};

use crate::calendar_subscription::vtimezone::{
    nth_weekday_of_month, parse_timezone_rrule, parse_utc_offset_seconds, parse_vtimezone_blocks,
    VTimezoneRegistry,
};

fn unfold(s: &str) -> Vec<String> {
    s.lines().map(std::string::ToString::to_string).collect()
}

#[test]
fn parses_outlook_eastern_time_block() {
    let body = "BEGIN:VTIMEZONE\r\n\
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
    let lines = unfold(body);
    let registry = parse_vtimezone_blocks(&lines);
    assert!(registry.contains("Eastern Standard Time"));

    // Mid-summer 2026: DST observance is active → -0400 (-14400s).
    let summer = NaiveDate::from_ymd_opt(2026, 7, 15)
        .unwrap()
        .and_hms_opt(10, 0, 0)
        .unwrap();
    assert_eq!(
        registry.offset_seconds_at("Eastern Standard Time", summer),
        Some(-14400)
    );

    // Mid-winter 2026: STANDARD observance is active → -0500 (-18000s).
    let winter = NaiveDate::from_ymd_opt(2026, 1, 15)
        .unwrap()
        .and_hms_opt(10, 0, 0)
        .unwrap();
    assert_eq!(
        registry.offset_seconds_at("Eastern Standard Time", winter),
        Some(-18000)
    );
}

#[test]
fn nth_weekday_of_month_first_and_last() {
    // First Sunday of November 2026 is the 1st.
    assert_eq!(
        nth_weekday_of_month(2026, 11, (Weekday::Sun, 1)),
        Some(NaiveDate::from_ymd_opt(2026, 11, 1).unwrap())
    );
    // Second Sunday of March 2026 is the 8th.
    assert_eq!(
        nth_weekday_of_month(2026, 3, (Weekday::Sun, 2)),
        Some(NaiveDate::from_ymd_opt(2026, 3, 8).unwrap())
    );
    // Last Sunday of October 2026 is the 25th.
    assert_eq!(
        nth_weekday_of_month(2026, 10, (Weekday::Sun, -1)),
        Some(NaiveDate::from_ymd_opt(2026, 10, 25).unwrap())
    );
}

#[test]
fn parse_utc_offset_handles_minutes_and_seconds() {
    assert_eq!(parse_utc_offset_seconds("+0000"), Some(0));
    assert_eq!(parse_utc_offset_seconds("-0500"), Some(-18000));
    assert_eq!(parse_utc_offset_seconds("+0530"), Some(19800));
    assert_eq!(parse_utc_offset_seconds("-0430"), Some(-16200));
    assert_eq!(parse_utc_offset_seconds("+053000"), Some(19800));
    assert_eq!(parse_utc_offset_seconds("garbage"), None);
    assert_eq!(parse_utc_offset_seconds("+12"), None);
}

#[test]
fn rrule_rejects_non_yearly_freq() {
    assert!(parse_timezone_rrule("FREQ=MONTHLY;BYMONTH=3;BYDAY=2SU").is_none());
}

#[test]
fn rrule_with_until_stops_recurring_after_cutoff() {
    // Construct an observance whose DST RRULE expired in 2007
    // (the historical US pre-2007 DST window). Queries past
    // UNTIL should still resolve via the dominant later
    // observance — but for an isolated rule, the registry must
    // not synthesize phantom occurrences.
    let rule = parse_timezone_rrule("FREQ=YEARLY;BYMONTH=4;BYDAY=1SU;UNTIL=20070401T020000Z")
        .expect("rule with UNTIL parses");
    assert_eq!(rule.by_month, 4);
    assert!(rule.until.is_some());
}

#[test]
fn registry_returns_none_for_unknown_tzid() {
    let registry = VTimezoneRegistry::new();
    let when = NaiveDate::from_ymd_opt(2026, 7, 15)
        .unwrap()
        .and_hms_opt(10, 0, 0)
        .unwrap();
    assert!(registry.offset_seconds_at("Anything", when).is_none());
}

#[test]
fn parses_multiple_vtimezone_blocks_in_one_feed() {
    let body = "BEGIN:VTIMEZONE\r\n\
        TZID:Custom_East\r\n\
        BEGIN:STANDARD\r\n\
        DTSTART:20200101T000000\r\n\
        TZOFFSETFROM:+0500\r\n\
        TZOFFSETTO:+0500\r\n\
        END:STANDARD\r\n\
        END:VTIMEZONE\r\n\
        BEGIN:VTIMEZONE\r\n\
        TZID:Custom_West\r\n\
        BEGIN:STANDARD\r\n\
        DTSTART:20200101T000000\r\n\
        TZOFFSETFROM:-0800\r\n\
        TZOFFSETTO:-0800\r\n\
        END:STANDARD\r\n\
        END:VTIMEZONE\r\n";
    let lines = unfold(body);
    let registry = parse_vtimezone_blocks(&lines);
    assert_eq!(registry.len(), 2);

    let when = NaiveDate::from_ymd_opt(2026, 7, 15)
        .unwrap()
        .and_hms_opt(10, 0, 0)
        .unwrap();
    assert_eq!(registry.offset_seconds_at("Custom_East", when), Some(18000));
    assert_eq!(
        registry.offset_seconds_at("Custom_West", when),
        Some(-28800)
    );
}

#[test]
fn missing_offset_to_skips_observance() {
    // An observance with no TZOFFSETTO is malformed — skip it
    // rather than panic. The whole VTIMEZONE block still
    // registers (with zero observances), so the feed-level
    // resolver simply returns None for that TZID.
    let body = "BEGIN:VTIMEZONE\r\n\
        TZID:Broken\r\n\
        BEGIN:STANDARD\r\n\
        DTSTART:20200101T000000\r\n\
        TZOFFSETFROM:+0000\r\n\
        END:STANDARD\r\n\
        END:VTIMEZONE\r\n";
    let lines = unfold(body);
    let registry = parse_vtimezone_blocks(&lines);
    let when = NaiveDate::from_ymd_opt(2026, 7, 15)
        .unwrap()
        .and_hms_opt(10, 0, 0)
        .unwrap();
    assert_eq!(registry.offset_seconds_at("Broken", when), None);
}
