use crate::contract::{
    GetTodaysTasksArgs, GET_TODAYS_LIMIT_PER_BUCKET_CAP, GET_TODAYS_LIMIT_PER_BUCKET_DEFAULT,
};
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::system::handler_support::{bounded_limit, enrich_and_fence_tasks_for_response};
use lorvex_store::repositories::task::read;
use lorvex_store::with_deferred_read_transaction;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::{types::Value as SqlValue, Connection};
use serde_json::json;

/// Convert a `Vec<TaskRow>` from the shared repo into the enriched JSON format
/// that the MCP response contract expects (with tags, depends_on, reminders).
fn task_rows_to_enriched_json(
    conn: &Connection,
    rows: &[read::TaskRow],
) -> Result<Vec<serde_json::Value>, McpError> {
    // Convert TaskRow structs to generic JSON values, then use the existing
    // enrichment pipeline (which adds tags, deps, and reminders via JOINs).
    // The enrichment functions expect SELECT * shaped JSON, so we re-query
    // using the IDs returned by the shared repo. This preserves the existing
    // enrichment pipeline while ensuring the WHERE clause is shared.
    if rows.is_empty() {
        return Ok(Vec::new());
    }

    let ids: Vec<String> = rows.iter().map(|r| r.core().id().to_string()).collect();
    let placeholders = lorvex_domain::sql_in_placeholders(ids.len(), 0);

    // Reconstruct the ORDER BY from the shared repo by using the original
    // ID order. SQLite's "ORDER BY ... IN ..." preserves nothing, so we
    // use a CASE-based ordering.
    //
    // #3403: every repo query that feeds this enrichment helper
    // (`get_overdue_tasks_for_today`, `get_exact_today_tasks`,
    // `get_high_priority_undated_tasks`) ends its ORDER BY in `id ASC`
    // as the deterministic tiebreaker required for stable OFFSET
    // pagination (CLAUDE.md core rule #4). The CASE expression below
    // reproduces the repo's row order whenever every row id is
    // distinct — which it always is, since these are primary-key ids
    // — but `ORDER BY <expr>` with a CASE that has no ELSE branch
    // emits SQL `NULL` for any unmatched id, and SQLite resolves ties
    // (and any pathological NULL) in unspecified order. Appending
    // `id ASC` as the secondary key restores the deterministic
    // tiebreaker the repo guarantees, so the IDs we re-select land
    // back in the exact order the bucket query produced.
    let order_cases: String = ids
        .iter()
        .enumerate()
        .map(|(i, id)| format!("WHEN '{}' THEN {}", id.replace('\'', "''"), i))
        .collect::<Vec<_>>()
        .join(" ");

    let sql = format!(
        "SELECT * FROM tasks WHERE id IN ({placeholders}) ORDER BY CASE id {order_cases} END, id ASC"
    );

    let params: Vec<SqlValue> = ids.into_iter().map(SqlValue::Text).collect();

    let mut enriched = query_all_as_json(conn, &sql, rusqlite::params_from_iter(params))?;
    enrich_and_fence_tasks_for_response(conn, &mut enriched)?;
    Ok(enriched)
}

pub(crate) fn get_todays_tasks(
    conn: &Connection,
    args: &GetTodaysTasksArgs,
) -> Result<String, McpError> {
    // the three bucket counts + their top-N lists must all
    // resolve against the same snapshot so the `truncated` flags stay
    // consistent with the returned rows.
    with_deferred_read_transaction(conn, |conn| {
        let &GetTodaysTasksArgs {
            limit_per_bucket,
            offset,
        } = args;
        let today = today_ymd_for_conn(conn)?;
        let limit = bounded_limit(
            limit_per_bucket,
            GET_TODAYS_LIMIT_PER_BUCKET_DEFAULT,
            GET_TODAYS_LIMIT_PER_BUCKET_CAP,
        );

        // Use shared repository predicates — single source of truth for WHERE clauses.
        let overdue_total = read::count_overdue_tasks_for_today(conn, &today)?;
        let overdue_rows = read::get_overdue_tasks_for_today(conn, &today, limit, offset)?;
        let overdue = task_rows_to_enriched_json(conn, &overdue_rows)?;

        let today_tasks_total = read::count_exact_today_tasks(conn, &today)?;
        let today_rows = read::get_exact_today_tasks(conn, &today, limit, offset)?;
        let today_tasks = task_rows_to_enriched_json(conn, &today_rows)?;

        let high_priority_undated_total = read::count_high_priority_undated_tasks(conn)?;
        let high_priority_rows = read::get_high_priority_undated_tasks(conn, limit, offset)?;
        let high_priority_undated = task_rows_to_enriched_json(conn, &high_priority_rows)?;

        // #3029-M3: per-bucket `next_offset` slots so peers can
        // walk past the per-bucket cap. The offset applies
        // symmetrically to every bucket (overdue / today /
        // high-priority-undated), so each bucket reports its own
        // truncation state against the unbounded total.
        let bucket_consumed =
            |returned: usize| -> i64 { i64::from(offset).saturating_add(returned as i64) };
        let bucket_next_offset = |returned: usize, total: i64| -> Option<u64> {
            let consumed = bucket_consumed(returned);
            (total > consumed && returned > 0).then_some(consumed as u64)
        };
        let overdue_consumed = bucket_consumed(overdue.len());
        let today_consumed = bucket_consumed(today_tasks.len());
        let hpu_consumed = bucket_consumed(high_priority_undated.len());

        let payload = json!({
            "date": today,
            "limit_per_bucket": limit,
            "offset": offset,
            "overdue": overdue,
            "today_tasks": today_tasks,
            "high_priority_undated": high_priority_undated,
            "truncated": {
                "overdue": overdue_total > overdue_consumed,
                "today_tasks": today_tasks_total > today_consumed,
                "high_priority_undated": high_priority_undated_total > hpu_consumed,
            },
            "next_offset": {
                "overdue": bucket_next_offset(overdue.len(), overdue_total),
                "today_tasks": bucket_next_offset(today_tasks.len(), today_tasks_total),
                "high_priority_undated": bucket_next_offset(
                    high_priority_undated.len(),
                    high_priority_undated_total,
                ),
            },
            "summary": {
                "overdue_count": overdue_total,
                "overdue_returned": overdue.len(),
                "today_pool_count": today_tasks_total,
                "today_tasks_returned": today_tasks.len(),
                "high_priority_undated_count": high_priority_undated_total,
                "high_priority_undated_returned": high_priority_undated.len(),
                // #2750 — canonical field names:
                //   `total_matching` — pool size across all three buckets
                //                      (WHERE-matched, not all returned)
                //   `count`          — length of the returned rows across all
                //                      three buckets
                "total_matching": overdue_total + today_tasks_total + high_priority_undated_total,
                "count": overdue.len() + today_tasks.len() + high_priority_undated.len(),
            },
            "total_matching": overdue_total + today_tasks_total + high_priority_undated_total,
            "returned": overdue.len() + today_tasks.len() + high_priority_undated.len(),
            "any_truncated": overdue_total > overdue_consumed
                || today_tasks_total > today_consumed
                || high_priority_undated_total > hpu_consumed,
        });
        Ok(serde_json::to_string(&payload)?)
    })
}
