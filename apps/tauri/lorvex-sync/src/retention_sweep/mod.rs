//! Cross-process periodic retention sweep.
//!
//! This module owns the full retention pass that lived only inside
//! the Tauri app's diagnostics command tree (`app/src-tauri/src/commands/
//! diagnostics/changelog.rs::run_data_retention_cleanup_with_conn`). Headless
//! processes — the MCP server (`mcp-server/`) and the long-running CLI
//! surfaces (`lorvex tui-watch`, `lorvex mcp serve`) — never reached that
//! function, so users running Lorvex without the desktop app accumulated
//! `ai_changelog`, `error_logs`, `memory_revisions`, sync queues, blob
//! orphans, etc. forever.
//!
//! Lifting the body into `lorvex-sync` lets every process surface call the
//! same code path, with a `device_state` watermark guarding against doing the
//! work too often (so a long-lived MCP session does not sweep on every
//! reconnect).
//!
//! See [`run_periodic_retention_sweep`] for the entry point and
//! [`should_run_retention_sweep`] for the watermark-based gate.

use rusqlite::{params, Connection};

use crate::startup_maintenance::{
    persist_startup_maintenance_warnings, run_pending_queue_retention_maintenance,
};
use lorvex_store::error::StoreError;
use lorvex_store::error_log::append_error_log_best_effort;
use lorvex_store::repositories::ai_changelog_actor_filter::ai_changelog_assistant_actor_filter_sql;

/// Watermark key persisted to `sync_checkpoints` so a long-lived MCP /
/// `tui-watch` session does not re-run the entire sweep every reconnect.
/// Mirrors the shape of the tombstone GC's checkpoint pattern.
pub const KEY_LAST_RETENTION_SWEEP_AT: &str = "last_retention_sweep_at";

/// Minimum gap between successive retention sweeps. Matches the desktop
/// renderer's 6-hour cron cadence so the headless surfaces converge on the
/// same effective frequency without colliding.
pub const MIN_RETENTION_SWEEP_INTERVAL_HOURS: u32 = 6;

/// Shipping-default retention windows when the user has not set a
/// preference. Keeps enough history for debugging but bounds the PII
/// surface so a disk image / bug-report export / provider snapshot
/// doesn't contain years of "completed 'Therapy with Dr. X'"
/// changelog rows.
const DEFAULT_ERROR_LOG_RETENTION_DAYS: i64 = 30;
pub const DEFAULT_AI_CHANGELOG_RETENTION_DAYS: i64 = 90;

/// Absolute ceiling on retention regardless of user preference. The
/// `ai_changelog` table syncs to remote providers, and an explicit "forever"
/// choice would grow unbounded across devices. Clamping at one year
/// keeps the bound finite without surprising a user who explicitly
/// chose a long window.
///
/// Bound to `lorvex_domain::naming::TOMBSTONE_MAX_RETENTION_DAYS`
/// so a single edit covers every "year-long retention safety net"
/// in the workspace.
pub const HARD_CAP_RETENTION_DAYS: i64 = lorvex_domain::naming::TOMBSTONE_MAX_RETENTION_DAYS as i64;

/// belt-and-suspenders row cap on `error_logs`.
const MAX_ERROR_LOG_ROWS: i64 = 10_000;

const OUTBOX_RETENTION_DAYS: u32 = 7;
const CONFLICT_LOG_RETENTION_DAYS: u32 = 30;

/// Counts of rows reaped by the diagnostic sweeps. Used by the Tauri
/// `run_data_retention_cleanup` IPC to decide whether to emit a
/// `data-changed` event to the renderer.
#[derive(Debug, Default, Clone, Copy)]
pub struct RetentionSweepOutcome {
    pub changelog_deleted: u64,
    pub error_logs_deleted: u64,
    pub memory_revisions_deleted: u64,
}

