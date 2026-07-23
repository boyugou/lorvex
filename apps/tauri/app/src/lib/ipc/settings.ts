import { invoke, invokeIpc } from './core';
import type { DeviceStateKey, PreferenceKey } from '../preferences/keys';
import type { DeviceStateValueOf, PreferenceValueOf } from '../preferences/values';

export const getPreference = (key: PreferenceKey, signal?: AbortSignal): Promise<string | null> =>
  invoke('get_preference', { key }, signal);

/**
 * Batched preference fetch.: callers that want several
 * preferences at once should use this instead of `Promise.all` over
 * multiple `getPreference` calls — the backend returns all requested
 * keys in a single `WHERE key IN (...)` SELECT.
 *
 * Returns a Map keyed by preference name. Missing keys are absent
 * from the Map (mirrors `getPreference`'s null behavior).
 */
export async function getPreferences(
  keys: readonly PreferenceKey[],
  signal?: AbortSignal,
): Promise<Map<string, string>> {
  if (keys.length === 0) return new Map();
  const pairs = await invoke<Array<[string, string]>>('get_preferences', {
    keys: [...keys],
  }, signal);
  return new Map(pairs);
}

// keys constrained to the literal unions in
// `lib/preferenceKeys.ts`, *and* values constrained to the per-key
// shape in `lib/preferenceValues.ts`. A typo, stale key, or
// mismatched value (e.g. passing a boolean to a numeric key) all fail
// at compile time. Runtime serialization is unchanged — every value
// still goes through `JSON.stringify` and lands in the same
// `preferences` / `device_state` text column.
export const setPreference = <K extends PreferenceKey>(
  key: K,
  value: PreferenceValueOf<K>,
  signal?: AbortSignal,
): Promise<void> =>
  invokeIpc('set_preference', { key, value: JSON.stringify(value) }, signal);

export const getDeviceState = (key: DeviceStateKey, signal?: AbortSignal): Promise<string | null> =>
  invoke('get_device_state', { key }, signal);

export const setDeviceState = <K extends DeviceStateKey>(
  key: K,
  value: DeviceStateValueOf<K>,
  signal?: AbortSignal,
): Promise<void> =>
  invoke('set_device_state', { key, value: JSON.stringify(value) }, signal);

export interface SetupStatus {
  list_count: number;
  default_list_id: string | null;
  lists_ready: boolean;
  default_list_ready: boolean;
  working_hours_ready: boolean;
  normal_task_creation_ready: boolean;
  prerequisites_ready: boolean;
  explicit_setup_completed: boolean;
  setup_completed: boolean;
}

export const getSetupStatus = (signal?: AbortSignal): Promise<SetupStatus> =>
  invoke('get_setup_status', undefined, signal);

export interface ErrorLogEntry {
  id: string;
  source: string;
  level: 'debug' | 'info' | 'warn' | 'error' | string;
  message: string;
  details: string | null;
  created_at: string;
}

interface ClearErrorLogsResult {
  deleted: number;
}

export interface ExportSnapshotResult {
  export_path: string;
  format_version: number;
  scope_kind: 'full' | 'scoped';
  scope_categories: SnapshotExportCategory[];
  dependency_mode: 'closure';
  entity_counts: Record<string, number>;
  edge_counts: Record<string, number>;
}

export type SnapshotExportCategory =
  | 'tasks'
  | 'lists'
  | 'calendar'
  | 'habits'
  | 'daily_reviews'
  | 'memory'
  | 'preferences'
  | 'focus'
  | 'subscriptions'
  | 'audit';

export interface ImportSnapshotResult {
  entities_created: number;
  entities_updated: number;
  entities_skipped: number;
  scope_kind: 'full' | 'scoped';
  scope_categories: SnapshotExportCategory[];
  dependency_mode: 'closure';
  validation_findings: Array<{
    severity: 'error' | 'warning';
    code: string;
    message: string;
  }>;

  // dry-run preview fields. `dry_run` is true when the caller
  // asked for a preview; the *_to_* counts describe what the commit
  // path would do, and no DB mutation occurred.
  dry_run: boolean;
  tasks_to_create: number;
  tasks_to_update: number;
  tasks_to_skip: number;
  lists_to_create: number;
  habits_to_create: number;
  preferences_to_change: number;
  memory_to_write: number;
  blobs_hash_mismatch: number;
  estimated_size_bytes: number;
  schema_version: number | null;
  source_device_id: string | null;
  export_timestamp: string | null;
}

export const appendErrorLog = (
  source: string,
  message: string,
  details?: string,
  level?: 'debug' | 'info' | 'warn' | 'error',
  signal?: AbortSignal,
): Promise<void> =>
  invoke('append_error_log', {
    source,
    message,
    details: details ?? null,
    level: level ?? null,
  }, signal);

export const getErrorLogs = (
  limit?: number,
  options?: { sinceIso?: string | null },
  signal?: AbortSignal,
): Promise<ErrorLogEntry[]> =>
  invoke(
    'get_error_logs',
    {
      limit: limit ?? null,
      since_iso: options?.sinceIso ?? null,
    },
    signal,
  );

export const clearErrorLogs = (signal?: AbortSignal): Promise<ClearErrorLogsResult> =>
  invoke('clear_error_logs', undefined, signal);

