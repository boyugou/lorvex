import { invoke, invokeIpc } from './core';

export const SYNC_OUTBOX_MAX_RETRIES = 10;

export interface SyncStatus {
  sync_backend_kind_raw: string | null;
  /** Canonical configured backend kind, or null when unset or malformed. */
  sync_backend_kind: string | null;
  /** Backend kind the runtime will actually treat as active after default fallback. */
  sync_backend_kind_effective: string;
  sync_backend_kind_malformed: boolean;
  sync_backend_kind_malformed_reason: string | null;
  pending_count: number;
  retrying_count: number;
  failed_count: number;
  oldest_pending_at: string | null;
  newest_pending_at: string | null;
  apply_cycle_count: number;
  apply_cycle_last_started_at: string | null;
  apply_cycle_last_completed_at: string | null;
  apply_cycle_last_duration_ms: number | null;
  apply_cycle_last_received: number;
  apply_cycle_last_processed: number;
  apply_cycle_last_applied: number;
  apply_cycle_last_skipped_duplicate: number;
  apply_cycle_last_skipped_stale: number;
  apply_cycle_last_skipped_deferred: number;
  apply_cycle_last_skipped_malformed: number;
  apply_cycle_last_error: string | null;
  apply_cycles_retained_received: number;
  apply_cycles_retained_processed: number;
  apply_cycles_retained_applied: number;
  apply_cycles_retained_skipped_duplicate: number;
  apply_cycles_retained_skipped_stale: number;
  apply_cycles_retained_skipped_deferred: number;
  apply_cycles_retained_skipped_malformed: number;
  pending_inbox_count: number;
  pending_inbox_oldest_at: string | null;
  pending_inbox_oldest_at_malformed: boolean;
  pending_inbox_oldest_at_malformed_reason: string | null;
  tombstone_count: number;
  tombstone_oldest_deleted_at: string | null;
  tombstone_oldest_deleted_at_malformed: boolean;
  tombstone_oldest_deleted_at_malformed_reason: string | null;
  tombstone_newest_deleted_at: string | null;
  tombstone_newest_deleted_at_malformed: boolean;
  tombstone_newest_deleted_at_malformed_reason: string | null;
  conflict_log_count: number;
  conflict_log_last_resolved_at: string | null;
  conflict_log_last_resolved_at_malformed: boolean;
  conflict_log_last_resolved_at_malformed_reason: string | null;
  ical_subscription_total_count: number;
  ical_subscription_failing_count: number;
  ical_subscription_never_refreshed_count: number;
  ical_subscription_stale_count: number;
  reseed_required: boolean;
  reseed_required_malformed: boolean;
  reseed_required_malformed_reason: string | null;
  last_synced_at: string | null;
  last_synced_at_malformed: boolean;
  last_synced_at_malformed_reason: string | null;
  last_success_at: string | null;
  last_success_at_malformed: boolean;
  last_success_at_malformed_reason: string | null;
  last_pull_at: string | null;
  last_pull_at_malformed: boolean;
  last_pull_at_malformed_reason: string | null;
  filesystem_bridge_last_pull_cursor: string | null;
  filesystem_bridge_last_pull_updated_at: string | null;
  filesystem_bridge_last_pull_device_id: string | null;
  filesystem_bridge_last_pull_event_id: string | null;
  filesystem_bridge_last_pull_cursor_malformed: boolean;
  filesystem_bridge_last_pull_cursor_malformed_reason: string | null;
  filesystem_bridge_lookback_known_id_skipped_last_run: number;
  filesystem_bridge_lookback_known_id_skipped_last_run_malformed: boolean;
  filesystem_bridge_lookback_known_id_skipped_last_run_malformed_reason: string | null;
  filesystem_bridge_lookback_known_id_skipped_last_run_at: string | null;
  filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed: boolean;
  filesystem_bridge_lookback_known_id_skipped_last_run_at_malformed_reason: string | null;
  device_id: string | null;
  last_error: string | null;
}

export interface SyncOutboxEntry {
  id: string;
  entity_type: string;
  entity_id: string;
  operation: string;
  payload: string;
  created_at: string;
  device_id: string;
  synced_at: string | null;
  retry_count: number;
  last_retry_at: string | null;
}

interface ApplyRemoteSyncResult {
  received: number;
  processed: number;
  applied: number;
  skipped_duplicate: number;
  skipped_stale: number;
  skipped_deferred: number;
  skipped_malformed: number;
  diagnostics_log_failures: number;
}

