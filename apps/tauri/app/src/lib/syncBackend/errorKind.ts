/**
 * parse the `{kind, message, retryable, path}` envelope that
 * `run_filesystem_bridge_sync` now emits on failure
 * (see `app/src-tauri/src/commands/sync_error_kind.rs`). This lets the
 * UI render an actionable toast / status line instead of a raw
 * transport-specific error string.
 */
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { tryParseJson } from '../security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from '../objectGuards';

export type SyncErrorKind =
  | 'offline'
  | 'permissions'
  | 'timeout'
  | 'unknown';

export interface SyncErrorEnvelope {
  kind: SyncErrorKind;
  message: string;
  retryable: boolean;
  path: string | null;
}

const KNOWN_KINDS: ReadonlySet<SyncErrorKind> = new Set<SyncErrorKind>([
  'offline',
  'permissions',
  'timeout',
  'unknown',
]);

function isSyncErrorKind(value: unknown): value is SyncErrorKind {
  return typeof value === 'string' && KNOWN_KINDS.has(value as SyncErrorKind);
}

const SYNC_ERROR_ENVELOPE_KEYS = new Set(['kind', 'message', 'path', 'retryable']);

function hasOnlySyncErrorEnvelopeKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, SYNC_ERROR_ENVELOPE_KEYS);
}

/**
 * Parse a caught error into the wire envelope. The Rust command returns
 * the envelope as a JSON-encoded `String` (Tauri serializes
 * `Result<T, String>` errors as the raw error value, so the JSON arrives
 * as the error's `message` through `toIpcErrorMessage`). Any input that
 * can't be parsed as a valid envelope returns an empty `unknown`-kind
 * envelope; callers localize the user-facing fallback.
 */
export function parseSyncErrorEnvelope(error: unknown): SyncErrorEnvelope {
  const raw = toIpcErrorMessage(error);
  const trimmed = raw.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    const parseResult = tryParseJson(trimmed);
    if (parseResult.ok && isRecord(parseResult.value) && hasOnlySyncErrorEnvelopeKeys(parseResult.value)) {
      const record = parseResult.value;
      const pathValue = record.path;
      if (
        isSyncErrorKind(record.kind) &&
        typeof record.message === 'string' &&
        typeof record.retryable === 'boolean' &&
        (typeof pathValue === 'string' || pathValue === null)
      ) {
        return {
          kind: record.kind,
          message: record.message,
          retryable: record.retryable,
          path: pathValue,
        };
      }
    }
  }
  return { kind: 'unknown', message: '', retryable: false, path: null };
}
