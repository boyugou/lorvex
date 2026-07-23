//! Batched write helpers for the `task_dependencies` edge table.
//!
//! These functions replace N+1 individual INSERT/DELETE loops with single
//! multi-row SQL statements. Sync outbox enqueue remains the caller's
//! responsibility (one event per edge) and is NOT handled here.

use crate::error::StoreError;
use crate::transaction::with_immediate_transaction;
use lorvex_domain::TaskId;
use rusqlite::{params_from_iter, types::Value as SqlValue, Connection};

/// hard upper bound on a single `depends_on_ids` batch.
/// SQLite's default `SQLITE_MAX_VARIABLE_NUMBER` is 999, and the
/// preflight `WHERE id IN (?, ?, …)` consumes one bind slot per
/// endpoint plus one for `task_id`. Capping the batch at 256 leaves
/// headroom for fixed-position parameters (`task_id`, `version`,
/// `now`) and for the multi-row INSERT below which adds three more.
/// Beyond ~250 dependency edges per task the dependency graph becomes
/// indistinguishable from a tag list — split the request at the IPC
/// boundary if you genuinely need more.
const MAX_DEPENDS_ON_BATCH: usize = 256;

/// Insert multiple dependency edges in a single multi-row INSERT statement.
///
/// Returns the number of rows affected. Edges that already exist are silently
/// ignored (`INSERT OR IGNORE`). The caller is responsible for enqueuing sync
/// events for each edge.
///
/// preflights both endpoints (`task_id` and every entry in
/// `depends_on_ids`) for `archived_at IS NULL`. Without this check a UI race
/// could re-introduce a soft-deleted task into the dependency graph,
/// reviving it visually because the dependency surface skips the
/// `archived_at IS NULL` filter applied by the ordinary task read paths.
/// Returns [`StoreError::Validation`] when any endpoint is missing or
/// archived so the caller surfaces a typed validation error rather than
/// a generic database failure.
///
/// the preflight + INSERT pair must run inside a single
/// transaction so a concurrent `update_task` that archives an endpoint
/// between the two statements cannot slip a tombstoned row back into the
/// dependency graph (TOCTOU). When invoked outside an existing transaction
/// (`is_autocommit()`), we wrap in `BEGIN IMMEDIATE`; nested callers that
/// already hold a transaction skip the wrap and rely on their outer
/// boundary's atomicity.
pub fn insert_dependency_edges_batch(
    conn: &Connection,
    task_id: &TaskId,
    depends_on_ids: &[TaskId],
    version: &str,
    now: &str,
) -> Result<usize, StoreError> {
    if depends_on_ids.is_empty() {
        return Ok(0);
    }

    // defense-in-depth. The IPC boundary is supposed
    // to clamp the batch to MAX_DEPENDS_ON_BATCH before we ever see
    // it; this assert is the repository-level backstop in case a
    // future caller (CLI scripting, sync apply) bypasses the IPC
    // gate. Returning a typed `Validation` error keeps the surface
    // identical to the IPC clamp so the user-visible error is the
    // same regardless of which path overshoots.
    if depends_on_ids.len() > MAX_DEPENDS_ON_BATCH {
        return Err(StoreError::Validation(format!(
            "task_dependency batch contains {} edges, which exceeds the \
             {}-edge per-call cap (split into multiple calls)",
            depends_on_ids.len(),
            MAX_DEPENDS_ON_BATCH
        )));
    }

    if conn.is_autocommit() {
        with_immediate_transaction(conn, |c| {
            insert_dependency_edges_batch_inner(c, task_id, depends_on_ids, version, now)
        })
    } else {
        insert_dependency_edges_batch_inner(conn, task_id, depends_on_ids, version, now)
    }
}

