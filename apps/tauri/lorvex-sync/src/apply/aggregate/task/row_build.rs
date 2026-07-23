//! Build a fully-typed [`TaskRow`] from a raw envelope payload.
//!
//! This module owns everything the upsert pipeline needs to do
//! between "JSON arrives over the wire" and "we are ready to bind
//! into SQL":
//!
//! 1. Parse the JSON.
//! 2. Tri-state every nullable column (absent / explicit-null /
//!    explicit-value) so partial-update envelopes preserve local
//!    values on field absence.
//! 3. Validate every scalar against the canonical domain bounds —
//!    same gates the MCP/Tauri/CLI write paths use.
//! 4. Apply the Unicode hygiene scrubber to free-text columns so a
//!    peer running an older / hostile build cannot smuggle bidi
//!    overrides, zero-width chars, or line separators into local
//!    tables.
//! 5. Resolve the `list_id` fallback (prefer the canonical inbox
//!    list, fall back to the oldest remaining list) when the peer
//!    omits the field.
//! 6. Split each tri-state into its `(value, present)` bind pair
//!    that the partial-update UPDATE template expects.
//!
//! The output [`TaskRow`] owns every string it carries so it can
//! outlive the original `serde_json::Value`. The upsert site binds
//! its fields straight into `named_params!` without any further
//! transformation, which keeps the parent file focused on dispatch.

use rusqlite::{Connection, OptionalExtension};

use lorvex_domain::ids::TaskId;

use super::super::super::ApplyError;
use super::super::helpers::{
    nullable_str_or_clear, optional_i64_preserving_null, optional_str,
    optional_str_preserving_empty, required_str, scrub, scrub_opt, split_partial_i64_value,
    split_partial_str_value, STATUS_CANCELLED, STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY,
};

/// Fully-typed row state ready to bind into the partial-update
/// UPDATE or the fresh-row INSERT.
///
/// Every nullable column travels as a `(value, present)` pair so
/// the UPDATE's `CASE WHEN :col_present THEN :col ELSE tasks.col END`
/// gate can preserve the local column when the envelope omits the
/// field. The INSERT path ignores the `_present` flags — absent /
/// explicit-clear both land as SQL NULL on a fresh row, which is
/// what the schema defaults model anyway.
///
/// Strings are owned (`Option<String>` rather than `Option<&str>`)
/// so the row outlives the `serde_json::Value` that backs it. The
/// scrubber returns a fresh allocation already, so no extra copy
/// happens here on the hot path.
#[cfg_attr(test, derive(Debug))]
pub(super) struct TaskRow {
    /// Typed task id. Constructed once at the apply handler entry
    /// via `TaskId::from_trusted` (issue #3285 phase 3) so the SQL
    /// `:id` bind in both the UPDATE and the fresh-row INSERT
    /// templates flows through the rusqlite ToSql impl on the
    /// newtype — zero `.as_str()` allocations on the upsert path,
    /// and a future mismatched-kind id can never silently slip
    /// into a task-shaped statement.
    pub(super) entity_id: TaskId,
    pub(super) title: String,
    pub(super) body: Option<String>,
    pub(super) body_present: i64,
    pub(super) raw_input: Option<String>,
    pub(super) raw_input_present: i64,
    pub(super) ai_notes: Option<String>,
    pub(super) ai_notes_present: i64,
    pub(super) status: String,
    pub(super) list_id: Option<String>,
    pub(super) priority: Option<i64>,
    pub(super) priority_present: i64,
    pub(super) due_date: Option<String>,
    pub(super) due_date_present: i64,
    pub(super) due_time: Option<String>,
    pub(super) due_time_present: i64,
    pub(super) estimated_minutes: Option<i64>,
    pub(super) estimated_minutes_present: i64,
    pub(super) recurrence: Option<String>,
    pub(super) recurrence_present: i64,
    pub(super) recurrence_exceptions: Option<String>,
    pub(super) recurrence_exceptions_present: i64,
    pub(super) spawned_from: Option<String>,
    pub(super) spawned_from_present: i64,
    pub(super) recurrence_group_id: Option<String>,
    pub(super) recurrence_group_id_present: i64,
    pub(super) canonical_occurrence_date: Option<String>,
    pub(super) canonical_occurrence_date_present: i64,
    pub(super) created_at: String,
    pub(super) updated_at: String,
    pub(super) completed_at: Option<String>,
    pub(super) completed_at_present: i64,
    pub(super) last_deferred_at: Option<String>,
    pub(super) last_deferred_at_present: i64,
    pub(super) last_defer_reason: Option<String>,
    pub(super) last_defer_reason_present: i64,
    pub(super) planned_date: Option<String>,
    pub(super) planned_date_present: i64,
    pub(super) available_from: Option<String>,
    pub(super) available_from_present: i64,
    pub(super) defer_count: i64,
    pub(super) defer_count_present: i64,
    pub(super) recurrence_instance_key: Option<String>,
    pub(super) recurrence_instance_key_present: i64,
    pub(super) archived_at: Option<String>,
    pub(super) archived_at_present: i64,
    pub(super) version: String,
}

