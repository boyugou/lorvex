import { QueryClient } from '@tanstack/react-query';
import { describe, expect, it } from 'vitest';

import { PREF_SIDEBAR_VISIBLE_MODULES } from '../preferences/keys';

import {
  getPreferenceQueryData,
  preferenceQueryKey,
  preferenceQueryRootKey,
  setPreferenceQueryData,
  setPreferenceQueryDefaults,
} from './preferenceCache';
import { invalidatePreferenceQueries, QK } from './queryKeys';
import { buildPreferenceQueryConfig } from './usePreference.logic';

describe('preference query cache helpers', () => {
  it('builds the canonical preference query key used by preference reads', () => {
    expect(preferenceQueryKey(PREF_SIDEBAR_VISIBLE_MODULES)).toEqual([
      QK.preference,
      PREF_SIDEBAR_VISIBLE_MODULES,
    ]);
    expect(buildPreferenceQueryConfig({ key: PREF_SIDEBAR_VISIBLE_MODULES }).queryKey)
      .toEqual(preferenceQueryKey(PREF_SIDEBAR_VISIBLE_MODULES));
  });

  it('preserves preference query option overrides', () => {
    expect(buildPreferenceQueryConfig({
      key: PREF_SIDEBAR_VISIBLE_MODULES,
      staleTime: 0,
      enabled: false,
    })).toEqual({
      queryKey: preferenceQueryKey(PREF_SIDEBAR_VISIBLE_MODULES),
      staleTime: 0,
      enabled: false,
    });
  });

  it('uses the same key for direct cache writes and reads', () => {
    const queryClient = new QueryClient();

    setPreferenceQueryData(queryClient, PREF_SIDEBAR_VISIBLE_MODULES, '["today","lists"]');

    expect(getPreferenceQueryData(queryClient, PREF_SIDEBAR_VISIBLE_MODULES))
      .toBe('["today","lists"]');
    expect(queryClient.getQueryData(buildPreferenceQueryConfig({
      key: PREF_SIDEBAR_VISIBLE_MODULES,
    }).queryKey)).toBe('["today","lists"]');
  });

  it('invalidates the same canonical preference cache key', () => {
    const queryClient = new QueryClient();
    setPreferenceQueryData(queryClient, PREF_SIDEBAR_VISIBLE_MODULES, '["today","lists"]');

    invalidatePreferenceQueries(queryClient, { key: PREF_SIDEBAR_VISIBLE_MODULES });

    expect(queryClient.getQueryState(preferenceQueryKey(PREF_SIDEBAR_VISIBLE_MODULES))?.isInvalidated)
      .toBe(true);
  });

  it('scopes preference defaults to the preference root key', () => {
    const queryClient = new QueryClient();

    setPreferenceQueryDefaults(queryClient, { staleTime: 12_345 });

    expect(preferenceQueryRootKey()).toEqual([QK.preference]);
    expect(queryClient.getQueryDefaults(preferenceQueryRootKey())?.staleTime).toBe(12_345);
  });
});
