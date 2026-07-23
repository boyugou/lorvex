// trust: tests intentionally use unwrap() / expect() for assertion clarity —
// panics there ARE the failure mode.
#![cfg_attr(test, allow(clippy::unwrap_used))]

//! `lorvex-domain` — Pure domain logic for Lorvex.
//!
//! This crate contains types, validation, merge policy, HLC, and canonical
//! naming constants. It has ZERO IO/storage dependencies (no rusqlite, no
//! tokio, no reqwest).
//!
//! ## Modules
//!
//! See the module index below — every `pub mod` in this crate is a
//! self-contained domain concern with its own crate-level rustdoc.
//! The rustdoc-generated index is the single source of truth for the
//! module list; an inlined hand-maintained copy here would drift on
//! every refactor.

pub mod attendee_identity;
pub mod attendee_status;
pub mod calendar;
pub mod calendar_ics;
pub mod canonical_json;
pub mod capability;
pub mod checklist;
pub mod content_limits;
pub mod defaults;
pub mod diagnostics;
pub mod dst;
pub mod entity_id;
pub mod focus_block;
pub mod fts;
pub mod habits;
pub mod hlc;
pub mod hlc_observer;
pub mod hlc_session;
pub mod hlc_state;
pub mod ids;
pub mod memory;
pub mod merge;
pub mod naming;
pub mod parsing;
pub mod patch;
pub mod preference_keys;
pub mod provider_kind;
pub mod provider_link;
pub mod query;
pub mod recurrence;
pub mod serde_support;
pub mod setup;
pub mod sql;
pub mod status_transition;
pub mod storage_schema;
pub mod tag;
pub mod text_sanitize;
pub mod time;
pub mod unicode_hygiene;
pub mod validation;
pub mod version;

// ---------------------------------------------------------------------------
// Convenience re-exports for downstream crates
// ---------------------------------------------------------------------------

pub use attendee_status::{
    attendee_status_allowlist_display, AttendeeStatus, ATTENDEE_STATUS_ALLOWLIST,
};
pub use calendar::{
    AllDayPatch, CalendarEventTiming, CalendarEventTimingFlat, CanonicalCalendarEventType,
};
pub use provider_kind::{
    is_allowed_provider_kind, provider_kind_allowlist_display, PROVIDER_KIND_ALLOWLIST,
    PROVIDER_KIND_EVENTKIT, PROVIDER_KIND_GOOGLE_CALENDAR, PROVIDER_KIND_ICAL_SUBSCRIPTION,
    PROVIDER_KIND_ICS, PROVIDER_KIND_LINUX_ICS, PROVIDER_KIND_OUTLOOK,
    PROVIDER_KIND_WINDOWS_APPOINTMENTS,
};
// `validate_export_range` reaches three callers via this façade
// (`lorvex-cli/src/db_ops/calendar/mod.rs`, `mcp-server/src/calendar/ics.rs`,
// `app/src-tauri/src/commands/calendar/events/ics_export.rs`); the rest of the
// crate's surface stays module-pathed (`lorvex_domain::calendar_ics::*`).
// `CalendarIcsError` and `CalendarIcsEvent` are reached via module path.
pub use calendar_ics::{export_calendar_ics, validate_export_range};
// `MAX_TASK_CHECKLIST_ITEMS`, `MAX_TASK_CHECKLIST_ITEM_TEXT_LENGTH`,
// `ExtractedMarkdownChecklistItem`, `MarkdownChecklistExtraction`, and
// `extract_markdown_checklist` are reached via module path
// (`lorvex_domain::checklist::*`) — re-add to this façade if a high-traffic
// flat caller appears.
pub use checklist::{validate_task_checklist_item_count, validate_task_checklist_item_text};
// `ClampOutcome` is reached via module path
// (`lorvex_domain::content_limits::ClampOutcome`); `clamp_to_byte_limit`
// consumers destructure inline and never name the enum.
pub use content_limits::clamp_to_byte_limit;
pub use defaults::{DEFAULT_WORKING_HOURS_END, DEFAULT_WORKING_HOURS_START};
// Canonical UUIDv7 entity-id minter. Every entity created across
// `lorvex-store`, `lorvex-sync`, `lorvex-cli`, the Tauri app, and the
// MCP server routes through this single helper so a future swap to a
// different k-sortable variant patches one place. See
// `entity_id.rs` rustdoc for the format guarantees.
pub use entity_id::{new_entity_id_string, validate_sync_entity_id_for_kind};
// `dst::*` consumers use the module path
// (`lorvex_domain::dst::{resolve_local_datetime, DstResolution}`).
pub use focus_block::FocusBlockType;
pub use fts::{
    contains_cjk, sanitize_fts_query, short_trailing_token_for_like_retry, should_use_like_fallback,
};
// `WeekDay` is reached via the module path (`lorvex_domain::habits::WeekDay`).
pub use habits::{
    habit_expected_completions_in_days, habit_progress_kind, habit_required_completions_per_period,
    habit_uses_week_bucket, is_habit_scheduled_on_day, HabitCadence, HabitFrequencyType,
    HabitProgressKind,
};
pub use naming::CalendarAiAccessMode;
// Keep this root prelude limited to the high-traffic flat helpers.
// Typed parser variants and result enums live under
// `lorvex_domain::parsing::*` so callers opt in explicitly instead of
// growing a parallel compatibility surface at the crate root.
pub use parsing::{
    decode_hlc_cursor_projection, escape_like, format_minutes_hhmm, parse_hhmm_to_minutes,
    parse_hlc_cursor_projection_state, parse_json_bool_preference, parse_json_string_field,
    parse_json_string_preference, parse_optional_bool_state, parse_optional_i64_state,
    parse_optional_rfc3339_state, parse_positive_i64_preference, JsonStringFieldError,
    SyncBackendKind,
};
pub use patch::Patch;
// `effective_action_date`, `is_deadline_overdue`, `is_today_pool_task`, and
// `is_upcoming_task` are reached via the module path (`lorvex_domain::query::*`).
pub use query::{derive_open_task_lateness, TaskLateness};
// `SetupReadiness` is reached via the module path
// (`lorvex_domain::setup::SetupReadiness`).
pub use setup::{derive_setup_readiness, SetupReadinessInput};
pub use sql::{sql_csv_placeholders, sql_in_placeholders};
pub use time::{
    canonicalize_rfc3339_instant, date_plus_days_ymd_for_timezone_name, format_sync_timestamp,
    format_sync_timestamp_from_unix_ms, normalize_sync_timestamp, normalize_timezone_name,
    parse_json_timezone_preference, parse_required_timezone_preference, parse_timezone_name,
    resolve_anchored_timezone_name, sync_timestamp_now, today_ymd_for_timezone_name, Date, DueAt,
    DueAtFlat, SyncTimestamp, SyncTimestampParseError, TimeOfDay,
};
// Issue #3285: typed entity-id newtypes are re-exported flat because
// they appear in nearly every storage / sync / wire signature. Reaching
// for `lorvex_domain::ids::TaskId` per call site would clutter every
// import; the flat re-export matches the convention used for other
// high-traffic types (`SyncTimestamp`, `ValidationError`, …).
pub use ids::{
    ChecklistItemId, CompositeEdgeIdParseError, EventId, HabitId, HabitReminderPolicyId, ListId,
    MemoryKey, MemoryRevisionId, ReminderId, TagId, TaskDependencyEdgeId, TaskId, TaskTagEdgeId,
};
pub use unicode_hygiene::{sanitize_user_text, sanitize_user_text_in_json_in_place};
pub use validation::assert_safe_sql_identifier;