/// Tri-state column shape used throughout the row builder:
/// `Patch<&str>` where `Unset` means absent, `Clear` means explicit-clear
/// (JSON `null` or `""`), and `Set(s)` means an explicit non-empty value.
type StrTri<'a> = lorvex_domain::Patch<&'a str>;
/// Tri-state column shape for `i64` columns.
type I64Tri = lorvex_domain::Patch<i64>;

/// Parse the always-present `title` plus the three free-text columns
/// (`body`, `raw_input`, `ai_notes`), scrub each one for unicode
/// hygiene, and validate the scrubbed values against the canonical
/// domain bounds.
fn parse_text_columns<'a>(
    val: &'a serde_json::Value,
    entity_id: &str,
) -> Result<(String, StrTri<'a>, StrTri<'a>, StrTri<'a>), ApplyError> {
    let title_raw = required_str(val, "title", "task")?;
    let body_tri = optional_str_preserving_empty(val, "body", "task")?;
    let raw_input_tri = optional_str_preserving_empty(val, "raw_input", "task")?;
    let ai_notes_tri = optional_str_preserving_empty(val, "ai_notes", "task")?;
    let body_raw = nullable_str_or_clear(&body_tri);
    let raw_input_raw = nullable_str_or_clear(&raw_input_tri);
    let ai_notes_raw = nullable_str_or_clear(&ai_notes_tri);
    // Unicode hygiene (#2427): scrub free-text fields at the sync
    // apply boundary so peers running an older build cannot push
    // bidi overrides, zero-width chars, or line separators into
    // our local tables.
    let title_owned = scrub(title_raw);
    let body_validate = scrub_opt(body_raw);
    let raw_input_validate = scrub_opt(raw_input_raw);
    let ai_notes_validate = scrub_opt(ai_notes_raw);

    // validate scrubbed fields against the shared domain bounds.
    // A peer could otherwise push unbounded `title`/`body` or an
    // out-of-range `priority` and the only gate would be the DB
    // CHECK (which returns an opaque error and retries forever).
    lorvex_domain::validation::validate_title(&title_owned).map_err(|e| {
        ApplyError::InvalidPayload(format!("task {entity_id} title failed validation: {e}"))
    })?;
    if let Some(b) = body_validate.as_deref() {
        lorvex_domain::validation::validate_body(b).map_err(|e| {
            ApplyError::InvalidPayload(format!("task {entity_id} body failed validation: {e}"))
        })?;
    }
    if let Some(notes) = ai_notes_validate.as_deref() {
        lorvex_domain::validation::validate_body(notes).map_err(|e| {
            ApplyError::InvalidPayload(format!("task {entity_id} ai_notes failed validation: {e}"))
        })?;
    }
    if let Some(input) = raw_input_validate.as_deref() {
        lorvex_domain::validation::validate_body(input).map_err(|e| {
            ApplyError::InvalidPayload(format!("task {entity_id} raw_input failed validation: {e}"))
        })?;
    }
    Ok((title_owned, body_tri, raw_input_tri, ai_notes_tri))
}

