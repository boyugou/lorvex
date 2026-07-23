use crate::contract::{CALENDAR_RECURRENCE_FIELD_DESCRIPTION, IDEMPOTENCY_KEY_DESCRIPTION};
use lorvex_domain::{AttendeeStatus, CanonicalCalendarEventType};
use lorvex_sync_payload::CalendarEventUpdateWire;
use schemars::JsonSchema;

/// Closed RFC 5545 PARTSTAT subset accepted on the MCP write surface.
///
/// `kebab-case` rendering means `NeedsAction` deserializes from
/// `"needs-action"` — the canonical wording that
/// [`lorvex_domain::AttendeeStatus::as_str`] emits and the schema
/// CHECK constraint enforces.
/// `Option<String>` and the parse happened deep inside
/// `replace_attendees`, far from the trust boundary; an invalid
/// PARTSTAT only failed after the surrounding write had already
/// fingered the DB. With this typed shape, `serde` rejects bad input
/// at the JSON parse boundary so the validation error never escapes
/// the contract layer.
#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum AttendeeStatusArg {
    Accepted,
    Declined,
    Tentative,
    NeedsAction,
}

impl From<AttendeeStatusArg> for AttendeeStatus {
    fn from(value: AttendeeStatusArg) -> Self {
        match value {
            AttendeeStatusArg::Accepted => AttendeeStatus::Accepted,
            AttendeeStatusArg::Declined => AttendeeStatus::Declined,
            AttendeeStatusArg::Tentative => AttendeeStatus::Tentative,
            AttendeeStatusArg::NeedsAction => AttendeeStatus::NeedsAction,
        }
    }
}

/// Input representation for a calendar event attendee.
#[derive(Debug, Clone, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct AttendeeInput {
    #[schemars(description = "Attendee email address")]
    pub(crate) email: String,
    #[schemars(description = "Attendee display name")]
    pub(crate) name: Option<String>,
    #[schemars(description = "RSVP status: accepted, declined, tentative, needs-action")]
    pub(crate) status: Option<AttendeeStatusArg>,
}

#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum CalendarEventTypeArg {
    Event,
    Birthday,
    Anniversary,
    Memorial,
}

impl From<CalendarEventTypeArg> for CanonicalCalendarEventType {
    fn from(value: CalendarEventTypeArg) -> Self {
        match value {
            CalendarEventTypeArg::Event => CanonicalCalendarEventType::Event,
            CalendarEventTypeArg::Birthday => CanonicalCalendarEventType::Birthday,
            CalendarEventTypeArg::Anniversary => CanonicalCalendarEventType::Anniversary,
            CalendarEventTypeArg::Memorial => CanonicalCalendarEventType::Memorial,
        }
    }
}

// Serialize required for the idempotency cache
// checksum.
#[derive(Debug, Clone, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct CreateCalendarEventArgs {
    #[schemars(description = "Calendar event title")]
    pub(crate) title: String,
    #[schemars(description = CALENDAR_RECURRENCE_FIELD_DESCRIPTION)]
    pub(crate) recurrence: Option<String>,
    #[schemars(description = "Optional IANA timezone like America/Los_Angeles")]
    pub(crate) timezone: Option<String>,
    #[schemars(description = "Event start date in YYYY-MM-DD")]
    pub(crate) start_date: String,
    #[schemars(description = "Event start time in HH:MM (24h). Omit for all-day events.")]
    pub(crate) start_time: Option<String>,
    #[schemars(description = "Optional end date in YYYY-MM-DD")]
    pub(crate) end_date: Option<String>,
    #[schemars(description = "Optional end time in HH:MM (24h)")]
    pub(crate) end_time: Option<String>,
    #[schemars(description = "Whether the event is all-day.")]
    pub(crate) all_day: Option<bool>,
    #[schemars(description = "Optional event description")]
    pub(crate) description: Option<String>,
    #[schemars(description = "Optional event location")]
    pub(crate) location: Option<String>,
    #[schemars(
        description = "Optional URL associated with the event (e.g. meeting link, ticket URL)"
    )]
    pub(crate) url: Option<String>,
    #[schemars(description = "Optional hex color")]
    pub(crate) color: Option<String>,
    #[schemars(description = "Event type: event (default), birthday, anniversary, memorial")]
    pub(crate) event_type: Option<CalendarEventTypeArg>,
    #[schemars(description = "Person name for people-centric events (birthdays, anniversaries)")]
    pub(crate) person_name: Option<String>,
    #[schemars(description = "Optional attendees list: [{email, name?, status?}]")]
    pub(crate) attendees: Option<Vec<AttendeeInput>>,
}

