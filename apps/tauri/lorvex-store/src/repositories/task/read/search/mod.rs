//! Search-task read paths: FTS5, trigram-FTS5 (CJK), and LIKE fallback.
//!
//! The dispatcher (`search_tasks_with_fallback`) lives here; each
//! per-strategy SQL builder owns its own submodule:
//!
//! * `fts` — main `tasks_fts` (`unicode61`) BM25 path
//! * `trigram` — `tasks_fts_trigram` path for CJK / whitespace-less
//!   queries (issue #2288)
//! * `like` — full-scan LIKE fallback for missing FTS shadow
//!   tables, pure-emoji queries, and short-CJK queries
//!
//! Filter helpers (`apply_status_filter`, `apply_list_filter`,
//! `apply_tag_filter_exists`, `build_fts_filter_scaffolding`) live in
//! `filters` and are shared across strategies.
//!
//! Public surface (re-exported below) is the same as the pre-split
//! single file: `search_tasks_with_fallback` for production callers,
//! `search_tasks` for the FTS-only behaviour tests, and
//! `is_fts_schema_missing` for the live-SQLite probe tests.

mod filters;
mod fts;
mod like;
mod trigram;

use lorvex_domain::query::*;
use rusqlite::Connection;

use crate::error::StoreError;

use super::SearchResult;

#[cfg(test)]
pub(crate) use fts::search_tasks;

/// Full-text search with automatic LIKE fallback.
///
/// Picks an index strategy based on the query's script:
///
/// * CJK queries (which the main `tasks_fts` `unicode61` tokenizer
///   treats as opaque tokens) go through the `tasks_fts_trigram`
///   virtual table — a trigram-tokenized FTS5 index that supports
///   substring MATCH for CJK and other whitespace-less scripts.
///   Issue #2288 added this path to replace the prior full-table LIKE
///   scan on every CJK keystroke.
/// * Latin-script queries go through the main `tasks_fts` table,
///   which has BM25 ranking, tag-column indexing, and the short-token
///   retry behaviour documented on `search_tasks_fts_counted`.
/// * Queries with zero alphanumerics (pure emoji/punctuation) fall
///   through to the LIKE path — they would tokenize to nothing on
///   either FTS table.
/// * The LIKE scan remains the last-resort safety net for missing
///   FTS shadow tables (fresh install before migrations ran, manual
///   schema corruption).
///
/// Returns both matched rows and total matching count for pagination.
pub fn search_tasks_with_fallback(
    conn: &Connection,
    pred: &SearchPredicate,
    page: Pagination,
) -> Result<SearchResult, StoreError> {
    // short-circuit empty-or-whitespace queries. Prior
    // behaviour fell through to `should_use_like_fallback("") == true`
    // (no alphanumeric) → \`search_tasks_like\` with pattern "%%"
    // → full-table scan filtered by whatever status/list/tag
    // predicates the caller passed. An AI assistant invoking
    // \`search_tasks({query: ""})\` through MCP would trigger this
    // scan, and even with filters the LIKE path orders by raw
    // \`due_date\` instead of \`priority_effective\` (drift from
    // the canonical sort rule). Callers who want a filter-only
    // listing should use the dedicated list endpoints; refuse this
    // shape explicitly instead of silently scanning.
    if pred.query.trim().is_empty() {
        return Ok(SearchResult {
            rows: Vec::new(),
            total_matching: 0,
        });
    }

    // CJK queries hit the trigram index instead of the LIKE full-
    // scan — but only for queries long enough for trigram to index
    // (the SQLite `trigram` tokenizer emits no tokens from strings
    // shorter than 3 characters, so a 1-2 char CJK query would
    // silently return zero rows). Short CJK queries stay on the
    // LIKE path, which is faster than nothing and preserves
    // correctness; the noticeable keystroke pause only hits once
    // users type a 3+ character term anyway.
    //
    // On trigram FTS5 schema-missing errors we fall through to LIKE
    // so a fresh install / corrupted schema still returns results
    // instead of erroring the whole search.
    if lorvex_domain::contains_cjk(&pred.query) {
        if pred.query.chars().count() >= 3 {
            match trigram::search_tasks_trigram_counted(conn, &pred.query, pred, page) {
                Ok(result) => return Ok(result),
                Err(e) => {
                    if !is_fts_schema_missing(&e) {
                        return Err(e);
                    }
                    return like::search_tasks_like(conn, &pred.query, pred, page);
                }
            }
        }
        return like::search_tasks_like(conn, &pred.query, pred, page);
    }

    // Non-CJK queries with zero alphanumerics (pure emoji /
    // punctuation) would tokenize to nothing on `tasks_fts`; go
    // straight to LIKE. The pre-filter replaces the brittle
    // "CJK check plus string-match on FTS error messages" approach
    // that breaks whenever SQLite rewords a parse error.
    if lorvex_domain::should_use_like_fallback(&pred.query) {
        return like::search_tasks_like(conn, &pred.query, pred, page);
    }

    let sanitized = lorvex_domain::sanitize_fts_query(&pred.query);

    if !sanitized.is_empty() {
        match fts::search_tasks_fts_counted(conn, &sanitized, pred, page) {
            Ok(result) => {
                // FTS5 prefix wildcards only match the
                // *start* of indexed tokens, so a short trailing run
                // like `oject` cannot hit a task titled
                // "project-alpha". When FTS returns zero rows *and*
                // the sanitizer flags the trailing token as short
                // (2–3 chars, bare, not part of an email/quoted
                // phrase), retry via the LIKE path on just that
                // trailing token — that gives users suffix/substring
                // coverage without a full second FTS round-trip.
                if result.total_matching == 0 {
                    if let Some(tok) =
                        lorvex_domain::short_trailing_token_for_like_retry(&pred.query)
                    {
                        return like::search_tasks_like(conn, tok, pred, page);
                    }
                }
                return Ok(result);
            }
            Err(e) => {
                // Schema-shape errors (missing FTS5 module or the shadow
                // table was never built) are the only surviving reason
                // to fall back instead of erroring. Structural match
                // against the typed `StoreError::Sql` payload (#3027-M2);
                // every other variant — including the disk-full
                // breaker — must propagate.
                if !is_fts_schema_missing(&e) {
                    return Err(e);
                }
            }
        }
    }

    like::search_tasks_like(conn, &pred.query, pred, page)
}