/// Parse + validate `status`. Mirrors the schema CHECK constraint at
/// the apply boundary so malformed envelopes surface as typed
/// `InvalidPayload` (handled by conflict-log) rather than an opaque
/// SQL error that retries forever in `pending_inbox`.
fn parse_status<'a>(val: &'a serde_json::Value, entity_id: &str) -> Result<&'a str, ApplyError> {
    let status_str = required_str(val, "status", "task")?;
    if !matches!(
        status_str,
        STATUS_OPEN | STATUS_COMPLETED | STATUS_CANCELLED | STATUS_SOMEDAY
    ) {
        return Err(ApplyError::InvalidPayload(format!(
            "task {entity_id} status {status_str:?} must be one of open|completed|cancelled|someday"
        )));
    }
    Ok(status_str)
}

/// Parse + validate the scheduling columns: `priority`, `due_date`,
/// `due_time`, `estimated_minutes`. Each goes
/// through the canonical domain validator so the sync boundary
/// enforces the same invariants every other write surface does.
#[allow(clippy::type_complexity)]
fn parse_scheduling_columns<'a>(
    val: &'a serde_json::Value,
    entity_id: &str,
) -> Result<(I64Tri, StrTri<'a>, StrTri<'a>, I64Tri), ApplyError> {
    use lorvex_domain::Patch;
    let priority_tri = optional_i64_preserving_null(val, "priority", "task")?;
    if let Patch::Set(p) = &priority_tri {
        lorvex_domain::validation::validate_priority(*p).map_err(|e| {
            ApplyError::InvalidPayload(format!("task {entity_id} priority failed validation: {e}"))
        })?;
    }
    let due_date_tri = optional_str_preserving_empty(val, "due_date", "task")?;
    if let Patch::Set(d) = &due_date_tri {
        lorvex_domain::validation::validate_date_format(d).map_err(|e| {
            ApplyError::InvalidPayload(format!("task {entity_id} due_date failed validation: {e}"))
        })?;
    }
    let due_time_tri = optional_str_preserving_empty(val, "due_time", "task")?;
    if let Patch::Set(t) = &due_time_tri {
        lorvex_domain::validation::validate_time_format(t).map_err(|e| {
            ApplyError::InvalidPayload(format!("task {entity_id} due_time failed validation: {e}"))
        })?;
    }
    let estimated_minutes_tri = optional_i64_preserving_null(val, "estimated_minutes", "task")?;
    if let Patch::Set(m) = &estimated_minutes_tri {
        lorvex_domain::validation::validate_estimated_minutes(*m).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "task {entity_id} estimated_minutes failed validation: {e}"
            ))
        })?;
    }
    Ok((
        priority_tri,
        due_date_tri,
        due_time_tri,
        estimated_minutes_tri,
    ))
}

/// Parse + validate the lifecycle columns. `last_defer_reason` is
/// scrubbed + enum-validated against the schema CHECK.
/// `defer_count` rejects negatives at the apply boundary.
#[allow(clippy::type_complexity)]
fn parse_lifecycle_columns<'a>(
    val: &'a serde_json::Value,
    entity_id: &str,
) -> Result<
    (
        StrTri<'a>,
        StrTri<'a>,
        StrTri<'a>,
        Option<String>,
        StrTri<'a>,
        StrTri<'a>,
        I64Tri,
        StrTri<'a>,
        StrTri<'a>,
        StrTri<'a>,
    ),
    ApplyError,
