//! Tag-scoped task lookup backing the `ByTagPredicate` query.

use lorvex_domain::query::*;
use rusqlite::{params, Connection, OptionalExtension};

use crate::error::StoreError;

use super::{task_from_row, TaskRow, TASK_COLUMNS_QUALIFIED_T, TASK_ORDER_BY_QUALIFIED_T};

/// Get tasks by tag, using the `ByTagPredicate`.
///
/// If `tag_id` is provided, it is used directly. Otherwise `tag_lookup_key`
/// is used to resolve the tag first. Results follow the canonical
/// [`TASK_ORDER_BY`] sort: `priority_effective ASC, due_date ASC NULLS LAST,
/// id ASC` (#2898).
pub fn get_tasks_by_tag(
    conn: &Connection,
    pred: &ByTagPredicate,
    page: Pagination,
) -> Result<Vec<TaskRow>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let resolved_tag_id = if let Some(ref tid) = pred.tag_id {
        tid.clone()
    } else if let Some(ref key) = pred.tag_lookup_key {
        // tags.lookup_key has no UNIQUE index (the sync
        // merge needs to hold two rows mid-convergence). In the narrow
        // race window between two-devices-emit-same-key and the
        // \`merge_duplicate_tags\` sweep, duplicates are observable.
        // \`ORDER BY id LIMIT 1\` makes this read deterministic: the
        // min-id winner is the same one the merger picks, so a query
        // that observes a pre-merge state still agrees with the
        // eventually-converged state.
        let maybe_id: Option<String> = conn
            .query_row(
                "SELECT id FROM tags WHERE lookup_key = ?1 ORDER BY id ASC LIMIT 1",
                [key],
                |row| row.get(0),
            )
            .optional()?;
        match maybe_id {
            Some(id) => id,
            None => return Ok(vec![]),
        }
    } else {
        return Ok(vec![]);
    };

    // route through the cached `TASK_ORDER_BY_QUALIFIED_T`
    // LazyLock so the per-segment splitn rebuild only happens once
    // for the lifetime of the process. used
    // `COALESCE(t.priority, 3)` (sentinel 3 collides with real P3
    // tasks) and lacked the `id ASC` tiebreaker mandated by
    // `mod.rs:201-205` rule #4. The canonical `TASK_ORDER_BY` uses
    // `priority_effective` (sentinel 4) + `id ASC` for stable
    // OFFSET pagination.
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {cols} FROM tasks t \
             JOIN task_tags tt ON t.id = tt.task_id \
             WHERE tt.tag_id = ?1 AND t.archived_at IS NULL \
             ORDER BY {task_order_by} \
             LIMIT ?2 OFFSET ?3",
            cols = &*TASK_COLUMNS_QUALIFIED_T,
            task_order_by = &*TASK_ORDER_BY_QUALIFIED_T,
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(
            params![resolved_tag_id, page.limit, page.offset],
            task_from_row,
        )?
        .collect::<rusqlite::Result<_>>()?;
    Ok(rows)
}
