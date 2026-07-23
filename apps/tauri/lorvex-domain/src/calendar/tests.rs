use super::{CalendarEventTiming, CalendarEventTimingFlat, CanonicalCalendarEventType};
use crate::time::{Date, TimeOfDay};

#[test]
fn canonical_calendar_event_type_round_trips() {
    for raw in ["event", "birthday", "anniversary", "memorial"] {
        let parsed = raw.parse::<CanonicalCalendarEventType>().unwrap();
        assert_eq!(parsed.as_str(), raw);
        assert_eq!(
            serde_json::to_string(&parsed).unwrap(),
            format!("\"{raw}\"")
        );
    }
}

#[test]
fn canonical_calendar_event_type_rejects_unknown_values() {
    let err = "meeting"
        .parse::<CanonicalCalendarEventType>()
        .expect_err("unknown calendar event type should fail");
    assert!(err.contains("event_type must be one of"));
}

#[test]
fn canonical_calendar_event_type_serde_deserialize_rejects_unknown() {
    // with the `Unknown` catch-all removed, a peer
    // emitting a non-canonical tag must fail deserialize — no
    // silent coercion to a sentinel that the persistence layer
    // would later refuse to write anyway.
    let result = serde_json::from_str::<CanonicalCalendarEventType>("\"holiday\"");
    assert!(
        result.is_err(),
        "non-canonical event_type must fail serde deserialize"
    );
}

#[test]
fn canonical_calendar_event_type_validate_matches_from_str() {
    // every layer that guards event_type now routes
    // through `validate`; pin its message shape so refactors
    // can't drift its error string out of sync with FromStr.
    let validate_err = CanonicalCalendarEventType::validate("meeting").expect_err("must reject");
    let from_str_err = "meeting"
        .parse::<CanonicalCalendarEventType>()
        .expect_err("must reject");
    assert_eq!(validate_err, from_str_err);
}

// ---------------------------------------------------------------------------
// CalendarEventTiming construction + validation
// ---------------------------------------------------------------------------

fn d(s: &str) -> Date {
    Date::parse(s).unwrap()
}

fn t(s: &str) -> TimeOfDay {
    TimeOfDay::parse(s).unwrap()
}

#[test]
fn from_flat_all_day_single_day_constructs_all_day_variant() {
    let timing =
        CalendarEventTiming::from_flat_fields(d("2026-05-04"), None, None, None, true).unwrap();
    assert_eq!(
        timing,
        CalendarEventTiming::AllDay {
            start: d("2026-05-04"),
            end: None
        }
    );
    assert!(timing.all_day());
    assert_eq!(timing.start_date(), d("2026-05-04"));
    assert_eq!(timing.start_time(), None);
    assert_eq!(timing.end_date(), None);
    assert_eq!(timing.end_time(), None);
}

#[test]
fn from_flat_all_day_multi_day_constructs_all_day_with_end() {
    let timing = CalendarEventTiming::from_flat_fields(
        d("2026-05-04"),
        None,
        Some(d("2026-05-06")),
        None,
        true,
    )
    .unwrap();
    assert_eq!(
        timing,
        CalendarEventTiming::AllDay {
            start: d("2026-05-04"),
            end: Some(d("2026-05-06"))
        }
    );
    assert_eq!(timing.end_date(), Some(d("2026-05-06")));
}

#[test]
fn from_flat_all_day_rejects_start_time() {
    let err =
        CalendarEventTiming::from_flat_fields(d("2026-05-04"), Some(t("09:00")), None, None, true)
            .expect_err("all-day with start_time must reject");
    assert!(err.to_string().contains("all_day"));
}

#[test]
fn from_flat_all_day_rejects_end_time() {
    let err =
        CalendarEventTiming::from_flat_fields(d("2026-05-04"), None, None, Some(t("17:00")), true)
            .expect_err("all-day with end_time must reject");
    assert!(err.to_string().contains("all_day"));
}

#[test]
fn from_flat_all_day_rejects_end_date_before_start() {
    let err = CalendarEventTiming::from_flat_fields(
        d("2026-05-06"),
        None,
        Some(d("2026-05-04")),
        None,
        true,
    )
    .expect_err("end_date < start_date must reject");
    assert!(err.to_string().contains("end_date"));
}

