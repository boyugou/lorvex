//! Minute-of-day arithmetic helpers + the private `EventRange` span used
//! by the packing state machine.
//!
//! Kept in a leaf sibling so neither the orchestrator nor the queries
//! module depend on chrono internals; they go through the typed
//! `TimeOfDay` boundary.

use lorvex_domain::time::TimeOfDay;

use super::types::FocusScheduleBlock;

#[derive(Debug, Clone)]
pub(super) struct EventRange {
    pub(super) start: i64,
    pub(super) end: i64,
    pub(super) title: String,
    pub(super) event_id: Option<String>,
}

/// Render a typed `TimeOfDay` as the integer minute offset from
/// midnight (0..=1440). Mirrors the legacy `parse_hhmm_to_minutes`
/// helper used at the boundary, but takes the typed value so the
/// scheduling math no longer routes through a string round-trip.
pub(super) fn time_of_day_to_minutes(value: TimeOfDay) -> i64 {
    use chrono::Timelike;
    let nt = value.as_naive_time();
    i64::from(nt.hour() * 60 + nt.minute())
}

/// Convert minutes-from-midnight back into a typed `TimeOfDay`.
/// Saturates at 23:59 to mirror the previous `format_minutes_hhmm`
/// fallback (a value past 1439 minutes is a programming bug; the
/// fallback prevents a panic at the rendering boundary).
pub(super) fn minutes_to_time_of_day(value: i64) -> TimeOfDay {
    let clamped = value.clamp(0, 1439);
    let hour = (clamped / 60) as u32;
    let minute = (clamped % 60) as u32;
    TimeOfDay::from(
        chrono::NaiveTime::from_hms_opt(hour, minute, 0).unwrap_or_else(|| {
            chrono::NaiveTime::from_hms_opt(23, 59, 0)
                .expect("23:59:00 is always a representable NaiveTime")
        }),
    )
}

pub(super) fn make_event_block(event: &EventRange, start: i64, end: i64) -> FocusScheduleBlock {
    FocusScheduleBlock {
        block_type: "event".to_string(),
        start_time: minutes_to_time_of_day(start),
        end_time: minutes_to_time_of_day(end),
        task_id: None,
        event_id: event.event_id.clone(),
        title: Some(event.title.clone()),
    }
}
