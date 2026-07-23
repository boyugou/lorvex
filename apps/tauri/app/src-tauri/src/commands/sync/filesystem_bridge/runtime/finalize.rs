use super::super::collection::CollectedRemoteFilesystemBridgeEnvelopes;
use super::super::cursor::{newest_filesystem_bridge_pull_cursor, FilesystemBridgePullCursor};
use super::super::diagnostics::{
    persist_filesystem_bridge_diagnostic, persist_filesystem_bridge_diagnostics,
    FilesystemBridgeDiagnostic,
};
use super::super::{
    apply_remote_sync_records_with_checkpoint_writer, emit_data_changed_for_entity_types,
    flag_reseed_required_due_to_pending_horizon_in_transaction, fs,
    gc_expired_pending_queues_best_effort, gc_synced_events, store_filesystem_bridge_pull_cursor,
    upsert_sync_checkpoint_timestamp_if_newer, ApplyRemoteSyncResult, IncomingSyncRecord,
    RemoteApplyMode, SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY,
};
use super::naming::filesystem_bridge_local_file_prefix;
use super::orchestration::usize_to_i64;
use crate::error::{AppError, AppResult};

pub(super) fn phase_apply_and_finalize(
    conn: &rusqlite::Connection,
    sync_dir: &std::path::Path,
    local_device_id: &str,
    collected_remote: CollectedRemoteFilesystemBridgeEnvelopes,
    _push_write_errors: i64,
    now: &str,
) -> AppResult<(ApplyRemoteSyncResult, i64, i64, i64, bool)> {
    persist_filesystem_bridge_diagnostics(conn, &collected_remote.diagnostics);
    let newest_pull_cursor = if collected_remote.cursor_blocking_parse_errors == 0 {
        newest_filesystem_bridge_pull_cursor(&collected_remote.remote_events)
    } else {
        None
    };
    let pulled_remote_events = usize_to_i64(
        "pulled remote event count",
        collected_remote.remote_events.len(),
    )?;
    let remote_entity_types: Vec<lorvex_domain::naming::EntityKind> = {
        let mut seen = Vec::new();
        for r in &collected_remote.remote_events {
            let kind = r.envelope.entity_type;
            if !seen.contains(&kind) {
                seen.push(kind);
            }
        }
        seen
    };
    let CollectedRemoteFilesystemBridgeEnvelopes {
        pulled_files,
        pull_parse_errors: _pull_parse_errors,
        cursor_blocking_parse_errors: _cursor_blocking_parse_errors,
        lookback_known_id_skipped,
        pull_limit_hit,
        diagnostics: _,
        remote_events,
    } = collected_remote;

    // Apply incoming events via lorvex_sync::apply::apply_envelope.
    let apply_result =
        apply_incoming_via_envelope(conn, remote_events, now, newest_pull_cursor.as_ref())?;
    if apply_result.applied > 0 {
        emit_data_changed_for_entity_types(&remote_entity_types);
    }

    // coalesce the checkpoint-upsert cluster + pending
    // inbox horizon check under a single `BEGIN IMMEDIATE` so the
    // checkpoints commit atomically and inherit busy-retry via
    // `with_immediate_transaction`. This transaction must stay SHORT
    // because the orchestrator explicitly releases the writer mutex
    // between phases (see `run_filesystem_bridge_sync_inner`); the GC
    // section below intentionally stays OUTSIDE this transaction
    // because it performs filesystem I/O that would otherwise hold
    // the write lock across network-ish latencies.
    lorvex_store::with_immediate_transaction(conn, |conn| {
        lorvex_runtime::sync_checkpoint_set(
            conn,
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY,
            &lookback_known_id_skipped.to_string(),
        )
        .map_err(AppError::from)?;
        lorvex_runtime::sync_checkpoint_set(
            conn,
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY,
            now,
        )
        .map_err(AppError::from)?;
        flag_reseed_required_due_to_pending_horizon_in_transaction(conn)?;

        Ok::<_, AppError>(())
    })?;

    gc_expired_pending_queues_best_effort(conn);
    gc_synced_events(conn)?;
    gc_stale_sync_files(conn, sync_dir, local_device_id);
    lorvex_sync::tombstone::gc_tombstones_watermark(conn).map_err(AppError::from)?;
    lorvex_sync::conflict_log::gc_conflicts(conn, 30).map_err(AppError::from)?;
    let retention_days = crate::commands::diagnostics::read_changelog_retention_days(conn)?
        .and_then(|days| u32::try_from(days).ok());
    lorvex_sync::audit_retention::gc_changelog_by_retention_days(conn, retention_days)
        .map_err(AppError::from)?;

    Ok((
        apply_result,
        pulled_files,
        pulled_remote_events,
        lookback_known_id_skipped,
        pull_limit_hit,
    ))
}

