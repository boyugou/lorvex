/**
 * per-category "Restore defaults" button. Reads canonical
 * defaults from `preferenceDefaults.ts`, writes each through
 * `setPreference`, then fires a single success toast with an Undo
 * action that replays the pre-restore snapshot bundle.
 *
 * Intentionally distinct from the global `reset_preferences` IPC
 * (which is covered by the Danger Zone +). Category restores
 * touch only the keys the caller hands in — everything else stays as
 * the user configured it.
 */
import { useCallback, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { toUserFacingErrorMessage } from '@/lib/ipc/core.logic';
import { getPreferences, setPreference } from '@/lib/ipc/settings';
import { parseJsonValueOrNull } from '@/lib/security/jsonParse';
import type { PreferenceKey } from '@/lib/preferences/keys';
import { getPreferenceDefault } from '@/lib/preferences/defaults';
import type { PreferenceValueOf } from '@/lib/preferences/values';
import { invalidatePreferenceQueries } from '@/lib/query/queryKeys';
import { toast } from '@/lib/notifications/toast';

interface RestoreDefaultsButtonProps {
  /** Preference keys whose defaults should be written on click. Each
   *  key must have an entry in `PREFERENCE_DEFAULTS` — keys without one
   *  are skipped with a console warning. */
  keys: readonly PreferenceKey[];
  /** Category label for the success toast body (e.g. "Appearance
   *  defaults restored"). */
  categoryLabel: string;
  /** Optional override for the button's visible text. Defaults to
   *  `settings.restoreDefaults`. */
  label?: string;
  /** Optional error-log prefix, default `settings.restoreDefaults`. */
  errorKeyPrefix?: string;
  /** Optional extra className applied to the button. */
  className?: string;
}

export function RestoreDefaultsButton({
  keys,
  categoryLabel,
  label,
  errorKeyPrefix = 'settings.restoreDefaults',
  className,
}: RestoreDefaultsButtonProps) {
  const { t, format } = useI18n();
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);

  const handleClick = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    try {
      // Snapshot all requested keys, including keys that are absent
      // from `getPreferences`, so Undo can delete defaults that did
      // not exist before the restore.
      const snapshot = buildRestoreDefaultsSnapshot(keys, await getPreferences(keys));

      // Per-row write tracking: a single failing preference must not
      // discard the rest of the restore. `Promise.allSettled`
      // surfaces every failure individually so we can aggregate them
      // into one user-facing summary instead of swallowing all but the
      // first.
      const attempted: PreferenceKey[] = [];
      const writes: Array<Promise<void>> = [];
      for (const key of keys) {
        const next = getPreferenceDefault(key);
        if (next === undefined) {
          // a missing preference default is a code-path
          // bug (someone added a key to the registry but forgot the
          // default), not user input. Route through Diagnostics with
          // 'warn' severity so it shows up in Settings → Diagnostics
          // instead of getting buried in the console where users
          // don't look.
          reportClientError(
            'settings.restoreDefaults.missingDefault',
            'No default registered for preference key during restore',
            undefined,
            `key=${key}`,
            'warn',
          );
          continue;
        }
        attempted.push(key);
        // `next` comes from `PREFERENCE_DEFAULTS` (a structurally
        // typed bag keyed on `PreferenceKey`); per-key narrowing
        // would require a key-by-key dispatch table. The cast
        // preserves runtime behaviour — every default is just a JSON
        // payload that round-trips through `JSON.stringify`.
        writes.push(setPreference(key, next as PreferenceValueOf<typeof key>));
      }
      const settled = await Promise.allSettled(writes);
      // match `runUndo`'s map+filter+type-guard idiom (below)
      // instead of the prior forEach + push pattern. Same outcome, but
      // the two paths now share an idiom which is easier to keep in
      // lockstep when one of them grows new behaviour.
      const failures = settled
        .map((r, i) => (r.status === 'rejected' ? { key: attempted[i]!, error: r.reason } : null))
        .filter((e): e is { key: PreferenceKey; error: unknown } => e !== null);
      invalidatePreferenceQueries(qc);

      summarizeRestoreOutcome({
        failures,
        total: attempted.length,
        partialKey: 'settings.restoreDefaults.partialSuccess',
        totalKey: 'settings.restoreDefaults.allFailed',
        errorKeyPrefix: `${errorKeyPrefix}.partial`,
        successKey: 'settings.restoreDefaultsToast',
        successVars: { category: categoryLabel },
        undoAction: () => {
          void runUndo({ snapshot, qc, errorKeyPrefix, t, format });
        },
        t,
        format,
      });
    } catch (err) {
      reportClientError(`${errorKeyPrefix}.forward`, 'Failed to restore category defaults', err);
      toast.errorWithDetail(err, t('common.error'));
    } finally {
      setBusy(false);
    }
  }, [busy, keys, qc, t, format, categoryLabel, errorKeyPrefix]);

  return (
    /*
      #3790 — Intentionally distinct from `<Button variant="outline">`.
      The danger-zone "Restore defaults" affordance needs a `bg-surface-1/80`
      fill (rather than the outline variant's transparent background) so it
      reads as a recessed action against the settings panel — outline buttons
      blend into the surrounding form fields and bury the destructive intent.
      `hover:bg-surface-3` (one rung deeper than the outline variant's
      `hover:bg-surface-2`) gives the button visible depth on hover so the
      user pauses before clicking. Documenting the deviation here rather
      than promoting a `fill='subtle'` modifier on Button — primitives
      shouldn't accumulate exceptions for single-site recipes.
    */
    <button
      type="button"
      onClick={() => { void handleClick(); }}
      disabled={busy}
      className={
        className ??
        'text-xs px-2.5 py-1 rounded-r-control bg-surface-1/80 border border-surface-3 text-text-secondary hover:bg-surface-3 transition-colors focus-ring-soft disabled:opacity-50'
      }
    >
      {label ?? t('settings.restoreDefaults')}
    </button>
  );
}

