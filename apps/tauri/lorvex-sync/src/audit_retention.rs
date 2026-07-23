//! ai_changelog retention GC.
//!
//! #3053 DC6: production code in this module is `unwrap()`-free; the
//! attribute below pins that contract so a future refactor that
//! sneaks a `.unwrap()` into a non-test path fails at compile time.
//! Test bodies are exempt — every `unwrap()` in this file's
//! `#[cfg(test)] mod tests` is on a fixture-hydration call where the
//! panic is the test failure signal.

#![cfg_attr(not(test), deny(clippy::unwrap_used))]

//!
//! The `ai_changelog` is an append-only audit stream synced across devices with
//! a user-configurable retention window in days. This module exposes a single
//! retention-aware GC entry point used after every successful sync push:
//!
//! - **Retention-aware GC**: [`gc_changelog_by_retention_days`] deletes entries
//!   beyond the retention window. `None` retention = "forever", which still
//!   enforces [`AUDIT_MAX_ENTRIES_SAFEGUARD`] as an absolute row cap.
//!
//! Read access to `ai_changelog` lives in
//! [`lorvex_store::repositories::ai_changelog_query`] — that module is the
//! canonical typed read API.
//!
//! See spec Section 16: ai_changelog as Syncable Audit Stream.

use lorvex_domain::naming::AUDIT_MAX_ENTRIES_SAFEGUARD;
use rusqlite::{params, Connection};

/// Clean up changelog entries beyond the user's retention window.
///
/// - `None` (forever): keep everything inside the window but still enforce
///   [`AUDIT_MAX_ENTRIES_SAFEGUARD`] as an absolute row cap, deleting the
///   oldest rows beyond that cap. Without the cap, "forever" means the
///   table grows unbounded, and peers doing a first-sync would replay the
///   entire history. The cap keeps the local table bounded without user
///   action while still being large enough (10 000 entries ≈ multiple
///   years at typical AI-write cadences) that users never lose signal.
/// - `Some(days)`: delete entries older than `days` days.
///
/// Returns the number of deleted rows.
///
/// **Post-sync garbage collection.** Call after a successful sync push
/// cycle to garbage-collect changelog entries beyond the retention
/// window. This keeps the local `ai_changelog` table bounded.
pub fn gc_changelog_by_retention_days(
    conn: &Connection,
    retention_days: Option<u32>,
) -> Result<u64, rusqlite::Error> {
    match retention_days {
        None => {
            // Forever retention with a hard safeguard: delete the oldest rows
            // past the absolute cap. If the table is still under the cap,
            // this is a no-op.
            //
            // the previous shape used SQLite's scalar
            // `MAX()` on the LIMIT expression. Modern SQLite (>=3.47)
            // supports it but older builds — including some Linux
            // distros that ship a vendored libsqlite3 we may bundle
            // for filesystem-bridge mode — interpret `MAX(...)` as
            // the aggregate function inside a non-aggregate context
            // and either error or return the row's first column. A
            // `CASE WHEN ... THEN ... ELSE 0 END` is portable across
            // every SQLite build we ship and produces the same
            // "trim to cap, no-op when below cap" semantics.
            let deleted = conn
                .prepare_cached(
                    "DELETE FROM ai_changelog
                     WHERE id IN (
                         SELECT id FROM ai_changelog
                         ORDER BY timestamp ASC, id ASC
                         LIMIT CASE
                                 WHEN (SELECT COUNT(*) FROM ai_changelog) > ?1
                                     THEN (SELECT COUNT(*) FROM ai_changelog) - ?1
                                     ELSE 0
                               END
                     )",
                )?
                .execute(params![AUDIT_MAX_ENTRIES_SAFEGUARD])?;
            Ok(deleted as u64)
        }
        Some(0) => {
            // `Some(0)` is unreachable via the canonical preference path —
            // `lorvex_domain::parsing::parse_positive_i64_preference`
            // rejects non-positive values before they ever land in
            // `read_changelog_retention_days`. Treating 0 as "delete
            // everything older than now" would silently wipe the entire
            // audit log, so the public API rejects it as a no-op
            // defense-in-depth gate against a future caller that
            // bypasses the preference reader.
            Ok(0)
        }
        Some(days) => {
            // Inlined from former `gc_changelog` + `gc_changelog_with_cutoff_iso`:
            // compute the ISO cutoff via SQLite's date math (so the cutoff and
            // any rows the test harness inserts via the same expression share
            // a single wall-clock instant), then strict-`<` delete.
            let modifier = format!("-{days} days");
            let cutoff_iso: String = conn
                .prepare_cached("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)")?
                .query_row(params![modifier], |r| r.get(0))?;
            let deleted = conn
                .prepare_cached("DELETE FROM ai_changelog WHERE timestamp < ?1")?
                .execute(params![cutoff_iso])?;
            Ok(deleted as u64)
        }
    }
}

#[cfg(test)]
mod tests;
