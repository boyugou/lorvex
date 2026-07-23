use super::super::collection::{
    collect_remote_filesystem_bridge_envelopes, load_recent_lookback_outbox_ids,
};
use super::super::cursor::{load_filesystem_bridge_pull_cursor, FilesystemBridgePullCursor};
use super::super::diagnostics::FilesystemBridgeDiagnostic;
use super::super::lease_heartbeat::{HeartbeatGuard, DEFAULT_HEARTBEAT_INTERVAL};
use super::super::{fs, get_conn, get_or_create_sync_device_id_typed, sync_timestamp_now};
use super::finalize::phase_apply_and_finalize;
use super::lease::renew_filesystem_bridge_lease_or_abort;
use super::push::{phase_push_to_filesystem, phase_record_push_results};
use super::result::{
    build_filesystem_bridge_sync_result, FilesystemBridgeSyncCounts, FilesystemBridgeSyncResult,
};
use crate::error::{AppError, AppResult};
use lorvex_sync::outbox;

#[derive(Debug)]
pub(super) struct SyncReadState {
    pub(super) pending: Vec<outbox::OutboxEntry>,
    pub(super) local_device_id: String,
    pub(super) last_pull_cursor: Option<FilesystemBridgePullCursor>,
    pub(super) known_lookback_event_ids: std::collections::HashSet<String>,
}

/// **Phase A -- DB read:** reseed check, read outbox, device ID, pull cursor,
/// lookback IDs. Returns the data needed for the I/O-heavy phases.
pub(super) fn phase_read_outbox_and_pull_state(
    conn: &rusqlite::Connection,
    sync_dir: &std::path::Path,
    sync_dir_display: &str,
    cap: i64,
) -> AppResult<Result<SyncReadState, FilesystemBridgeSyncResult>> {
    if lorvex_workflow::reseed::is_reseed_required(conn)? {
        let diagnostic = FilesystemBridgeDiagnostic::warn(
            "sync.filesystem_bridge.runtime.reseed_required",
            "Filesystem bridge incremental sync paused because reseed is required",
            format!("filesystem_bridge_root_path={sync_dir_display}"),
        );
        super::super::diagnostics::persist_filesystem_bridge_diagnostic(conn, &diagnostic);
        return Ok(Err(build_filesystem_bridge_sync_result(
            sync_dir_display.to_string(),
            FilesystemBridgeSyncCounts {
                attempted_push: 0,
                pushed: 0,
                push_write_errors: 0,
                pulled_files: 0,
                pulled_remote_events: 0,
                pull_parse_errors: 0,
                lookback_known_id_skipped: 0,
                pull_limit_hit: false,
            },
            super::result::empty_apply_remote_sync_result(),
            true,
        )));
    }

    ensure_filesystem_bridge_full_sync_seeded_before_push(conn, sync_dir, sync_dir_display)?;

    let pending = outbox::get_pending(conn).map_err(AppError::from)?;
    let pending: Vec<_> = pending
        .into_iter()
        .take(usize::try_from(cap).unwrap_or(200))
        .collect();

    let local_device_id = get_or_create_sync_device_id_typed(conn)?;
    let last_pull_cursor = load_filesystem_bridge_pull_cursor(conn)?;
    let known_lookback_event_ids =
        load_recent_lookback_outbox_ids(conn, last_pull_cursor.as_ref())?;

    Ok(Ok(SyncReadState {
        pending,
        local_device_id,
        last_pull_cursor,
        known_lookback_event_ids,
    }))
}

fn full_sync_seed_checkpoint_exists(conn: &rusqlite::Connection) -> AppResult<bool> {
    Ok(
        lorvex_runtime::sync_checkpoint_get(conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
            .map_err(AppError::from)?
            .is_some(),
    )
}

fn filesystem_bridge_sync_dir_has_envelope_files(sync_dir: &std::path::Path) -> AppResult<bool> {
    let entries = match fs::read_dir(sync_dir) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => {
            return Err(AppError::Internal(format!(
                "failed to inspect filesystem bridge sync dir for full-sync seed gating: {error}"
            )));
        }
    };
    for entry in entries {
        let entry = entry.map_err(|error| {
            AppError::Internal(format!(
                "failed to inspect filesystem bridge sync dir entry for full-sync seed gating: {error}"
            ))
        })?;
        if entry
            .path()
            .extension()
            .and_then(|ext| ext.to_str())
            .is_some_and(|ext| ext.eq_ignore_ascii_case("json"))
        {
            return Ok(true);
        }
    }
    Ok(false)
}

