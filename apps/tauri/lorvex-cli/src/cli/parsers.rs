//! Parser combinators for clap `value_parser` attributes. Each function
//! validates a raw `&str` argument and returns a typed value or a
//! human-readable error message that clap prints to stderr.
//!
//! Whitespace policy: every parser that accepts free
//! form text or a structured value MUST trim ASCII whitespace before
//! validating, and MUST reject input that becomes empty after the trim.
//! The shared `trim_required` helper enforces the contract once and the
//! per-parser sites call it before their own validation step, so a
//! stray leading space cannot turn a valid arg into a parse error with
//! a confusing "got \" 2026-05-01\"" message.

/// Trim ASCII whitespace from `raw` and reject the result if empty.
/// Returns the trimmed slice on success and a clap-friendly error
/// message on failure. Centralizing the trim+nonempty check keeps the
/// per-parser sites a single line shorter and prevents drift.
fn trim_required<'a>(raw: &'a str, field: &str) -> Result<&'a str, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(format!("{field} must not be empty"));
    }
    Ok(trimmed)
}

pub(super) fn parse_positive_u32(raw: &str) -> Result<u32, String> {
    let value = raw
        .parse::<u32>()
        .map_err(|_| format!("expected a positive integer, got {raw:?}"))?;
    if value == 0 {
        Err("value must be >= 1".to_string())
    } else {
        Ok(value)
    }
}

/// Parse a single `BYMONTHDAY` value: an integer in `-31..=31`,
/// excluding `0`. Negative values count back from the end of the month
/// (`-1` = last day), matching the `[i64]` wire model. Used with clap's
/// `value_delimiter = ','` so `--bymonthday=1,15,-1` yields the full
/// day array; `lorvex_domain::validation` re-validates the assembled
/// rule (sort/dedup, FREQ compatibility) downstream.
pub(super) fn parse_bymonthday(raw: &str) -> Result<i64, String> {
    let trimmed = trim_required(raw, "bymonthday")?;
    let value = trimmed
        .parse::<i64>()
        .map_err(|_| format!("expected an integer in -31..=31 (excluding 0), got {raw:?}"))?;
    if value == 0 || !(-31..=31).contains(&value) {
        return Err("bymonthday must be an integer in -31..=31, excluding 0".to_string());
    }
    Ok(value)
}

pub(super) fn parse_positive_i64(raw: &str) -> Result<i64, String> {
    let value = raw
        .parse::<i64>()
        .map_err(|_| format!("expected a positive integer, got {raw:?}"))?;
    if value < 1 {
        Err("value must be >= 1".to_string())
    } else {
        Ok(value)
    }
}

pub(super) fn parse_hex_color(raw: &str) -> Result<String, String> {
    // Delegate to `lorvex_domain::validation::validate_hex_color`,
    // the single canonical hex-color validator. The 3-digit short form
    // (`#FFF`) and the 6-digit form (`#4A90D9`) both validate, matching
    // the calendar writer's acceptance set so user-imported feeds with
    // short-form colors are not rejected at the CLI argument parser
    // while accepted downstream.
    lorvex_domain::validation::validate_hex_color(raw)
        .map(|()| raw.to_string())
        .map_err(|_| format!("expected hex color like #4A90D9 or #FFF, got {raw:?}"))
}

pub(super) fn parse_habit_frequency_type(raw: &str) -> Result<String, String> {
    match raw {
        "daily" | "weekly" | "monthly" | "times_per_week" => Ok(raw.to_string()),
        _ => Err(format!(
            "frequency_type must be one of: daily, weekly, monthly, times_per_week. Got: {raw}"
        )),
    }
}

pub(super) fn parse_priority(raw: &str) -> Result<i64, String> {
    let trimmed = trim_required(raw, "priority")?;
    let value = trimmed
        .parse::<i64>()
        .map_err(|_| format!("expected an integer priority, got {trimmed:?}"))?;
    lorvex_domain::validation::validate_priority(value).map_err(|e| e.to_string())?;
    Ok(value)
}

pub(super) fn parse_task_priority(raw: &str) -> Result<u8, String> {
    let value = parse_priority(raw)?;
    u8::try_from(value).map_err(|_| format!("priority is out of range ({value}, must be 1..=3)"))
}

