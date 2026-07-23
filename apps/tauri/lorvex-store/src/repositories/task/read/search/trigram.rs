//! `tasks_fts_trigram` search path for CJK / whitespace-less queries.

use lorvex_domain::query::*;
use rusqlite::Connection;

use crate::error::StoreError;

use super::super::{task_from_row, SearchResult, TaskRow, TASK_COLUMNS_QUALIFIED_T, TASK_ORDER_BY};
use super::filters::{apply_list_filter, apply_status_filter, apply_tag_filter_exists};

/// Trigram-FTS5 search for CJK (and other whitespace-less) queries.
///
/// CJK runs are opaque tokens to the main `tasks_fts`
/// `unicode61` tokenizer, so every CJK keystroke drop into
/// `search_tasks_like` and full-scan the base table. The
/// `tasks_fts_trigram` virtual table indexes 3-character windows so
/// substring MATCH is an index-backed lookup.
///
/// Ranking mirrors `search_tasks_like`: exact title equality outranks
/// title-substring, title outranks body, body outranks ai_notes. BM25
/// from the trigram index would be misleading here — trigram
/// tokenization makes every CJK character contribute independently,
/// inflating short-title IDF weight against long-body rows regardless
/// of relevance. The column-weighted score pins the same contract as
/// the LIKE path so CJK users see a consistent result order whichever
/// index backed the lookup.
///
/// Tag-name substring hits are still carried as a second OR branch so
/// a CJK query that matches only a tag display_name continues to
/// surface. Tag text is not duplicated into the trigram FTS column —
/// tags live on a small table and the existing `EXISTS (...)` on
/// `task_tags` is cheap.
pub(super) fn search_tasks_trigram_counted(
    conn: &Connection,
    raw_query: &str,
    pred: &SearchPredicate,
    page: Pagination,
) -> Result<SearchResult, StoreError> {
    let raw_query = lorvex_domain::fts::cap_fts_query_length(raw_query);
    // FTS5 MATCH strings use `"..."` to quote phrases. Double quotes
    // inside the query have to be doubled to escape — this is the
    // FTS5 equivalent of SQL string-literal escaping. Keeping the
    // query inside one phrase means punctuation/whitespace in the
    // user input can't accidentally get parsed as FTS operators.
    let fts_query = format!("\"{}\"", raw_query.replace('"', "\"\""));
    // The tag display_name OR branch keeps using LIKE — trigram
    // doesn't index tag text on this table.
    let tag_like = lorvex_domain::escape_like(raw_query);

    // Match set = trigram hits ∪ tag-name LIKE hits. Keeping the two
    // branches as `IN` subqueries (rather than a JOIN with MATCH in an
    // OR) lets SQLite pick each branch's dedicated index path: the
    // FTS5 MATCH flows through the virtual table's posting-list
    // lookup, and the tag branch hits `task_tags(task_id)` directly.
    let mut conditions = vec![
        "t.archived_at IS NULL".to_string(),
        "(t.rowid IN (SELECT rowid FROM tasks_fts_trigram WHERE tasks_fts_trigram MATCH ?1) \
          OR EXISTS (SELECT 1 FROM task_tags tt2 JOIN tags tg ON tg.id = tt2.tag_id \
                     WHERE tt2.task_id = t.id AND tg.display_name LIKE '%' || ?2 || '%' ESCAPE '\\'))"
            .to_string(),
    ];
    let mut param_values: Vec<&dyn rusqlite::types::ToSql> = vec![&fts_query, &tag_like];

    apply_status_filter(pred, &mut conditions, &mut param_values);
    apply_list_filter(pred, &mut conditions, &mut param_values);
    apply_tag_filter_exists(pred, &mut conditions, &mut param_values);

    let where_clause = conditions.join(" AND ");

    // Count total matches.
    let count_sql = format!("SELECT COUNT(*) FROM tasks t WHERE {where_clause}");
    // trigram-FTS count + data SELECTs share the
    // same per-keystroke surface as the standard FTS path; cache the
    // prepared statements identically.
    let total_matching: i64 = {
        let mut count_stmt = conn.prepare_cached(&count_sql)?;
        count_stmt.query_row(param_values.as_slice(), |row| row.get(0))?
    };

    let limit_idx = param_values.len() + 1;
    let offset_idx = param_values.len() + 2;
    param_values.push(&page.limit);
    param_values.push(&page.offset);

    // `?2` is the escaped bare query reused for title-scoring LIKE checks.
    // `LOWER(...)` is a no-op on CJK but keeps Latin-mixed CJK queries
    // case-consistent with the Latin-script LIKE fallback.
    let sql = format!(
        "SELECT {cols}, ( \
             (CASE WHEN LOWER(t.title) LIKE LOWER(?2) ESCAPE '\\' THEN 100 ELSE 0 END) \
             + (CASE WHEN LOWER(t.title) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 50 ELSE 0 END) \
             + (CASE WHEN LOWER(t.body) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 10 ELSE 0 END) \
             + (CASE WHEN LOWER(t.ai_notes) LIKE LOWER('%' || ?2 || '%') ESCAPE '\\' THEN 5 ELSE 0 END) \
         ) AS match_score \
         FROM tasks t \
         WHERE {where_clause} \
         ORDER BY match_score DESC, {TASK_ORDER_BY} \
         LIMIT ?{limit_idx} OFFSET ?{offset_idx}",
        cols = &*TASK_COLUMNS_QUALIFIED_T,
    );

    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(param_values.as_slice(), task_from_row)?;
    let rows: Result<Vec<TaskRow>, _> = rows.collect();

    Ok(SearchResult {
        rows: rows?,
        total_matching,
    })
}
