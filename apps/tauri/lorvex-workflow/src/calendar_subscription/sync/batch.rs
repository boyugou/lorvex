//! Batch driver: walk every enabled subscription and refresh each in
//! turn, short-circuiting on process-wide terminal errors but keeping
//! per-feed transient failures from aborting the rest of the batch.
//!
//! The test-visible [`run_batch_loop`] helper drives the same per-feed
//! result handling against a caller-supplied callback so tests can
//! inject deterministic errors (including the typed disk-full failure
//! that cannot be triggered through the real fetch backend).

use lorvex_store::StoreError;
use rusqlite::params;

use super::super::error::CalendarSubscriptionError;
use super::super::tzid::UnknownTzidSink;
use super::single::sync_calendar_subscription;
use super::types::{FetchBackend, SubscriptionSyncResult};

/// Walk every enabled subscription and refresh each one in turn.
pub fn sync_all_calendar_subscriptions(
    conn: &rusqlite::Connection,
    backend: &dyn FetchBackend,
    unknown_tzid_sink: UnknownTzidSink<'_>,
) -> Result<Vec<SubscriptionSyncResult>, CalendarSubscriptionError> {
    let ids: Vec<String> = {
        let mut stmt =
            conn.prepare_cached("SELECT id FROM calendar_subscriptions WHERE enabled = 1")?;
        let rows: Vec<String> = stmt
            .query_map([], |row| row.get(0))?
            .collect::<Result<Vec<_>, _>>()?;
        rows
    };

    let mut results = Vec::new();
    for id in ids {
        // Per-feed graceful failure: an unexpected DB / store error on
        // one feed must NOT abort the rest of a 5-feed batch — for
        // per-feed-recoverable failures (transient HTTP, parse
        // warnings, single-row LWW conflicts, generic SQL). Push a
        // result row carrying the error message so the CLI / UI still
        // sees partial counters for the remaining feeds.
        //
        // Process-wide terminal failures (currently `DiskFull`)
        // short-circuit instead: every subsequent feed in the same
        // batch would hit the same out-of-disk wall and produce N
        // duplicate "out of disk space" rows, plus the process-wide
        // breaker would trip mid-loop while the loop kept running.
        // Break with the typed error so the surface adapter can
        // surface a single actionable message.
        match sync_calendar_subscription(conn, backend, unknown_tzid_sink, &id) {
            Ok(result) => results.push(result),
            Err(err) if is_terminal_batch_error(&err) => {
                return Err(err);
            }
            Err(err) => {
                let name = subscription_name_for_error(conn, &id);
                results.push(SubscriptionSyncResult {
                    subscription_id: id,
                    subscription_name: name,
                    events_imported: 0,
                    events_updated: 0,
                    events_removed: 0,
                    error: Some(err.to_string()),
                });
            }
        }
    }
    Ok(results)
}

/// True for errors that affect the whole process, not just one
/// feed. The batch orchestrator short-circuits on these instead of
/// emitting N duplicate per-feed error rows. Currently a typed
/// disk-full classification is the only such case; future
/// process-wide failures (corrupted DB, schema mismatch) would be
/// added here.
pub(crate) const fn is_terminal_batch_error(err: &CalendarSubscriptionError) -> bool {
    matches!(
        err,
        CalendarSubscriptionError::Store(StoreError::DiskFull { .. })
    )
}

/// Test-visible variant of [`sync_all_calendar_subscriptions`] that
/// drives the batch loop against a caller-supplied per-feed result
/// function. Production code uses the public entry point which wires
/// in `sync_calendar_subscription`; tests use this helper to inject
/// deterministic per-feed errors (including the typed disk-full
/// failure that cannot be triggered through the real fetch backend).
#[cfg(test)]
pub(crate) fn run_batch_loop<F>(
    conn: &rusqlite::Connection,
    ids: Vec<String>,
    mut per_feed: F,
) -> Result<Vec<SubscriptionSyncResult>, CalendarSubscriptionError>
where
    F: FnMut(&str) -> Result<SubscriptionSyncResult, CalendarSubscriptionError>,
{
    let mut results = Vec::new();
    for id in ids {
        match per_feed(&id) {
            Ok(result) => results.push(result),
            Err(err) if is_terminal_batch_error(&err) => return Err(err),
            Err(err) => {
                let name = subscription_name_for_error(conn, &id);
                results.push(SubscriptionSyncResult {
                    subscription_id: id,
                    subscription_name: name,
                    events_imported: 0,
                    events_updated: 0,
                    events_removed: 0,
                    error: Some(err.to_string()),
                });
            }
        }
    }
    Ok(results)
}

/// Best-effort name lookup used by the batch error path so a feed
/// whose refresh blew up still carries a human-readable label in
/// the returned `SubscriptionSyncResult`. Failures fall back to the
/// id so the CLI / UI always has something to render.
fn subscription_name_for_error(conn: &rusqlite::Connection, id: &str) -> String {
    conn.query_row(
        "SELECT name FROM calendar_subscriptions WHERE id = ?1",
        params![id],
        |row| row.get::<_, String>(0),
    )
    .unwrap_or_else(|_| id.to_string())
}
