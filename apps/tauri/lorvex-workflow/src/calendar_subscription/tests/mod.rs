//! Unit tests for the lifted calendar_subscription primitives.

pub(super) use super::parse::{
    extract_ics_param, parse_ics_events, parse_ics_events_with_diagnostics, rrule_to_json,
    unescape_ics, MAX_ATTENDEES_PER_EVENT,
};
pub(super) use super::truncation::{detect_ics_truncation, IcsTruncationReason};
pub(super) use super::tzid::noop_unknown_tzid_sink;

mod parse_core;
mod parse_properties;
mod parse_recurrence;
mod parse_truncation;
mod parse_vtimezone;
mod scheduling;
mod sync;
mod tzid;
mod validation;
mod vtimezone;
