//! Write the status column and transition metadata columns for a status change.
//!
//! Uses `status_transition_columns` from lorvex-domain for the metadata rules
//! (completed_at, last_deferred_at, defer_count, etc.), then builds a single
//! UPDATE statement that sets status + all metadata columns + version + updated_at.
//!
//! The static SQL fragments for [`lorvex_domain::status_transition::ColumnAction`]
//! live in `lorvex_store::status_transition_sql` so the workflow's status
//! mutation path here and the storage-layer `apply_task_update` share a
//! single closed-set match without allocating per-column `String`s.

use lorvex_domain::{naming::TaskStatus, TaskId};
use rusqlite::{types::Value as SqlValue, Connection};

use lorvex_store::status_transition_sql as column_action_sql;
use lorvex_store::StoreError;

/// Apply a status mutation + transition metadata columns under an LWW
/// version gate.
///
/// Gates the UPDATE on `?{n} > version` so a stale local
/// complete/cancel/reopen racing an in-flight sync apply cannot
/// silently overwrite a peer's freshly-applied newer version.
/// Mirrors the gate on `apply_task_update`, `update_list_patched`,
/// `set_preference`, and `rename_tag` so every LWW-converged path
/// shares the same shape.
///
/// Returns the number of rows changed (0 or 1). Zero means either the
/// row is missing or the caller's version stamp lost the LWW comparison.
/// Callers that pre-checked existence should treat `Ok(0)` as
/// `StaleVersion` and surface it accordingly.
pub(crate) fn write_status_and_metadata(
    conn: &Connection,
    task_id: &TaskId,
    old_status: TaskStatus,
    new_status: TaskStatus,
    now: &str,
    version: &str,
) -> Result<usize, StoreError> {
    use lorvex_domain::status_transition::{status_transition_columns, ColumnAction};

    // Status-transition column SET clauses are drawn from a closed
    // set of `&'static str` columns (see [`column_action_sql`]); the
    // SQL fragments are therefore also `&'static str` and
    // `Vec<&'static str>` carries them without a `Cow` allocation per
    // fragment.
    let mut set_clauses: Vec<&'static str> = vec!["status = ?", "updated_at = ?", "version = ?"];
    let mut values: Vec<SqlValue> = vec![
        SqlValue::Text(new_status.as_str().to_string()),
        SqlValue::Text(now.to_string()),
        SqlValue::Text(version.to_string()),
    ];

    for action in status_transition_columns(old_status, new_status, now) {
        match action {
            ColumnAction::SetText(col, val) => {
                set_clauses.push(column_action_sql::set_value_fragment(col));
                values.push(SqlValue::Text(val));
            }
            ColumnAction::SetNull(col) => {
                set_clauses.push(column_action_sql::set_null_fragment(col));
            }
            ColumnAction::SetInt(col, val) => {
                set_clauses.push(column_action_sql::set_value_fragment(col));
                values.push(SqlValue::Integer(val));
            }
        }
    }

    values.push(SqlValue::Text(task_id.as_str().to_string()));
    values.push(SqlValue::Text(version.to_string()));

    let sql = format!(
        "UPDATE tasks SET {} WHERE id = ? AND ? > version",
        set_clauses.join(", ")
    );
    let rows = conn.execute(&sql, rusqlite::params_from_iter(values.iter()))?;
    Ok(rows)
}
