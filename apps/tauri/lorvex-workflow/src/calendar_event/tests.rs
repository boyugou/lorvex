//! Tests for the [`super::update`] EXDATE start-time-shift policy.
//!
//! The skeleton-comparator tests live alongside
//! [`super::recurrence_skeleton`]; this module exercises the
//! [`super::update::UpdateCalendarEventMutation`] decision that
//! routes around the comparator when only the anchor time-of-day
//! shifts (or doesn't).

use lorvex_domain::Patch;
use serde_json::Value;

use super::{CalendarEventUpdateInput, UpdateCalendarEventMutation};
use crate::calendar_normalization::CalendarUpdateExisting;

fn existing_with_start_time(value: Option<&str>) -> CalendarUpdateExisting {
    CalendarUpdateExisting {
        start_date: "2026-01-01".to_string(),
        start_time: value.map(|s| s.to_string()),
        end_date: None,
        end_time: None,
        all_day: value.is_none(),
        timezone: Some("UTC".to_string()),
    }
}

fn update_input_with_start_time(start_time: Patch<String>) -> CalendarEventUpdateInput {
    CalendarEventUpdateInput {
        id: "evt-1".to_string(),
        title: None,
        recurrence: Patch::Unset,
        timezone: Patch::Unset,
        start_date: Patch::Unset,
        start_time,
        end_date: Patch::Unset,
        end_time: Patch::Unset,
        all_day: None,
        description: Patch::Unset,
        location: Patch::Unset,
        url: Patch::Unset,
        color: Patch::Unset,
        event_type: Patch::Unset,
        person_name: Patch::Unset,
        attendees: Patch::Unset,
    }
}

/// #4509: re-sending the same `start_time` as a `Patch::Set` is
/// a no-op; the mutation must not flag the patch as a time shift
/// and must not wipe EXDATE.
#[test]
fn start_time_patch_set_with_same_value_is_not_shift() {
    let input = update_input_with_start_time(Patch::Set("09:00".to_string()));
    let existing = existing_with_start_time(Some("09:00"));
    let mutation = UpdateCalendarEventMutation::new(
        input,
        existing,
        Value::Null,
        Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#.to_string()),
    )
    .expect("mutation should build");
    assert!(
        !mutation.is_anchor_shift(),
        "Patch::Set with same value must not flag shift"
    );
}

/// #4509: `Patch::Set` carrying a genuinely different value is a
/// real shift; EXDATE must drop.
#[test]
fn start_time_patch_set_with_different_value_is_shift() {
    let input = update_input_with_start_time(Patch::Set("10:00".to_string()));
    let existing = existing_with_start_time(Some("09:00"));
    let mutation = UpdateCalendarEventMutation::new(
        input,
        existing,
        Value::Null,
        Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#.to_string()),
    )
    .expect("mutation should build");
    assert!(
        mutation.is_anchor_shift(),
        "Patch::Set with different value must flag shift"
    );
}

fn update_input_with_start_date(start_date: Patch<String>) -> CalendarEventUpdateInput {
    CalendarEventUpdateInput {
        id: "evt-1".to_string(),
        title: None,
        recurrence: Patch::Unset,
        timezone: Patch::Unset,
        start_date,
        start_time: Patch::Unset,
        end_date: Patch::Unset,
        end_time: Patch::Unset,
        all_day: None,
        description: Patch::Unset,
        location: Patch::Unset,
        url: Patch::Unset,
        color: Patch::Unset,
        event_type: Patch::Unset,
        person_name: Patch::Unset,
        attendees: Patch::Unset,
    }
}

/// #4600 F1: re-anchoring the start_date (e.g. Monday → Wednesday)
/// shifts the EXDATE grid and must drop the exception list, even
/// when the RRULE itself is unchanged.
#[test]
fn start_date_patch_set_with_different_value_is_shift() {
    let input = update_input_with_start_date(Patch::Set("2026-01-07".to_string()));
    // Default existing start_date is 2026-01-01 (a Thursday).
    let existing = existing_with_start_time(Some("09:00"));
    let mutation = UpdateCalendarEventMutation::new(
        input,
        existing,
        Value::Null,
        Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#.to_string()),
    )
    .expect("mutation should build");
    assert!(
        mutation.is_anchor_shift(),
        "start_date re-anchor must flag anchor shift so EXDATE drops"
    );
}

/// #4600 F1: re-sending the same `start_date` as a `Patch::Set` is
/// a no-op (analogous to #4509 for start_time); the mutation must
/// not flag this as an anchor shift.
#[test]
fn start_date_patch_set_with_same_value_is_not_shift() {
    let input = update_input_with_start_date(Patch::Set("2026-01-01".to_string()));
    let existing = existing_with_start_time(Some("09:00"));
    let mutation = UpdateCalendarEventMutation::new(
        input,
        existing,
        Value::Null,
        Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#.to_string()),
    )
    .expect("mutation should build");
    assert!(
        !mutation.is_anchor_shift(),
        "start_date Patch::Set with same value must not flag shift"
    );
}

/// #4600 F1: `Patch::Unset` for start_date (the unchanged case) is
/// not an anchor shift.
#[test]
fn start_date_patch_unset_is_not_shift() {
    let input = update_input_with_start_date(Patch::Unset);
    let existing = existing_with_start_time(Some("09:00"));
    let mutation = UpdateCalendarEventMutation::new(
        input,
        existing,
        Value::Null,
        Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#.to_string()),
    )
    .expect("mutation should build");
    assert!(
        !mutation.is_anchor_shift(),
        "Patch::Unset start_date must not flag shift"
    );
}
