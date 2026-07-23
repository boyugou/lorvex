import { useCallback, useMemo } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { getPreference, setPreference } from '@/lib/ipc/settings';
import type { PreferenceKey } from '../preferences/keys';
import type { PreferenceValueOf } from '../preferences/values';
import { reportClientError } from '../errors/errorLogging';
import { useI18n } from '../i18n';
import { toast } from '../notifications/toast';
import { invalidatePreferenceQueries } from './queryKeys';
import { preferenceQueryKey } from './preferenceCache';
import {
  assertValidPreferenceWriteValue,
  buildPreferenceQueryConfig,
  encodePreferenceCacheValue,
} from './usePreference.logic';

/**
 * A hook for reading and writing a single preference key with TanStack Query caching.
 *
 * Encapsulates the repeated pattern:
 *   1. useQuery(preferenceQueryKey(key)) to load the raw value
 *   2. Parse/transform the raw string into a typed value
 *   3. setPreference(key, value) + invalidate on write
 *
 * @param key       The preference key in the database.
 * @param parse     A function to transform the raw string | null into the desired type.
 * @param options   Optional staleTime override (default 30_000ms).
 *
 * @example
 * ```ts
 * const { value, set, isLoading } = usePreference(
 *   PREF_AI_BRIEFING_ENABLED,
 *   (raw) => raw !== 'false',
 * );
 * ```
 */
export function usePreference<K extends PreferenceKey, T>(
  key: K,
  parse: (raw: string | null) => T,
  options?: { staleTime?: number; enabled?: boolean; refetchInterval?: number | false },
): {
  /** The parsed preference value (uses parse(null) while loading). */
  value: T;
  /** Persist a new value. Automatically invalidates the query cache. */
  set: (value: PreferenceValueOf<K>) => Promise<void>;
  /** True while the initial load is in progress. */
  isLoading: boolean;
  /** True while a set() call is in flight. */
  isSaving: boolean;
  /** Query error from the underlying preference read. */
  error: unknown | null;
} {
  const qc = useQueryClient();
  const { t } = useI18n();

  const preferenceQueryConfigArgs: {
    key: string;
    staleTime?: number;
    enabled?: boolean;
  } = { key };
  if (options?.staleTime !== undefined) {
    preferenceQueryConfigArgs.staleTime = options.staleTime;
  }
  if (options?.enabled !== undefined) {
    preferenceQueryConfigArgs.enabled = options.enabled;
  }

  const queryOptions: Parameters<typeof useQuery>[0] = {
    ...buildPreferenceQueryConfig(preferenceQueryConfigArgs),
    queryFn: ({ signal }) => getPreference(key, signal),
  };
  if (options?.refetchInterval !== undefined) {
    queryOptions.refetchInterval = options.refetchInterval;
  }

  const { data: raw, error, isLoading } = useQuery(queryOptions);

  const value = useMemo(
    () => parse(typeof raw === 'string' ? raw : null),
    [parse, raw],
  );

  // Optimistic update + rollback on failure:
  //   - onMutate writes the optimistic raw value into the query
  //     cache so the UI flips immediately,
  //   - onError restores the snapshot, surfaces a toast, and reports
  //     to the diagnostics log,
  //   - onSettled re-invalidates so any server-side coercion lands.
  // A bare await-then-invalidate would leave the toggle in its
  // prior visual state until the server confirmed and would either
  // swallow IPC failures or surface them as unstyled rejections.
  const setMutation = useMutation({
    mutationFn: async (nextValue: PreferenceValueOf<K>) => {
      assertValidPreferenceWriteValue(key, nextValue);
      await setPreference(key, nextValue);
    },
    onMutate: async (nextValue: PreferenceValueOf<K>) => {
      const queryKey = preferenceQueryKey(key);
      await qc.cancelQueries({ queryKey });
      const prev = qc.getQueryData<string | null>(queryKey);
      // Mirror the wire format the query produces: a string blob or
      // null. `setPreference` JSON-encodes every non-null value before
      // sending it over IPC, including string preferences.
      qc.setQueryData<string | null>(queryKey, encodePreferenceCacheValue(nextValue));
      return { prev };
    },
    onError: (err, _vars, context) => {
      if (context && 'prev' in context) {
        qc.setQueryData(preferenceQueryKey(key), context.prev);
      }
      reportClientError(
        'preference.set',
        `Failed to set preference ${key}`,
        err,
      );
      toast.error(t('settings.saveFailed'));
    },
    onSettled: () => {
      invalidatePreferenceQueries(qc, { key });
    },
  });

  // The mutation's `onError` already surfaces the failure (toast + log).
  // Re-throwing from `set()` would force every caller to re-catch the
  // same error to avoid an unhandledrejection. Resolve to `undefined`
  // on either path so the hook is the single point of error handling.
  const set = useCallback(
    (nextValue: PreferenceValueOf<K>) =>
      setMutation.mutateAsync(nextValue).then(
        () => undefined,
        () => undefined,
      ),
    [setMutation],
  );

  return { value, set, isLoading, isSaving: setMutation.isPending, error };
}