#[test]
fn from_flat_timed_single_day_constructs_with_optional_end() {
    let point =
        CalendarEventTiming::from_flat_fields(d("2026-05-04"), Some(t("09:00")), None, None, false)
            .unwrap();
    assert_eq!(
        point,
        CalendarEventTiming::TimedSingleDay {
            date: d("2026-05-04"),
            start: t("09:00"),
            end: None,
        }
    );

    let span = CalendarEventTiming::from_flat_fields(
        d("2026-05-04"),
        Some(t("09:00")),
        None,
        Some(t("10:30")),
        false,
    )
    .unwrap();
    assert_eq!(
        span,
        CalendarEventTiming::TimedSingleDay {
            date: d("2026-05-04"),
            start: t("09:00"),
            end: Some(t("10:30")),
        }
    );
}

#[test]
fn from_flat_timed_single_day_accepts_end_date_equal_to_start() {
    // Some carriers explicitly pass `end_date = Some(start_date)`
    // for same-day timed events; the typed shape collapses that to
    // the `TimedSingleDay` variant where `end_date` is implicit.
    let timing = CalendarEventTiming::from_flat_fields(
        d("2026-05-04"),
        Some(t("09:00")),
        Some(d("2026-05-04")),
        Some(t("10:00")),
        false,
    )
    .unwrap();
    assert_eq!(
        timing,
        CalendarEventTiming::TimedSingleDay {
            date: d("2026-05-04"),
            start: t("09:00"),
            end: Some(t("10:00")),
        }
    );
    assert_eq!(timing.end_date(), None);
}

#[test]
fn from_flat_timed_rejects_missing_start_time() {
    let err = CalendarEventTiming::from_flat_fields(d("2026-05-04"), None, None, None, false)
        .expect_err("timed event must require start_time");
    assert!(err.to_string().contains("start_time"));
}

#[test]
fn from_flat_timed_single_day_rejects_end_before_start() {
    let err = CalendarEventTiming::from_flat_fields(
        d("2026-05-04"),
        Some(t("10:00")),
        None,
        Some(t("09:00")),
        false,
    )
    .expect_err("end_time < start_time must reject");
    assert!(err.to_string().contains("end_time"));
}

#[test]
fn from_flat_timed_multi_day_constructs_full_form() {
    let timing = CalendarEventTiming::from_flat_fields(
        d("2026-05-04"),
        Some(t("18:00")),
        Some(d("2026-05-06")),
        Some(t("09:00")),
        false,
    )
    .unwrap();
    assert_eq!(
        timing,
        CalendarEventTiming::TimedMultiDay {
            start_date: d("2026-05-04"),
            start_time: t("18:00"),
            end_date: d("2026-05-06"),
            end_time: t("09:00"),
        }
    );
}

#[test]
fn from_flat_timed_multi_day_rejects_missing_end_time() {
    let err = CalendarEventTiming::from_flat_fields(
        d("2026-05-04"),
        Some(t("09:00")),
        Some(d("2026-05-06")),
        None,
        false,
    )
    .expect_err("multi-day timed event must require end_time");
    assert!(err.to_string().contains("end_time"));
}

#[test]
fn from_flat_timed_multi_day_rejects_end_date_before_start() {
    let err = CalendarEventTiming::from_flat_fields(
        d("2026-05-06"),
        Some(t("09:00")),
        Some(d("2026-05-04")),
        Some(t("10:00")),
        false,
    )
    .expect_err("end_date < start_date must reject");
    assert!(err.to_string().contains("end_date"));
}

#[test]
fn accessors_round_trip_through_as_flat_fields() {
    let cases = vec![
        CalendarEventTiming::AllDay {
            start: d("2026-05-04"),
            end: None,
        },
        CalendarEventTiming::AllDay {
            start: d("2026-05-04"),
            end: Some(d("2026-05-06")),
        },
        CalendarEventTiming::TimedSingleDay {
            date: d("2026-05-04"),
            start: t("09:00"),
            end: None,
        },
        CalendarEventTiming::TimedSingleDay {
            date: d("2026-05-04"),
            start: t("09:00"),
            end: Some(t("10:30")),
        },
        CalendarEventTiming::TimedMultiDay {
            start_date: d("2026-05-04"),
            start_time: t("18:00"),
            end_date: d("2026-05-06"),
            end_time: t("09:00"),
        },
    ];
    for original in cases {
        let (sd, st, ed, et, ad) = original.as_flat_fields();
        let rebuilt = CalendarEventTiming::from_flat_fields(sd, st, ed, et, ad).unwrap();
        assert_eq!(original, rebuilt);
    }
}

