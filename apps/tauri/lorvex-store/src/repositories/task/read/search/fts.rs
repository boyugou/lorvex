//! Canonical `tasks_fts` (`unicode61`) search path with BM25 ranking.

use lorvex_domain::naming::{STATUS_OPEN, STATUS_SOMEDAY};
use lorvex_domain::query::*;
use rusqlite::Connection;

use crate::error::StoreError;

use super::super::{task_from_row, SearchResult, TaskRow, TASK_COLUMNS_QUALIFIED_T};
use super::filters::build_fts_filter_scaffolding;

/// Full-text search tasks with optional filters.
///
/// Uses the `tasks_fts` FTS5 table. The query string is sanitized via
/// `lorvex_domain::sanitize_fts_query` before being passed to MATCH.
/// Optional status, list, and tag filters narrow the result set.
///
/// ## Ranking model
///
/// The ORDER BY is `status_bucket ASC, bm25 ASC, updated_at DESC`.
/// Status is the **primary** ranking modifier and BM25 is the
/// within-bucket tiebreaker — not the other way around. The explicit
/// BM25 column weights `(title=10, body=1, ai_notes=0.5)` shape
/// relevance inside a status bucket; they do NOT promote a
/// completed task above an open one regardless of term strength.
///
/// This is intentional: the UX intent of `search_tasks` is "show
/// me open work that matches" first, "closed history" second. A
/// completed task with a perfect title hit should still rank
/// below an open task whose match is only a body-term hit. If a
/// future change flips to `bm25 * status_multiplier`, update this
/// comment and the rank_pins tests below.
///
/// Status filter placement: the `t.status IN (...)` predicate sits
/// OUTSIDE the MATCH (regular WHERE), so BM25's term-frequency /
/// inverse-document-frequency statistics are computed against the
/// full corpus (open + completed + cancelled). That slightly
/// dilutes IDF for terms common in completed-task titles, but
/// keeping the filter outside MATCH is structurally required:
/// FTS5 MATCH columns cannot reference non-FTS columns.
// demoted to `pub(crate)` so future external callers
// can't reach for the shorter name and silently lose CJK results.
// The `unicode61` FTS tokenizer treats CJK runs as opaque tokens, so
// a bare MATCH of `中文` returns nothing; the CJK-aware
// `search_tasks_with_fallback` is the only public entrypoint.
// gated on `cfg(test)` because production call-paths
// go through the counted / fallback variants which duplicate this
// logic; the bare function exists solely for FTS-only behaviour
// tests. Production builds no longer ship the dead path.
#[cfg(test)]
pub(crate) fn search_tasks(
    conn: &Connection,
    pred: &SearchPredicate,
    page: Pagination,
) -> Result<Vec<TaskRow>, StoreError> {
    let sanitized = lorvex_domain::sanitize_fts_query(&pred.query);
    if sanitized.is_empty() {
        return Ok(vec![]);
    }

    let mut param_values: Vec<&dyn rusqlite::types::ToSql> = vec![&sanitized];
    let (tag_join, where_extra) = build_fts_filter_scaffolding(pred, &mut param_values);

    let limit_idx = param_values.len() + 1;
    let offset_idx = param_values.len() + 2;
    param_values.push(&page.limit);
    param_values.push(&page.offset);

    let sql = format!(
        "SELECT {cols} FROM tasks t \
         JOIN tasks_fts ON t.rowid = tasks_fts.rowid \
         {tag_join} \
         WHERE tasks_fts MATCH ?1{where_extra} \
         ORDER BY CASE WHEN t.status = '{STATUS_OPEN}' THEN 0 WHEN t.status = '{STATUS_SOMEDAY}' THEN 1 ELSE 2 END, bm25(tasks_fts, 10.0, 1.0, 0.5, 3.0), t.updated_at DESC, t.id ASC \
         LIMIT ?{limit_idx} OFFSET ?{offset_idx}",
        cols = &*TASK_COLUMNS_QUALIFIED_T,
    );

    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(param_values.as_slice(), task_from_row)?;
    Ok(rows.collect::<Result<_, _>>()?)
}

/// FTS5 search returning rows + total count.
pub(super) fn search_tasks_fts_counted(
    conn: &Connection,
    sanitized: &str,
    pred: &SearchPredicate,
    page: Pagination,
) -> Result<SearchResult, StoreError> {
    // The FTS path uses a JOIN form for the tag filter (rather than
    // EXISTS) because the JOIN feeds the SELECT FROM clause; the
    // shared `apply_tag_filter_exists` is the right helper for the
    // trigram + LIKE paths only — see `build_fts_filter_scaffolding`.
    let mut param_values: Vec<&dyn rusqlite::types::ToSql> = vec![&sanitized];
    let (tag_join, where_extra) = build_fts_filter_scaffolding(pred, &mut param_values);

    // Count total matches.
    let count_sql = format!(
        "SELECT COUNT(*) FROM tasks t \
         JOIN tasks_fts ON t.rowid = tasks_fts.rowid \
         {tag_join} \
         WHERE tasks_fts MATCH ?1{where_extra}"
    );
    // route the search count + data SELECTs through
    // `prepare_cached` so the per-keystroke search surface (#2966
    // residue) reuses the prepared statement when the filter shape
    // (status / list / tag predicates) is stable across keystrokes.
    let total_matching: i64 = {
        let mut count_stmt = conn.prepare_cached(&count_sql)?;
        count_stmt.query_row(param_values.as_slice(), |row| row.get(0))?
    };

    // Fetch ranked results.
    let limit_idx = param_values.len() + 1;
    let offset_idx = param_values.len() + 2;
    param_values.push(&page.limit);
    param_values.push(&page.offset);

    let cols = &*TASK_COLUMNS_QUALIFIED_T;

    let sql = format!(
        "SELECT {cols} FROM tasks t \
         JOIN tasks_fts ON t.rowid = tasks_fts.rowid \
         {tag_join} \
         WHERE tasks_fts MATCH ?1{where_extra} \
         ORDER BY CASE WHEN t.status = '{STATUS_OPEN}' THEN 0 WHEN t.status = '{STATUS_SOMEDAY}' THEN 1 ELSE 2 END, bm25(tasks_fts, 10.0, 1.0, 0.5, 3.0), t.updated_at DESC, t.id ASC \
         LIMIT ?{limit_idx} OFFSET ?{offset_idx}"
    );

    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(param_values.as_slice(), task_from_row)?;
    let rows: Result<Vec<TaskRow>, _> = rows.collect();

    Ok(SearchResult {
        rows: rows?,
        total_matching,
    })
}
