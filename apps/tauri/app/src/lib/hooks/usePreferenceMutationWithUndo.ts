/**
 * "undo: preference writes are silent and irreversible".
 *
 * This hook wraps `setPreference` with a success toast + Undo button,
 * mirroring the `lifecycleUndoRedo.ts` pattern used for task
 * complete/cancel but simpler: preferences have no backend undo token,
 * so the previous value is snapshotted in the React closure and
 * replayed through the same `setPreference` IPC when the user clicks
 * Undo. The undo window follows the toast's visible lifetime
 * (`ACTIONABLE_SUCCESS_TOAST_DURATION_MS` = 4.5s, intentionally shorter
 * than the backend undo-token hold so the affordance disappears at the
 * same visual cadence as task-complete undo).
 *
 * Semantic guards ( scope):
 *   - Validation/write errors DO NOT show a success toast — `setPreference`
 *     will throw and the caller's normal error path takes over. Only
 *     successful writes enqueue the Undo toast.
 *   - Equal previous + next values are a no-op: we never fire a "set to X"
 *     toast when the value didn't actually change (keeps rapid toggles
 *     of the same selected option silent).
 * - No token persistence: unlike task-complete undo, preference
 *     undo does NOT survive page reload. The in-flight closure captures
 *     the previous value; the Undo button writes it back through the
 *     normal IPC if clicked before the toast auto-dismisses.
 */
import { useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { useI18n, type TranslationKey } from '../i18n';
import { getPreference, setPreference } from '@/lib/ipc/settings';
import type { PreferenceKey } from '../preferences/keys';
import type { PreferenceValueOf } from '../preferences/values';
import { invalidatePreferenceQueries } from '../query/queryKeys';
import { toast } from '../notifications/toast';
import { reportClientError } from '../errors/errorLogging';
import { parseJsonValueOrNull } from '../security/jsonParse';

type Translator = (key: TranslationKey) => string;

interface PreferenceMutationOptions<K extends PreferenceKey = PreferenceKey> {
  /**
   * Key this mutation writes to. Snapshotting reads through
   * `getPreference(key)` before the forward write so the Undo action
   * replays the literal stored string.
   */
  key: K;
  /**
   * Optional rendered-message override. Defaults to the translated
   * `settings.preferenceSaved`. Callers with category-specific copy
   * ("Theme set to Dark") supply an already-translated string here.
   */
  successMessage?: string;
  /**
   * Translation key for the failure toast that fires if the Undo write
   * itself fails. Defaults to `common.error`.
   */
  undoErrorKey?: TranslationKey;
  /**
   * Error-logging key prefix; the hook suffixes `.forward` / `.undo`
   * so both legs report under distinct keys.
   */
  errorKeyPrefix?: string;
  /**
   * Optional local-state rollback hook. Use this when the caller applies
   * an optimistic UI state before persistence; Undo must then update both
   * the stored preference and the in-memory view state.
   */
  onUndoValue?: (previousValue: unknown) => void;
}

interface PreferenceMutationResult<K extends PreferenceKey = PreferenceKey> {
  /**
   * Invoke the preference write. Snapshots the previous raw string via
   * `getPreference`, writes `nextValue`, invalidates caches, and fires
   * the success + Undo toast. Rejects (and skips the toast) if the
   * forward write itself fails.
   */
  run: (nextValue: PreferenceValueOf<K>) => Promise<void>;
}

export async function performPreferenceWriteWithSnapshot(
  key: string,
  previousRaw: string | null,
  nextValue: unknown,
  writer: (key: string, value: unknown) => Promise<void>,
): Promise<{ applied: boolean; undo: () => Promise<void> }> {
  const nextRaw = JSON.stringify(nextValue);
  if (previousRaw === nextRaw) {
    return {
      applied: false,
      undo: async () => {},
    };
  }

  await writer(key, nextValue);
  return {
    applied: true,
    undo: async () => {
      await writer(key, previousRaw === null ? null : parseJsonValueOrNull(previousRaw));
    },
  };
}

/**
 * Wrap a `setPreference` write with a success toast + Undo affordance.
 * The returned `run` function is stable across renders (`useCallback`).
 *
 * Usage:
 *   const { run } = usePreferenceMutationWithUndo({ key: PREF_THEME });
 *   await run('dark');
 *   // → toast: "Preference saved" with Undo button that restores previous theme.
 */
export function usePreferenceMutationWithUndo<K extends PreferenceKey>(
  options: PreferenceMutationOptions<K>,
): PreferenceMutationResult<K> {
  const { t } = useI18n();
  const qc = useQueryClient();

  const run = useCallback(
    async (nextValue: PreferenceValueOf<K>): Promise<void> => {
      // Snapshot BEFORE the forward write so validation failures leave
      // the previous value intact and the Undo closure has a source of
      // truth to roll back to. We capture the raw string (what the
      // backend actually stored) rather than the parsed value to avoid
      // double-serialization ambiguity on replay.
      const previousRaw = await getPreference(options.key);
      const nextRaw = JSON.stringify(nextValue);
      if (previousRaw === nextRaw) {
        // No-op — same value already persisted. Skip the toast to avoid
        // noise on idempotent writes (rapid toggles of an already-selected
        // option).
        return;
      }

      await setPreference(options.key, nextValue);
      invalidatePreferenceQueries(qc, { key: options.key });

      const successMessage = options.successMessage ?? t('settings.preferenceSaved');
      toast.success(
        successMessage,
        {
          label: t('common.undo'),
          onClick: () => {
            const undoArgs: UndoArgs = {
              key: options.key,
              previousRaw,
              qc,
              t,
              errorKeyPrefix: options.errorKeyPrefix ?? 'settings.preference',
              undoErrorKey: options.undoErrorKey ?? 'common.error',
            };
            if (options.onUndoValue) {
              undoArgs.onUndoValue = options.onUndoValue;
            }
            void runUndo({
              ...undoArgs,
            });
          },
        },
      );
    },
    [
      options.key,
      options.successMessage,
      options.undoErrorKey,
      options.errorKeyPrefix,
      options.onUndoValue,
      qc,
      t,
    ],
  );

  return { run };
}

interface UndoArgs {
  key: PreferenceKey;
  previousRaw: string | null;
  qc: ReturnType<typeof useQueryClient>;
  t: Translator;
  errorKeyPrefix: string;
  undoErrorKey: TranslationKey;
  onUndoValue?: (previousValue: unknown) => void;
}

async function runUndo(args: UndoArgs): Promise<void> {
  try {
    // Parse the snapshot back into the original JS value so it flows
    // through the normal `setPreference → JSON.stringify` path exactly
    // once. `previousRaw === null` means the preference was absent
    // before the forward write, which we restore by writing `null`
    // (the backend treats null the same as "never set" for readers
    // that supply a default, see parseBool / parseJson).
    const parsedPrev = args.previousRaw === null ? null : parseJsonValueOrNull(args.previousRaw);
    // Undo replays the snapshot the backend already stored, so the
    // parsed JSON necessarily matches the key's declared shape. The
    // `as PreferenceValueOf<typeof args.key>` cast bypasses the
    // structural check the typed `setPreference<K>` would otherwise
    // require — we cannot statically narrow `unknown` to the per-key
    // shape from a runtime string.
    await setPreference(args.key, parsedPrev as PreferenceValueOf<typeof args.key>);
    invalidatePreferenceQueries(args.qc, { key: args.key });
    args.onUndoValue?.(parsedPrev);
    toast.info(args.t('settings.preferenceReverted'));
  } catch (err) {
    reportClientError(`${args.errorKeyPrefix}.undo`, 'Failed to undo preference write', err);
    toast.errorWithDetail(err, args.t(args.undoErrorKey));
  }
}
