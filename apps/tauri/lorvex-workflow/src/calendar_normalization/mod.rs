//! Calendar event normalization and validation.
//!
//! Two public entry points — `normalize_calendar_create` for the create
//! flow and `normalize_calendar_update` for the patch flow. Both fan out
//! into helpers split across:
//!
//! - `create` — create-path normalization driver
//! - `update` — update-path normalization driver + effective-field
//!   reconciliation against the pre-mutation row
//! - `patches` — `Patch<T>` and `Option<T>` field-shape normalizers
//!   (text, url, timezone, recurrence, date, time, color)
//! - `validation` — pure validation helpers: date/time shape, recurrence
//!   UNTIL ordering, DST-gap rejection, color, length

mod create;
mod patches;
mod update;
mod validation;

use lorvex_domain::{CanonicalCalendarEventType, Patch};

pub use create::normalize_calendar_create;
pub use update::normalize_calendar_update;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CalendarDstGuard {
    Ok,
    Ambiguous {
        wall_clock: String,
        timezone: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CalendarNormalizationError {
    message: String,
}

impl CalendarNormalizationError {
    pub(crate) fn validation(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl std::fmt::Display for CalendarNormalizationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for CalendarNormalizationError {}

#[derive(Debug, Clone)]
pub struct CalendarCreateInput {
    pub title: String,
    pub recurrence: Option<String>,
    pub timezone: Option<String>,
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: Option<bool>,
    pub description: Option<String>,
    pub location: Option<String>,
    pub url: Option<String>,
    pub color: Option<String>,
    pub event_type: Option<CanonicalCalendarEventType>,
    pub person_name: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NormalizedCalendarCreate {
    pub title: String,
    pub recurrence: Option<String>,
    pub timezone: Option<String>,
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: bool,
    pub description: Option<String>,
    pub location: Option<String>,
    pub url: Option<String>,
    pub color: Option<String>,
    pub event_type: CanonicalCalendarEventType,
    pub person_name: Option<String>,
    pub dst_guard: CalendarDstGuard,
}

#[derive(Debug, Clone)]
pub struct CalendarUpdateExisting {
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: bool,
    pub timezone: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CalendarUpdateInput {
    pub title: Option<String>,
    pub recurrence: Patch<String>,
    pub timezone: Patch<String>,
    pub start_date: Option<String>,
    pub start_time: Patch<String>,
    pub end_date: Patch<String>,
    pub end_time: Patch<String>,
    pub all_day: Option<bool>,
    pub description: Patch<String>,
    pub location: Patch<String>,
    pub url: Patch<String>,
    pub color: Patch<String>,
    pub event_type: Patch<CanonicalCalendarEventType>,
    pub person_name: Patch<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EffectiveCalendarEventFields {
    pub start_date: String,
    pub start_time: Option<String>,
    pub end_date: Option<String>,
    pub end_time: Option<String>,
    pub all_day: bool,
    pub timezone: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NormalizedCalendarUpdate {
    pub title: Option<String>,
    pub recurrence: Patch<String>,
    pub timezone: Patch<String>,
    pub start_date: Option<String>,
    pub start_time: Patch<String>,
    pub end_date: Patch<String>,
    pub end_time: Patch<String>,
    pub all_day: Option<bool>,
    pub description: Patch<String>,
    pub location: Patch<String>,
    pub url: Patch<String>,
    pub color: Patch<String>,
    pub event_type: Patch<CanonicalCalendarEventType>,
    pub person_name: Patch<String>,
    pub effective: EffectiveCalendarEventFields,
    pub dst_guard: CalendarDstGuard,
}

pub type CalendarNormalizationResult<T> = Result<T, CalendarNormalizationError>;

#[cfg(test)]
mod tests;
