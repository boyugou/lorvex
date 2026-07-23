// trust: integration tests intentionally use unwrap() for assertion clarity —
// panics ARE the failure mode.
#![allow(clippy::unwrap_used)]

//! Integration tests for calendar timeline queries.
//!
//! These tests exercise `get_calendar_timeline` and `get_day_blocking_ranges`
//! against an in-memory SQLite database seeded with test data.

#[path = "calendar_timeline/access_modes.rs"]
mod access_modes;
#[path = "calendar_timeline/blocking_ranges.rs"]
mod blocking_ranges;
#[path = "calendar_timeline/recurrence_pruning.rs"]
mod recurrence_pruning;
#[path = "calendar_timeline/support.rs"]
mod support;
#[path = "calendar_timeline/timeline_queries.rs"]
mod timeline_queries;
#[path = "calendar_timeline/timezone_resilience.rs"]
mod timezone_resilience;