/**
 * count of `error_logs` rows written after the user last
 * opened Settings → Data → Diagnostics on this device. Drives the
 * unseen-count badge on the Settings sidebar entry. When the marker
 * has never been written, every existing row counts as unseen, so
 * fresh installs with pre-populated errors still surface the badge.
 */
export const getUnseenErrorLogCount = (signal?: AbortSignal): Promise<number> =>
  invoke('get_unseen_error_log_count', undefined, signal);

/**
 * writes `error_logs_last_viewed_at = now()` to
 * `device_state`. The frontend fires this when the Settings Data
 * section mounts so the sidebar badge clears. No-op if the write
 * fails; the badge simply keeps its prior value.
 */
export const markErrorLogsViewed = (signal?: AbortSignal): Promise<void> =>
  invoke('mark_error_logs_viewed', undefined, signal);

interface PurgeCancelledTasksResult {
  purged_count: number;
  purged_task_ids: string[];
}

export const purgeCancelledTasks = (signal?: AbortSignal): Promise<PurgeCancelledTasksResult> =>
  invokeIpc('purge_cancelled_tasks', {}, signal);

export interface DiagnosticsVersions {
  app_version: string;
  mcp_server_version: string;
  schema_version: number;
  payload_schema_version: number;
}

/**
 * Bundle versions for the About panel so a bug reporter can copy the
 * app/runtime/schema contract in one click.
 */
export const getDiagnosticsVersions = (signal?: AbortSignal): Promise<DiagnosticsVersions> =>
  invoke('get_diagnostics_versions', undefined, signal);

interface ClearChangelogResult {
  deleted: number;
}

export const clearChangelog = (signal?: AbortSignal): Promise<ClearChangelogResult> =>
  invokeIpc('clear_changelog', undefined, signal);

interface DataRetentionCleanupResult {
  changelog_deleted: number;
  error_logs_deleted: number;
}

export const runDataRetentionCleanup = (signal?: AbortSignal): Promise<DataRetentionCleanupResult> =>
  invokeIpc('run_data_retention_cleanup', undefined, signal);

export const exportDataSnapshot = (
  outputPath?: string,
  scopeCategories?: SnapshotExportCategory[],
  signal?: AbortSignal,
): Promise<ExportSnapshotResult> =>
  invoke('export_data_snapshot', {
    output_path: outputPath ?? null,
    scope_categories: scopeCategories ?? null,
  }, signal);

export const importDataSnapshot = (
  filePath: string,
  options?: { dryRun?: boolean; signal?: AbortSignal },
): Promise<ImportSnapshotResult> => {
  const payload = {
    file_path: filePath,
    // optional dry-run flag. When true the backend returns the
    // preview summary without mutating the DB. When omitted/false the
    // backend commits as before.
    dry_run: options?.dryRun ?? false,
  };
  return options?.dryRun === true
    ? invoke('import_data_snapshot', payload, options.signal)
    : invokeIpc('import_data_snapshot', payload, options?.signal);
};

/** Per-table row counts from a lorvex-interchange operation. */
export interface InterchangeExportResult {
  export_path: string;
  row_counts: Record<string, number>;
}
export interface InterchangeImportResult {
  row_counts: Record<string, number>;
}

/**
 * Export the store as a `lorvex-interchange` ZIP (the lean whole-database
 * migration format). Writes to the data dir's `exports/` unless a path is
 * given; returns the written path and counts.
 */
export const exportInterchange = (
  options?: { outputPath?: string; listIds?: string[]; signal?: AbortSignal },
): Promise<InterchangeExportResult> =>
  invoke(
    'export_interchange',
    {
      output_path: options?.outputPath ?? null,
      list_ids: options?.listIds && options.listIds.length > 0 ? options.listIds : null,
    },
    options?.signal,
  );

/** Import a `lorvex-interchange` ZIP into the current store. */
export const importInterchange = (
  filePath: string,
  signal?: AbortSignal,
): Promise<InterchangeImportResult> =>
  invokeIpc('import_interchange', { input_path: filePath }, signal);

interface ResetAllDataResult {
  tables_cleared: number;
  /**
   * count of `OP_DELETE` envelopes (and matching
   * tombstones) the backend emitted to the sync outbox before the bulk
   * wipe so peers honor the reset on the next sync cycle. Sums across
   * every syncable aggregate-root table (tasks, lists, tags,
   * calendar_events, habits, memories, daily_reviews,
   * focus_schedule, current_focus, calendar_subscriptions); the
   * receiver cascade-tombstones edges and child collections.
   */
  entities_tombstoned: number;
}

export const resetAllData = (confirmation: string, signal?: AbortSignal): Promise<ResetAllDataResult> =>
  invokeIpc('reset_all_data', { confirmation }, signal);

interface ResetPreferencesResult {
  deleted: number;
}

export const resetPreferences = (signal?: AbortSignal): Promise<ResetPreferencesResult> =>
  invokeIpc('reset_preferences', {}, signal);

export interface McpServerStatus {
  resolved: boolean;
  command: string | null;
  args: string[] | null;
  cwd: string | null;
  error: string | null;
  /** Shared MCP host authority: "cli" | "app" | null (not set) */
  mcp_host_authority: string | null;
  /** Whether the CLI binary is detected at a well-known path */
  cli_detected: boolean;
}

export const getMcpServerStatus = (signal?: AbortSignal): Promise<McpServerStatus> =>
  invoke('get_mcp_server_status', undefined, signal);
