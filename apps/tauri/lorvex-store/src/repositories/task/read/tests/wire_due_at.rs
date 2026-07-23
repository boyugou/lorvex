//! Wire-format byte-stability tests for the typed
//! [`lorvex_domain::time::DueAt`] carrier inside
//! [`super::super::TaskScheduling`].
//!
//! The (`due_date`, `due_time`) pair was migrated to a single typed
//! `DueAt` enum so the implicit "time-without-date is invalid"
//! invariant is enforced by the type system. The on-disk
//! `payload_shadow` JSON, the cross-peer envelope payloads, and the
//! IPC `TaskRow` JSON all flatten the typed carrier back into the
//! legacy two flat keys (`due_date`, `due_time`) via a custom
//! `serialize_with` adapter. These tests pin the wire format so a
//! future refactor cannot silently drift into a tagged-enum shape
//! that older peer builds wouldn't parse.

use super::support::{TaskScheduling, TaskSchedulingFields};
use lorvex_domain::time::{Date, DueAt, TimeOfDay};

fn fields_with_due(due: DueAt) -> TaskSchedulingFields {
    TaskSchedulingFields {
        due,
        ..TaskSchedulingFields::default()
    }
}

#[test]
fn task_scheduling_serializes_at_moment_with_flat_legacy_keys() {
    let date = Date::parse("2026-05-04").unwrap();
    let time = TimeOfDay::parse("09:30").unwrap();
    let scheduling = TaskScheduling::new(fields_with_due(DueAt::AtMoment { date, time }));
    let value: serde_json::Value =
        serde_json::to_value(&scheduling).expect("serialize TaskScheduling");
    assert_eq!(value["due_date"], serde_json::json!("2026-05-04"));
    assert_eq!(value["due_time"], serde_json::json!("09:30"));
}

#[test]
fn task_scheduling_serializes_on_day_with_only_due_date_key() {
    let date = Date::parse("2026-05-04").unwrap();
    let scheduling = TaskScheduling::new(fields_with_due(DueAt::OnDay(date)));
    let value: serde_json::Value =
        serde_json::to_value(&scheduling).expect("serialize TaskScheduling");
    assert_eq!(value["due_date"], serde_json::json!("2026-05-04"));
    // OnDay → due_time MUST be absent so the JSON shape on
    // payload_shadow rows for "all-day-due" tasks matches the legacy
    // (Some(date), None) emission.
    assert!(value.get("due_time").is_none() || value["due_time"].is_null());
}

#[test]
fn task_scheduling_serializes_unscheduled_with_no_due_keys() {
    let scheduling = TaskScheduling::new(fields_with_due(DueAt::Unscheduled));
    let value: serde_json::Value =
        serde_json::to_value(&scheduling).expect("serialize TaskScheduling");
    // Unscheduled → both keys absent (skip_serializing_if). Mirrors
    // the legacy emission for `(None, None)`.
    assert!(value.get("due_date").is_none() || value["due_date"].is_null());
    assert!(value.get("due_time").is_none() || value["due_time"].is_null());
}
