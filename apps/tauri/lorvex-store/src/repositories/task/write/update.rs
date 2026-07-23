//! UPDATE — patch an existing task row.
//!
//! Owns the [`TaskUpdatePatch`] carrier and the dynamic [`apply_task_update`]
//! UPDATE used by every status / metadata / trash transition. The
//! per-field semantics (Some(None) clears, Some(Some(v)) sets,
//! None skips) mirror the patch-shape conventions in the rest of the
//! repository.

use lorvex_domain::naming::{TaskStatus, ENTITY_TASK};
use lorvex_domain::status_transition::{status_transition_columns, ColumnAction};
use lorvex_domain::Patch;
use rusqlite::{
    types::{ToSqlOutput, Value as SqlValue, ValueRef},
    Connection, OptionalExtension,
};

use crate::error::StoreError;
use crate::repositories::lww_update::execute_lww_update;

/// Patch struct for a task update. Nullable columns use [`Patch<T>`]
/// for explicit three-state semantics: `Patch::Unset` skips,
/// `Patch::Clear` writes SQL NULL, `Patch::Set(v)` writes the value.
/// `list_id` is the exception: clearing it to NULL is rejected because normal
/// tasks must remain classified into a real list.
///
/// Fields NOT in this patch (handled by their own shared ops):
/// - `due_date`, `recurrence` -> `apply_recurrence_change`
/// - `tags` -> tag_repo / task_tags join table
/// - `depends_on` -> edge table
#[derive(Debug, Clone, Default)]
pub struct TaskUpdatePatch<'a> {
    pub task_id: &'a str,
    pub title: Option<&'a str>,
    pub body: Patch<&'a str>,
    pub raw_input: Patch<&'a str>,
    pub ai_notes: Patch<&'a str>,
    pub status: Option<TaskStatus>,
    pub list_id: Patch<&'a str>,
    pub priority: Patch<i64>,
    pub due_time: Patch<&'a str>,
    pub estimated_minutes: Patch<i64>,
    pub planned_date: Patch<&'a str>,
    /// Trash-state column. `Patch::Set(ts)` archives (moves to Trash),
    /// `Patch::Clear` restores (clears the trash flag), `Patch::Unset`
    /// skips. Routed through the canonical patch so trash transitions
    /// land alongside the same `version`/`updated_at` invariant
    /// updates as every other status-bearing mutation, instead of
    /// bypassing them via raw SQL.
    pub archived_at: Patch<&'a str>,
    pub version: &'a str,
    pub now: &'a str,
    /// The task's current status before this update. Required when
    /// `status` is set so transition metadata is calculated from a
    /// typed persisted value instead of a fallback.
    pub before_status: Option<TaskStatus>,
}

/// Parse a task status read from a trusted row before passing it into
/// [`TaskUpdatePatch`]. A non-canonical persisted value is an
/// invariant break, not a no-op transition.
pub fn parse_task_status_for_update(
    task_id: &str,
    raw_status: &str,
) -> Result<TaskStatus, StoreError> {
    TaskStatus::parse(raw_status).ok_or_else(|| {
        StoreError::Invariant(format!(
            "task {task_id} has invalid persisted status {raw_status:?}; expected one of: open, completed, cancelled, someday"
        ))
    })
}