> {
    let completed_at_tri = optional_str_preserving_empty(val, "completed_at", "task")?;
    let last_deferred_at_tri = optional_str_preserving_empty(val, "last_deferred_at", "task")?;
    let last_defer_reason_tri = optional_str_preserving_empty(val, "last_defer_reason", "task")?;
    let last_defer_reason_raw = nullable_str_or_clear(&last_defer_reason_tri);
    let last_defer_reason_owned = scrub_opt(last_defer_reason_raw);
    if let Some(reason) = last_defer_reason_owned.as_deref() {
        if !lorvex_domain::naming::is_valid_defer_reason(reason) {
            return Err(ApplyError::InvalidPayload(format!(
                "task {entity_id} last_defer_reason {reason:?} must be one of: {}",
                lorvex_domain::naming::ALL_DEFER_REASONS.join("|")
            )));
        }
    }
    let planned_date_tri = optional_str_preserving_empty(val, "planned_date", "task")?;
    if let lorvex_domain::Patch::Set(d) = &planned_date_tri {
        lorvex_domain::validation::validate_date_format(d).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "task {entity_id} planned_date failed validation: {e}"
            ))
        })?;
    }
    let available_from_tri = optional_str_preserving_empty(val, "available_from", "task")?;
    if let lorvex_domain::Patch::Set(d) = &available_from_tri {
        lorvex_domain::validation::validate_date_format(d).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "task {entity_id} available_from failed validation: {e}"
            ))
        })?;
    }
    let defer_count_tri = optional_i64_preserving_null(val, "defer_count", "task")?;
    if let lorvex_domain::Patch::Set(n) = &defer_count_tri {
        if *n < 0 {
            return Err(ApplyError::InvalidPayload(format!(
                "task {entity_id} defer_count must be non-negative (got {n})"
            )));
        }
    }
    let recurrence_instance_key_tri =
        optional_str_preserving_empty(val, "recurrence_instance_key", "task")?;
    let canonical_occurrence_date_tri =
        optional_str_preserving_empty(val, "canonical_occurrence_date", "task")?;
    if let lorvex_domain::Patch::Set(d) = &canonical_occurrence_date_tri {
        lorvex_domain::validation::validate_date_format(d).map_err(|e| {
            ApplyError::InvalidPayload(format!(
                "task {entity_id} canonical_occurrence_date failed validation: {e}"
            ))
        })?;
    }
    let archived_at_tri = optional_str_preserving_empty(val, "archived_at", "task")?;
    Ok((
        completed_at_tri,
        last_deferred_at_tri,
        last_defer_reason_tri,
        last_defer_reason_owned,
        planned_date_tri,
        available_from_tri,
        defer_count_tri,
        recurrence_instance_key_tri,
        canonical_occurrence_date_tri,
        archived_at_tri,
    ))
}

