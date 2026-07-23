//! Shared filter-clause helpers for the search SQL builders.
//!
//! The status / list / tag filter blocks of `search_tasks_fts_counted`,
//! the trigram path, and `search_tasks_like` were near-byte-identical
//! (~30 lines per site × 3 sites). Each pushed an `IN (?, ?, …)`
//! predicate with a placeholder count derived from `param_values.len()`.
//! Centralizing the boilerplate here keeps the search variants in sync —
//! adding a new filter shape (priority, due-window, …) becomes a
//! single-site change.

use lorvex_domain::query::*;

/// Build the shared `(tag_join, where_extra)` FROM/WHERE scaffolding
/// the FTS-counted and (test-only) FTS read paths both use.
///
/// byte-identical `tag_join` blocks plus duplicate WHERE assembly —
/// any future filter addition (e.g. priority) had to land in both
/// places, with no compiler help when the two diverged. This helper
/// pins one source of truth.
///
/// Returns `(tag_join, where_extra)`. The caller owns the param
/// vector and seeds it with the FTS query as `?1` before calling.
/// Filter-element binds are appended to the caller's vector by
/// borrowing directly from `pred` — no per-keystroke heap allocs
/// for status / list / tag binds.
pub(super) fn build_fts_filter_scaffolding<'a>(
    pred: &'a SearchPredicate,
    param_values: &mut Vec<&'a dyn rusqlite::types::ToSql>,
) -> (&'static str, String) {
    let mut conditions = vec!["t.archived_at IS NULL".to_string()];

    apply_status_filter(pred, &mut conditions, param_values);
    apply_list_filter(pred, &mut conditions, param_values);

    let tag_join: &'static str = match pred.tag_filter.as_ref() {
        Some(tags) if !tags.is_empty() => {
            let ph = lorvex_domain::sql_in_placeholders(tags.len(), param_values.len());
            conditions.push(format!("tt.tag_id IN ({ph})"));
            for tag in tags {
                param_values.push(tag);
            }
            "JOIN task_tags tt ON t.id = tt.task_id"
        }
        _ => "",
    };

    let where_extra = if conditions.is_empty() {
        String::new()
    } else {
        format!(" AND {}", conditions.join(" AND "))
    };

    (tag_join, where_extra)
}

/// Append `t.status IN (?, ?, …)` to `conditions` and bind every
/// status into `param_values`. No-op when the filter is absent or
/// empty.
pub(super) fn apply_status_filter<'a>(
    pred: &'a SearchPredicate,
    conditions: &mut Vec<String>,
    param_values: &mut Vec<&'a dyn rusqlite::types::ToSql>,
) {
    if let Some(ref statuses) = pred.status_filter {
        if !statuses.is_empty() {
            let ph = lorvex_domain::sql_in_placeholders(statuses.len(), param_values.len());
            conditions.push(format!("t.status IN ({ph})"));
            for s in statuses {
                param_values.push(s);
            }
        }
    }
}

/// Append `t.list_id IN (?, ?, …)` to `conditions` and bind every
/// list_id into `param_values`. No-op when the filter is absent or
/// empty.
pub(super) fn apply_list_filter<'a>(
    pred: &'a SearchPredicate,
    conditions: &mut Vec<String>,
    param_values: &mut Vec<&'a dyn rusqlite::types::ToSql>,
) {
    if let Some(ref lists) = pred.list_filter {
        if !lists.is_empty() {
            let ph = lorvex_domain::sql_in_placeholders(lists.len(), param_values.len());
            conditions.push(format!("t.list_id IN ({ph})"));
            for l in lists {
                param_values.push(l);
            }
        }
    }
}

/// Append the EXISTS-form tag predicate to `conditions` and bind
/// every tag id into `param_values`. The EXISTS shape is what the
/// trigram and LIKE-fallback paths use; the canonical-FTS path keeps
/// its tag-JOIN inline because the JOIN feeds the SELECT FROM clause.
pub(super) fn apply_tag_filter_exists<'a>(
    pred: &'a SearchPredicate,
    conditions: &mut Vec<String>,
    param_values: &mut Vec<&'a dyn rusqlite::types::ToSql>,
) {
    if let Some(ref tags) = pred.tag_filter {
        if !tags.is_empty() {
            let ph = lorvex_domain::sql_in_placeholders(tags.len(), param_values.len());
            conditions.push(format!(
                "EXISTS (SELECT 1 FROM task_tags tt3 WHERE tt3.task_id = t.id AND tt3.tag_id IN ({ph}))"
            ));
            for tag in tags {
                param_values.push(tag);
            }
        }
    }
}
