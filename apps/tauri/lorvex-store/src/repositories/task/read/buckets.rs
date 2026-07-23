//! Day-bucket predicate builders shared across the today / overdue / upcoming
//! read paths, plus the canonical aggregate counter for the three buckets.

use lorvex_domain::naming::STATUS_OPEN;
use rusqlite::{params, Connection};

use crate::error::StoreError;

use super::OpenTaskDayBucketCounts;

pub(super) fn overdue_bucket_predicate(task_alias: &str, date_placeholder: &str) -> String {
    format!("{task_alias}.due_date < {date_placeholder}")
}

pub(super) fn today_pool_bucket_predicate(task_alias: &str, date_placeholder: &str) -> String {
    // the prior column-split-OR form couldn't use the
    // `idx_tasks_action_date_open` expression index (COALESCE on
    // planned_date/due_date WHERE status NOT IN
    // ('cancelled','completed')), so every open-task bucket count on
    // every shell tick full-scanned via `idx_tasks_status`.
    //
    // The COALESCE form is algebraically equivalent:
    //   Case A: planned_date NOT NULL → COALESCE = planned_date, the
    //           `<= today` matches the original `planned_date <= today`.
    //   Case B: planned_date IS NULL → COALESCE = due_date. The
    //           `due_date IS NULL OR due_date >= today` guard already
    //           excludes the overdue case (due_date < today), so
    //           `COALESCE <= today AND due_date >= today` collapses
    //           to `due_date = today` — matching the original.
    //
    // The deadline guard stays as an OR because it encodes "no
    // deadline OR deadline not yet passed" — a column choice, not an
    // index-expression one.
    format!(
        "(COALESCE({task_alias}.planned_date, {task_alias}.due_date) <= {date_placeholder} \
          AND ({task_alias}.due_date IS NULL OR {task_alias}.due_date >= {date_placeholder}))"
    )
}

pub(super) fn upcoming_bucket_predicate(
    task_alias: &str,
    from_placeholder: &str,
    to_placeholder: &str,
) -> String {
    format!(
        "(({task_alias}.due_date IS NULL OR {task_alias}.due_date >= {from_placeholder}) \
          AND COALESCE({task_alias}.planned_date, {task_alias}.due_date) > {from_placeholder} \
          AND COALESCE({task_alias}.planned_date, {task_alias}.due_date) <= {to_placeholder})"
    )
}

/// Count the canonical open-task day buckets from one shared owner.
///
/// This is the aggregate counterpart to `get_overdue_tasks`, `get_today_tasks`,
/// and `get_upcoming_tasks`, so overview/widget/query surfaces don't have to
/// compose these counts independently.
///
/// Today / overdue / upcoming all read from the same `tasks` table with the
/// same `status='open' AND archived_at IS NULL` prefix, so a single
/// `SUM(CASE WHEN ...)` aggregate computes all three buckets from one indexed
/// scan instead of three independent counts. Today-view, widget snapshot,
/// and overview all open this on every keystroke / data event, so cutting
/// from 3 indexed scans to 1 is a real saving.
pub fn count_open_task_day_buckets(
    conn: &Connection,
    as_of_date: chrono::NaiveDate,
    upcoming_days: u32,
) -> Result<OpenTaskDayBucketCounts, StoreError> {
    // The 3 bucket predicates and the outer aggregate SQL are fully
    // determined by the static `("tasks", "?1", "?2")` tuple; cache
    // the rendered SQL once for the process. Today-view, widget
    // snapshot, and the overview surface all hit this on every shell
    // tick — the per-call ~600-byte format! disappears entirely.
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let from = as_of_date.format("%Y-%m-%d").to_string();
    let to = (as_of_date + chrono::Duration::days(i64::from(upcoming_days)))
        .format("%Y-%m-%d")
        .to_string();
    let sql = SQL.get_or_init(|| {
        let overdue = overdue_bucket_predicate("tasks", "?1");
        let today_pool = today_pool_bucket_predicate("tasks", "?1");
        let upcoming = upcoming_bucket_predicate("tasks", "?1", "?2");
        format!(
            "SELECT \
                SUM(CASE WHEN {overdue} THEN 1 ELSE 0 END) AS overdue, \
                SUM(CASE WHEN {today_pool} THEN 1 ELSE 0 END) AS today_pool, \
                SUM(CASE WHEN {upcoming} THEN 1 ELSE 0 END) AS upcoming \
             FROM tasks \
             WHERE status = '{STATUS_OPEN}' AND tasks.archived_at IS NULL"
        )
    });
    // SUM over zero rows yields NULL — coalesce via Option<i64> so an
    // empty-table install reports `0`s instead of erroring out.
    let (overdue_count, today_pool_count, upcoming_count): (Option<i64>, Option<i64>, Option<i64>) =
        conn.prepare_cached(sql)?
            .query_row(params![from, to], |row| {
                Ok((row.get(0)?, row.get(1)?, row.get(2)?))
            })?;
    Ok(OpenTaskDayBucketCounts {
        overdue: overdue_count.unwrap_or(0),
        today_pool: today_pool_count.unwrap_or(0),
        upcoming: upcoming_count.unwrap_or(0),
    })
}