pub(super) fn parse_task_status_filter(raw: &str) -> Result<String, String> {
    match raw {
        "open" | "completed" | "cancelled" | "someday" | "all" => Ok(raw.to_string()),
        _ => Err(format!(
            "status must be one of: open, completed, cancelled, someday, all. Got: {raw}"
        )),
    }
}

/// allowlist parser for `task update --status`.
/// Distinct from `parse_task_status_filter` (used by *query* args)
/// because `all` is meaningless when patching a single task. Mirrors
/// the four canonical status values defined in
/// `lorvex_domain::naming::{STATUS_OPEN,STATUS_COMPLETED,STATUS_CANCELLED,STATUS_SOMEDAY}`.
pub(super) fn parse_task_status_value(raw: &str) -> Result<String, String> {
    match raw {
        "open" | "completed" | "cancelled" | "someday" => Ok(raw.to_string()),
        _ => Err(format!(
            "status must be one of: open, completed, cancelled, someday. Got: {raw}"
        )),
    }
}

pub(super) fn parse_task_sort_by(raw: &str) -> Result<String, String> {
    match raw {
        "priority_due" | "due_date" | "planned_date" | "updated_at" | "created_at" | "title" => {
            Ok(raw.to_string())
        }
        _ => Err(format!(
            "sort_by must be one of: priority_due, due_date, planned_date, updated_at, created_at, title. Got: {raw}"
        )),
    }
}

pub(super) fn parse_sort_direction(raw: &str) -> Result<String, String> {
    match raw {
        "asc" | "desc" => Ok(raw.to_string()),
        _ => Err(format!("sort direction must be asc or desc. Got: {raw}")),
    }
}

/// Clap value-parser for `--date` / `--due-date` / `--planned-date` / etc.
///
/// Renamed (#3022 M2) from the ambiguous `parse_date`. The store layer
/// has its own `parse_date` helpers (now folded into the shared
/// recurrence-exceptions engine and `lorvex_domain::time::parse_iso_date`),
/// so the CLI surface keeps a `_cli_date_arg` suffix to make the
/// shape obvious at every `value_parser =` call site.
pub(super) fn parse_cli_date_arg(raw: &str) -> Result<String, String> {
    let trimmed = trim_required(raw, "date")?;
    lorvex_domain::validation::validate_date_format(trimmed).map_err(|e| e.to_string())?;
    Ok(trimmed.to_string())
}

pub(super) fn parse_review_scale(raw: &str) -> Result<u8, String> {
    let value = raw
        .parse::<u8>()
        .map_err(|_| format!("expected a 1..=5 score, got {raw:?}"))?;
    if (1..=5).contains(&value) {
        Ok(value)
    } else {
        Err(format!("expected a 1..=5 score, got {value}"))
    }
}

pub(super) fn parse_time(raw: &str) -> Result<String, String> {
    let trimmed = trim_required(raw, "time")?;
    lorvex_domain::validation::validate_time_format(trimmed).map_err(|e| e.to_string())?;
    Ok(trimmed.to_string())
}

pub(super) fn parse_estimated_minutes(raw: &str) -> Result<i64, String> {
    let trimmed = trim_required(raw, "estimated minutes")?;
    let value = trimmed
        .parse::<i64>()
        .map_err(|_| format!("expected an integer minute estimate, got {trimmed:?}"))?;
    lorvex_domain::validation::validate_estimated_minutes(value).map_err(|e| e.to_string())?;
    Ok(value)
}

pub(super) fn parse_tag(raw: &str) -> Result<String, String> {
    // Route trim+nonempty through the shared helper so the policy stays
    // centralized and every parser site shares `trim_required`'s
    // contract.
    let tag = trim_required(raw, "tag")?;
    let char_count = tag.chars().count();
    if char_count > lorvex_domain::validation::MAX_TAG_NAME_LENGTH {
        return Err(format!(
            "tag is too long ({char_count}, max {})",
            lorvex_domain::validation::MAX_TAG_NAME_LENGTH
        ));
    }
    Ok(tag.to_string())
}