fn run_filesystem_bridge_full_sync_seed(
    conn: &rusqlite::Connection,
    sync_dir_display: &str,
) -> AppResult<()> {
    crate::commands::sync::runtime::seed_full_sync_internal(conn)
        .map(|_| ())
        .map_err(|error| {
            let message = format!("Filesystem bridge full-sync seed failed: {error}");
            let checkpoint_message = format!("[{}] {message}", sync_timestamp_now());
            if let Err(checkpoint_error) = lorvex_runtime::sync_checkpoint_set(
                conn,
                lorvex_runtime::KEY_LAST_ERROR,
                &checkpoint_message,
            ) {
                let diagnostic = FilesystemBridgeDiagnostic::warn(
                    "sync.filesystem_bridge.runtime.auto_seed_last_error_failed",
                    "Filesystem bridge full-sync seed failure could not update sync status",
                    format!(
                        "filesystem_bridge_root_path={sync_dir_display}, error={checkpoint_error}"
                    ),
                );
                super::super::diagnostics::persist_filesystem_bridge_diagnostic(conn, &diagnostic);
            }
            let diagnostic = FilesystemBridgeDiagnostic::warn(
                "sync.filesystem_bridge.runtime.auto_seed_failed",
                message.clone(),
                format!("filesystem_bridge_root_path={sync_dir_display}, error={error}"),
            );
            super::super::diagnostics::persist_filesystem_bridge_diagnostic(conn, &diagnostic);
            AppError::Internal(message)
        })
}

fn ensure_filesystem_bridge_full_sync_seeded_before_push(
    conn: &rusqlite::Connection,
    sync_dir: &std::path::Path,
    sync_dir_display: &str,
) -> AppResult<()> {
    if full_sync_seed_checkpoint_exists(conn)? {
        return Ok(());
    }
    if filesystem_bridge_sync_dir_has_envelope_files(sync_dir)? {
        return Ok(());
    }
    run_filesystem_bridge_full_sync_seed(conn, sync_dir_display)
}

pub(super) fn ensure_filesystem_bridge_full_sync_seeded_after_pull(
    conn: &rusqlite::Connection,
    sync_dir_display: &str,
) -> AppResult<()> {
    if full_sync_seed_checkpoint_exists(conn)? {
        return Ok(());
    }
    run_filesystem_bridge_full_sync_seed(conn, sync_dir_display)
}

pub(super) fn refresh_dispatchable_pending_outbox(
    conn: &rusqlite::Connection,
    pending: Vec<outbox::OutboxEntry>,
) -> AppResult<Vec<outbox::OutboxEntry>> {
    lorvex_sync::outbox::retain_still_dispatchable(conn, pending).map_err(AppError::from)
}

pub(super) fn record_filesystem_bridge_completion_status(
    conn: &rusqlite::Connection,
    push_write_errors: i64,
    pull_parse_errors: i64,
    cursor_blocking_parse_errors: i64,
) -> AppResult<()> {
    lorvex_store::with_immediate_transaction(conn, |conn| {
        if push_write_errors == 0 && pull_parse_errors == 0 {
            lorvex_runtime::sync_checkpoint_set(
                conn,
                lorvex_runtime::KEY_LAST_SUCCESS_AT,
                &sync_timestamp_now(),
            )
            .map_err(AppError::from)?;
            lorvex_runtime::sync_checkpoint_clear(conn, lorvex_runtime::KEY_LAST_ERROR)
                .map_err(AppError::from)?;
        } else {
            let message = format!(
                "[{}] file sync warnings: push_write_errors={}, pull_parse_errors={}, cursor_blocking_parse_errors={}",
                sync_timestamp_now(),
                push_write_errors,
                pull_parse_errors,
                cursor_blocking_parse_errors,
            );
            lorvex_runtime::sync_checkpoint_set(conn, lorvex_runtime::KEY_LAST_ERROR, &message)
                .map_err(AppError::from)?;
        }
        Ok::<_, AppError>(())
    })
}

