//! Shared validation rules for domain entities.
//!
//! These functions enforce business constraints (field lengths, value
//! ranges, format requirements) before data enters the domain layer. All
//! limits are expressed as public constants so that callers (MCP server,
//! Tauri commands, sync apply) can reference them for error messages or
//! client-side pre-checks.
//!
//! Per audit D2: each concern lives in its own submodule
//! (`limits`, `error`, `text`, `numeric`, `format`, `recurrence`,
//! `sql`) and the public surface is re-exported flat so existing call
//! sites (`lorvex_domain::validation::validate_title` etc.) keep
//! working without changes.

mod error;
mod format;
mod limits;
mod numeric;
mod recurrence;
mod sql;
mod text;

#[cfg(test)]
mod tests;

pub use error::ValidationError;
pub use format::{
    validate_calendar_date_range, validate_calendar_url, validate_date_format, validate_hex_color,
    validate_hex_color_field, validate_time_format, validate_user_url,
};
pub use limits::{
    KV_KEY_MAX_CHARS, KV_VALUE_MAX_BYTES, MAX_BODY_LENGTH, MAX_ESTIMATED_MINUTES,
    MAX_HABIT_CUE_LENGTH, MAX_LIST_DESCRIPTION_LENGTH, MAX_REMINDERS_PER_TASK,
    MAX_REMINDER_WINDOW_SECONDS, MAX_SHORT_TEXT_LENGTH, MAX_TAG_NAME_LENGTH, MAX_TASK_DEPENDENCIES,
    MAX_TASK_TAGS, MAX_TITLE_LENGTH, MEMORY_KEY_MAX_CHARS, MOOD_MAX, MOOD_MIN, PRIORITY_MAX,
    PRIORITY_MIN, TASK_PRIORITY_ALLOWED_VALUES_DISPLAY,
};
pub use numeric::{
    validate_estimated_minutes, validate_mood, validate_priority, validate_reminder_window,
};
pub use recurrence::{
    is_valid_byday_code, is_valid_byday_token_for_freq, is_valid_recurrence_freq,
    normalize_calendar_recurrence, normalize_task_recurrence,
    normalize_task_recurrence_with_warnings, RecurrenceWarning, MAX_CALENDAR_RECURRENCE_COUNT,
};
pub use sql::assert_safe_sql_identifier;
pub use text::{
    is_visually_empty, validate_body, validate_optional_string_length, validate_string_length,
    validate_tag_name, validate_title,
};