/// typed enum for ID-shaped CLI arguments.
///
/// Replaces the prior `field: &str` discriminator pattern (where the
/// inbox-sentinel carve-out keyed off the literal string `"list id"`
/// — renaming the label silently dropped the carve-out, and a typo
/// in any other call site silently disabled validation).
///
/// Each variant carries:
/// - a stable human-readable label (`as_label`) used in error messages
///   and aligned with the MCP server's `validate_uuid_shape` and the
///   Tauri `validate_uuid_id` wording for cross-surface parity;
/// - an `accepts_inbox_sentinel` policy flag — only `ListId` opts in,
///   because the schema seeds `INBOX_LIST_ID` ("inbox") as the canonical
///   default list. No other entity (`task`, `event`, `habit`, `policy`,
///   `revision`, `reminder`, `dependency task`, `checklist item`) has a
///   sentinel-named instance.
// Every variant intentionally ends in `Id`: at call-sites the type
// reads `IdKind::ListId`, `IdKind::TaskId`, …, which mirrors the
// human-readable label the parser emits in error messages and the
// `parse_<kind>_id` helper names below. Stripping the suffix would
// only obscure that intent at the call-site for no real benefit.
#[allow(clippy::enum_variant_names)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum IdKind {
    ListId,
    TaskId,
    ChecklistItemId,
    HabitId,
    PolicyId,
    EventId,
    ReminderId,
    RevisionId,
    DependencyTaskId,
}

impl IdKind {
    /// Human-readable field label used in clap error messages. Aligned
    /// with the MCP server's `validate_uuid_shape` and the Tauri
    /// `validate_uuid_id` so every surface emits the same sentence on
    /// rejection.
    pub(super) const fn as_label(self) -> &'static str {
        match self {
            Self::ListId => "list id",
            Self::TaskId => "task id",
            Self::ChecklistItemId => "checklist item id",
            Self::HabitId => "habit id",
            Self::PolicyId => "policy id",
            Self::EventId => "event id",
            Self::ReminderId => "reminder id",
            Self::RevisionId => "revision id",
            Self::DependencyTaskId => "dependency task id",
        }
    }

    /// only `ListId` accepts the schema-seeded
    /// `INBOX_LIST_ID` sentinel. Every other ID-shaped field rejects
    /// non-UUID input.
    const fn accepts_inbox_sentinel(self) -> bool {
        matches!(self, Self::ListId)
    }
}

/// validate a UUIDv7-shaped id at the trust boundary
/// so a typo or malformed identifier never reaches the repositories.
///
/// the three trust-boundary UUID validators (Tauri
/// `validate_uuid_id`, MCP `validate_uuid_shape`, this `parse_uuid_id`)
/// were promoted to
/// [`lorvex_domain::entity_id::parse_id_with_sentinel`]. The CLI
/// keeps its `IdKind` policy enum (the inbox-sentinel carve-out is
/// expressed via [`IdKind::accepts_inbox_sentinel`] so the literal-
/// string match in #2998-H8 stays gone) and routes through the
/// canonical helper. The wording the wrapper emits is byte-identical
/// to the issue #2994 H5 standard, preserved by the typed
/// `ValidationError` translation below.
pub(super) fn parse_uuid_id(raw: &str, kind: IdKind) -> Result<String, String> {
    use lorvex_domain::validation::ValidationError;
    let field = kind.as_label();
    // Trim before delegation so a stray
    // leading/trailing space lands in the same "must not be empty"
    // bucket as a literal empty string instead of falling through to
    // the underlying parser as an invalid-format rejection.
    let trimmed = trim_required(raw, field)?;
    let sentinel = kind
        .accepts_inbox_sentinel()
        .then_some(lorvex_store::INBOX_LIST_ID);
    lorvex_domain::entity_id::parse_id_with_sentinel(trimmed, field, sentinel).map_err(|err| {
        match err {
            ValidationError::Empty(_) => format!("{field} must not be empty"),
            ValidationError::InvalidFormat { actual, .. } => {
                format!("{field} is not a valid UUID: '{actual}'")
            }
            other => other.to_string(),
        }
    })
}

pub(super) fn parse_dependency_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::DependencyTaskId)
}

/// validate a task id at the trust boundary.
pub(super) fn parse_task_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::TaskId)
}

/// validate a checklist item id.
pub(super) fn parse_checklist_item_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::ChecklistItemId)
}

/// validate a list id (with inbox sentinel
/// carve-out per `IdKind::accepts_inbox_sentinel`).
pub(super) fn parse_list_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::ListId)
}

/// validate a habit id.
pub(super) fn parse_habit_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::HabitId)
}

/// validate a calendar event id.
pub(super) fn parse_event_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::EventId)
}

/// validate a task reminder id.
pub(super) fn parse_reminder_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::ReminderId)
}

