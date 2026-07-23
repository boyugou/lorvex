mod calendar;
mod defaults;
mod habits;
mod observability;
mod preferences;
mod task;
mod ui_control;
mod workflow;

pub(crate) use calendar::*;
pub(crate) use defaults::*;
pub(crate) use habits::*;
pub(crate) use observability::*;
pub(crate) use preferences::*;
pub(crate) use task::*;
pub(crate) use ui_control::*;
pub(crate) use workflow::*;

pub(crate) const MCP_RESULT_LIMIT_CAP: u32 = 500;
pub(crate) const LIST_TASKS_LIMIT_DEFAULT: u32 = 100;
pub(crate) const SEARCH_TASKS_LIMIT_DEFAULT: u32 = 50;
pub(crate) const DEFERRED_TASKS_LIMIT_DEFAULT: u32 = 100;
pub(crate) const GET_TODAYS_LIMIT_PER_BUCKET_DEFAULT: u32 = 100;
pub(crate) const GET_TODAYS_LIMIT_PER_BUCKET_CAP: u32 = 500;
pub(crate) const GET_UPCOMING_DAYS_DEFAULT: u32 = 7;
pub(crate) const GET_UPCOMING_LIMIT_DEFAULT: u32 = 200;
pub(crate) const GET_UPCOMING_LIMIT_CAP: u32 = 1000;
pub(crate) const GET_LIST_LIMIT_DEFAULT: u32 = 250;
pub(crate) const GET_LIST_LIMIT_CAP: u32 = 1000;
pub(crate) const LIST_HEALTH_LIMIT_DEFAULT: u32 = 50;
pub(crate) const LIST_HEALTH_LIMIT_CAP: u32 = 200;
pub(crate) const REVIEW_HISTORY_LIMIT_DEFAULT: u32 = 14;
pub(crate) const REVIEW_HISTORY_LIMIT_CAP: u32 = 90;
pub(crate) const AI_CHANGELOG_LIMIT_DEFAULT: u32 = 50;
pub(crate) const AI_CHANGELOG_LIMIT_CAP: u32 = 200;
pub(crate) const WEEKLY_BRIEF_LIMIT_CAP: u32 = 500;
pub(crate) const WEEKLY_BRIEF_COMPLETED_DEFAULT: u32 = 50;
pub(crate) const WEEKLY_BRIEF_STALLED_DEFAULT: u32 = 50;
pub(crate) const WEEKLY_BRIEF_DEFERRED_DEFAULT: u32 = 10;
pub(crate) const WEEKLY_BRIEF_SOMEDAY_DEFAULT: u32 = 20;
pub(crate) const CALENDAR_EVENTS_LIMIT_DEFAULT: u32 = 200;
pub(crate) const CALENDAR_EVENTS_LIMIT_CAP: u32 = 1000;
pub(crate) const TASKS_BY_TAG_LIMIT_DEFAULT: u32 = 100;
pub(crate) const RECENT_LOG_LIMIT_DEFAULT: u32 = 100;
pub(crate) const RECENT_LOG_LIMIT_CAP: u32 = 500;
pub(crate) const RECENT_LOG_FETCH_MIN: u32 = 150;
pub(crate) const RECENT_LOG_FETCH_CAP: u32 = 1000;
// ── String length caps (defense-in-depth) ───────────────────────────
// the body/title/ai_notes limits are canonical in
// lorvex-domain. Re-export them here instead of shadowing to prevent
// the drift this audit tracks.
/// Title fields: task title, list name, calendar event title, habit name.
pub(crate) const MAX_TITLE_LENGTH: usize = lorvex_domain::validation::MAX_TITLE_LENGTH;
/// Body/description fields: task body, calendar event description.
pub(crate) const MAX_BODY_LENGTH: usize = lorvex_domain::validation::MAX_BODY_LENGTH;
/// List description cap. Short metadata, not
/// free-form prose — capped much smaller than task body.
pub(crate) const MAX_LIST_DESCRIPTION_LENGTH: usize =
    lorvex_domain::validation::MAX_LIST_DESCRIPTION_LENGTH;
/// AI notes fields: task ai_notes, list ai_notes, daily review ai_synthesis.
pub(crate) const MAX_AI_NOTES_LENGTH: usize = 50_000;
/// Short metadata fields: tags (each), color, icon, raw_input, reason, etc.
/// Single source of truth at the canonical
/// `lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH` so the literal
/// `2_000` lives in one place;
/// here AND a few sites already imported the domain version directly,
/// creating a two-path drift hazard.
pub(crate) const MAX_SHORT_TEXT_LENGTH: usize = lorvex_domain::validation::MAX_SHORT_TEXT_LENGTH;
/// Memory section content. Hoisted to `lorvex-domain` so the sync apply
/// pipeline can enforce the same cap on incoming envelopes (#2429).
pub(crate) const MAX_MEMORY_CONTENT_LENGTH: usize =
    lorvex_domain::memory::MAX_MEMORY_CONTENT_LENGTH;
