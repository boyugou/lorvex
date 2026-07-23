//! Top-level orchestrator: assembles every sub-aggregate into a
//! [`SyncStatusSnapshot`]. Every concern dispatches to a per-file
//! helper ([`super::loaders`], [`super::parsers`],
//! [`super::apply_cycle`]) so this module reads as a flat
//! "load → parse → assemble" pipeline.

use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};

use crate::StoreError;

use super::apply_cycle::load_apply_cycle_status;
use super::loaders::{load_preference_value, load_sync_checkpoint_value};
use super::parsers::{
    deconstruct_sync_backend_preference, observe_timestamp_field, parse_hlc_cursor_projection,
    parse_optional_bool_state, parse_optional_i64_state, parse_optional_rfc3339_state,
    TimestampFieldState,
};
use super::{
    SYNC_CHECKPOINT_DEVICE_ID_KEY, SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY,
    SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY,
};

const SYNC_OUTBOX_FAILED_RETRY_THRESHOLD: i64 = 10;

#[derive(Debug, Serialize, Deserialize, Clone, PartialEq, Eq)]
pub struct SyncStatusSnapshot {
    pub sync_backend_kind_raw: Option<String>,
    pub sync_backend_kind: Option<String>,
    pub sync_backend_kind_effective: String,
    pub sync_backend_kind_malformed: bool,
    pub sync_backend_kind_malformed_reason: Option<String>,
    pub pending_count: i64,
    pub retrying_count: i64,
    pub failed_count: i64,
    pub oldest_pending_at: Option<String>,
    pub newest_pending_at: Option<String>,
    pub apply_cycle_count: i64,
    pub apply_cycle_last_started_at: Option<String>,
    pub apply_cycle_last_completed_at: Option<String>,
    pub apply_cycle_last_duration_ms: Option<i64>,
    pub apply_cycle_last_received: i64,
    pub apply_cycle_last_processed: i64,
    pub apply_cycle_last_applied: i64,
    pub apply_cycle_last_skipped_duplicate: i64,
    pub apply_cycle_last_skipped_stale: i64,
    pub apply_cycle_last_skipped_deferred: i64,
    pub apply_cycle_last_skipped_malformed: i64,
    pub apply_cycle_last_error: Option<String>,
    pub apply_cycles_retained_received: i64,
    pub apply_cycles_retained_processed: i64,
    pub apply_cycles_retained_applied: i64,
    pub apply_cycles_retained_skipped_duplicate: i64,
    pub apply_cycles_retained_skipped_stale: i64,
    pub apply_cycles_retained_skipped_deferred: i64,
    pub apply_cycles_retained_skipped_malformed: i64,
    pub pending_inbox_count: i64,
    pub pending_inbox_oldest_at: Option<String>,
    pub pending_inbox_oldest_at_malformed: bool,
    pub pending_inbox_oldest_at_malformed_reason: Option<String>,
    pub tombstone_count: i64,
    pub tombstone_oldest_deleted_at: Option<String>,
    pub tombstone_oldest_deleted_at_malformed: bool,
    pub tombstone_oldest_deleted_at_malformed_reason: Option<String>,
    pub tombstone_newest_deleted_at: Option<String>,
    pub tombstone_newest_deleted_at_malformed: bool,
    pub tombstone_newest_deleted_at_malformed_reason: Option<String>,
    pub conflict_log_count: i64,
    pub conflict_log_last_resolved_at: Option<String>,
    pub conflict_log_last_resolved_at_malformed: bool,
    pub conflict_log_last_resolved_at_malformed_reason: Option<String>,
    pub ical_subscription_total_count: i64,
    pub ical_subscription_failing_count: i64,
    pub ical_subscription_never_refreshed_count: i64,
    pub ical_subscription_stale_count: i64,
    pub reseed_required: bool,
    pub reseed_required_malformed: bool,
    pub reseed_required_malformed_reason: Option<String>,
    pub last_synced_at: Option<String>,
    pub last_synced_at_malformed: bool,
    pub last_synced_at_malformed_reason: Option<String>,
    pub last_success_at: Option<String>,
    pub last_success_at_malformed: bool,
    pub last_success_at_malformed_reason: Option<String>,
    pub last_pull_at: Option<String>,
    pub last_pull_at_malformed: bool,
    pub last_pull_at_malformed_reason: Option<String>,
    pub filesystem_bridge_last_pull_cursor: Option<String>,
    pub filesystem_bridge_last_pull_updated_at: Option<String>,
    pub filesystem_bridge_last_pull_device_id: Option<String>,
    pub filesystem_bridge_last_pull_event_id: Option<String>,
    pub filesystem_bridge_last_pull_cursor_malformed: bool,
    pub filesystem_bridge_last_pull_cursor_malformed_reason: Option<String>,
    pub filesystem_bridge_lookback_known_id_skipped_last_run: i64,
    pub filesystem_bridge_lookback_known_id_skipped_last_run_malformed: bool,
    pub filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason: Option<String>,
    pub filesystem_bridge_lookback_known_id_skipped_last_run_at: Option<String>,
    pub filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed: bool,
    pub filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason: Option<String>,
    pub device_id: Option<String>,
    pub last_error: Option<String>,
}

