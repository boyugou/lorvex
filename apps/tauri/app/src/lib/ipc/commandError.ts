/**
 * Typed IPC command error envelope.
 *
 * The Tauri command surface returns `Result<T, String>` because the
 * IPC bridge serializes errors as strings. wire payload
 * was a free-text human-readable message, optionally prefixed with a
 * class-specific sentinel like `__disk_full__:` for the toast layer
 * to pattern-match. The
 * sentinel approach worked but didn't scale: every new class needed a
 * new prefix, and any non-prefixed error fell through to the opaque
 * "An internal error occurred" toast — the renderer couldn't tell
 * `NotFound` from `Validation` from a raw SQL error.
 *
 * The typed envelope replaces the prefix-matching dispatch with a JSON
 * object the frontend parses into a discriminated union. The CLI
 * surface completed an analogous typed-kind rewrite in
 * `2c08c97c8` (`CliError` enum); the Tauri side mirrors it. The Rust
 * source of truth lives in `app/src-tauri/src/error.rs::CommandError`;
 * the round-trip is pinned by `app_error_*_emits_typed_envelope` tests
 * there and by the parser tests in `commandError.logic.test.ts`.
 *
 * Wire shape:
 *
 * ```json
 * { "kind": "validation", "message": "title cannot be empty" }
 * { "kind": "not_found",  "message": "Task not found: abc-123" }
 * { "kind": "disk_full",  "message": "...", "detail": "SQLITE_FULL: ..." }
 * ```
 */

/** Stable machine-tag for the failure class. Mirrors the Rust
 * `CommandErrorKind` enum verbatim. */
type CommandErrorKind =
  | 'validation'
  | 'not_found'
  | 'disk_full'
  | 'timeout'
  | 'tauri'
  | 'serialization'
  | 'internal'
  // user-initiated cancellation of a long-running
  // sync command (filesystem-bridge sync, snapshot import/export).
  // Toasts should render this as a benign
  // "Cancelled" state rather than the red error banner.
  | 'cancelled'
  // biometric-gated memory lock engaged. Renderer prompts for
  // Touch ID / Windows Hello unlock rather than rendering an error
  // toast.
  | 'memory_locked';

export interface CommandError {
  readonly kind: CommandErrorKind;
  readonly message: string;
  /** Optional diagnostic detail; not safe to render unconditionally. */
  readonly detail?: string;
}

const KNOWN_KINDS: ReadonlySet<CommandErrorKind> = new Set<CommandErrorKind>([
  'validation',
  'not_found',
  'disk_full',
  'timeout',
  'tauri',
  'serialization',
  'internal',
  'cancelled',
  'memory_locked',
]);

function isCommandErrorEnvelope(value: unknown): value is CommandError {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return false;
  const record = value as Record<string, unknown>;
  const kind = record.kind;
  const message = record.message;
  if (typeof kind !== 'string' || !KNOWN_KINDS.has(kind as CommandErrorKind)) return false;
  if (typeof message !== 'string') return false;
  return true;
}

/**
 * Try to parse an IPC error string into a typed [`CommandError`].
 * Returns `null` when the input is not a valid typed envelope — falls
 * through to legacy free-text handling so any third-party
 * `String`-typed reject (e.g. plugin errors that bypass `AppError`)
 * still renders.
 */
export function parseCommandError(error: unknown): CommandError | null {
  let message: string | null = null;
  if (typeof error === 'string') {
    message = error;
  } else if (typeof error === 'object' && error !== null) {
    const descriptor = Object.getOwnPropertyDescriptor(error, 'message');
    const candidate = descriptor && 'value' in descriptor ? descriptor.value : undefined;
    if (typeof candidate === 'string') {
      message = candidate;
    }
  }
  if (message === null) return null;
  // Cheap guard so we don't JSON.parse every plain error string.
  if (!message.startsWith('{')) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(message);
  } catch {
    return null;
  }
  if (!isCommandErrorEnvelope(parsed)) return null;
  // Normalize shape (drop unknown fields, ensure detail is a string
  // when present).
  const normalized: CommandError = {
    kind: parsed.kind,
    message: parsed.message,
    ...(typeof parsed.detail === 'string' ? { detail: parsed.detail } : {}),
  };
  return normalized;
}

/**
 * Convenience: returns the typed envelope OR a synthesized
 * `kind: 'internal'` envelope wrapping a free-text error. Lets call
 * sites switch on `kind` without separately handling the
 * not-an-envelope case.
 */
export function classifyCommandError(error: unknown): CommandError {
  const typed = parseCommandError(error);
  if (typed !== null) return typed;
  let message = '';
  if (typeof error === 'string') {
    message = error;
  } else if (typeof error === 'object' && error !== null) {
    const descriptor = Object.getOwnPropertyDescriptor(error, 'message');
    const candidate = descriptor && 'value' in descriptor ? descriptor.value : undefined;
    if (typeof candidate === 'string') message = candidate;
  }
  return { kind: 'internal', message };
}
