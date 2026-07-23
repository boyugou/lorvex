//! Database lookups feeding the Windows Jump List indexers. Lifts
//! the prepare/query/log helper so per-list, per-id-batch, and
//! full-reindex paths read indexable rows through the same
//! projection.

use super::TaskRow;

/// Shared prepare/map/collect ladder so every reindex helper reads
/// indexable rows through the same projection. Mirrors the macOS
/// `read_spotlight_rows` helper.
pub(super) fn read_jump_list_rows<P>(
    conn: &rusqlite::Connection,
    sql: &str,
    params: P,
    context: &'static str,
) -> Option<Vec<TaskRow>>
where
    P: rusqlite::Params,
{
    match super::super::queries::read_indexable_rows(conn, sql, params) {
        Ok(rows) => Some(
            rows.into_iter()
                .map(|r| TaskRow {
                    id: r.id,
                    title: r.title,
                    body: r.body,
                    list_name: r.list_name,
                    due_date: r.due_date,
                })
                .collect(),
        ),
        Err(e) => {
            super::super::log_spotlight_error(context, &e.to_string());
            None
        }
    }
}

/// gated `#[cfg(test)]` to mirror the macOS
/// `query_spotlight_task_row` symmetry. Both helpers exist solely
/// to back regression tests for the `WHERE status IN ('open',
/// 'someday')` discoverability invariant — wiring the helper into
/// `index_task` would require restructuring the public callsite to
/// fetch a connection, which is a separate refactor. Until then,
/// keep the dead-code surface gated identically across platforms.
#[cfg(test)]
pub(super) fn query_task_row(
    conn: &rusqlite::Connection,
    task_id: &str,
) -> Result<Option<TaskRow>, rusqlite::Error> {
    use rusqlite::OptionalExtension;

    // shared projection/visibility helper.
    conn.prepare_cached(&super::super::queries::select_by_id_sql())?
        .query_row(rusqlite::params![task_id], |row| {
            Ok(TaskRow {
                id: row.get(0)?,
                title: row.get(1)?,
                body: row.get(2)?,
                list_name: row.get(3)?,
                due_date: row.get(4)?,
            })
        })
        .optional()
}