/// validate a habit reminder policy id.
pub(super) fn parse_policy_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::PolicyId)
}

/// validate a memory revision id.
pub(super) fn parse_revision_id(raw: &str) -> Result<String, String> {
    parse_uuid_id(raw, IdKind::RevisionId)
}

pub(super) fn parse_calendar_event_type(raw: &str) -> Result<String, String> {
    match raw {
        "event" | "birthday" | "anniversary" | "memorial" => Ok(raw.to_string()),
        _ => Err(format!(
            "event_type must be one of: event, birthday, anniversary, memorial. Got: {raw}"
        )),
    }
}

pub(super) fn parse_rfc3339_timestamp(raw: &str) -> Result<String, String> {
    let trimmed = trim_required(raw, "timestamp")?;
    chrono::DateTime::parse_from_rfc3339(trimmed)
        .map(|_| trimmed.to_string())
        .map_err(|_| {
            format!("invalid RFC 3339 timestamp {trimmed:?}; expected e.g. 2026-05-01T09:00:00Z")
        })
}

pub(super) fn parse_timezone(raw: &str) -> Result<String, String> {
    // Reuse `trim_required` so every parser's empty/whitespace contract
    // collapses through the same branch; the message wording is preserved.
    let trimmed = trim_required(raw, "timezone")?;
    lorvex_domain::normalize_timezone_name(Some(trimmed))
        .ok_or_else(|| "expected valid IANA timezone like America/Los_Angeles".to_string())
}

#[cfg(test)]
mod whitespace_policy_tests {
    //! M1. Pin the contract that every
    //! free-form / structured CLI parser trims ASCII whitespace
    //! before validating its content AND rejects an input that
    //! becomes empty after the trim. A regression here would
    //! re-introduce the inconsistency where `parse_tag` /
    //! `parse_timezone` accepted `" foo "` while `parse_priority`
    //! / `parse_cli_date_arg` / etc. rejected the same shape with a
    //! confusing "expected an integer, got \" 1\"" / "invalid date
    //! format" message.
    use super::*;

    #[test]
    fn parse_priority_accepts_padded_value_and_rejects_empty_post_trim() {
        assert_eq!(parse_priority("  2  ").unwrap(), 2);
        let err = parse_priority("   ").unwrap_err();
        assert!(err.contains("priority must not be empty"), "{err}");
        let err = parse_priority("").unwrap_err();
        assert!(err.contains("priority must not be empty"), "{err}");
    }

    #[test]
    fn parse_estimated_minutes_accepts_padded_value_and_rejects_empty_post_trim() {
        assert_eq!(parse_estimated_minutes(" 45\t").unwrap(), 45);
        let err = parse_estimated_minutes("\t \n").unwrap_err();
        assert!(err.contains("estimated minutes must not be empty"), "{err}");
    }

    #[test]
    fn parse_cli_date_arg_accepts_padded_value_and_rejects_empty_post_trim() {
        assert_eq!(parse_cli_date_arg("  2026-05-01 ").unwrap(), "2026-05-01");
        let err = parse_cli_date_arg("   ").unwrap_err();
        assert!(err.contains("date must not be empty"), "{err}");
    }

    #[test]
    fn parse_time_accepts_padded_value_and_rejects_empty_post_trim() {
        assert_eq!(parse_time(" 09:30 ").unwrap(), "09:30");
        let err = parse_time("\t").unwrap_err();
        assert!(err.contains("time must not be empty"), "{err}");
    }

    #[test]
    fn parse_uuid_id_accepts_padded_value_and_rejects_empty_post_trim() {
        let uuid = "0190abcd-1111-7222-8333-444455556666";
        let padded = format!(" {uuid} ");
        assert_eq!(parse_uuid_id(&padded, IdKind::TaskId).unwrap(), uuid);
        let err = parse_uuid_id("   ", IdKind::TaskId).unwrap_err();
        assert!(err.contains("task id must not be empty"), "{err}");
    }

    #[test]
    fn parse_rfc3339_timestamp_accepts_padded_value_and_rejects_empty_post_trim() {
        assert_eq!(
            parse_rfc3339_timestamp(" 2026-05-01T09:00:00Z ").unwrap(),
            "2026-05-01T09:00:00Z"
        );
        let err = parse_rfc3339_timestamp("   ").unwrap_err();
        assert!(err.contains("timestamp must not be empty"), "{err}");
    }
}
