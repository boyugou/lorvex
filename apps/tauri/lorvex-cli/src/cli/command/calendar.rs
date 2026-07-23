//! Calendar event CRUD, link/unlink, exception, provider-link, ICS, and
//! search arms.

use super::OutputFormat;

/// Attendee patch surfaced through `--attendees-json` /
/// `--clear-attendees`. `Json(raw)` defers JSON parsing to dispatch
/// so a malformed payload can surface through the CLI's `Result`
/// channel; `Clear` deletes every attendee row.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum AttendeesPatch {
    Unset,
    Clear,
    Json(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum CalendarCommand {
    List {
        limit: u32,
        format: OutputFormat,
    },
    Show {
        event_id: String,
        format: OutputFormat,
    },
    Today {
        format: OutputFormat,
    },
    Create {
        title: String,
        start_date: String,
        start_time: Option<String>,
        end_date: Option<String>,
        end_time: Option<String>,
        all_day: bool,
        description: Option<String>,
        location: Option<String>,
        url: Option<String>,
        color: Option<String>,
        recurrence: Option<String>,
        timezone: Option<String>,
        event_type: Option<String>,
        person_name: Option<String>,
        format: OutputFormat,
    },
    BatchCreate {
        events_json: String,
        format: OutputFormat,
    },
    Update {
        event_id: String,
        title: Option<String>,
        start_date: Option<String>,
        start_time: lorvex_domain::Patch<String>,
        end_date: lorvex_domain::Patch<String>,
        end_time: lorvex_domain::Patch<String>,
        all_day: Option<bool>,
        description: lorvex_domain::Patch<String>,
        location: lorvex_domain::Patch<String>,
        url: lorvex_domain::Patch<String>,
        color: lorvex_domain::Patch<String>,
        recurrence: lorvex_domain::Patch<String>,
        timezone: lorvex_domain::Patch<String>,
        event_type: lorvex_domain::Patch<String>,
        person_name: lorvex_domain::Patch<String>,
        /// Replace-set patch over the per-event attendee sub-table.
        /// Surfaced through `--attendees-json` / `--clear-attendees`.
        /// JSON parsing happens at dispatch time so a malformed
        /// payload surfaces through the CLI's `Result` channel.
        attendees: AttendeesPatch,
        format: OutputFormat,
    },
    Delete {
        event_id: String,
        format: OutputFormat,
    },
    Link {
        event_id: String,
        task_ids: Vec<String>,
        format: OutputFormat,
    },
    Unlink {
        event_id: String,
        task_id: String,
        format: OutputFormat,
    },
    LinksForTask {
        task_id: String,
        format: OutputFormat,
    },
    LinksForEvent {
        event_id: String,
        format: OutputFormat,
    },
    AddException {
        event_id: String,
        date: String,
        format: OutputFormat,
    },
    RemoveException {
        event_id: String,
        date: String,
        format: OutputFormat,
    },
    ProviderLink {
        task_id: String,
        provider_kind: String,
        provider_scope: String,
        provider_event_key: String,
        format: OutputFormat,
    },
    ProviderUnlink {
        task_id: String,
        provider_kind: String,
        provider_scope: String,
        provider_event_key: String,
        format: OutputFormat,
    },
    ProviderLinksForTask {
        task_id: String,
        format: OutputFormat,
    },
    ExportIcs {
        from: String,
        to: String,
        format: OutputFormat,
    },
    /// full-text calendar event search (MCP `search_calendar_events`).
    Search {
        query: String,
        from: Option<String>,
        to: Option<String>,
        limit: u32,
        format: OutputFormat,
    },
}