// ---------------------------------------------------------------------------
// Wire-format byte stability — the serialized JSON shape MUST be
// identical to the legacy 5-key flat shape so existing envelopes / IPC
// responses / sync payloads round-trip across the migration boundary.
// ---------------------------------------------------------------------------

#[test]
fn wire_all_day_single_day_serializes_to_three_legacy_keys() {
    let timing = CalendarEventTiming::AllDay {
        start: d("2026-05-04"),
        end: None,
    };
    let json = serde_json::to_string(&timing.to_flat()).unwrap();
    // `start_time`, `end_date`, `end_time` are skipped when None
    // (mirroring the historical behavior where SQLite NULLs
    // serialized as missing keys in many of the carrier structs).
    assert_eq!(json, r#"{"start_date":"2026-05-04","all_day":true}"#);
}

#[test]
fn wire_all_day_multi_day_serializes_with_end_date() {
    let timing = CalendarEventTiming::AllDay {
        start: d("2026-05-04"),
        end: Some(d("2026-05-06")),
    };
    let json = serde_json::to_string(&timing.to_flat()).unwrap();
    assert_eq!(
        json,
        r#"{"start_date":"2026-05-04","end_date":"2026-05-06","all_day":true}"#
    );
}

#[test]
fn wire_timed_single_day_serializes_with_start_and_optional_end_time() {
    let point = CalendarEventTiming::TimedSingleDay {
        date: d("2026-05-04"),
        start: t("09:00"),
        end: None,
    };
    assert_eq!(
        serde_json::to_string(&point.to_flat()).unwrap(),
        r#"{"start_date":"2026-05-04","start_time":"09:00","all_day":false}"#
    );

    let span = CalendarEventTiming::TimedSingleDay {
        date: d("2026-05-04"),
        start: t("09:00"),
        end: Some(t("10:30")),
    };
    assert_eq!(
        serde_json::to_string(&span.to_flat()).unwrap(),
        r#"{"start_date":"2026-05-04","start_time":"09:00","end_time":"10:30","all_day":false}"#
    );
}

#[test]
fn wire_timed_multi_day_serializes_with_full_quintuple() {
    let timing = CalendarEventTiming::TimedMultiDay {
        start_date: d("2026-05-04"),
        start_time: t("18:00"),
        end_date: d("2026-05-06"),
        end_time: t("09:00"),
    };
    let json = serde_json::to_string(&timing.to_flat()).unwrap();
    assert_eq!(
        json,
        r#"{"start_date":"2026-05-04","start_time":"18:00","end_date":"2026-05-06","end_time":"09:00","all_day":false}"#
    );
}

#[test]
fn wire_round_trip_typed_to_flat_to_typed() {
    let originals = vec![
        CalendarEventTiming::AllDay {
            start: d("2026-05-04"),
            end: None,
        },
        CalendarEventTiming::AllDay {
            start: d("2026-05-04"),
            end: Some(d("2026-05-06")),
        },
        CalendarEventTiming::TimedSingleDay {
            date: d("2026-05-04"),
            start: t("09:00"),
            end: None,
        },
        CalendarEventTiming::TimedSingleDay {
            date: d("2026-05-04"),
            start: t("09:00"),
            end: Some(t("10:30")),
        },
        CalendarEventTiming::TimedMultiDay {
            start_date: d("2026-05-04"),
            start_time: t("18:00"),
            end_date: d("2026-05-06"),
            end_time: t("09:00"),
        },
    ];
    for original in originals {
        let json = serde_json::to_string(&original.to_flat()).unwrap();
        let flat: CalendarEventTimingFlat = serde_json::from_str(&json).unwrap();
        let rebuilt = flat.into_typed().unwrap();
        assert_eq!(rebuilt, original);
        // And the rebuilt timing serializes byte-identical back.
        assert_eq!(serde_json::to_string(&rebuilt.to_flat()).unwrap(), json);
    }
}

#[test]
fn wire_deserialize_validates_via_into_typed() {
    // A flat-shape JSON with all_day=true AND start_time set is a
    // schema-illegal nonsense row; the validating TryFrom must reject.
    let json = r#"{"start_date":"2026-05-04","start_time":"09:00","all_day":true}"#;
    let flat: CalendarEventTimingFlat = serde_json::from_str(json).unwrap();
    let err = flat
        .into_typed()
        .expect_err("must reject all_day+start_time");
    assert!(err.to_string().contains("all_day"));
}
