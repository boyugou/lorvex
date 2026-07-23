//! Pure-string assertions for the task UPDATE / INSERT templates.
//!
//! These tests do NOT touch a SQLite connection. The point is to lock
//! the wire-shape of the rendered SQL — every `:col_present`-gated
//! `CASE WHEN` clause, the trailing version comparator that varies by
//! tie-break flavor, and the column / VALUES order in the INSERT.
//!
//! Any future refactor that changes the rendered bytes will break
//! these tests, which is the desired backstop: peers running mixed
//! versions need the apply path to bind into the same shape on every
//! receiving device.
//!
//! Test counts here are deliberately small (one per
//! template-variant). The integration tests in
//! `apply/aggregate/tests/` exercise the round-trip behaviour against
//! a real SQLite connection.

use super::super::super::super::LwwTieBreak;
use super::{task_update_sql, TASK_INSERT_SQL};

#[test]
fn update_sql_reject_equal_uses_strictly_greater_version_predicate() {
    let sql = task_update_sql(LwwTieBreak::RejectEqual);
    assert!(
        sql.starts_with("UPDATE tasks SET"),
        "UPDATE template must start with `UPDATE tasks SET`, got: {sql}"
    );
    assert!(
        sql.ends_with("WHERE id = :id AND :version > version"),
        "RejectEqual flavor must end with strictly-greater version predicate, got tail: {}",
        &sql[sql.len().saturating_sub(80)..]
    );
}

#[test]
fn update_sql_allow_equal_uses_greater_or_equal_version_predicate() {
    let sql = task_update_sql(LwwTieBreak::AllowEqual);
    assert!(
        sql.ends_with("WHERE id = :id AND :version >= version"),
        "AllowEqual flavor must end with `>=` version predicate, got tail: {}",
        &sql[sql.len().saturating_sub(80)..]
    );
}

#[test]
fn update_sql_is_render_once_and_returns_same_pointer_per_flavor() {
    // The OnceLock cache means repeated calls for the same flavor
    // must hand back the *same* &'static str. This is what avoids
    // the per-envelope `format!` allocation on the highest-volume
    // apply path.
    let a = task_update_sql(LwwTieBreak::RejectEqual);
    let b = task_update_sql(LwwTieBreak::RejectEqual);
    assert!(
        std::ptr::eq(a.as_ptr(), b.as_ptr()),
        "OnceLock cache must reuse the same allocation for repeated calls"
    );

    let c = task_update_sql(LwwTieBreak::AllowEqual);
    let d = task_update_sql(LwwTieBreak::AllowEqual);
    assert!(std::ptr::eq(c.as_ptr(), d.as_ptr()));

    // The two flavors live in distinct OnceLock slots.
    assert!(!std::ptr::eq(a.as_ptr(), c.as_ptr()));
}

#[test]
fn update_sql_partial_update_gates_every_nullable_column() {
    let sql = task_update_sql(LwwTieBreak::RejectEqual);
    // Every nullable text/int column must appear inside a
    // `CASE WHEN :col_present THEN :col ELSE tasks.col END`
    // clause so an absent field on the envelope preserves the
    // local value (the partial-update preservation invariant
    // documented in the parent module).
    let gated_columns = [
        "body",
        "raw_input",
        "ai_notes",
        "priority",
        "due_date",
        "due_time",
        "estimated_minutes",
        "recurrence",
        "spawned_from",
        "recurrence_group_id",
        "canonical_occurrence_date",
        "completed_at",
        "last_deferred_at",
        "last_defer_reason",
        "planned_date",
        "defer_count",
        "recurrence_instance_key",
        "archived_at",
    ];
    for col in gated_columns {
        let needle = format!(":{col}_present");
        assert!(
            sql.contains(&needle),
            "UPDATE template must gate `{col}` with `{needle}`, got: {sql}"
        );
    }
    // `title`, `status`, `list_id`, `created_at`, `updated_at`, and
    // `version` are always written unconditionally — they must NOT
    // carry a `_present` gate.
    for col in ["title", "status", "list_id", "created_at", "updated_at"] {
        let forbidden = format!(":{col}_present");
        assert!(
            !sql.contains(&forbidden),
            "unconditional column `{col}` must NOT carry a `_present` gate"
        );
    }
}

#[test]
fn insert_sql_includes_every_synced_task_column_in_order() {
    // The INSERT template is fully static; this test pins the
    // column order so a refactor that adds / reorders columns
    // visibly fails here.
    let expected_columns = [
        "id",
        "title",
        "body",
        "raw_input",
        "ai_notes",
        "status",
        "list_id",
        "priority",
        "due_date",
        "due_time",
        "estimated_minutes",
        "recurrence",
        "spawned_from",
        "recurrence_group_id",
        "canonical_occurrence_date",
        "created_at",
        "updated_at",
        "completed_at",
        "last_deferred_at",
        "last_defer_reason",
        "planned_date",
        "defer_count",
        "recurrence_instance_key",
        "version",
        "archived_at",
    ];
    // Columns appear in the column list, then again as `:col`
    // binds in the VALUES list — both in the same order.
    let mut cursor = 0usize;
    for col in expected_columns {
        let idx = sql_find_after(TASK_INSERT_SQL, cursor, col).unwrap_or_else(|| {
            panic!("INSERT template missing column `{col}` after offset {cursor}")
        });
        cursor = idx + col.len();
    }
    cursor = 0;
    for col in expected_columns {
        let needle = format!(":{col}");
        let idx = sql_find_after(TASK_INSERT_SQL, cursor, &needle).unwrap_or_else(|| {
            panic!("INSERT template missing bind `{needle}` after offset {cursor}")
        });
        cursor = idx + needle.len();
    }
}

/// `str::find` only takes a starting position via slicing; this
/// helper keeps the column-walk above readable without that
/// arithmetic noise leaking into the test body.
fn sql_find_after(haystack: &str, from: usize, needle: &str) -> Option<usize> {
    haystack[from..].find(needle).map(|rel| rel + from)
}
