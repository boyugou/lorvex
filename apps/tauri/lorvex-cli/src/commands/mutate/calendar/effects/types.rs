//! Calendar event input/result/patch shapes.
//!
//! Pure data types — no DB access, no validation logic. Serves the
//! `mutations` and `load` submodules as the shared vocabulary the CLI
//! exposes to its dispatch handlers and the JSON batch-create entry
//! point.

use std::borrow::Cow;

use lorvex_store::repositories::provider_repo::TaskProviderEventLink;
use lorvex_store::repositories::task::calendar_links::TaskCalendarEventLink;
use serde::{Deserialize, Serialize};

/// Field bundle for calendar-event creation. Holds string slices as
/// `Cow<'a, str>` so the same struct serves both the CLI flag path
/// (borrowed from `&str`) and the JSON batch path (borrowed from the
/// owned `String` fields of the deserialized payload) — no dedicated
/// `as_fields` adapter needed.
#[derive(Debug, Clone)]
pub(crate) struct CalendarEventCreateFields<'a> {
    pub(crate) title: Cow<'a, str>,
    pub(crate) start_date: Cow<'a, str>,
    pub(crate) start_time: Option<Cow<'a, str>>,
    pub(crate) end_date: Option<Cow<'a, str>>,
    pub(crate) end_time: Option<Cow<'a, str>>,
    pub(crate) all_day: bool,
    pub(crate) description: Option<Cow<'a, str>>,
    pub(crate) location: Option<Cow<'a, str>>,
    pub(crate) url: Option<Cow<'a, str>>,
    pub(crate) color: Option<Cow<'a, str>>,
    pub(crate) recurrence: Option<Cow<'a, str>>,
    pub(crate) timezone: Option<Cow<'a, str>>,
    pub(crate) event_type: Option<Cow<'a, str>>,
    pub(crate) person_name: Option<Cow<'a, str>>,
}

/// Fully-owned variant used by the JSON batch-create entry point.
/// Carries the same fields as [`CalendarEventCreateFields`] but with
/// `String`-typed strings so it can survive the
/// `serde_json::from_str` deserialize and be turned into a borrowing
/// [`CalendarEventCreateFields`] inline.
#[derive(Debug, Clone, Deserialize)]
pub(crate) struct CalendarEventCreateInput {
    pub(crate) title: String,
    pub(crate) start_date: String,
    pub(crate) start_time: Option<String>,
    pub(crate) end_date: Option<String>,
    pub(crate) end_time: Option<String>,
    #[serde(default)]
    pub(crate) all_day: bool,
    pub(crate) description: Option<String>,
    pub(crate) location: Option<String>,
    pub(crate) url: Option<String>,
    pub(crate) color: Option<String>,
    pub(crate) recurrence: Option<String>,
    pub(crate) timezone: Option<String>,
    pub(crate) event_type: Option<String>,
    pub(crate) person_name: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct CalendarEventsCreateResult {
    pub(crate) created_count: usize,
    pub(crate) calendar_events: Vec<lorvex_store::calendar_timeline::CalendarEventRow>,
}

/// CLI-side attendee payload. The CLI accepts attendee patches via
/// the `--attendees-json` flag (a JSON array string parsed once at
/// dispatch time) so the borrowed `Cow`-of-`&str` shape that every
/// other CLI calendar field uses can stay homogeneous; this struct
/// is the owned form the dispatch layer feeds in.
#[derive(Debug, Clone)]
pub(crate) struct CliAttendeeInput {
    pub(crate) email: String,
    pub(crate) name: Option<String>,
    pub(crate) status: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct CalendarEventUpdateFields<'a> {
    pub(crate) title: Option<&'a str>,
    pub(crate) start_date: Option<&'a str>,
    pub(crate) start_time: lorvex_domain::Patch<&'a str>,
    pub(crate) end_date: lorvex_domain::Patch<&'a str>,
    pub(crate) end_time: lorvex_domain::Patch<&'a str>,
    pub(crate) all_day: Option<bool>,
    pub(crate) description: lorvex_domain::Patch<&'a str>,
    pub(crate) location: lorvex_domain::Patch<&'a str>,
    pub(crate) url: lorvex_domain::Patch<&'a str>,
    pub(crate) color: lorvex_domain::Patch<&'a str>,
    pub(crate) recurrence: lorvex_domain::Patch<&'a str>,
    pub(crate) timezone: lorvex_domain::Patch<&'a str>,
    pub(crate) event_type: lorvex_domain::Patch<&'a str>,
    pub(crate) person_name: lorvex_domain::Patch<&'a str>,
    /// Replace-set semantics for the per-event attendee sub-table:
    /// `Patch::Unset` leaves the existing attendee rows alone,
    /// `Patch::Clear` deletes every attendee row, and
    /// `Patch::Set(list)` replaces the rows with `list` (an empty
    /// `list` behaves like `Clear`).
    pub(crate) attendees: lorvex_domain::Patch<Vec<CliAttendeeInput>>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct DeletedCalendarEventResult {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) deleted: bool,
    pub(crate) unlinked_task_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct CalendarLinkTasksResult {
    pub(crate) event_id: String,
    pub(crate) linked_count: usize,
    pub(crate) links: Vec<TaskCalendarEventLink>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct CalendarUnlinkTaskResult {
    pub(crate) task_id: String,
    pub(crate) event_id: String,
    pub(crate) deleted: bool,
    pub(crate) remaining_links: Vec<TaskCalendarEventLink>,
}

#[derive(Debug, Clone, Serialize)]
pub(crate) struct CalendarProviderUnlinkResult {
    pub(crate) task_id: String,
    pub(crate) provider_kind: String,
    pub(crate) provider_scope: String,
    pub(crate) provider_event_key: String,
    pub(crate) remaining_links: Vec<TaskProviderEventLink>,
}