/// Parse + validate an envelope payload and return the row state
/// ready to bind into the UPDATE / INSERT templates.
///
/// `conn` is needed for the `list_id` fallback (we look up the
/// canonical inbox list, then the oldest remaining list, when the
/// peer omits the field). The lookup runs inside the same
/// transaction as the apply, so concurrent INSERTs by other
/// pipeline branches cannot race the resolution.
pub(super) fn build_task_row(
    conn: &Connection,
    task_id: &TaskId,
    payload: &str,
    version: &str,
) -> Result<TaskRow, ApplyError> {
    // Reuse the `task_id` reference for every error-message format
    // — the typed seam at the upsert handler entry hands us the
    // already-parsed `TaskId`, so `.as_str()` on the borrow is
    // zero-copy.
    let entity_id = task_id.as_str();
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let (title_owned, body_tri, raw_input_tri, ai_notes_tri) = parse_text_columns(&val, entity_id)?;

    let status_str = parse_status(&val, entity_id)?;

    // list_id is NOT NULL. Sync payloads from older devices may
    // omit it, or supply an empty string (coerced to None here).
    // Prefer the well-known inbox list, then deterministically
    // fall back to the oldest remaining list (ties broken by id).
    // If no lists exist, the FK preflight check will defer the
    // envelope until a list is synced.
    let list_id_owned = resolve_list_id(conn, &val)?;

    let (priority_tri, due_date_tri, due_time_tri, estimated_minutes_tri) =
        parse_scheduling_columns(&val, entity_id)?;

    // Per-field tri-state parses for every nullable text column on
    // `tasks`. Empty-string is treated as an explicit clear
    // (collapses to SQL NULL). Field-absence preserves the
    // existing column value via the `:col_present` gate in the
    // upsert SQL.
    let recurrence_tri = optional_str_preserving_empty(&val, "recurrence", "task")?;
    let recurrence_exceptions_tri =
        optional_str_preserving_empty(&val, "recurrence_exceptions", "task")?;
    let spawned_from_tri = optional_str_preserving_empty(&val, "spawned_from", "task")?;
    let recurrence_group_id_tri =
        optional_str_preserving_empty(&val, "recurrence_group_id", "task")?;

    let created_at_str = required_str(&val, "created_at", "task")?;
    let updated_at_str = required_str(&val, "updated_at", "task")?;

    let (
        completed_at_tri,
        last_deferred_at_tri,
        last_defer_reason_tri,
        last_defer_reason_owned,
        planned_date_tri,
        available_from_tri,
        defer_count_tri,
        recurrence_instance_key_tri,
        canonical_occurrence_date_tri,
        archived_at_tri,
    ) = parse_lifecycle_columns(&val, entity_id)?;

    // Split each tri-state parse into its (value, present) bind
    // pair, then re-scrub the value half so the bytes that hit
    // SQLite match the bytes that passed validation.
    // upsert site computed two scrubbed copies (one for validate,
    // one for bind) on every envelope; consolidating into the row
    // builder keeps that intent explicit.
    let (body_bind, body_present) = split_partial_str_value(body_tri);
    let body_owned = scrub_opt(body_bind);
    let (raw_input_bind, raw_input_present) = split_partial_str_value(raw_input_tri);
    let raw_input_owned = scrub_opt(raw_input_bind);
    let (ai_notes_bind, ai_notes_present) = split_partial_str_value(ai_notes_tri);
    let ai_notes_owned = scrub_opt(ai_notes_bind);
    let (priority_bind, priority_present) = split_partial_i64_value(priority_tri);
    let (due_date_bind, due_date_present) = split_partial_str_value(due_date_tri);
    let (due_time_bind, due_time_present) = split_partial_str_value(due_time_tri);
    let (estimated_minutes_bind, estimated_minutes_present) =
        split_partial_i64_value(estimated_minutes_tri);
    let (recurrence_bind, recurrence_present) = split_partial_str_value(recurrence_tri);
    let (recurrence_exceptions_bind, recurrence_exceptions_present) =
        split_partial_str_value(recurrence_exceptions_tri);
    let (spawned_from_bind, spawned_from_present) = split_partial_str_value(spawned_from_tri);
    let (recurrence_group_id_bind, recurrence_group_id_present) =
        split_partial_str_value(recurrence_group_id_tri);
    let (completed_at_bind, completed_at_present) = split_partial_str_value(completed_at_tri);
    let (last_deferred_at_bind, last_deferred_at_present) =
        split_partial_str_value(last_deferred_at_tri);
    let (_, last_defer_reason_present) = split_partial_str_value(last_defer_reason_tri);
    let (planned_date_bind, planned_date_present) = split_partial_str_value(planned_date_tri);
    let (available_from_bind, available_from_present) = split_partial_str_value(available_from_tri);
    let (defer_count_value, defer_count_present) = split_partial_i64_value(defer_count_tri);
    // For the INSERT path defer_count is NOT NULL with DEFAULT 0,
    // so pass through the schema default when the field is absent
    // or explicitly null.
    let defer_count: i64 = defer_count_value.unwrap_or(0);
    let (recurrence_instance_key_bind, recurrence_instance_key_present) =
        split_partial_str_value(recurrence_instance_key_tri);
    let (canonical_occurrence_date_bind, canonical_occurrence_date_present) =
        split_partial_str_value(canonical_occurrence_date_tri);
    let (archived_at_bind, archived_at_present) = split_partial_str_value(archived_at_tri);

    Ok(TaskRow {
        entity_id: task_id.clone(),
        title: title_owned,
        body: body_owned,
        body_present,
        raw_input: raw_input_owned,
        raw_input_present,
        ai_notes: ai_notes_owned,
        ai_notes_present,
        status: status_str.to_owned(),
        list_id: list_id_owned,
        priority: priority_bind,
        priority_present,
        due_date: due_date_bind.map(str::to_owned),
        due_date_present,
        due_time: due_time_bind.map(str::to_owned),
        due_time_present,
        estimated_minutes: estimated_minutes_bind,
        estimated_minutes_present,
        recurrence: recurrence_bind.map(str::to_owned),
        recurrence_present,
        recurrence_exceptions: recurrence_exceptions_bind.map(str::to_owned),
        recurrence_exceptions_present,
        spawned_from: spawned_from_bind.map(str::to_owned),
        spawned_from_present,
        recurrence_group_id: recurrence_group_id_bind.map(str::to_owned),
        recurrence_group_id_present,
        canonical_occurrence_date: canonical_occurrence_date_bind.map(str::to_owned),
        canonical_occurrence_date_present,
        created_at: created_at_str.to_owned(),
        updated_at: updated_at_str.to_owned(),
        completed_at: completed_at_bind.map(str::to_owned),
        completed_at_present,
        last_deferred_at: last_deferred_at_bind.map(str::to_owned),
        last_deferred_at_present,
        last_defer_reason: last_defer_reason_owned,
        last_defer_reason_present,
        planned_date: planned_date_bind.map(str::to_owned),
        planned_date_present,
        available_from: available_from_bind.map(str::to_owned),
        available_from_present,
        defer_count,
        defer_count_present,
        recurrence_instance_key: recurrence_instance_key_bind.map(str::to_owned),
        recurrence_instance_key_present,
        archived_at: archived_at_bind.map(str::to_owned),
        archived_at_present,
        version: version.to_owned(),
    })
}

