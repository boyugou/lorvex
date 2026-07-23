//! Calendar event argument structs.

use clap::{Args, Subcommand};

use super::super::parsers::{
    parse_calendar_event_type, parse_cli_date_arg, parse_event_id, parse_hex_color,
    parse_positive_u32, parse_task_id, parse_time, parse_timezone,
};
use super::LimitArgs;

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum CalendarCmd {
    /// List upcoming calendar events.
    List(LimitArgs),
    /// Show a single event's detail.
    Show(CalendarShowArgs),
    /// Show today's events.
    Today,
    /// Create a calendar event.
    Create(Box<CalendarCreateArgs>),
    /// Create multiple calendar events from a JSON array.
    BatchCreate(CalendarBatchCreateArgs),
    /// Update a calendar event.
    Update(Box<CalendarUpdateArgs>),
    /// Delete a calendar event.
    Delete(CalendarShowArgs),
    /// Link one or more tasks to a calendar event.
    Link(CalendarLinkArgs),
    /// Unlink one task from a calendar event.
    Unlink(CalendarUnlinkArgs),
    /// List calendar event links for a task.
    LinksForTask(CalendarTaskLinksArgs),
    /// List task links for a calendar event.
    LinksForEvent(CalendarShowArgs),
    /// Add a recurrence exception date to a recurring calendar event.
    AddException(CalendarExceptionArgs),
    /// Remove a recurrence exception date from a recurring calendar event.
    RemoveException(CalendarExceptionArgs),
    /// Link a task to a provider calendar event (local-only).
    ProviderLink(CalendarProviderLinkArgs),
    /// Unlink a task from a provider calendar event (local-only).
    ProviderUnlink(CalendarProviderLinkArgs),
    /// List provider calendar event links for a task.
    ProviderLinksForTask(CalendarTaskLinksArgs),
    /// Export canonical calendar events as iCalendar (.ics).
    ExportIcs(CalendarExportIcsArgs),
    /// Full-text search across calendar events.
    ///
    /// mirrors MCP `search_calendar_events` — FTS5 with a
    /// CJK-aware LIKE fallback baked into the store query layer.
    Search(CalendarSearchArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarShowArgs {
    #[arg(value_parser = parse_event_id)]
    pub(in crate::cli) event_id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarCreateArgs {
    /// One or more words for the event title (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) title: Vec<String>,
    #[arg(long = "start-date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) start_date: String,
    #[arg(long = "start-time", value_parser = parse_time)]
    pub(in crate::cli) start_time: Option<String>,
    #[arg(long = "end-date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) end_date: Option<String>,
    #[arg(long = "end-time", value_parser = parse_time)]
    pub(in crate::cli) end_time: Option<String>,
    #[arg(long = "all-day")]
    pub(in crate::cli) all_day: bool,
    #[arg(long = "description")]
    pub(in crate::cli) description: Option<String>,
    #[arg(long = "location")]
    pub(in crate::cli) location: Option<String>,
    #[arg(long = "url")]
    pub(in crate::cli) url: Option<String>,
    #[arg(long = "color", value_parser = parse_hex_color)]
    pub(in crate::cli) color: Option<String>,
    #[arg(long = "recurrence")]
    pub(in crate::cli) recurrence: Option<String>,
    #[arg(long = "timezone", value_parser = parse_timezone)]
    pub(in crate::cli) timezone: Option<String>,
    #[arg(long = "event-type", value_parser = parse_calendar_event_type)]
    pub(in crate::cli) event_type: Option<String>,
    #[arg(long = "person-name")]
    pub(in crate::cli) person_name: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarBatchCreateArgs {
    /// JSON array of event objects. Uses the same field names as calendar create: title, start_date, start_time, end_date, end_time, all_day, description, location, url, color, recurrence, timezone, event_type, person_name.
    #[arg(long = "events-json")]
    pub(in crate::cli) events_json: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarLinkArgs {
    #[arg(value_parser = parse_event_id)]
    pub(in crate::cli) event_id: String,
    /// One or more task ids to link to the event.
    #[arg(
        required = true,
        num_args = 1..,
        value_parser = parse_task_id
    )]
    pub(in crate::cli) task_ids: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarUnlinkArgs {
    #[arg(value_parser = parse_event_id)]
    pub(in crate::cli) event_id: String,
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarTaskLinksArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarExceptionArgs {
    #[arg(value_parser = parse_event_id)]
    pub(in crate::cli) event_id: String,
    #[arg(value_parser = parse_cli_date_arg)]
    pub(in crate::cli) date: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarProviderLinkArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    #[arg(long = "provider-kind")]
    pub(in crate::cli) provider_kind: String,
    #[arg(long = "provider-scope", default_value = "")]
    pub(in crate::cli) provider_scope: String,
    #[arg(long = "provider-event-key")]
    pub(in crate::cli) provider_event_key: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarSearchArgs {
    /// One or more words for the search query (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) query: Vec<String>,
    /// Optional inclusive `from` date (YYYY-MM-DD).
    #[arg(long = "from", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) from: Option<String>,
    /// Optional inclusive `to` date (YYYY-MM-DD).
    #[arg(long = "to", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) to: Option<String>,
    #[arg(short = 'l', long = "limit", default_value_t = 25, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarExportIcsArgs {
    #[arg(long = "from", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) from: String,
    #[arg(long = "to", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) to: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CalendarUpdateArgs {
    #[arg(value_parser = parse_event_id)]
    pub(in crate::cli) event_id: String,
    #[arg(long = "title")]
    pub(in crate::cli) title: Option<String>,
    #[arg(long = "start-date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) start_date: Option<String>,
    #[arg(long = "start-time", value_parser = parse_time, conflicts_with = "clear_start_time")]
    pub(in crate::cli) start_time: Option<String>,
    #[arg(long = "clear-start-time")]
    pub(in crate::cli) clear_start_time: bool,
    #[arg(long = "end-date", value_parser = parse_cli_date_arg, conflicts_with = "clear_end_date")]
    pub(in crate::cli) end_date: Option<String>,
    #[arg(long = "clear-end-date")]
    pub(in crate::cli) clear_end_date: bool,
    #[arg(long = "end-time", value_parser = parse_time, conflicts_with = "clear_end_time")]
    pub(in crate::cli) end_time: Option<String>,
    #[arg(long = "clear-end-time")]
    pub(in crate::cli) clear_end_time: bool,
    #[arg(long = "all-day", conflicts_with = "timed")]
    pub(in crate::cli) all_day: bool,
    #[arg(long = "timed", conflicts_with = "all_day")]
    pub(in crate::cli) timed: bool,
    #[arg(long = "description", conflicts_with = "clear_description")]
    pub(in crate::cli) description: Option<String>,
    #[arg(long = "clear-description")]
    pub(in crate::cli) clear_description: bool,
    #[arg(long = "location", conflicts_with = "clear_location")]
    pub(in crate::cli) location: Option<String>,
    #[arg(long = "clear-location")]
    pub(in crate::cli) clear_location: bool,
    #[arg(long = "url", conflicts_with = "clear_url")]
    pub(in crate::cli) url: Option<String>,
    #[arg(long = "clear-url")]
    pub(in crate::cli) clear_url: bool,
    #[arg(long = "color", value_parser = parse_hex_color, conflicts_with = "clear_color")]
    pub(in crate::cli) color: Option<String>,
    #[arg(long = "clear-color")]
    pub(in crate::cli) clear_color: bool,
    #[arg(long = "recurrence", conflicts_with = "clear_recurrence")]
    pub(in crate::cli) recurrence: Option<String>,
    #[arg(long = "clear-recurrence")]
    pub(in crate::cli) clear_recurrence: bool,
    #[arg(long = "timezone", value_parser = parse_timezone, conflicts_with = "clear_timezone")]
    pub(in crate::cli) timezone: Option<String>,
    #[arg(long = "clear-timezone")]
    pub(in crate::cli) clear_timezone: bool,
    #[arg(long = "event-type", value_parser = parse_calendar_event_type, conflicts_with = "clear_event_type")]
    pub(in crate::cli) event_type: Option<String>,
    #[arg(long = "clear-event-type")]
    pub(in crate::cli) clear_event_type: bool,
    #[arg(long = "person-name", conflicts_with = "clear_person_name")]
    pub(in crate::cli) person_name: Option<String>,
    #[arg(long = "clear-person-name")]
    pub(in crate::cli) clear_person_name: bool,
    /// Replace the attendee list. Pass a JSON array of
    /// `{"email":"...","name":"...","status":"..."}` objects (status
    /// is optional and must be one of `accepted`, `declined`,
    /// `tentative`, `needs-action`). Pass `[]` or use
    /// `--clear-attendees` to drop every attendee row.
    #[arg(long = "attendees-json", conflicts_with = "clear_attendees")]
    pub(in crate::cli) attendees_json: Option<String>,
    /// Delete every attendee row attached to the event.
    #[arg(long = "clear-attendees")]
    pub(in crate::cli) clear_attendees: bool,
}
