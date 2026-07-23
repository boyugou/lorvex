//! Database lookups feeding the CoreSpotlight indexers. Lifts the
//! shared `TaskRow` shape + the prepare/query/log helper so per-list,
//! per-id-batch, and full-reindex paths read indexable rows through
//! the same projection.

use super::TaskRow;

/// Lifts the four-step (prepare → map → collect →
/// log_spotlight_error on each step) read pattern into a single
/// helper. Callers pass `context` so the diagnostic naming stays
/// unique per call site and the per-call fingerprints in
/// `error_logs` remain distinguishable.
pub(super) fn read_spotlight_rows<P>(
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

#[cfg(test)]
pub(super) fn query_spotlight_task_row(
    conn: &rusqlite::Connection,
    task_id: &str,
) -> Result<Option<TaskRow>, rusqlite::Error> {
    use rusqlite::OptionalExtension;

    // use the shared projection/predicate.
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