interface UndoRestoreArgs {
  snapshot: RestoreDefaultsSnapshot;
  qc: ReturnType<typeof useQueryClient>;
  errorKeyPrefix: string;
  t: (key: TranslationKey) => string;
  format: (key: TranslationKey, vars?: Record<string, string>) => string;
}

interface RestoreDefaultsSnapshotEntry {
  key: PreferenceKey;
  raw: string | null;
}

type RestoreDefaultsSnapshot = RestoreDefaultsSnapshotEntry[];

export function buildRestoreDefaultsSnapshot(
  keys: readonly PreferenceKey[],
  presentValues: ReadonlyMap<string, string>,
): RestoreDefaultsSnapshot {
  return keys.map((key) => ({
    key,
    raw: presentValues.get(key) ?? null,
  }));
}

async function runUndo(args: UndoRestoreArgs): Promise<void> {
  // Mirror the forward path: per-row tracking with `Promise.allSettled`
  // so a single failing key doesn't drop the rest of the user's
  // restored values on the floor.
  //
  // Filter the snapshot through the same skip-default check the
  // forward path uses (`getPreferenceDefault(key) !== undefined`).
  // The forward path silently skips keys without a registered
  // default, so they were never written and cannot meaningfully be
  // "undone"; using `args.snapshot.length` as the denominator would
  // overstate it on the partial-success template ("Reverted N of
  // TOTAL preferences" where TOTAL included keys never touched).
  const attempted = args.snapshot.filter(({ key }) => getPreferenceDefault(key) !== undefined);
  const keys: PreferenceKey[] = [];
  const writes: Array<Promise<void>> = [];
  for (const { key, raw } of attempted) {
    const parsed = raw === null ? null : parseJsonValueOrNull(raw);
    keys.push(key);
    // Snapshot replay — `parsed` is whatever the backend already
    // stored, which by definition matches the key's declared shape.
    writes.push(setPreference(key, parsed as PreferenceValueOf<typeof key>));
  }
  const settled = await Promise.allSettled(writes);
  invalidatePreferenceQueries(args.qc);
  const failures = settled
    .map((r, i) => (r.status === 'rejected' ? { key: keys[i]!, error: r.reason } : null))
    .filter((e): e is { key: PreferenceKey; error: unknown } => e !== null);

  // branch on partial-vs-total like the forward path so undo
  // outcomes route to the same lanes as the original toast — total
  // failure stays on the error lane (red), partial failure flows
  // through the amber warning lane. Mixed undo means *some* of the
  // user's prior values came back; surfacing that as a hard red error
  // mis-represents what just happened.
  //
  // route through the shared
  // `summarizeRestoreOutcome` helper so the undo path inherits the same
  // template structure (`{success}/{total}/{firstFailedKey}/{detail}`),
  // the same `failures.length > 1 ? showErrors : retry` action lane, and
  // the same per-failure Diagnostics logging as the forward partial
  // branch — eliminating the prior "partial undo had no action" gap and
  // the "totalUndo overstates denominator" miscount.
  summarizeRestoreOutcome({
    failures,
    total: attempted.length,
    partialKey: 'settings.restoreDefaults.undoPartialSuccess',
    totalKey: 'settings.restoreDefaults.allFailed',
    errorKeyPrefix: `${args.errorKeyPrefix}.undo`,
    successKey: 'settings.preferenceReverted',
    successVars: undefined,
    // No further undo lane on undo itself — re-running undo would
    // restore the defaults again. Leave the partial branch with just
    // "Show all errors" (when >1 failed) or no action (when 1 failed).
    undoAction: undefined,
    t: args.t,
    format: args.format,
  });
}