/// Run the full periodic retention sweep against `conn`.
///
/// Covers:
/// - `ai_changelog` time-window GC (with hard cap on retention days)
/// - `error_logs` time-window GC + row-count cap
/// - `memory_revisions` retention GC (per-key keep-last-N safeguard)
/// - sync queue GC: `outbox` synced rows, tombstone watermark,
///   `conflict_log`
/// - heavier PRAGMA / FTS / WAL maintenance
/// - PRAGMA quick_check / foreign_key_check, with findings recorded to
///   `error_logs`
///
/// Returns top-level row counts. Per-step failures are recorded into
/// `error_logs` and do NOT abort the whole pass — the caller cares about
/// the aggregate outcome rather than per-step errors.
pub fn run_periodic_retention_sweep(
    conn: &Connection,
) -> Result<RetentionSweepOutcome, StoreError> {
    // Read retention preferences (stored as JSON-encoded strings),
    // applying a sane default when the preference is unset and clamping to
    // a hard ceiling so diagnostic tables are never unbounded, even for
    // users who never visit Settings → Data.
    let explicit_changelog_days = read_retention_days(
        conn,
        lorvex_domain::preference_keys::PREF_AI_CHANGELOG_RETENTION_POLICY,
    )?;
    let explicit_error_log_days = read_retention_days(
        conn,
        lorvex_domain::preference_keys::PREF_ERROR_LOG_RETENTION_DAYS,
    )?;
    let changelog_days =
        resolve_retention_days(explicit_changelog_days, DEFAULT_AI_CHANGELOG_RETENTION_DAYS);
    let error_log_days =
        resolve_retention_days(explicit_error_log_days, DEFAULT_ERROR_LOG_RETENTION_DAYS);

    // CRITICAL: `timestamp` / `created_at` are stored in RFC 3339 form
    // (e.g. `2026-04-04T12:34:56.789Z`) via `sync_timestamp_now()`, but
    // `datetime('now', ...)` returns a SPACE-separated string
    // (`2026-04-04 12:34:56`). The string comparison `col < cutoff`
    // compares `'T' (0x54)` vs `' ' (0x20)` and always succeeds on the
    // data side, making the predicate false — no rows were ever deleted.
    // Use `strftime('%Y-%m-%dT%H:%M:%fZ', ...)` so the cutoff matches the
    // stored format lexicographically.
    static CHANGELOG_DELETE_SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let changelog_deleted = conn.execute(
        CHANGELOG_DELETE_SQL.get_or_init(|| {
            let actor_filter = ai_changelog_assistant_actor_filter_sql();
            format!(
                "DELETE FROM ai_changelog WHERE {actor_filter} \
                 AND timestamp < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)"
            )
        }),
        params![format!("-{changelog_days} days")],
    )? as u64;

    let mut error_logs_deleted = conn.execute(
        "DELETE FROM error_logs WHERE created_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        params![format!("-{error_log_days} days")],
    )? as u64;

    // burst-then-quiet failure mode where a bug emits 100k rows in a few
    // minutes and then stops, leaving them to age out over 30 days. Keep
    // the most recent 10,000 rows so the table stays bounded to ~5 MB at
    // typical row sizes.
    let row_count: i64 = conn.query_row("SELECT COUNT(*) FROM error_logs", [], |row| row.get(0))?;
    if row_count > MAX_ERROR_LOG_ROWS {
        let excess = row_count - MAX_ERROR_LOG_ROWS;
        let cap_deleted = conn.execute(
            "DELETE FROM error_logs WHERE id IN ( \
               SELECT id FROM error_logs ORDER BY created_at ASC, id ASC LIMIT ?1 \
             )",
            params![excess],
        )? as u64;
        error_logs_deleted = error_logs_deleted.saturating_add(cap_deleted);
    }

    // memory_revisions reuses the same retention preference as
    // ai_changelog — both are audit trails for "what the AI did" — with a
    // per-key keep-last-N safeguard baked into the GC so the Restore
    // feature keeps working even on heavily churned keys.
    // `resolve_retention_days` already clamps to `[1, HARD_CAP_RETENTION_DAYS]`
    // (see #issue-2393), so the value is always positive and fits in u32 —
    // `try_from` cannot fail under the clamped contract, but use `ok()` so
    // a future widening of the cap surfaces as a `None` skip rather than
    // a panic.
    let memory_revision_days: Option<u32> = u32::try_from(changelog_days).ok();
    let memory_revisions_deleted =
        crate::memory_revision_retention::gc_memory_revisions_by_retention_days(
            conn,
            memory_revision_days,
        )?;

    // sync-table GC (outbox, tombstones, conflict log, blob fetch queue)
    // only ran inside the active sync cycle — local-only users
    // (no remote provider, no filesystem-bridge) would see these tables grow
    // forever. Each call is bounded and idempotent. Errors from individual
    // GC calls are recorded in error_logs but do not abort the whole pass
    // — the caller cares about the top-level row counts.
    if let Err(err) = crate::outbox::gc_synced(conn, OUTBOX_RETENTION_DAYS) {
        record_retention_warning(
            conn,
            "diagnostics.retention.outbox_gc",
            format!("outbox gc_synced failed: {err}"),
        );
    }
    if let Err(err) = crate::tombstone::gc_tombstones_watermark(conn) {
        record_retention_warning(
            conn,
            "diagnostics.retention.tombstone_gc",
            format!("tombstone watermark gc failed: {err}"),
        );
    }
    if let Err(err) = crate::conflict_log::gc_conflicts(conn, CONFLICT_LOG_RETENTION_DAYS) {
        record_retention_warning(
            conn,
            "diagnostics.retention.conflict_log_gc",
            format!("conflict_log gc failed: {err}"),
        );
    }

    // Peer-delete restore snapshots and pending inbox entries are sync
    // queues, not diagnostic logs, but the visible-window retention cron
    // is the startup / long-running-app maintenance entrypoint for users
    // with sync disabled or paused. Route through the same helper used by
    // post-sync finalizers so pending-queue retention cannot drift by
    // caller. Inlines the same shape as the Tauri-side
    // `commands/sync_runtime/maintenance.rs::run_pending_queue_retention_maintenance`
    // wrapper, since we have direct access to lorvex-sync internals here.
    match run_pending_queue_retention_maintenance(conn) {
        Ok(warnings) => persist_startup_maintenance_warnings(conn, &warnings),
        Err(err) => record_retention_warning(
            conn,
            "diagnostics.retention.pending_queue_gc",
            format!("pending queue retention failed: {err}"),
        ),
    }

    // Piggyback the heavier PRAGMA / FTS / WAL maintenance on the same
    // cron so page reclamation, optimizer stats refresh, and FTS
    // compaction run periodically without a dedicated scheduler.
    if let Err(err) = lorvex_store::run_periodic_maintenance(conn) {
        record_retention_warning(
            conn,
            "diagnostics.retention.periodic_maintenance",
            format!("periodic maintenance failed: {err}"),
        );
    }

    // PRAGMA quick_check + PRAGMA foreign_key_check on the same cron so
    // page-level corruption or orphan FK rows become visible in
    // diagnostics instead of surfacing as random "database disk image is
    // malformed" errors. Findings land in `error_logs` at warn level.
    match lorvex_store::run_integrity_check(conn) {
        Ok(findings) if !findings.is_empty() => {
            let detail = findings.join("\n");
            append_error_log_best_effort(
                conn,
                "integrity_check",
                &format!("integrity_check found {} issue(s)", findings.len()),
                Some(&detail),
                Some("warn"),
            );
        }
        Ok(_) => {}
        Err(err) => {
            record_retention_warning(
                conn,
                "diagnostics.retention.integrity_check",
                format!("integrity_check run failed: {err}"),
            );
        }
    }

    Ok(RetentionSweepOutcome {
        changelog_deleted,
        error_logs_deleted,
        memory_revisions_deleted,
    })
}