/// Orchestrator that acquires short-lived DB connections between phases,
/// releasing the writer during filesystem I/O so other writes are not blocked.
pub(super) fn run_filesystem_bridge_sync_inner(
    sync_dir: &std::path::Path,
    cap: i64,
) -> AppResult<FilesystemBridgeSyncResult> {
    let sync_dir_display = sync_dir.to_string_lossy().to_string();
    let now = sync_timestamp_now();

    // arm a thread-local heartbeat for the duration of
    // this orchestrator call. The phase-boundary renewals below already
    // bound how stale the lease can become *between* phases, but a
    // single phase's I/O loop (push of hundreds of envelopes; pull of
    // thousands of files on a slow shared folder) can outlast the 30 s
    // TTL on its own. The push and pull inner loops tick this
    // heartbeat once per file; the first tick after
    // [`DEFAULT_HEARTBEAT_INTERVAL`] elapses calls
    // `renew_filesystem_bridge_lease_or_abort` so a slow USB / network
    // sweep cannot finish under a stolen lease and then race the
    // rightful new owner at flush time. The guard is RAII-scoped to
    // this function so panic-or-early-return paths cannot leak the
    // heartbeat into a subsequent (lease-less) invocation reusing the
    // same Tauri worker thread.
    let _heartbeat_guard = HeartbeatGuard::install(
        DEFAULT_HEARTBEAT_INTERVAL,
        renew_filesystem_bridge_lease_or_abort,
    );

    // ── Phase A: short-lived conn for DB reads ──
    let mut read_state = {
        let conn = get_conn()?;
        match phase_read_outbox_and_pull_state(&conn, sync_dir, &sync_dir_display, cap)? {
            Ok(data) => data,
            Err(reseed_result) => return Ok(reseed_result),
        }
    }; // conn dropped — writer released before filesystem I/O

    // cancel-signal probe at every phase boundary.
    // The user can hit "Cancel" at any moment; surfacing the
    // cancellation as `AppError::Cancelled` (rather than `Internal`)
    // lets the toast layer render a benign "Cancelled" affordance
    // instead of a red error banner.
    if crate::commands::sync::runtime::is_sync_cancelled_for(
        crate::commands::sync::runtime::SyncKind::FilesystemBridge,
    ) {
        return Err(AppError::Cancelled(
            "filesystem-bridge sync cancelled by user before push".to_string(),
        ));
    }

    let pending = {
        let conn = get_conn()?;
        // Move the pending Vec out of `read_state` so
        // `retain_still_dispatchable` can drop no-longer-eligible
        // entries in place (no per-row payload clone). The other
        // `read_state` fields (`local_device_id`, etc.) survive the
        // swap intact.
        refresh_dispatchable_pending_outbox(&conn, std::mem::take(&mut read_state.pending))?
    };

    // ── Phase B: filesystem push I/O (no conn held) ──
    let push_outcome = phase_push_to_filesystem(pending, sync_dir)?;
    let pushed = usize_to_i64("pushed outbox count", push_outcome.pushed_ids.len())?;
    let push_write_errors = push_outcome.push_write_errors;
    let attempted_push = push_outcome.attempted_push;
    let push_cancelled = push_outcome.cancelled;

    // renew the lease before the Phase C batch flush.
    // Phase B (filesystem push I/O) can run for tens of seconds on a
    // slow shared folder; without renewal, the 30 s lease may have
    // expired by the time we re-acquire the writer to record results.
    renew_filesystem_bridge_lease_or_abort()?;

    // ── Phase C: short-lived conn to record push results ──
    {
        let conn = get_conn()?;
        phase_record_push_results(&conn, &push_outcome, &now)?;
    } // conn dropped — writer released before filesystem I/O

    if push_cancelled {
        return Err(AppError::Cancelled(
            "filesystem-bridge sync cancelled by user during push".to_string(),
        ));
    }

    // cancel-signal probe before the pull I/O —
    // pulling thousands of envelopes from a slow shared folder is
    // exactly the case where users want a working cancel button.
    if crate::commands::sync::runtime::is_sync_cancelled_for(
        crate::commands::sync::runtime::SyncKind::FilesystemBridge,
    ) {
        return Err(AppError::Cancelled(
            "filesystem-bridge sync cancelled by user before pull".to_string(),
        ));
    }

    // ── Phase D: filesystem pull I/O (no conn held) ──
    let pull_cap = usize::try_from(cap.saturating_mul(5))
        .unwrap_or(1_000)
        .max(1);
    let collected_remote = collect_remote_filesystem_bridge_envelopes(
        sync_dir,
        &read_state.local_device_id,
        pull_cap,
        read_state.last_pull_cursor.as_ref(),
        Some(&read_state.known_lookback_event_ids),
    )?;
    let pull_parse_errors = collected_remote.pull_parse_errors;
    let cursor_blocking_parse_errors = collected_remote.cursor_blocking_parse_errors;

    // renew the lease before the Phase E batch flush.
    // Phase D's pull I/O scans every `.json` envelope in the sync dir
    // and parses payloads up to the per-envelope cap; a vault with
    // hundreds of pending files easily eats the lease window before
    // the apply pipeline lands.
    renew_filesystem_bridge_lease_or_abort()?;

    // ── Phase E: short-lived conn to apply envelopes, checkpoints, GC ──
    let (
        apply_result,
        pulled_files,
        pulled_remote_events,
        lookback_known_id_skipped,
        pull_limit_hit,
    ) = {
        let conn = get_conn()?;
        let finalize_result = phase_apply_and_finalize(
            &conn,
            sync_dir,
            &read_state.local_device_id,
            collected_remote,
            push_write_errors,
            &now,
        )?;
        ensure_filesystem_bridge_full_sync_seeded_after_pull(&conn, &sync_dir_display)?;
        record_filesystem_bridge_completion_status(
            &conn,
            push_write_errors,
            pull_parse_errors,
            cursor_blocking_parse_errors,
        )?;
        finalize_result
    }; // conn dropped

    Ok(build_filesystem_bridge_sync_result(
        sync_dir_display,
        FilesystemBridgeSyncCounts {
            attempted_push,
            pushed,
            push_write_errors,
            pulled_files,
            pulled_remote_events,
            pull_parse_errors,
            lookback_known_id_skipped,
            pull_limit_hit,
        },
        apply_result,
        false,
    ))
}

pub(super) fn usize_to_i64(label: &str, value: usize) -> AppResult<i64> {
    i64::try_from(value).map_err(|_| AppError::Internal(format!("{label} overflowed i64: {value}")))
}