/// Returns true if the error indicates that FTS5 itself is not
/// available or one of the `tasks_fts*` shadow tables has not been
/// created (e.g. fresh install, corrupted schema). These are the only
/// cases where we want the search API to silently degrade to the LIKE
/// fallback; every other error (bad parameter, IO, transaction abort,
/// etc.) should surface. Covers both `tasks_fts` (unicode61 path) and
/// `tasks_fts_trigram` (CJK path, issue #2288).
///
/// The structural check inspects the typed
/// `rusqlite::Error::SqliteFailure` variant for the `Unknown`
/// extended code — the surface SQLite uses for both "no such table"
/// and "no such module" errors against a virtual table — and only
/// falls back to a substring probe of the message when the typed
/// inspection cannot positively classify the error. A pure
/// substring check on the lowercased SQLite error message would be
/// fragile: SQLite has reworded those messages multiple times
/// across point releases, and a future rewording would silently
/// turn every FTS-missing error into a hard failure. The structural
/// arm wins on every modern rusqlite release; the substring
/// fallback is kept solely as a defense against future rusqlite
/// repackagings.
pub(in crate::repositories::task::read) fn is_fts_schema_missing(err: &StoreError) -> bool {
    // pattern-match the typed `StoreError::Sql` carrier
    // (#3027-M2). Disk-full errors land in `StoreError::DiskFull` and
    // every other variant is a real failure that must propagate; only
    // a wrapped `rusqlite::Error::SqliteFailure` with the missing-
    // table/module shape qualifies the search path for LIKE-fallback.
    let StoreError::Sql(rusqlite::Error::SqliteFailure(code, msg)) = err else {
        return false;
    };
    // SQLite surfaces both "no such table: X" and "no such module: Y"
    // as primary code `SQLITE_ERROR` (= `Unknown` in the rusqlite
    // enum, since the C-level constant is the generic error). Other
    // primary codes (`Constraint`, `Busy`, `IoErr`, etc.) are real
    // failures and must propagate.
    if code.code != rusqlite::ErrorCode::Unknown {
        return false;
    }
    // The message-substring probe is the only way to discriminate
    // "missing FTS table" from any other generic `SQLITE_ERROR`,
    // because SQLite does not assign a distinct extended code to
    // missing-virtual-table errors. The earlier `to_string()` form
    // matched against the full `Display` envelope ("Error: ..."),
    // which is fragile across rusqlite repackagings; matching the
    // raw `Some(msg)` payload is the structural improvement —
    // we're inspecting the same string SQLite emitted, not whatever
    // rusqlite chose to wrap it in.
    if let Some(msg) = msg {
        let lower = msg.to_ascii_lowercase();
        return lower.contains("no such table") || lower.contains("no such module");
    }
    false
}
