use chrono::NaiveDate;

use crate::validation::ValidationError;

use super::cadence::{HabitCadence, HabitFrequencyFields, WeekDay};
use super::*;

#[test]
fn validate_habit_create_draft_sanitizes_and_computes_lookup_key() {
    let validated = validate_habit_create_draft(HabitCreateDraft {
        name: "  Morning Pages  ",
        icon: Some("  M  "),
        color: Some("  #AABBCC  "),
        cue: Some("  After coffee  "),
        frequency: Some(HabitCadence::Daily),
        target_count: Some(0),
    })
    .expect("valid habit create draft");

    assert_eq!(validated.name(), "Morning Pages");
    assert_eq!(validated.icon(), Some("M"));
    assert_eq!(validated.color(), Some("#AABBCC"));
    assert_eq!(validated.cue(), Some("After coffee"));
    assert_eq!(validated.frequency(), &HabitCadence::Daily);
    assert_eq!(validated.target_count(), 1);
    assert_eq!(
        validated.lookup_key(),
        crate::tag::normalize_lookup_key("Morning Pages")
    );
}

#[test]
fn validate_habit_create_draft_omitted_frequency_defaults_to_daily() {
    let validated = validate_habit_create_draft(HabitCreateDraft {
        name: "Hydrate",
        icon: None,
        color: None,
        cue: None,
        frequency: None,
        target_count: None,
    })
    .expect("valid habit create draft");
    assert_eq!(validated.frequency(), &HabitCadence::Daily);
}

#[test]
fn validate_habit_create_draft_rejects_invalid_color() {
    let error = validate_habit_create_draft(HabitCreateDraft {
        name: "Hydrate",
        icon: None,
        color: Some("red"),
        cue: None,
        frequency: Some(HabitCadence::Daily),
        target_count: None,
    })
    .expect_err("invalid color should be rejected");

    assert_eq!(
        error,
        ValidationError::InvalidFormat {
            field: "color",
            expected: "#RGB or #RRGGBB",
            actual: "red".to_string(),
        }
    );
}

#[test]
fn validate_habit_update_draft_normalizes_empty_optional_text_to_clear() {
    let validated = validate_habit_update_draft(HabitUpdateDraft {
        color: crate::Patch::Set("   "),
        cue: crate::Patch::Set("\u{200B}"),
        target_count: Some(-3),
        ..HabitUpdateDraft::default()
    })
    .expect("empty optional update fields normalize to clear");

    assert_eq!(validated.color(), crate::Patch::Clear);
    assert_eq!(validated.cue(), crate::Patch::Clear);
    assert_eq!(validated.target_count(), Some(1));
}

#[test]
fn times_per_week_cadence_from_fields() {
    let cadence = HabitCadence::from_fields(&HabitFrequencyFields {
        per_period_target: 3,
        ..HabitFrequencyFields::new("times_per_week")
    })
    .expect("parse cadence");
    assert_eq!(cadence, HabitCadence::TimesPerWeek { count: 3 });
    assert_eq!(habit_required_completions_per_period(&cadence, 2), 6);
    assert!(habit_uses_week_bucket(&cadence));
}

#[test]
fn times_per_week_cadence_rejects_non_positive_target() {
    let error = HabitCadence::from_fields(&HabitFrequencyFields {
        per_period_target: 0,
        ..HabitFrequencyFields::new("times_per_week")
    })
    .expect_err("non-positive per_period_target should be rejected")
    .to_string();
    assert!(error.contains("positive"), "unexpected error: {error}");
}

#[test]
fn weekly_cadence_from_fields_sorts_and_dedups_weekdays() {
    let cadence = HabitCadence::from_fields(&HabitFrequencyFields {
        weekdays: Some(vec![WeekDay::Wed, WeekDay::Mon, WeekDay::Wed]),
        ..HabitFrequencyFields::new("weekly")
    })
    .expect("parse cadence");
    assert_eq!(
        cadence,
        HabitCadence::Weekly {
            days: Some(vec![WeekDay::Mon, WeekDay::Wed]),
        }
    );
    assert_eq!(habit_required_completions_per_period(&cadence, 1), 2);
}

