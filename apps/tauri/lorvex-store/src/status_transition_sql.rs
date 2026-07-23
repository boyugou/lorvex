//! Static SQL fragments for [`lorvex_domain::status_transition::ColumnAction`].
//!
//! The status-transition rules in `lorvex-domain` enumerate a fixed
//! set of metadata columns (`completed_at`, `last_deferred_at`,
//! `last_defer_reason`, `planned_date`, `defer_count`). A column not
//! in the closed set is a contract violation between `lorvex-domain`
//! and `lorvex-store`: the `set_*_fragment` paths return a
//! conservative fallback (`format!`-built `String` leaked to
//! `'static`) gated behind `debug_assert!` so test runs catch a new
//! `ColumnAction` variant immediately while release builds degrade
//! gracefully — preferable to a panic that would hard-fail the
//! status-mutation hot path on an unfamiliar column.
//!
//! Two callers share these helpers:
//!
//! 1. `repositories::task::write::apply_task_update` (in this crate) —
//!    direct UPDATE-statement column-fragment assembly.
//! 2. `lorvex_workflow::lifecycle::write_status::write_status_and_metadata`
//!    — the workflow-layer status-mutation primitive.
//!
//! These helpers live as a top-level `lorvex-store` module — sharing
//! them between `repositories::task::write` and the workflow-layer
//! `write_status` primitive without creating a `store ↔ workflow`
//! cycle (the workflow crate depends on store, not the other way
//! around).

/// `&'static str` SQL fragment of the form `"{col} = ?"` for the
/// closed set of status-transition metadata columns.
pub fn set_value_fragment(col: &'static str) -> &'static str {
    match col {
        "completed_at" => "completed_at = ?",
        "last_deferred_at" => "last_deferred_at = ?",
        "last_defer_reason" => "last_defer_reason = ?",
        "planned_date" => "planned_date = ?",
        "defer_count" => "defer_count = ?",
        other => fallback_value_fragment(other),
    }
}

/// `&'static str` SQL fragment of the form `"{col} = NULL"` for the
/// closed set of status-transition metadata columns.
pub fn set_null_fragment(col: &'static str) -> &'static str {
    match col {
        "completed_at" => "completed_at = NULL",
        "last_deferred_at" => "last_deferred_at = NULL",
        "last_defer_reason" => "last_defer_reason = NULL",
        "planned_date" => "planned_date = NULL",
        "defer_count" => "defer_count = NULL",
        other => fallback_null_fragment(other),
    }
}

#[cold]
fn fallback_value_fragment(col: &'static str) -> &'static str {
    debug_assert!(
        false,
        "status_transition_sql::set_value_fragment: unknown status-transition column {col:?}; \
         add it to the match arm above to keep the hot path allocation-free"
    );
    // Defense-in-depth: the fallback path actually `format!`-interpolates
    // `col` into a SQL fragment. Every current caller passes a
    // `&'static str` literal from the closed status-transition column
    // set, but a release-build path through this branch on an unknown
    // column would synthesize SQL from whatever string the caller
    // supplied. Validate first so a malformed identifier panics with
    // the typed error rather than producing broken SQL.
    lorvex_domain::assert_safe_sql_identifier(col);
    Box::leak(format!("{col} = ?").into_boxed_str())
}

#[cold]
fn fallback_null_fragment(col: &'static str) -> &'static str {
    debug_assert!(
        false,
        "status_transition_sql::set_null_fragment: unknown status-transition column {col:?}; \
         add it to the match arm above to keep the hot path allocation-free"
    );
    // Defense-in-depth: see `fallback_value_fragment`.
    lorvex_domain::assert_safe_sql_identifier(col);
    Box::leak(format!("{col} = NULL").into_boxed_str())
}