fn insert_dependency_edges_batch_inner(
    conn: &Connection,
    task_id: &TaskId,
    depends_on_ids: &[TaskId],
    version: &str,
    now: &str,
) -> Result<usize, StoreError> {
    // reject self-dependency edges before the
    // preflight (#3027-M5). The schema carries a `CHECK (task_id !=
    // depends_on_task_id)` backstop on `task_dependencies`, but
    // bouncing off the constraint surfaces as a generic
    // `StoreError::Sql` constraint-violation; AI assistants and the
    // CLI both want a typed `Validation` error so they can render a
    // human-actionable message ("a task cannot depend on itself")
    // without parsing SQLite error text. The dedup pass below
    // collapses `(A, [A])` to a single endpoint, hiding the
    // self-dep at the preflight level — without this explicit
    // rejection the request would only fail at the INSERT step,
    // wrapped as a generic constraint failure.
    for dep_id in depends_on_ids {
        if dep_id == task_id {
            return Err(StoreError::Validation(format!(
                "task_dependency self-reference rejected: task `{task_id}` \
                 cannot depend on itself"
            )));
        }
    }

    // gather every endpoint that must be live.
    // `task_id` is always one; `depends_on_ids` adds N more. We then
    // verify the count of rows where `archived_at IS NULL` matches —
    // any mismatch means a task is missing OR is in the trash. Either
    // way the edge would point at a row the rest of the system
    // ignores, so we refuse to create it.
    let mut endpoints: Vec<String> = Vec::with_capacity(1 + depends_on_ids.len());
    endpoints.push(task_id.as_str().to_string());
    for dep_id in depends_on_ids {
        endpoints.push(dep_id.as_str().to_string());
    }
    endpoints.sort();
    endpoints.dedup();

    let placeholders = lorvex_domain::sql_in_placeholders(endpoints.len(), 0);
    let preflight_sql =
        format!("SELECT COUNT(*) FROM tasks WHERE id IN ({placeholders}) AND archived_at IS NULL");
    let mut preflight_params: Vec<SqlValue> = Vec::with_capacity(endpoints.len());
    for id in &endpoints {
        preflight_params.push(SqlValue::Text(id.clone()));
    }
    // route through `prepare_cached` keyed by the
    // exact placeholder count. A single apply transaction
    // typically reaches this preflight 1-3 times with the same N,
    // so the cache key (one entry per N) hits warm after the first
    // call.
    // time.
    let live: i64 = conn
        .prepare_cached(&preflight_sql)?
        .query_row(params_from_iter(preflight_params.iter()), |row| row.get(0))?;
    // Compare in i64 space — `endpoints.len() as i64` always fits
    // (a single dependency batch is bounded by the IPC payload cap),
    // whereas `live as usize` would silently lose the high bit on
    // 32-bit builds if a corrupted COUNT(*) somehow exceeded
    // `usize::MAX`. The bug class is theoretical given the bounds
    // here but the safer cast direction is free.
    if live != endpoints.len() as i64 {
        return Err(StoreError::Validation(
            "task_dependency endpoint missing or archived".to_string(),
        ));
    }

    let mut sql = String::from(
        "INSERT OR IGNORE INTO task_dependencies (task_id, depends_on_task_id, version, created_at) VALUES ",
    );
    let mut params: Vec<SqlValue> = Vec::with_capacity(3 + depends_on_ids.len());

    params.push(SqlValue::Text(task_id.as_str().to_string()));
    params.push(SqlValue::Text(version.to_string()));
    params.push(SqlValue::Text(now.to_string()));

    use std::fmt::Write as _;
    for (i, dep_id) in depends_on_ids.iter().enumerate() {
        if i > 0 {
            sql.push_str(", ");
        }
        let param_idx = 4 + i;
        // `write!` formats directly into the SQL builder buffer; the
        // previous `push_str(&format!(...))` allocated a temp String
        // per dependency just to copy it. Writing into `String` is
        // infallible.
        write!(sql, "(?1, ?{param_idx}, ?2, ?3)").expect("write! to String is infallible");
        params.push(SqlValue::Text(dep_id.as_str().to_string()));
    }

    // `prepare_cached` so the per-N INSERT shape stays
    // warm across calls in the same writer connection. Same-N
    // batches in a single apply transaction reuse the parsed plan
    // after the first call.
    let mut stmt = conn.prepare_cached(&sql)?;
    let affected = stmt.execute(params_from_iter(params.iter()))?;
    Ok(affected)
}

/// Delete specific dependency edges in a single statement using `IN (...)`.
///
/// Returns the number of rows deleted. The caller is responsible for enqueuing
/// sync delete events for each removed edge.
pub fn delete_dependency_edges_batch(
    conn: &Connection,
    task_id: &TaskId,
    depends_on_ids: &[TaskId],
) -> Result<usize, StoreError> {
    if depends_on_ids.is_empty() {
        return Ok(0);
    }

    let placeholders = lorvex_domain::sql_in_placeholders(depends_on_ids.len(), 1);

    let sql = format!(
        "DELETE FROM task_dependencies WHERE task_id = ?1 AND depends_on_task_id IN ({placeholders})"
    );

    let mut params: Vec<SqlValue> = Vec::with_capacity(1 + depends_on_ids.len());
    params.push(SqlValue::Text(task_id.as_str().to_string()));
    for dep_id in depends_on_ids {
        params.push(SqlValue::Text(dep_id.as_str().to_string()));
    }

    let mut stmt = conn.prepare_cached(&sql)?;
    let affected = stmt.execute(params_from_iter(params.iter()))?;
    Ok(affected)
}
