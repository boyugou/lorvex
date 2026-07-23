import { QueryClient } from '@tanstack/react-query';
import { describe, expect, it } from 'vitest';

import type { TodayBootstrap } from '@/lib/ipc/bootstrap';
import {
  PREF_DASHBOARD_LAYOUT,
  PREF_SIDEBAR_HIDE_EMPTY_LISTS,
  PREF_SIDEBAR_VISIBLE_MODULES,
  PREF_TIMEZONE,
} from '../preferences/keys';

import {
  BOOTSTRAP_SEEDED_PREFERENCE_KEYS,
  BOOTSTRAP_SEEDED_QUERY_HEADS,
  seedTodayBootstrapQueryData,
} from './bootstrapCache';
import { getPreferenceQueryData, preferenceQueryRootKey } from './preferenceCache';
import { QK } from './queryKeys';

function bootstrapFixture(): TodayBootstrap {
  return {
    overview: { stats: { total: 3 } },
    lists: [{ id: 'inbox', name: 'Inbox', task_count: 2 }],
    preferences: {
      [PREF_TIMEZONE]: '"America/New_York"',
      [PREF_SIDEBAR_VISIBLE_MODULES]: '["today","lists"]',
      [PREF_DASHBOARD_LAYOUT]: '{"sections":[]}',
    },
    timezone: 'America/New_York',
    today_ymd: '2026-04-30',
    setup_status: { is_setup_complete: true },
    current_focus: null,
  } as unknown as TodayBootstrap;
}

describe('today bootstrap cache seeding', () => {
  it('documents the exact root query heads seeded by the main-window bootstrap', () => {
    expect(BOOTSTRAP_SEEDED_QUERY_HEADS).toEqual([
      QK.overview,
      QK.lists,
      QK.currentFocus,
      QK.setupStatus,
    ]);
  });

  it('documents the exact preference keys seeded by the main-window bootstrap', () => {
    expect(BOOTSTRAP_SEEDED_PREFERENCE_KEYS).toEqual([
      PREF_TIMEZONE,
      PREF_SIDEBAR_VISIBLE_MODULES,
      PREF_SIDEBAR_HIDE_EMPTY_LISTS,
      PREF_DASHBOARD_LAYOUT,
    ]);
  });

  it('seeds bootstrap leaves and normalizes absent preferences to null', () => {
    const queryClient = new QueryClient();
    const bootstrap = bootstrapFixture();

    seedTodayBootstrapQueryData(queryClient, bootstrap, 12_345);

    expect(queryClient.getQueryData([QK.overview])).toBe(bootstrap.overview);
    expect(queryClient.getQueryData([QK.lists])).toBe(bootstrap.lists);
    expect(queryClient.getQueryData([QK.currentFocus])).toBeNull();
    expect(queryClient.getQueryData([QK.setupStatus])).toBe(bootstrap.setup_status);
    expect(getPreferenceQueryData(queryClient, PREF_TIMEZONE)).toBe('"America/New_York"');
    expect(getPreferenceQueryData(queryClient, PREF_SIDEBAR_VISIBLE_MODULES)).toBe('["today","lists"]');
    expect(getPreferenceQueryData(queryClient, PREF_SIDEBAR_HIDE_EMPTY_LISTS)).toBeNull();
    expect(getPreferenceQueryData(queryClient, PREF_DASHBOARD_LAYOUT)).toBe('{"sections":[]}');
  });

  it('assigns the bootstrap stale window to every seeded query family', () => {
    const queryClient = new QueryClient();

    seedTodayBootstrapQueryData(queryClient, bootstrapFixture(), 12_345);

    for (const head of BOOTSTRAP_SEEDED_QUERY_HEADS) {
      expect(queryClient.getQueryDefaults([head])?.staleTime).toBe(12_345);
    }
    expect(queryClient.getQueryDefaults(preferenceQueryRootKey())?.staleTime).toBe(12_345);
  });
});