// Memory section key, preference key, preference value: import the
// canonical `KV_KEY_MAX_CHARS` / `KV_VALUE_MAX_BYTES` from
// `lorvex_domain::validation::limits` directly at call sites — no
// re-aliasing here, so the symbol used at the validation site is the
// same name a reader would grep for in the domain crate.
/// Feedback detail, daily review prose fields (summary, wins, blockers, learnings).
pub(crate) const MAX_LONG_TEXT_LENGTH: usize = 50_000;
/// Briefing text (current focus, focus schedule).
pub(crate) const MAX_BRIEFING_LENGTH: usize = 10_000;
pub(crate) const DUE_REMINDERS_LIMIT_DEFAULT: u32 = 50;
pub(crate) const DUE_REMINDERS_LIMIT_CAP: u32 = 200;
pub(crate) const UPCOMING_REMINDERS_HOURS_DEFAULT: u32 = 24;
pub(crate) const UPCOMING_REMINDERS_HOURS_CAP: u32 = 168;
pub(crate) const UPCOMING_REMINDERS_LIMIT_DEFAULT: u32 = 50;
pub(crate) const UPCOMING_REMINDERS_LIMIT_CAP: u32 = 200;
pub(crate) const DEPENDENCY_GRAPH_LIMIT_NODES_DEFAULT: u32 = 100;
pub(crate) const DEPENDENCY_GRAPH_LIMIT_NODES_CAP: u32 = 500;
pub(crate) const DEPENDENCY_GRAPH_LIMIT_EDGES_DEFAULT: u32 = 500;
pub(crate) const DEPENDENCY_GRAPH_LIMIT_EDGES_CAP: u32 = 2000;
pub(crate) const TASK_PATTERN_ANALYSIS_WINDOW_DEFAULT: u32 = 14;
pub(crate) const TASK_PATTERN_ANALYSIS_WINDOW_CAP: u32 = 90;
pub(crate) const TASK_PATTERN_ANALYSIS_TOP_N_DEFAULT: u32 = 5;
pub(crate) const TASK_PATTERN_ANALYSIS_TOP_N_CAP: u32 = 20;
pub(crate) const CALENDAR_RECURRENCE_FIELD_DESCRIPTION: &str = concat!(
    "Recurrence as either a plain string DAILY|WEEKLY|MONTHLY|YEARLY",
    " or an RRULE-aligned JSON object string like ",
    "{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1,\"BYDAY\":[\"MO\",\"WE\"],\"UNTIL\":\"2026-03-31\"}",
    ". Optional fields: INTERVAL (default 1), BYDAY, BYMONTH, BYMONTHDAY, BYSETPOS, WKST, UNTIL (YYYY-MM-DD), COUNT (positive int, mutually exclusive with UNTIL).",
    " Field names follow RFC 5545 RRULE convention.",
);
// TASK_STATUS_ALLOWED_VALUES_DISPLAY removed —
// every consumer now works against the typed `TaskStatusValue` enum
// or threads through the canonical strings in
// `lorvex_domain::naming::STATUS_*`. The schema description below
// inlines the same allow-list wording so the JSON Schema still
// documents the four canonical values.
pub(crate) const TASK_STATUS_FIELD_DESCRIPTION: &str =
    "Task status. Supported values: open|completed|cancelled|someday.";
pub(crate) const TASK_PRIORITY_FIELD_DESCRIPTION: &str =
    "Task priority. Supported values: 1|2|3. Treat priority as importance-first, not urgency-first.";
pub(crate) const DUE_DATE_ALLOWED_INPUT_SUMMARY: &str =
    "YYYY-MM-DD, aliases today|tomorrow|yesterday, RFC3339 timestamps, or common date formats like YYYY/MM/DD, MM/DD/YYYY, and month-name dates";
pub(crate) const DUE_DATE_FIELD_DESCRIPTION: &str = concat!(
    "Due date. Accepted inputs: YYYY-MM-DD, aliases today|tomorrow|yesterday,",
    " RFC3339 timestamps, or common date formats like YYYY/MM/DD, MM/DD/YYYY, and month-name dates.",
);
pub(crate) const DUE_DATE_PATCH_FIELD_DESCRIPTION: &str = concat!(
    "Patch due_date. Accepted inputs: YYYY-MM-DD, aliases today|tomorrow|yesterday,",
    " RFC3339 timestamps, or common date formats like YYYY/MM/DD, MM/DD/YYYY, and month-name dates.",
    " Use null to clear.",
);
// `RECURRENCE_BYDAY_CODES_DISPLAY` retired —
// `set_recurrence` no longer hand-validates BYDAY tokens; the
// canonical `normalize_task_recurrence` owns the seven-code allow
// list (and the RFC 5545 ordinal-prefix grammar). The schema
// description below still inlines the same wording so the JSON
// Schema documents the codes.
pub(crate) const SET_RECURRENCE_BYDAY_FIELD_DESCRIPTION: &str =
    "Optional weekday codes for recurrence rules: SU|MO|TU|WE|TH|FR|SA. WEEKLY accepts bare codes; MONTHLY/YEARLY accept an optional [+-]?N prefix (e.g. '1MO' = first Monday) or pair bare codes with BYSETPOS.";
pub(crate) const SET_RECURRENCE_UNTIL_FIELD_DESCRIPTION: &str = "Optional end date in YYYY-MM-DD.";

/// Single source of truth for the `idempotency_key` schema description
/// reused across every retryable MCP tool. Centralizing the string
/// keeps the wording aligned across `preferences.rs`, `habits.rs`,
/// and `task/lists.rs` so a one-word edit lands once instead of three
/// times.
pub(crate) const IDEMPOTENCY_KEY_DESCRIPTION: &str =
    "Optional idempotency token. Clients that retry this tool after a transient failure should reuse the same key; the server short-circuits duplicates by returning the cached response for ~24h. Omit for non-retryable calls.";

#[cfg(test)]
mod tests;