/// Resolve the row's `list_id`. Tasks.list_id is NOT NULL, so when
/// the envelope omits the field (or sets it to an empty string) we
/// pick a sensible default rather than reject the apply: the
/// canonical inbox list when it exists locally, otherwise the
/// oldest remaining list (ties broken by id).
///
/// This must distinguish "row not found" (fall through to the
/// oldest-list lookup) from a real DB error (propagate) — otherwise
/// a transient DB error would get misclassified as "no lists exist"
/// and the apply pipeline would silently defer the envelope via
/// pending_inbox forever.
fn resolve_list_id(
    conn: &Connection,
    val: &serde_json::Value,
) -> Result<Option<String>, ApplyError> {
    let payload_list_id = optional_str(val, "list_id", "task")?.filter(|s| !s.is_empty());
    if let Some(id) = payload_list_id {
        return Ok(Some(id.to_owned()));
    }
    let inbox_exists: Option<String> = conn
        .prepare_cached("SELECT id FROM lists WHERE id = ?1")?
        .query_row([lorvex_store::INBOX_LIST_ID], |r| r.get::<_, String>(0))
        .optional()?;
    if let Some(id) = inbox_exists {
        return Ok(Some(id));
    }
    let oldest: Option<String> = conn
        .prepare_cached("SELECT id FROM lists ORDER BY created_at ASC, id ASC LIMIT 1")?
        .query_row([], |r| r.get::<_, String>(0))
        .optional()?;
    Ok(oldest)
}

#[cfg(test)]
mod tests;