interface SummarizeRestoreOutcomeArgs {
  failures: Array<{ key: PreferenceKey; error: unknown }>;
  total: number;
  /** i18n key for the "partial success" warning template. Receives
   *  `{success}/{total}/{firstFailedKey}/{detail}` placeholders. */
  partialKey: TranslationKey;
  /** i18n key for the "total failure" error template. Receives
   *  `{count}/{firstFailedKey}/{detail}` placeholders. */
  totalKey: TranslationKey;
  /** i18n key for the all-success toast (info or success lane). */
  successKey: TranslationKey;
  /** Optional vars for the success template (e.g. `{ category }`). */
  successVars: Record<string, string> | undefined;
  /** Diagnostics report key for each individual failure. */
  errorKeyPrefix: string;
  /** Optional Undo action attached to the success / single-row partial
   *  toast. When undefined (e.g. running on the undo path itself) the
   *  partial branch falls back to "Show all errors" only when >1 row
   *  failed and shows no action when exactly one failed. */
  undoAction: (() => void) | undefined;
  t: (key: TranslationKey) => string;
  format: (key: TranslationKey, vars?: Record<string, string>) => string;
}

/**
 * shared dispatch for the restore-defaults outcome triple
 * (success / partial / total). Both forward and undo paths gather a
 * `failures` array off `Promise.allSettled` and then have to fan out to
 * the same three toast lanes with the same per-failure Diagnostics
 * logging and the same `failures.length > 1 ? showErrors : (undo|none)`
 * action policy on the partial branch. Centralising the dispatch
 * keeps the two paths in lockstep so the undo partial path carries
 * the same action affordance as the forward partial path.
 */
function summarizeRestoreOutcome(args: SummarizeRestoreOutcomeArgs): void {
  const { failures, total, t, format } = args;

  if (failures.length === 0) {
    const message = args.successVars
      ? format(args.successKey, args.successVars)
      : t(args.successKey);
    if (args.undoAction) {
      toast.success(message, { label: t('common.undo'), onClick: args.undoAction });
    } else {
      // Undo-of-undo is a no-op the user wouldn't expect, so the undo
      // path passes `undoAction: undefined` and lands here as a plain
      // info toast (no action button).
      toast.info(message);
    }
    return;
  }

  // Log every failure to Diagnostics — the toast only names the first
  // one, but ops/support still need the complete picture when triaging.
  // Each row gets its own structured log entry keyed by preference name.
  for (const { key, error } of failures) {
    reportClientError(args.errorKeyPrefix, 'Failed to restore preference default', error, `key=${key}`);
  }

  const first = failures[0]!;
  const detail = toUserFacingErrorMessage(first.error, t('common.error'));

  if (failures.length === total) {
    // Total failure — surface as an error toast with the first
    // underlying detail so the user gets actionable context.
    toast.error(format(args.totalKey, {
      count: String(failures.length),
      firstFailedKey: first.key,
      detail,
    }));
    return;
  }

  // Partial path: amber-warning summary ( doctrine —
  // partial = warning, total = error). When more than one row failed
  // we offer "Show all errors" so the user can read each failure; when
  // only one failed we keep Undo (forward path) or no action (undo
  // path) so the user can roll the partial restore back.
  const successCount = total - failures.length;
  const summary = format(args.partialKey, {
    success: String(successCount),
    total: String(total),
    firstFailedKey: first.key,
    detail,
  });
  const action: { label: string; onClick: () => void } | undefined = failures.length > 1
    ? {
        label: t('settings.restoreDefaults.showErrors'),
        onClick: () => {
          // Show every failure in follow-up error toasts. Capped at
          // five so we don't drown the toast surface; the rest remain
          // in Diagnostics.
          const visible = failures.slice(0, 5);
          for (const { key, error } of visible) {
            toast.error(`${key}: ${toUserFacingErrorMessage(error, t('common.error'))}`);
          }
        },
      }
    : args.undoAction
      ? { label: t('common.undo'), onClick: args.undoAction }
      : undefined;
  // route partial-success outcomes through the amber warning
  // lane (parity with's useDashboardSectionActions migration).
  toast.warning(summary, action);
}