/// Watermark check: returns `true` if the retention sweep is due (it has
/// been at least [`MIN_RETENTION_SWEEP_INTERVAL_HOURS`] since the previous
/// sweep, or no watermark has ever been recorded). Persisting the
/// watermark on success is the caller's responsibility — see
/// [`record_retention_sweep_completed`].
///
/// Headless processes (MCP, `tui-watch`) call this at startup so they
/// don't sweep on every reconnect; one-shot CLI commands do not, so a
/// `lorvex add task` invocation isn't slowed by a multi-second GC.
pub fn should_run_retention_sweep(conn: &Connection) -> Result<bool, StoreError> {
    let stored = lorvex_runtime::sync_checkpoint_get(conn, KEY_LAST_RETENTION_SWEEP_AT)?;
    let Some(prev) = stored else {
        return Ok(true);
    };
    let trimmed = prev.trim();
    if trimmed.is_empty() {
        return Ok(true);
    }
    // Compare against `now - MIN_INTERVAL_HOURS` using the same
    // strftime-`T`-separated string format as everywhere else, so
    // lexicographic comparison is correct across timezones.
    let due: bool = conn.query_row(
        "SELECT ?1 < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?2)",
        params![
            trimmed,
            format!("-{MIN_RETENTION_SWEEP_INTERVAL_HOURS} hours")
        ],
        |row| row.get::<_, i64>(0).map(|v| v != 0),
    )?;
    Ok(due)
}

/// Record that a retention sweep just completed. Stamps the current
/// wall-clock time into the `KEY_LAST_RETENTION_SWEEP_AT` checkpoint so
/// [`should_run_retention_sweep`] returns `false` until the next interval
/// elapses.
pub fn record_retention_sweep_completed(conn: &Connection) -> Result<(), StoreError> {
    lorvex_runtime::sync_checkpoint_set(
        conn,
        KEY_LAST_RETENTION_SWEEP_AT,
        &lorvex_domain::sync_timestamp_now(),
    )?;
    Ok(())
}

/// Read a `preferences` row interpreting the JSON-encoded value as a
/// positive day count. `Ok(None)` for a missing row.
///
/// Public so callers (the Tauri `read_changelog_retention_days` shim, the
/// MCP audit-retention paths, the diagnostic test-support layer) all
/// share one parser instead of duplicating the JSON-to-`i64` shape.
pub fn read_retention_days(conn: &Connection, key: &str) -> Result<Option<i64>, StoreError> {
    let raw = match conn.query_row(
        "SELECT value FROM preferences WHERE key = ?1",
        params![key],
        |row| row.get::<_, String>(0),
    ) {
        Ok(raw) => raw,
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok(None),
        Err(error) => return Err(StoreError::from(error)),
    };

    lorvex_domain::parse_positive_i64_preference(&raw, key)
        .map(Some)
        .map_err(StoreError::from)
}

/// Clamp an explicit retention setting (or the default) into the
/// `[1, HARD_CAP_RETENTION_DAYS]` range. Treats zero / negative as "use
/// the default" rather than honoring the destructive reading.
pub fn resolve_retention_days(explicit: Option<i64>, default_days: i64) -> i64 {
    let days = explicit.unwrap_or(default_days);
    if days <= 0 {
        default_days
    } else {
        days.min(HARD_CAP_RETENTION_DAYS)
    }
}

fn record_retention_warning(conn: &Connection, source: &str, message: impl AsRef<str>) {
    append_error_log_best_effort(conn, source, message.as_ref(), None, Some("warn"));
}

#[cfg(test)]
mod tests;
