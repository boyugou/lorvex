// Shared task-row queries
// ---------------------------------------------------------------------------
//
// Every reindex/index helper consumes the same five-column SELECT
// over `tasks LEFT JOIN lists`. Centralizing the projection and the
// `WHERE status IN ('open','someday')` discoverability invariant
// here keeps macOS and Windows implementations from drifting when
// the schema changes (e.g. moving `name` to a new lists table, or
// adding a row-visibility predicate to the discoverability surface).
use rusqlite::{Connection, ToSql};

/// Canonical projection for a task that is eligible for the
/// platform-native search surface (Spotlight / Jump List).
pub(super) const SELECT_INDEXABLE_TASK_PROJECTION: &str =
    "t.id, t.title, t.body, l.name, t.due_date";

/// Canonical visibility predicate. Completed and cancelled tasks
/// are NOT useful in OS-level search and are excluded from the
/// index. The schema CHECK keeps `status` to a closed enum so a
/// future status added without updating this predicate would be
/// caught at code-review time.
pub(super) const VISIBILITY_PREDICATE: &str = "t.status IN ('open', 'someday')";

/// Common FROM clause for the indexable-task projection.
pub(super) const FROM_CLAUSE: &str = "FROM tasks t LEFT JOIN lists l ON l.id = t.list_id";

/// `SELECT … WHERE t.id = ?1` — used by the test-only single-row
/// fetch helpers that lock in the visibility invariant.
#[cfg(test)]
pub(super) fn select_by_id_sql() -> String {
    format!(
        "SELECT {SELECT_INDEXABLE_TASK_PROJECTION} {FROM_CLAUSE} WHERE t.id = ?1 AND {VISIBILITY_PREDICATE}",
    )
}

/// `SELECT … WHERE t.list_id = ?1` — used after a list rename or
/// task reassignment to refresh every indexed task tied to a
/// list.
pub(super) fn select_by_list_id_sql() -> String {
    format!(
        "SELECT {SELECT_INDEXABLE_TASK_PROJECTION} {FROM_CLAUSE} WHERE t.list_id = ?1 AND {VISIBILITY_PREDICATE}",
    )
}

/// `SELECT … WHERE t.id IN (…)` with the placeholder fan-out
/// rendered for the requested batch size. Callers pass
/// `task_ids.len()` because rusqlite has no built-in slice-bind
/// for `IN`-clauses.
pub(super) fn select_by_id_batch_sql(batch_size: usize) -> String {
    let placeholders = (0..batch_size).map(|_| "?").collect::<Vec<_>>().join(",");
    format!(
        "SELECT {SELECT_INDEXABLE_TASK_PROJECTION} {FROM_CLAUSE} WHERE {VISIBILITY_PREDICATE} AND t.id IN ({placeholders})",
    )
}

/// `SELECT … ORDER BY t.created_at DESC` — used by the full
/// reindex paths.
pub(super) fn select_all_sql() -> String {
    format!(
        "SELECT {SELECT_INDEXABLE_TASK_PROJECTION} {FROM_CLAUSE} WHERE {VISIBILITY_PREDICATE} ORDER BY t.created_at DESC",
    )
}

/// Bind helper: turn `&[String]` into the `params_from_iter`-
/// compatible `Vec<&dyn ToSql>` callers need.
pub(super) fn ids_as_params(ids: &[String]) -> Vec<&dyn ToSql> {
    ids.iter().map(|s| s as &dyn ToSql).collect()
}

/// Convenience: prepare + map a query that returns the canonical
/// 5-column projection, decoding into `(id, title, body, list,
/// due)`. Returns the raw rows; callers wrap them in their
/// platform-specific `TaskRow` struct (the macOS and Windows
/// modules each declare their own type to avoid forcing
/// either side to import the other's representation).
pub(super) fn read_indexable_rows<P>(
    conn: &Connection,
    sql: &str,
    params: P,
) -> Result<Vec<IndexableRow>, rusqlite::Error>
where
    P: rusqlite::Params,
{
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt
        .query_map(params, |row| {
            Ok(IndexableRow {
                id: row.get(0)?,
                title: row.get(1)?,
                body: row.get(2)?,
                list_name: row.get(3)?,
                due_date: row.get(4)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(rows)
}

/// Canonical decoded row from the indexable-task projection.
#[derive(Debug, Clone)]
pub(super) struct IndexableRow {
    pub id: String,
    pub title: String,
    pub body: Option<String>,
    pub list_name: Option<String>,
    pub due_date: Option<String>,
}