#[test]
fn weekly_cadence_empty_weekdays_normalizes_to_none() {
    let cadence = HabitCadence::from_fields(&HabitFrequencyFields {
        weekdays: Some(vec![]),
        ..HabitFrequencyFields::new("weekly")
    })
    .expect("parse cadence");
    assert_eq!(cadence, HabitCadence::Weekly { days: None });
    assert!(cadence.weekdays().is_none());
}

#[test]
fn monthly_cadence_from_fields_clamps_day_of_month() {
    let cadence = HabitCadence::from_fields(&HabitFrequencyFields {
        day_of_month: Some(15),
        ..HabitFrequencyFields::new("monthly")
    })
    .expect("parse cadence");
    assert_eq!(
        cadence,
        HabitCadence::Monthly {
            day_of_month: Some(15)
        }
    );
    assert_eq!(habit_required_completions_per_period(&cadence, 1), 1);
    // Monthly habits are always "scheduled" on any given day.
    let any_day = NaiveDate::from_ymd_opt(2026, 4, 15).expect("date");
    assert!(is_habit_scheduled_on_day(&cadence, any_day));
    // Monthly uses its own bucket, not weekly.
    assert!(!habit_uses_week_bucket(&cadence));

    // Out-of-range day_of_month degrades to None ("unspecified").
    let clamped = HabitCadence::from_fields(&HabitFrequencyFields {
        day_of_month: Some(99),
        ..HabitFrequencyFields::new("monthly")
    })
    .expect("parse cadence");
    assert_eq!(clamped, HabitCadence::Monthly { day_of_month: None });
}

#[test]
fn schedule_checks_weekday_membership() {
    let cadence = HabitCadence::Weekly {
        days: Some(vec![WeekDay::Mon, WeekDay::Fri]),
    };
    let monday = NaiveDate::from_ymd_opt(2026, 4, 6).expect("monday");
    let tuesday = NaiveDate::from_ymd_opt(2026, 4, 7).expect("tuesday");
    assert!(is_habit_scheduled_on_day(&cadence, monday));
    assert!(!is_habit_scheduled_on_day(&cadence, tuesday));
}

#[test]
fn from_fields_rejects_unknown_frequency_type() {
    let error = HabitCadence::from_fields(&HabitFrequencyFields::new("yearly"))
        .expect_err("unsupported frequency_type should be rejected")
        .to_string();
    assert!(
        error.contains("yearly"),
        "expected unsupported type in error, got: {error}"
    );
}

// ---------------------------------------------------------------------------
// HabitCadence <-> HabitFrequencyFields round-trip tests. These pin down the
// typed-column shape the cadence takes on disk / on the sync wire so the typed
// primitive cannot silently drift.
// ---------------------------------------------------------------------------

#[test]
fn cadence_to_fields_applies_schema_defaults() {
    let daily = HabitCadence::Daily.to_fields();
    assert_eq!(daily.frequency_type, "daily");
    assert!(daily.weekdays.is_none());
    assert_eq!(daily.per_period_target, 1);
    assert!(daily.day_of_month.is_none());

    let monthly = HabitCadence::Monthly {
        day_of_month: Some(9),
    }
    .to_fields();
    assert_eq!(monthly.frequency_type, "monthly");
    assert_eq!(monthly.day_of_month, Some(9));

    let tpw = HabitCadence::TimesPerWeek { count: 4 }.to_fields();
    assert_eq!(tpw.frequency_type, "times_per_week");
    assert_eq!(tpw.per_period_target, 4);
}

#[test]
fn cadence_round_trip_through_fields_is_stable() {
    let cases = [
        HabitCadence::Daily,
        HabitCadence::Weekly { days: None },
        HabitCadence::Weekly {
            days: Some(vec![WeekDay::Mon, WeekDay::Fri]),
        },
        HabitCadence::Monthly { day_of_month: None },
        HabitCadence::Monthly {
            day_of_month: Some(28),
        },
        HabitCadence::TimesPerWeek { count: 5 },
    ];
    for original in cases {
        let fields = original.to_fields();
        let parsed = HabitCadence::from_fields(&fields).expect("round-trip parse");
        assert_eq!(parsed, original, "round-trip mismatch for {original:?}");
    }
}

