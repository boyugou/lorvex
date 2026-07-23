//! LIKE-based fallback search path.

use lorvex_domain::query::*;
use rusqlite::Connection;

use crate::error::StoreError;

use super::super::{task_from_row, SearchResult, TaskRow, TASK_COLUMNS_QUALIFIED_T, TASK_ORDER_BY};
use super::filters::{apply_list_filter, apply_status_filter, apply_tag_filter_exists};

/// Count total — but cap the inner scan so a CJK / single-char
/// substring query against a workspace with millions of rows
/// doesn't materialize a full COUNT(*). The wrapper renders any
/// cap-saturated result as "10000+" to the UI: if the count is
/// exactly `LIKE_FALLBACK_COUNT_CAP` we know the real total is
/// at least that, but we deliberately stopped scanning. The FTS
/// and trigram paths are O(matches) so they don't need this
/// ceiling; the LIKE fallback is the one that can full-scan.
const LIKE_FALLBACK_COUNT_CAP: i64 = 10_000;

/// LIKE-based fallback search with tag-name matching.
///
/// The LIKE fallback is the only search path available for CJK
/// queries (the `unicode61` FTS tokenizer cannot substring-match
/// CJK text), so this path scores each row by where the query
/// matched. Returning matches in whatever incidental tiebreaker
/// `ORDER BY` the caller supplies would rank an exact title match
/// on "草莓" the same as an ai_notes substring hit in a 500-word
/// body — search would feel broken for Chinese / Japanese users.
/// Scoring rules:
///
///   * exact title equality          → 100 (strongest signal)
///   * title substring               →  50
///   * body substring                →  10
///   * ai_notes substring            →   5
///
/// Rows sort by `match_score DESC`, then by the canonical
/// `TASK_ORDER_BY` (`priority_effective ASC, due_date ASC NULLS LAST,
/// id ASC`) so within-bucket ordering stays stable under OFFSET
/// pagination.
///
/// Scope note: tag-name matches still contribute to `WHERE` (so a
/// tag-only hit surfaces), but do not contribute to the score.
/// Promoting tag hits into the ranking is tracked as a follow-up on
/// #2715.
pub(super) fn search_tasks_like(
    conn: &Connection,
    raw_query: &str,
    pred: &SearchPredicate,
    page: Pagination,
) -> Result<SearchResult, StoreError> {
    // cap the LIKE pattern length before construction so a
    // 10k-char pasted blob doesn't turn into an O(rows × pattern_len)
    // full-scan. FTS path already truncates via sanitize_fts_query.
    let raw_query = lorvex_domain::fts::cap_fts_query_length(raw_query);
    // `?1` is the bare (LIKE-escaped) query for exact-title equality;
    // `?2` is the same bare pattern that the SQL wraps with `'%' || ?2
    // || '%'` on each scored column. Keeping them separate lets us give
    // exact-title matches the full 100-point weight without also
    // awarding the substring tier.
    let escaped = lorvex_domain::escape_like(raw_query);

    let mut conditions = vec![
        "t.archived_at IS NULL".to_string(),
        "(t.title LIKE '%' || ?2 || '%' ESCAPE '\\' \
          OR t.body LIKE '%' || ?2 || '%' ESCAPE '\\' \
          OR t.ai_notes LIKE '%' || ?2 || '%' ESCAPE '\\' \
          OR EXISTS (SELECT 1 FROM task_tags tt2 JOIN tags tg ON tg.id = tt2.tag_id \
                     WHERE tt2.task_id = t.id AND tg.display_name LIKE '%' || ?2 || '%' ESCAPE '\\'))"
            .to_string(),
    ];
    let mut param_values: Vec<&dyn rusqlite::types::ToSql> = vec![&escaped, &escaped];

    apply_status_filter(pred, &mut conditions, &mut param_values);
    apply_list_filter(pred, &mut conditions, &mut param_values);
    apply_tag_filter_exists(pred, &mut conditions, &mut param_values);

    let where_clause = conditions.join(" AND ");

    let count_sql = format!(
        "SELECT COUNT(*) FROM (SELECT 1 FROM tasks t WHERE {where_clause} LIMIT {LIKE_FALLBACK_COUNT_CAP})"
    );
    // LIKE-fallback count + data SELECTs land in the
    // statement cache alongside the FTS / trigram paths.
    let total_matching: i64 = {
        let mut count_stmt = conn.prepare_cached(&count_sql)?;
        count_stmt.query_row(param_values.as_slice(), |row| row.get(0))?
    };

    // Fetch results ranked by relevance, then by the canonical
    // `TASK_ORDER_BY` for a stable tiebreaker. `LOWER(...)` on both
    // sides of each comparison gives case-insensitive scoring for
    // Latin-script queries without penalizing CJK (where LOWER is a
    // no-op) — see issue #2715.
    let limit_idx = param_values.len() + 1;
    let offset_idx = param_values.len() + 2;
    param_values.push(&page.limit);
    param_values.push(&page.offset);

    let sql = format!(
        "SELECT {cols}, ( \
             (CASE WHEN LOWER(t.title) LIKE LOWER(?1) ESCAPE '\\' THEN 100 ELSE 0 END) \
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