#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum RecurringCalendarEventScopeArg {
    AllInSeries,
    ThisOnly,
    ThisAndFollowing,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct ScopedCalendarEventEditArgs {
    #[schemars(description = "Recurring calendar event ID")]
    pub(crate) id: String,
    #[schemars(description = "Occurrence date to edit in YYYY-MM-DD")]
    pub(crate) occurrence_date: String,
    #[schemars(description = "Scope: all_in_series, this_only, or this_and_following")]
    pub(crate) scope: RecurringCalendarEventScopeArg,
    #[schemars(description = "Full replacement event payload for the edited occurrence or series")]
    pub(crate) payload: CreateCalendarEventArgs,
    #[schemars(description = "If true, preview the scoped edit and roll back. Default false.")]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct ScopedCalendarEventDeleteArgs {
    #[schemars(description = "Recurring calendar event ID")]
    pub(crate) id: String,
    #[schemars(description = "Occurrence date to delete in YYYY-MM-DD")]
    pub(crate) occurrence_date: String,
    #[schemars(description = "Scope: all_in_series, this_only, or this_and_following")]
    pub(crate) scope: RecurringCalendarEventScopeArg,
    #[schemars(description = "If true, preview the scoped delete and roll back. Default false.")]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

/// MCP tool args for `update_calendar_event`.
///
/// The 15 patchable wire fields are flattened in from the canonical
/// [`CalendarEventUpdateWire`] in `lorvex-sync-payload` so the Tauri,
/// MCP, and CLI surfaces share a single source of truth for the
/// shape (#4521). The MCP-only `idempotency_key`, `dry_run`, and
/// `include_diff` fields sit at the top level here because they're
/// MCP-tool affordances rather than parts of the wire contract.
///
/// Trust-boundary parses left to the handler: the raw `event_type`
/// and PARTSTAT strings on the wire are converted into typed
/// [`CanonicalCalendarEventType`] / [`AttendeeStatus`] values at the
/// adapter step in `mutations::update`.
/// carried `Patch<CalendarEventTypeArg>` / `AttendeeStatusArg`; both
/// rejected the same set of invalid strings, just at the serde-parse
/// layer instead of the workflow-lift layer.
#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct UpdateCalendarEventArgs {
    #[serde(flatten)]
    pub(crate) wire: CalendarEventUpdateWire,
    // #3029-M4: optional idempotency token. Cf.
    // `BatchCompleteTasksArgs`. A retry without this key re-stamps
    // the same patch and writes a duplicate audit row.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate updates; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
    // -M7: dry_run preview affordance.
    // returned only the post-update row, so the assistant could not
    // show a before/after diff for a series-rescheduling preview
    // even though the changelog stored both snapshots.
    #[schemars(
        description = "If true, run the patch in a rolled-back savepoint and return the would-be response with `dry_run: true` (no commit). Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    // #3033-M7: include_diff flag. When true the response also
    // carries `before` and `after` snapshots of the calendar event
    // row so the assistant can render a structured diff (or compute
    // its own diff) without an extra round-trip. Defaults to false
    // to preserve the lean response shape for callers that only
    // want the post-update payload.
    #[schemars(
        description = "If true, the response includes `before` (pre-update snapshot) and `after` (post-update snapshot) so the assistant can render a before/after diff. Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) include_diff: bool,
}

// Serialize required so the idempotency-cache checksum
// (`canonical_request_repr`) can fingerprint the call. The shape
// includes an `idempotency_key` field aligned with every other
// destructive calendar tool (`update_calendar_event`,
// `add_event_exception`, `remove_event_exception`,
// `link_task_to_event`, `unlink_task_from_event`,
// `batch_link_tasks_to_event`, `batch_create_calendar_events`).
#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct DeleteCalendarEventArgs {
    #[schemars(description = "Calendar event ID to delete")]
    pub(crate) id: String,
    // calendar event delete cascades through
    // task_calendar_event_links (per-edge tombstones), recurrence
    // exceptions, and provider links — destructive enough that the
    // assistant should preview the cascade (`unlinked_task_ids`)
    // before committing.
    #[schemars(
        description = "Issue #3019-H5: if true, run the delete (incl. cascade through task_calendar_event_links, recurrence exceptions, provider links) and return the would-be shape with `dry_run: true`, then roll back. Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(description = IDEMPOTENCY_KEY_DESCRIPTION)]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchCreateCalendarEventsArgs {
    // The element type is the same `CreateCalendarEventArgs` struct
    // the single-create tool consumes; the event shape is one
    // canonical contract shared by both surfaces.
    #[schemars(description = "Calendar events to create")]
    pub(crate) events: Vec<CreateCalendarEventArgs>,
    #[schemars(
        description = "Issue #2370: if true, run the inserts in a rolled-back savepoint and return the would-be calendar_events payload (with freshly-minted IDs) tagged `dry_run: true`. Default false."
    )]
    // schemars default mirrors serde's default so
    // strict assistant clients don't reject calls that omit the
    // field.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    // optional idempotency token mirroring
    // `batch_create_tasks`. A transport flake on the response leg
    // would otherwise produce duplicate calendar events on retry.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate creates; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
