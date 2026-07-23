//! `search_calendar_events` — FTS5 text search over canonical calendar
//! events with an automatic LIKE fallback for CJK queries (where
//! FTS5's `unicode61` tokenizer cannot perform substring matching).

use rusqlite::Connection;

use super::super::types::CalendarEventRow;
use super::{calendar_event_from_row, calendar_event_read_projection};

/// Text search of canonical calendar events.
///
/// Searches title, description, and location. Uses the `calendar_events_fts`
/// FTS5 virtual table for Latin-script queries, with an automatic LIKE
/// fallback for CJK queries (where FTS5's `unicode61` tokenizer cannot
/// perform substring matching). Optional `from`/`to` date range narrows results.
/// Results are sorted by `(start_date ASC, start_time ASC)`.
pub fn search_calendar_events(
    conn: &Connection,
    pred: &lorvex_domain::query::CalendarSearchPredicate,
    limit: u32,
) -> Result<Vec<CalendarEventRow>, rusqlite::Error> {
    // CJK queries bypass FTS entirely — fall through to LIKE.
    if lorvex_domain::contains_cjk(&pred.query) {
        let pattern = format!("%{}%", lorvex_domain::escape_like(&pred.query));
        return run_calendar_search(
            conn,
            "(ce.title LIKE ?1 ESCAPE '\\' \
              OR ce.description LIKE ?1 ESCAPE '\\' \
              OR ce.location LIKE ?1 ESCAPE '\\')",
            &pattern,
            pred,
            limit,
        );
    }

    let fts_query = lorvex_domain::sanitize_fts_query(&pred.query);
    if fts_query.is_empty() {
        return Ok(vec![]);
    }

    run_calendar_search(
        conn,
        "ce.rowid IN (SELECT rowid FROM calendar_events_fts WHERE calendar_events_fts MATCH ?1)",
        &fts_query,
        pred,
        limit,
    )
}

/// Shared body for the FTS and LIKE branches. The two seed conditions
/// differ (FTS rowid match vs. multi-column LIKE-OR), but everything
/// downstream — date predicates, projection, ORDER BY, LIMIT, and
/// statement caching — is identical.
/// 95% byte-duplicated and any change to the projection / ORDER had
/// to be made twice.
///
/// `seed_condition` is the SQL fragment that consumes `?1`;
/// `seed_param` is the corresponding bound value (an FTS query
/// string or a `%LIKE%` pattern). Both seeds bind exactly one
/// parameter at index `?1`, which is why the date predicates start
/// at `?2`.
fn run_calendar_search(
    conn: &Connection,
    seed_condition: &str,
    seed_param: &str,
    pred: &lorvex_domain::query::CalendarSearchPredicate,
    limit: u32,
) -> Result<Vec<CalendarEventRow>, rusqlite::Error> {
    let mut conditions = vec![seed_condition.to_string()];
    let mut params: Vec<&dyn rusqlite::types::ToSql> = vec![&seed_param];

    if let Some(ref from) = pred.from {
        params.push(from);
        conditions.push(format!(
            "COALESCE(ce.end_date, ce.start_date) >= ?{}",
            params.len()
        ));
    }
    if let Some(ref to) = pred.to {
        params.push(to);
        conditions.push(format!("ce.start_date <= ?{}", params.len()));
    }

    params.push(&limit);
    let limit_idx = params.len();

    let sql = format!(
        "SELECT {} \
         FROM calendar_events ce \
         WHERE {} \
         ORDER BY ce.start_date ASC, ce.start_time ASC, ce.id ASC \
         LIMIT ?{limit_idx}",
        calendar_event_read_projection(Some("ce")),
        conditions.join(" AND ")
    );

    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(params.as_slice(), calendar_event_from_row)?;
    rows.collect()
}