pub fn load_sync_status_snapshot(conn: &Connection) -> Result<SyncStatusSnapshot, StoreError> {
    let (
        pending_count,
        retrying_count,
        failed_count,
        oldest_pending_at,
        newest_pending_at,
        last_synced_at_raw,
        last_synced_at_malformed_count,
    ): (
        i64,
        i64,
        i64,
        Option<String>,
        Option<String>,
        Option<String>,
        i64,
    ) = conn
        .prepare_cached(
            "SELECT
                COUNT(*) AS pending_count,
                COALESCE(SUM(CASE WHEN retry_count > 0 THEN 1 ELSE 0 END), 0) AS retrying_count,
                COALESCE(SUM(CASE WHEN retry_count >= ?1 THEN 1 ELSE 0 END), 0) AS failed_count,
                /* Same GLOB shape gate as the sibling tombstone /
                 * pending_inbox / conflict_log aggregates below: a
                 * hand-edited row carrying a non-canonical literal
                 * (e.g. 'not-a-date') would otherwise win the lex
                 * MIN/MAX and shadow the well-formed values the
                 * settings panel needs to display. ?2 binds the
                 * `????-??-??T*` glob. */
                MIN(CASE WHEN trim(created_at) GLOB ?2 THEN trim(created_at) END) AS oldest_pending_at,
                MAX(CASE WHEN trim(created_at) GLOB ?2 THEN trim(created_at) END) AS newest_pending_at,
                (SELECT MAX(CASE WHEN trim(synced_at) GLOB ?2 THEN trim(synced_at) END)
                   FROM sync_outbox WHERE synced_at IS NOT NULL) AS last_synced_at,
                /* Count of `synced_at` values that exist but fail the
                 * shape gate. The aggregate above filters them out so
                 * the boundary stays well-formed; this count lets the
                 * post-aggregate code set the
                 * `last_synced_at_malformed` flag whenever ANY
                 * malformed row exists in the table, so the
                 * diagnostic surface can surface it. */
                (SELECT COALESCE(SUM(CASE WHEN synced_at IS NOT NULL
                                            AND trim(synced_at) NOT GLOB ?2
                                          THEN 1 ELSE 0 END), 0)
                   FROM sync_outbox) AS last_synced_at_malformed_count
             FROM sync_outbox
             WHERE synced_at IS NULL",
        )?
        .query_row(
            rusqlite::params![SYNC_OUTBOX_FAILED_RETRY_THRESHOLD, "????-??-??T*"],
            |row| {
                Ok((
                    row.get(0)?,
                    row.get(1)?,
                    row.get(2)?,
                    row.get(3)?,
                    row.get(4)?,
                    row.get(5)?,
                    row.get(6)?,
                ))
            },
        )?;
    let (last_synced_at, mut last_synced_at_malformed, mut last_synced_at_malformed_reason) =
        parse_optional_rfc3339_state(last_synced_at_raw.as_deref());
    if last_synced_at_malformed_count > 0 && !last_synced_at_malformed {
        // The boundary value (`last_synced_at`) was well-formed AND
        // passed the shape gate, but other rows in `sync_outbox`
        // carry malformed `synced_at` strings. Surface the flag so
        // the diagnostic surface still warns; the boundary value
        // scan, which advanced state.value only on parsable rows).
        last_synced_at_malformed = true;
        last_synced_at_malformed_reason = Some("invalid_rfc3339".to_string());
    }

    let apply_cycle_status = load_apply_cycle_status(conn)?;

    // Replaced three full-table scans (one per timestamp column) with
    // SQL aggregates. The previous shape pulled every row into Rust
    // just to compute MIN/MAX in a `for row in rows` loop —
    // pathological on a long-lived install with 100k tombstones,
    // every sync-status snapshot full-scanned the table. SQL's
    // MIN/MAX/COUNT are constant-time-ish via the indexes on these
    // columns. The shape-gate (`GLOB '????-??-??T*'`) restricts the
    // MIN/MAX to strings that pass a cheap RFC3339 prefix check so a
    // hand-edited row carrying a non-canonical literal (e.g.
    // `'not-a-timestamp'`) does NOT win the lex MAX and shadow the
    // well-formed value the diagnostic surface needs to display. A
    // separate `SUM(CASE WHEN <not glob> THEN 1 ELSE 0 END)` count
    // surfaces malformed rows back as the `malformed` flag —
    // never reported as the boundary value AND surface as a
    // malformed flag whenever at least one such row exists.
    const TS_GLOB: &str = "????-??-??T*";
    let (pending_inbox_count, pending_inbox_min, pending_inbox_malformed): (
        i64,
        Option<String>,
        i64,
    ) = conn
        .prepare_cached(
            "SELECT COUNT(*), \
                    MIN(CASE WHEN trim(first_attempted_at) GLOB ?1 THEN trim(first_attempted_at) END), \
                    COALESCE(SUM(CASE WHEN first_attempted_at IS NOT NULL \
                                       AND trim(first_attempted_at) NOT GLOB ?1 \
                                      THEN 1 ELSE 0 END), 0) \
             FROM sync_pending_inbox",
        )?
        .query_row(params![TS_GLOB], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })?;
    let mut pending_inbox_oldest_at_state = TimestampFieldState::default();
    observe_timestamp_field(
        &mut pending_inbox_oldest_at_state,
        pending_inbox_min.as_deref(),
        false,
    );
    if pending_inbox_malformed > 0 && !pending_inbox_oldest_at_state.malformed {
        pending_inbox_oldest_at_state.malformed = true;
        pending_inbox_oldest_at_state.malformed_reason = Some("invalid_rfc3339".to_string());
    }

    let (tombstone_count, tombstone_min, tombstone_max, tombstone_malformed): (
        i64,
        Option<String>,
        Option<String>,
        i64,
    ) = conn
        .prepare_cached(
            "SELECT COUNT(*), \
                    MIN(CASE WHEN trim(deleted_at) GLOB ?1 THEN trim(deleted_at) END), \
                    MAX(CASE WHEN trim(deleted_at) GLOB ?1 THEN trim(deleted_at) END), \
                    COALESCE(SUM(CASE WHEN deleted_at IS NOT NULL \
                                       AND trim(deleted_at) NOT GLOB ?1 \
                                      THEN 1 ELSE 0 END), 0) \
             FROM sync_tombstones",
        )?
        .query_row(params![TS_GLOB], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
        })?;
    let mut tombstone_oldest_deleted_at_state = TimestampFieldState::default();
    let mut tombstone_newest_deleted_at_state = TimestampFieldState::default();
    observe_timestamp_field(
        &mut tombstone_oldest_deleted_at_state,
        tombstone_min.as_deref(),
        false,
    );
    observe_timestamp_field(
        &mut tombstone_newest_deleted_at_state,
        tombstone_max.as_deref(),
        true,
    );
    if tombstone_malformed > 0 {
        if !tombstone_oldest_deleted_at_state.malformed {
            tombstone_oldest_deleted_at_state.malformed = true;
            tombstone_oldest_deleted_at_state.malformed_reason =
                Some("invalid_rfc3339".to_string());
        }
        if !tombstone_newest_deleted_at_state.malformed {
            tombstone_newest_deleted_at_state.malformed = true;
            tombstone_newest_deleted_at_state.malformed_reason =
                Some("invalid_rfc3339".to_string());
        }
    }

    let (conflict_log_count, conflict_max, conflict_malformed): (i64, Option<String>, i64) = conn
        .prepare_cached(
            "SELECT COUNT(*), \
                    MAX(CASE WHEN trim(resolved_at) GLOB ?1 THEN trim(resolved_at) END), \
                    COALESCE(SUM(CASE WHEN resolved_at IS NOT NULL \
                                       AND trim(resolved_at) NOT GLOB ?1 \
                                      THEN 1 ELSE 0 END), 0) \
             FROM sync_conflict_log",
        )?
        .query_row(params![TS_GLOB], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })?;
    let mut conflict_log_last_resolved_at_state = TimestampFieldState::default();
    observe_timestamp_field(
        &mut conflict_log_last_resolved_at_state,
        conflict_max.as_deref(),
        true,
    );
    if conflict_malformed > 0 && !conflict_log_last_resolved_at_state.malformed {
        conflict_log_last_resolved_at_state.malformed = true;
        conflict_log_last_resolved_at_state.malformed_reason = Some("invalid_rfc3339".to_string());
    }

    let (
        ical_subscription_total_count,
        ical_subscription_failing_count,
        ical_subscription_never_refreshed_count,
        ical_subscription_stale_count,
    ): (i64, i64, i64, i64) = conn
        .prepare_cached(
            // Inline `AVAILABILITY_STATE_ERROR_SQL_LIST` so the SQL set
            // stays in lock-step with `is_provider_error_label` (Rust-side
            // predicate). format! in a const-friendly position keeps the
            // SQL string identical across calls so prepare_cached still
            // hits the same cache slot.
            &format!(
                "WITH subscription_health AS (
                SELECT
                    s.enabled,
                    psr.provider_kind IS NULL AS missing_runtime_state,
                    psr.last_refresh_success_at,
                    COALESCE(
                        psr.availability_state IN ({error_states})
                        OR psr.last_refresh_result IN ({error_states}),
                        0
                    ) AS has_error
                FROM calendar_subscriptions s
                LEFT JOIN provider_scope_runtime_state psr
                  ON psr.provider_kind = 'ical_subscription' AND psr.provider_scope = s.id
            )
            SELECT
                COUNT(*) AS total_count,
                COALESCE(SUM(CASE WHEN enabled = 1 AND has_error THEN 1 ELSE 0 END), 0) AS failing_count,
                COALESCE(SUM(CASE
                    WHEN enabled = 1
                         AND (missing_runtime_state OR (last_refresh_success_at IS NULL AND NOT has_error))
                    THEN 1
                    ELSE 0
                END), 0) AS never_refreshed_count,
                COALESCE(SUM(CASE
                    WHEN enabled = 1
                         AND last_refresh_success_at IS NOT NULL
                         AND last_refresh_success_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours')
                         AND NOT has_error
                    THEN 1
                    ELSE 0
                END), 0) AS stale_count
             FROM subscription_health",
                error_states = lorvex_domain::naming::AVAILABILITY_STATE_ERROR_SQL_LIST,
            ),
        )?
        .query_row([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)))?;

    let device_id = load_sync_checkpoint_value(conn, SYNC_CHECKPOINT_DEVICE_ID_KEY)?;
    let (reseed_required, reseed_required_malformed, reseed_required_malformed_reason) =
        parse_optional_bool_state(load_sync_checkpoint_value(conn, "reseed_required")?.as_deref());
    let last_error = load_sync_checkpoint_value(conn, "last_error")?;
    let (last_success_at, last_success_at_malformed, last_success_at_malformed_reason) =
        parse_optional_rfc3339_state(
            load_sync_checkpoint_value(conn, "last_success_at")?.as_deref(),
        );
    let (last_pull_at, last_pull_at_malformed, last_pull_at_malformed_reason) =
        parse_optional_rfc3339_state(load_sync_checkpoint_value(conn, "last_pull_at")?.as_deref());

    let filesystem_bridge_last_pull_cursor =
        load_sync_checkpoint_value(conn, SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY)?;
    let (
        filesystem_bridge_last_pull_updated_at,
        filesystem_bridge_last_pull_device_id,
        filesystem_bridge_last_pull_event_id,
        filesystem_bridge_last_pull_cursor_malformed,
        filesystem_bridge_last_pull_cursor_malformed_reason,
    ) = parse_hlc_cursor_projection(filesystem_bridge_last_pull_cursor.as_deref());

    let (
        filesystem_bridge_lookback_known_id_skipped_last_run,
        filesystem_bridge_lookback_known_id_skipped_last_run_malformed,
        filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason,
    ) = parse_optional_i64_state(
        load_sync_checkpoint_value(
            conn,
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY,
        )?
        .as_deref(),
    );
    let (
        filesystem_bridge_lookback_known_id_skipped_last_run_at,
        filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed,
        filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason,
    ) = parse_optional_rfc3339_state(
        load_sync_checkpoint_value(
            conn,
            SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY,
        )?
        .as_deref(),
    );

    let sync_backend_kind_raw =
        load_preference_value(conn, lorvex_domain::preference_keys::PREF_SYNC_BACKEND_KIND)?;
    let (sync_backend_kind, sync_backend_kind_malformed, sync_backend_kind_malformed_reason) =
        deconstruct_sync_backend_preference(sync_backend_kind_raw.as_deref());
    let sync_backend_kind_effective = sync_backend_kind
        .clone()
        .unwrap_or_else(|| lorvex_domain::parsing::SyncBackendKind::platform_default().to_string());

    Ok(SyncStatusSnapshot {
        sync_backend_kind_raw,
        sync_backend_kind,
        sync_backend_kind_effective,
        sync_backend_kind_malformed,
        sync_backend_kind_malformed_reason,
        pending_count,
        retrying_count,
        failed_count,
        oldest_pending_at,
        newest_pending_at,
        apply_cycle_count: apply_cycle_status.count,
        apply_cycle_last_started_at: apply_cycle_status.last_started_at,
        apply_cycle_last_completed_at: apply_cycle_status.last_completed_at,
        apply_cycle_last_duration_ms: apply_cycle_status.last_duration_ms,
        apply_cycle_last_received: apply_cycle_status.last_received,
        apply_cycle_last_processed: apply_cycle_status.last_processed,
        apply_cycle_last_applied: apply_cycle_status.last_applied,
        apply_cycle_last_skipped_duplicate: apply_cycle_status.last_skipped_duplicate,
        apply_cycle_last_skipped_stale: apply_cycle_status.last_skipped_stale,
        apply_cycle_last_skipped_deferred: apply_cycle_status.last_skipped_deferred,
        apply_cycle_last_skipped_malformed: apply_cycle_status.last_skipped_malformed,
        apply_cycle_last_error: apply_cycle_status.last_error,
        apply_cycles_retained_received: apply_cycle_status.retained_received,
        apply_cycles_retained_processed: apply_cycle_status.retained_processed,
        apply_cycles_retained_applied: apply_cycle_status.retained_applied,
        apply_cycles_retained_skipped_duplicate: apply_cycle_status.retained_skipped_duplicate,
        apply_cycles_retained_skipped_stale: apply_cycle_status.retained_skipped_stale,
        apply_cycles_retained_skipped_deferred: apply_cycle_status.retained_skipped_deferred,
        apply_cycles_retained_skipped_malformed: apply_cycle_status.retained_skipped_malformed,
        pending_inbox_count,
        pending_inbox_oldest_at: pending_inbox_oldest_at_state.value,
        pending_inbox_oldest_at_malformed: pending_inbox_oldest_at_state.malformed,
        pending_inbox_oldest_at_malformed_reason: pending_inbox_oldest_at_state.malformed_reason,
        tombstone_count,
        tombstone_oldest_deleted_at: tombstone_oldest_deleted_at_state.value,
        tombstone_oldest_deleted_at_malformed: tombstone_oldest_deleted_at_state.malformed,
        tombstone_oldest_deleted_at_malformed_reason: tombstone_oldest_deleted_at_state
            .malformed_reason,
        tombstone_newest_deleted_at: tombstone_newest_deleted_at_state.value,
        tombstone_newest_deleted_at_malformed: tombstone_newest_deleted_at_state.malformed,
        tombstone_newest_deleted_at_malformed_reason: tombstone_newest_deleted_at_state
            .malformed_reason,
        conflict_log_count,
        conflict_log_last_resolved_at: conflict_log_last_resolved_at_state.value,
        conflict_log_last_resolved_at_malformed: conflict_log_last_resolved_at_state.malformed,
        conflict_log_last_resolved_at_malformed_reason: conflict_log_last_resolved_at_state
            .malformed_reason,
        ical_subscription_total_count,
        ical_subscription_failing_count,
        ical_subscription_never_refreshed_count,
        ical_subscription_stale_count,
        reseed_required,
        reseed_required_malformed,
        reseed_required_malformed_reason,
        last_synced_at,
        last_synced_at_malformed,
        last_synced_at_malformed_reason,
        last_success_at,
        last_success_at_malformed,
        last_success_at_malformed_reason,
        last_pull_at,
        last_pull_at_malformed,
        last_pull_at_malformed_reason,
        filesystem_bridge_last_pull_cursor,
        filesystem_bridge_last_pull_updated_at,
        filesystem_bridge_last_pull_device_id,
        filesystem_bridge_last_pull_event_id,
        filesystem_bridge_last_pull_cursor_malformed,
        filesystem_bridge_last_pull_cursor_malformed_reason,
        filesystem_bridge_lookback_known_id_skipped_last_run,
        filesystem_bridge_lookback_known_id_skipped_last_run_malformed,
        filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason,
        filesystem_bridge_lookback_known_id_skipped_last_run_at,
        filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed,
        filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason,
        device_id,
        last_error,
    })
}
