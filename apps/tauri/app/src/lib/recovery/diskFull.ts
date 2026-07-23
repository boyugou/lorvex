/**
 * Disk-full ("Storage is full") IPC error handling.
 *
 * The Rust layer classifies `SQLITE_FULL` / ENOSPC into a typed
 * `AppError::DiskFull` variant and emits it across the IPC boundary as
 * the typed `CommandError` envelope (`{ "kind": "disk_full", ... }`).
 * wire format was a free-text string with a magic
 * `__disk_full__:` prefix; the typed envelope replaces the prefix
 * matching with `kind`-based dispatch — the parser lives in
 * `app/src/lib/ipc/commandError.ts` and `diskFull.logic.ts`.
 *
 * This module:
 *   1. Recognizes the typed envelope as a disk-full error,
 *   2. Surfaces a 10-second actionable toast with two buttons
 *      ("Open storage" and "Try again"),
 *   3. De-duplicates the toast via the existing toast dedup window so
 *      a retry storm doesn't stack five copies of the same banner.
 *
 * The handler is wired into the app-level Query/Mutation error path in
 * `main.tsx`, so every surfaced IPC failure automatically benefits
 * without each caller adding a new try/catch.
 */
import { detectSystemLocale, translate, type TranslationKey } from '../../locales';

import { retryDiskFullProbe, revealDbFolder } from '../ipc/runtime';
import { extractDiskFullDetails } from './diskFull.logic';
import { reportClientError } from '../errors/errorLogging';
import { toast } from '../notifications/toast';

// Module-level translator: mirrors the non-React call site pattern used
// in `sync/runtime.ts`. The disk-full toast is surfaced from the
// query/mutation cache's `onError` hook — outside the React tree — so
// we can't use the `useI18n()` hook. `translate()` falls back to
// English when the locale's table hasn't been loaded yet.
const t = (key: TranslationKey): string => translate(detectSystemLocale(), key);

// Simple window-level guard so the toast doesn't stack on retry storms.
// Independent of the toast dedup window so the cooldown can be longer
// (full disk is a macro-state, not a per-tick alert). 10 s matches the
// toast duration below.
const DISK_FULL_TOAST_COOLDOWN_MS = 10_000;
let lastDiskFullToastAt = 0;

/**
 * Surface the "Storage is full" toast for an IPC error that was
 * classified as DiskFull. Safe to call unconditionally — non-disk-full
 * errors are ignored. Returns `true` if the toast was (or would have
 * been) surfaced, so the caller can suppress their own generic error
 * toast to avoid double-banner.
 */
export function handleDiskFullIpcError(error: unknown): boolean {
  const details = extractDiskFullDetails(error);
  if (details === null) return false;

  const now = Date.now();
  if (now - lastDiskFullToastAt < DISK_FULL_TOAST_COOLDOWN_MS) {
    return true;
  }
  lastDiskFullToastAt = now;

  // A DiskFull error is durable enough to deserve the info-style
  // actionable toast: two affordances in one banner.
  //
  // Action ordering: "Try again" is primary (most common user intent —
  // they've cleared space and want to continue). "Open storage" falls
  // through via the priority-toast action slot; the toast system only
  // supports one action button, so we chain them: the primary action
  // "Try again" runs the probe, and if it fails the user still sees
  // the next toast which routes to "Open storage".
  toast.info(
    t('error.diskFull.title'),
    {
      label: t('common.retry'),
      onClick: () => {
        retryDiskFullProbe()
          .then((cleared) => {
            if (cleared) {
              toast.success(t('error.diskFull.cleared'));
            } else {
              // Still full — offer the reveal path instead.
              toast.info(
                t('error.diskFull.stillFull'),
                {
                  label: t('error.diskFull.openStorage'),
                  onClick: () => {
                    revealDbFolder().catch((err) =>
                      reportClientError(
                        'diskFull.revealDbFolder',
                        'Failed to reveal DB folder',
                        err,
                      ),
                    );
                  },
                },
                'disk_full',
                { durationMs: DISK_FULL_TOAST_COOLDOWN_MS, priority: true },
              );
            }
          })
          .catch((err) =>
            reportClientError(
              'diskFull.retryProbe',
              'Failed to probe DiskFull breaker',
              err,
            ),
          );
      },
    },
    'disk_full',
    { durationMs: DISK_FULL_TOAST_COOLDOWN_MS, priority: true },
  );

  reportClientError(
    'diskFull.detected',
    'Local storage is full',
    error,
    details,
    'warn',
  );
  return true;
}