/// Apply a dynamic UPDATE to a task row. Builds `SET` clauses from non-None
/// fields, always includes `version` and `updated_at`, and applies
/// status-transition metadata columns when `status` is set.
///
/// Returns `Ok(())` when the LWW gate accepted the write. Returns
/// [`StoreError::StaleVersion`] when the gate rejected the write
/// because the patch's `version` was not strictly newer than the
/// row's current `version` — the boundary layers (Tauri / MCP / CLI)
/// translate this into the wire-level "sync conflict" / "concurrent
/// update; please retry" surface.
pub fn apply_task_update<'a>(
    conn: &Connection,
    patch: &TaskUpdatePatch<'a>,
) -> Result<(), StoreError> {
    if let Patch::Set(due_time) = patch.due_time {
        let current_due_date: Option<Option<String>> = conn
            .query_row(
                "SELECT due_date FROM tasks WHERE id = ?1",
                [patch.task_id],
                |row| row.get(0),
            )
            .optional()?;
        if let Some(current_due_date) = current_due_date {
            lorvex_domain::time::DueAt::from_optional_str_pair(
                current_due_date.as_deref(),
                Some(due_time),
            )?;
        }
    }

    // Helpers that route patch fields into `ToSqlOutput::Borrowed`
    // so the `&str`s in `TaskUpdatePatch<'a>` flow straight to
    // SQLite without per-field `String` clones.
    // `&str` was cloned into `SqlValue::Text(s.to_string())`
    // along the hot per-row UPDATE path; for a typical 8-field
    // patch that was 8 short-lived heap allocations per call.
    const fn borrowed_text(s: &str) -> ToSqlOutput<'_> {
        ToSqlOutput::Borrowed(ValueRef::Text(s.as_bytes()))
    }
    const fn opt_text(v: Option<&str>) -> ToSqlOutput<'_> {
        match v {
            Some(s) => borrowed_text(s),
            None => ToSqlOutput::Borrowed(ValueRef::Null),
        }
    }
    const fn opt_int(v: Option<i64>) -> ToSqlOutput<'static> {
        match v {
            Some(n) => ToSqlOutput::Owned(SqlValue::Integer(n)),
            None => ToSqlOutput::Borrowed(ValueRef::Null),
        }
    }

    // Upper bound on SET clauses + WHERE binds across every patch
    // shape: 14 patch columns + up to 4 status-transition
    // metadata columns (`completed_at`, `last_deferred_at`,
    // `last_defer_reason`, `planned_date`) + 2 trailing WHERE
    // binds (`id`, `version`). Pre-sizing skips the
    // 4 → 8 → 16 → 32 reallocs the dynamic builder would otherwise
    // do for fully-populated patches.
    const PATCH_CAPACITY: usize = 20;
    let mut set_clauses: Vec<std::borrow::Cow<'_, str>> = Vec::with_capacity(PATCH_CAPACITY);
    let mut values: Vec<ToSqlOutput<'a>> = Vec::with_capacity(PATCH_CAPACITY);

    set_clauses.push("updated_at = ?".into());
    values.push(borrowed_text(patch.now));
    set_clauses.push("version = ?".into());
    values.push(borrowed_text(patch.version));

    // Helper: convert `Patch<&str>` to `Option<&str>` for binding when
    // the patch is set or clear (caller gates on `is_set_or_clear`).
    const fn patch_to_opt_str<'p>(p: &Patch<&'p str>) -> Option<&'p str> {
        match p {
            Patch::Unset | Patch::Clear => None,
            Patch::Set(s) => Some(*s),
        }
    }
    const fn patch_to_opt_i64(p: &Patch<i64>) -> Option<i64> {
        match p {
            Patch::Unset | Patch::Clear => None,
            Patch::Set(n) => Some(*n),
        }
    }

    if let Some(title) = patch.title {
        set_clauses.push("title = ?".into());
        values.push(borrowed_text(title));
    }
    if patch.body.is_set_or_clear() {
        set_clauses.push("body = ?".into());
        values.push(opt_text(patch_to_opt_str(&patch.body)));
    }
    if patch.raw_input.is_set_or_clear() {
        set_clauses.push("raw_input = ?".into());
        values.push(opt_text(patch_to_opt_str(&patch.raw_input)));
    }
    if patch.ai_notes.is_set_or_clear() {
        set_clauses.push("ai_notes = ?".into());
        values.push(opt_text(patch_to_opt_str(&patch.ai_notes)));
    }
    if let Some(status) = patch.status {
        let before_status = patch.before_status.ok_or_else(|| {
            StoreError::Invariant(format!(
                "status update for task {} is missing typed before_status",
                patch.task_id
            ))
        })?;
        set_clauses.push("status = ?".into());
        values.push(borrowed_text(status.as_str()));
        // Apply status-transition metadata columns. The SET-clause
        // SQL fragments come from the closed-set `&'static str`
        // helpers in [`crate::status_transition_sql`] rather than a
        // `format!("{col} = ?")` per call, so each column action
        // borrows a `&'static str` instead of allocating a `String`.
        use crate::status_transition_sql as col_sql;
        for action in status_transition_columns(before_status, status, patch.now) {
            match action {
                ColumnAction::SetText(col, val) => {
                    set_clauses.push(col_sql::set_value_fragment(col).into());
                    values.push(ToSqlOutput::Owned(SqlValue::Text(val)));
                }
                ColumnAction::SetNull(col) => {
                    set_clauses.push(col_sql::set_null_fragment(col).into());
                }
                ColumnAction::SetInt(col, val) => {
                    set_clauses.push(col_sql::set_value_fragment(col).into());
                    values.push(ToSqlOutput::Owned(SqlValue::Integer(val)));
                }
            }
        }
    }
    match &patch.list_id {
        Patch::Unset => {}
        Patch::Clear => {
            return Err(StoreError::Validation(
                "tasks must belong to a real list. Choose a list instead of clearing list_id."
                    .to_string(),
            ));
        }
        Patch::Set(list_id) => {
            let typed_list_id = lorvex_domain::ListId::from_trusted((*list_id).to_string());
            crate::task_classification::validate_task_list_exists(conn, &typed_list_id)?;
            set_clauses.push("list_id = ?".into());
            values.push(borrowed_text(list_id));
        }
    }
    if patch.priority.is_set_or_clear() {
        set_clauses.push("priority = ?".into());
        values.push(opt_int(patch_to_opt_i64(&patch.priority)));
    }
    if patch.due_time.is_set_or_clear() {
        set_clauses.push("due_time = ?".into());
        values.push(opt_text(patch_to_opt_str(&patch.due_time)));
    }
    if patch.estimated_minutes.is_set_or_clear() {
        set_clauses.push("estimated_minutes = ?".into());
        values.push(opt_int(patch_to_opt_i64(&patch.estimated_minutes)));
    }
    if patch.planned_date.is_set_or_clear() {
        set_clauses.push("planned_date = ?".into());
        values.push(opt_text(patch_to_opt_str(&patch.planned_date)));
    }
    if patch.archived_at.is_set_or_clear() {
        set_clauses.push("archived_at = ?".into());
        values.push(opt_text(patch_to_opt_str(&patch.archived_at)));
    }

    // gate the UPDATE on a strict `version >`
    // comparison so a local write racing an in-flight sync apply that
    // already landed a newer remote version cannot blindly overwrite
    // the peer's freshly-applied changes. Mirrors the LWW guard
    // already in `update_list_patched` (#2896), `set_preference`, and
    // `rename_tag`. Without this, the task path was the lone hold-out
    // — a stale local update silently clobbered the cluster.
    values.push(borrowed_text(patch.task_id));
    values.push(borrowed_text(patch.version));

    let sql = format!(
        "UPDATE tasks SET {} WHERE id = ? AND ? > version RETURNING 1",
        set_clauses.join(", ")
    );
    // `format!`-built but the rendered SQL is keyed by the active
    // `set_clauses` permutation (stable per call-site shape).
    // `prepare_cached` reuses the parsed plan across every patch
    // with the same column-set.
    //
    // `RETURNING 1` + `query_row` lets the helper translate the
    // LWW miss (`QueryReturnedNoRows`) into `StaleVersion`
    // directly, which retires the duplicated `if rows == 0 { … }`
    // branches every caller carry.
    execute_lww_update(
        conn,
        &sql,
        rusqlite::params_from_iter(values.iter()),
        ENTITY_TASK,
        patch.task_id,
    )
}
