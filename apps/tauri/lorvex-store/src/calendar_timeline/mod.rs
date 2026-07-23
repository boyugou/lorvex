//! Shared calendar-timeline module.
//!
//! Contains output types for timeline items and blocking-event ranges,
//! consolidated recurrence-expansion primitives, range expansion, and
//! SQL query functions used by both the Tauri app and the MCP server.

pub(crate) mod expansion;
pub mod queries;
pub mod recurrence;
pub(crate) mod temporal;
pub mod types;

pub use queries::{get_calendar_timeline, get_day_blocking_ranges, search_calendar_events};
pub use recurrence::{
    add_months_clamped, calculate_next_occurrence_date, count_end_date,
    first_occurrence_on_or_after, first_weekly_byday_occurrence_on_or_after,
    next_occurrence_strictly_after, overlaps_calendar_range, parse_ymd, recurs_on_date,
    weekly_target_dows,
};
pub use types::{
    BlockingEventRange, CalendarEventRow, CalendarEventRowFields, CalendarTimelineItem,
    CalendarTimelineItemFields, TimelineSource,
};