#[test]
fn weekday_wire_str_round_trips_through_parse() {
    for day in [
        WeekDay::Mon,
        WeekDay::Tue,
        WeekDay::Wed,
        WeekDay::Thu,
        WeekDay::Fri,
        WeekDay::Sat,
        WeekDay::Sun,
    ] {
        assert_eq!(
            WeekDay::parse(day.as_wire_str()),
            Some(day),
            "weekday wire token round-trip failed for {day:?}"
        );
        assert_eq!(
            WeekDay::from_index(day.as_index()),
            Some(day),
            "weekday index round-trip failed for {day:?}"
        );
    }
    // Monday-first: Mon=0 … Sun=6, matching Apple's WeekDay raw value.
    assert_eq!(WeekDay::Mon.as_index(), 0);
    assert_eq!(WeekDay::Sun.as_index(), 6);
    assert!(WeekDay::from_index(7).is_none());
}

#[test]
fn effective_monthly_day_clamps_to_month_length() {
    // Day 31 requested in February clamps to 28 (non-leap) / 29 (leap).
    assert_eq!(effective_monthly_day(Some(31), 2026, 2), 28);
    assert_eq!(effective_monthly_day(Some(31), 2024, 2), 29);
    assert_eq!(effective_monthly_day(Some(31), 2026, 4), 30);
    assert_eq!(effective_monthly_day(Some(15), 2026, 1), 15);
    // None / non-positive default to the 1st.
    assert_eq!(effective_monthly_day(None, 2026, 3), 1);
}

#[test]
fn is_habit_reminder_day_fires_once_per_month_for_monthly() {
    let cadence = HabitCadence::Monthly {
        day_of_month: Some(31),
    };
    // February clamps day 31 to the 28th (2026 is not a leap year).
    assert!(is_habit_reminder_day(
        &cadence,
        NaiveDate::from_ymd_opt(2026, 2, 28).expect("date")
    ));
    assert!(!is_habit_reminder_day(
        &cadence,
        NaiveDate::from_ymd_opt(2026, 2, 27).expect("date")
    ));
    // Daily reminders fire every scheduled day.
    assert!(is_habit_reminder_day(
        &HabitCadence::Daily,
        NaiveDate::from_ymd_opt(2026, 2, 27).expect("date")
    ));
}

fn habit_payload_fixture(weekdays: &'static [WeekDay]) -> HabitSyncFields<'static> {
    HabitSyncFields {
        id: "habit-1",
        name: "Read",
        icon: Some("book"),
        color: Some("#112233"),
        cue: Some("After dinner"),
        frequency_type: "weekly",
        weekdays,
        per_period_target: 1,
        day_of_month: None,
        target_count: 1,
        milestone_target: Some(30),
        archived: false,
        created_at: "2026-04-01T00:00:00Z",
        updated_at: "2026-04-02T00:00:00Z",
        position: 7,
        version: "0000000000000_0000_a0a0a0a0a0a0a0a0",
    }
}

#[test]
fn habit_sync_payload_includes_typed_cadence_shape() {
    let payload = habit_payload_fixture(&[WeekDay::Mon, WeekDay::Wed]);
    let payload = habit_sync_payload(payload);

    assert_eq!(payload["id"], "habit-1");
    assert_eq!(payload["name"], "Read");
    assert_eq!(payload["icon"], "book");
    assert_eq!(payload["color"], "#112233");
    assert_eq!(payload["cue"], "After dinner");
    assert_eq!(payload["frequency_type"], "weekly");
    // Monday-first weekday integers materialized as an array.
    assert_eq!(payload["weekdays"], serde_json::json!([0, 2]));
    assert_eq!(payload["per_period_target"], 1);
    assert!(payload["day_of_month"].is_null());
    assert_eq!(payload["target_count"], 1);
    // Nullable milestone goal rides alongside `target_count`.
    assert_eq!(payload["milestone_target"], 30);
    assert_eq!(payload["archived"], false);
    assert_eq!(payload["created_at"], "2026-04-01T00:00:00Z");
    assert_eq!(payload["updated_at"], "2026-04-02T00:00:00Z");
    assert_eq!(payload["position"], 7);
    assert_eq!(payload["version"], "0000000000000_0000_a0a0a0a0a0a0a0a0");
    // frequency_value is gone from the wire shape.
    assert!(payload.get("frequency_value").is_none());
}

#[test]
fn habit_sync_payload_daily_emits_empty_weekdays_array() {
    let payload = habit_sync_payload(habit_payload_fixture(&[]));
    assert_eq!(payload["weekdays"], serde_json::json!([]));
}