/// Remove stale `.json` and orphaned `.json.tmp` sync files.
pub(super) fn gc_stale_sync_files(
    conn: &rusqlite::Connection,
    sync_dir: &std::path::Path,
    local_device_id: &str,
) {
    const STALE_LOCAL_AGE_SECS: u64 = 7 * 86_400;
    let stale_foreign_age_secs: u64 =
        u64::from(lorvex_domain::naming::FULL_RESYNC_HORIZON_DAYS) * 86_400;

    let entries = match fs::read_dir(sync_dir) {
        Ok(e) => e,
        Err(err) => {
            persist_filesystem_bridge_diagnostic(
                conn,
                &FilesystemBridgeDiagnostic::warn(
                    "sync.filesystem_bridge.finalize.stale_file_gc",
                    "Filesystem bridge stale file GC could not read sync directory",
                    format!("sync_dir={}, error={err}", sync_dir.display()),
                ),
            );
            return;
        }
    };

    // filenames on disk no longer carry the raw
    // `device_id` prefix; they're SHA-256-derived. Recompute the
    // local device's hashed prefix once so the loop below can still
    // separate "ours" (short retention) from "foreign" (long
    // retention) without leaking anything to the directory listing.
    let local_prefix = filesystem_bridge_local_file_prefix(local_device_id);
    let now = std::time::SystemTime::now();

    for entry in entries.flatten() {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();

        // Only .json envelopes and orphaned .json.tmp files.
        let is_tmp = name_str.ends_with(".json.tmp");
        let is_json = !is_tmp && name_str.ends_with(".json");
        if !is_tmp && !is_json {
            continue;
        }

        let is_local = name_str.starts_with(&local_prefix);

        // a `.json.tmp` file is the staging path for an
        // atomic write; only the device that opened it knows whether
        // the rename has happened yet. A sibling device sweeping
        // foreign tmps by mtime can race the writer's `fs::rename` and
        // delete in-flight bytes — the rename then fails, the writer
        // backs off, and the envelope never lands. Restrict tmp
        // sweeping to our own device prefix; foreign-device crash
        // artifacts will be reaped by their own owner the next time
        // that peer runs (its outbox row stays pinned in the retry
        // queue until then, which is correct).
        if is_tmp && !is_local {
            continue;
        }

        let Ok(metadata) = entry.metadata() else {
            continue;
        };
        if !metadata.is_file() {
            continue;
        }

        let Ok(modified) = metadata.modified() else {
            continue;
        };
        let age_secs = now.duration_since(modified).unwrap_or_default().as_secs();

        let threshold = if is_local {
            STALE_LOCAL_AGE_SECS
        } else {
            stale_foreign_age_secs
        };

        if age_secs >= threshold {
            if let Err(err) = fs::remove_file(entry.path()) {
                persist_filesystem_bridge_diagnostic(
                    conn,
                    &FilesystemBridgeDiagnostic::warn(
                        "sync.filesystem_bridge.finalize.stale_file_gc",
                        "Filesystem bridge stale file GC could not remove sync file",
                        format!("path={}, error={err}", entry.path().display()),
                    ),
                );
            }
        }
    }
}

/// Apply incoming remote records via `lorvex_sync::apply::apply_envelope`.
///
/// Each record's envelope is applied through the shared apply pipeline
/// (which handles LWW, tombstones, and version checks).
pub(super) fn apply_incoming_via_envelope(
    conn: &rusqlite::Connection,
    records: Vec<IncomingSyncRecord>,
    synced_ts: &str,
    filesystem_bridge_cursor: Option<&FilesystemBridgePullCursor>,
) -> AppResult<ApplyRemoteSyncResult> {
    // Delegate to the shared apply coordinator which handles:
    // topological sorting, projection maintenance,
    // device cursor recording, pending inbox drain, and filesystem bridge cursor.
    apply_remote_sync_records_with_checkpoint_writer(
        conn,
        records,
        synced_ts,
        RemoteApplyMode::BestEffort,
        |conn, _ordered, synced_ts| {
            upsert_sync_checkpoint_timestamp_if_newer(conn, "last_pull_at", synced_ts)?;
            if let Some(cursor) = filesystem_bridge_cursor {
                store_filesystem_bridge_pull_cursor(conn, cursor)?;
            }
            Ok(())
        },
    )
}