export interface FilesystemBridgeSyncResult {
  filesystem_bridge_root_path: string;
  attempted_push: number;
  pushed: number;
  push_write_errors: number;
  pulled_files: number;
  pulled_remote_events: number;
  pull_parse_errors: number;
  lookback_known_id_skipped: number;
  pull_limit_hit: boolean;
  apply_result: ApplyRemoteSyncResult;
  /** When true, incremental sync was skipped because a full reseed is required. */
  reseed_paused: boolean;
}

export const getSyncStatus = (signal?: AbortSignal): Promise<SyncStatus> =>
  invoke('get_sync_status', undefined, signal);

export const getDefaultFilesystemBridgeRootPath = (signal?: AbortSignal): Promise<string | null> =>
  invoke('get_default_filesystem_bridge_root_path', undefined, signal);

export const getPendingOutboxEntries = (limit?: number, signal?: AbortSignal): Promise<SyncOutboxEntry[]> =>
  invoke('get_pending_outbox_entries', { limit: limit ?? null }, signal);

export const getRecentOutboxEntries = (limit?: number, signal?: AbortSignal): Promise<SyncOutboxEntry[]> =>
  invoke('get_recent_outbox_entries', { limit: limit ?? null }, signal);

export const runFilesystemBridgeSync = (
  rootPath: string,
  maxEvents?: number,
  signal?: AbortSignal,
): Promise<FilesystemBridgeSyncResult> =>
  invokeIpc(
    'run_filesystem_bridge_sync',
    { filesystem_bridge_root_path: rootPath, max_events: maxEvents ?? null },
    signal,
  );

interface SeedFullSyncResult {
  tasks_enqueued: number;
  lists_enqueued: number;
  preferences_enqueued: number;
  task_calendar_event_links_enqueued: number;
  current_focus_enqueued: number;
  daily_reviews_enqueued: number;
  memories_enqueued: number;
  calendar_events_enqueued: number;
  habits_enqueued: number;
  habit_completions_enqueued: number;
  task_reminders_enqueued: number;
  task_checklist_items_enqueued: number;
  habit_reminder_policies_enqueued: number;
  focus_schedules_enqueued: number;
  tags_enqueued: number;
  task_tags_enqueued: number;
  task_dependencies_enqueued: number;
  memory_revisions_enqueued: number;
  ai_changelog_enqueued: number;
}

export const seedFullSync = (signal?: AbortSignal): Promise<SeedFullSyncResult> =>
  invokeIpc('seed_full_sync', {}, signal);

/**
 * call this after the user switches sync transports so
 * retry counts accumulated against the previous transport don't
 * permanently quarantine outbox rows for the new one. Returns the
 * number of rows whose
 * `retry_count` was reset to 0.
 */
export const resetOutboxRetryCountsForTransportSwitch = (signal?: AbortSignal): Promise<number> =>
  invokeIpc('reset_outbox_retry_counts_for_transport_switch', {}, signal);

/**
 * reset `retry_count`, `last_retry_at`, and `last_error`
 * on a single unsynced outbox row so the user can manually retry a
 * quarantined row (one whose `retry_count >= MAX_RETRIES` excluded it
 * from the pending queue) without the full reset-and-reseed sledgehammer.
 * No-op when the row is missing or already synced.
 */
export const resetOutboxEntryRetryCount = (id: string, signal?: AbortSignal): Promise<void> =>
  invokeIpc('reset_outbox_entry_retry_count', { id }, signal);

/**
 * Discriminant for the long-running sync arms that the `cancel_sync`
 * IPC can interrupt. Mirrors `SyncKind` in
 * `app/src-tauri/src/commands/sync/runtime/cancel_signal.rs` —
 * `#[serde(rename_all = "snake_case")]` is what makes these the wire
 * values.
 */
export type SyncKind =
  | 'filesystem_bridge'
  | 'snapshot_import'
  | 'snapshot_export';

/**
 * Cancel an in-flight sync arm. The targeted loop observes the cancel
 * flag at its next iteration boundary and unwinds cleanly; the next
 * arming clears the flag, so a stale cancel cannot poison a future
 * run. No-op when no run of that kind is active.
 */
export const cancelSync = (kind: SyncKind, signal?: AbortSignal): Promise<void> =>
  invokeIpc('cancel_sync', { kind }, signal);
