import { invoke } from './core';

/**
 * A row from `sync_conflict_log` (local-only, never synced). Surfaced
 * in Settings → Diagnostics so users can tell why a record "changed"
 * after a sync cycle..
 */
export interface SyncConflictLogEntry {
  id: number;
  /** Resolution strategy: lww / tag_merge / recurrence_dedup / fk_stalled / fk_unresolved / reseed_required. */
  kind: string;
  entity_type: string;
  entity_id: string;
  /** HLC version of the winner (kept) side. */
  local_version: string;
  /** HLC version of the loser (discarded) side. */
  remote_version: string;
  /** Device that produced the losing entity. */
  loser_device_id: string;
  /** RFC3339 timestamp when the conflict was resolved. */
  occurred_at: string;
  /** Scrubbed loser snapshot (PII fields redacted). May be null. */
  details: string | null;
}

export const getSyncConflictLog = (
  limit?: number,
  sinceIso?: string | null,
  sourceDeviceId?: string | null,
  signal?: AbortSignal,
): Promise<SyncConflictLogEntry[]> =>
  invoke(
    'get_sync_conflict_log',
    {
      limit: limit ?? null,
      since_iso: sinceIso ?? null,
      source_device_id: sourceDeviceId ?? null,
    },
    signal,
  );

/**
 * Distinct device IDs observed in diagnostics rows, ordered by most
 * recent activity first. Powers the "device scope" dropdown in
 * Settings → Diagnostics. Returns an empty array on local-only installs
 * where no diagnostic row carries device provenance.
 */
export const getDiagnosticsDeviceIds = (signal?: AbortSignal): Promise<string[]> =>
  invoke('get_diagnostics_device_ids', undefined, signal);

/**
 * Summary returned by `export_diagnostics_bundle`. Mirrors the Rust
 * `ExportDiagnosticsBundleResult` shape. The row counts let the UI
 * confirm — to both the user and a reviewer triaging the resulting
 * bug report — that the bundle actually contains something.
 */
export interface ExportDiagnosticsBundleResult {
  /** Absolute path the ZIP was written to (after extension normalization). */
  path: string;
  /** Rows written into `error_logs.jsonl`. */
  error_log_count: number;
  /** Rows written into `ai_changelog_recent.jsonl`. */
  changelog_count: number;
  /** Rows written into `sync_conflict_log.jsonl`. */
  conflict_log_count: number;
}

/**
 * Produce a single ZIP archive at `destPath` with the diagnostic
 * signals needed to triage a bug report. The caller must
 * obtain `destPath` from a user-gated native save dialog — there is no
 * silent fallback location. A `.zip` extension is appended if missing.
 */
export const exportDiagnosticsBundle = (
  destPath: string,
  signal?: AbortSignal,
): Promise<ExportDiagnosticsBundleResult> =>
  invoke('export_diagnostics_bundle', { dest_path: destPath }, signal);
