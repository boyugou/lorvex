import { QueryClient } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { getPreferenceQueryData } from '@/lib/query/preferenceCache';
import {
  PREF_MORNING_BRIEFING_TIME,
  PREF_SIDEBAR_VISIBLE_MODULES,
  PREF_TIMEZONE,
  PREF_WEEKLY_REVIEW_DAY,
  PREF_WEEKLY_REVIEW_TIME,
} from '@/lib/preferences/keys';
import { serializeSidebarModuleConfig, type SidebarModuleConfig } from '@/lib/sidebarModules';

import { saveAdvancedPreferences, saveSidebarModulesPreference } from './writes';

const { setPreferenceMock } = vi.hoisted(() => ({
  setPreferenceMock: vi.fn(),
}));

vi.mock('@/lib/ipc/settings', () => ({
  setDeviceState: vi.fn(),
  setPreference: setPreferenceMock,
}));

describe('general settings preference writes', () => {
  beforeEach(() => {
    setPreferenceMock.mockReset();
    setPreferenceMock.mockResolvedValue(undefined);
  });

  it('optimistically writes sidebar modules through the canonical preference cache key', async () => {
    const queryClient = new QueryClient();
    const config: SidebarModuleConfig = {
      show: ['today', 'calendar'],
      more: ['memory'],
    };

    await saveSidebarModulesPreference({
      queryClient,
      config,
    });

    expect(getPreferenceQueryData(queryClient, PREF_SIDEBAR_VISIBLE_MODULES))
      .toBe(serializeSidebarModuleConfig(config));
    expect(setPreferenceMock).toHaveBeenCalledWith(PREF_SIDEBAR_VISIBLE_MODULES, {
      show: ['today', 'calendar'],
      more: ['memory'],
    });
  });

  it('does not suppress advanced preference writes from previous module calls', async () => {
    const queryClient = new QueryClient();
    const args = {
      queryClient,
      lastPersistedAdvanced: null,
      runtimeClass: 'unknown' as const,
      trayPresentationKind: 'none' as const,
      desktopCloseActionDirty: false,
      desktopCloseAction: 'quit' as const,
      ensureTrayIconVisibleForHideToTray: vi.fn(),
      timezone: 'America/New_York',
      weeklyReviewDay: 'monday',
      weeklyReviewTime: '09:00',
      morningBriefingTime: '08:30',
    };

    await saveAdvancedPreferences(args);
    setPreferenceMock.mockClear();

    await saveAdvancedPreferences(args);

    expect(setPreferenceMock).toHaveBeenCalledTimes(4);
    expect(setPreferenceMock).toHaveBeenCalledWith(PREF_TIMEZONE, 'America/New_York');
    expect(setPreferenceMock).toHaveBeenCalledWith(PREF_WEEKLY_REVIEW_DAY, 'monday');
    expect(setPreferenceMock).toHaveBeenCalledWith(PREF_WEEKLY_REVIEW_TIME, '09:00');
    expect(setPreferenceMock).toHaveBeenCalledWith(PREF_MORNING_BRIEFING_TIME, '08:30');
  });

  it('uses the caller-owned advanced baseline to emit only changed preferences', async () => {
    const queryClient = new QueryClient();

    const persisted = await saveAdvancedPreferences({
      queryClient,
      lastPersistedAdvanced: {
        timezone: 'America/New_York',
        weeklyReviewDay: 'monday',
        weeklyReviewTime: '09:00',
        morningBriefingTime: '08:30',
      },
      runtimeClass: 'unknown',
      trayPresentationKind: 'none',
      desktopCloseActionDirty: false,
      desktopCloseAction: 'quit',
      ensureTrayIconVisibleForHideToTray: vi.fn(),
      timezone: 'America/New_York',
      weeklyReviewDay: 'tuesday',
      weeklyReviewTime: '09:00',
      morningBriefingTime: '08:30',
    });

    expect(setPreferenceMock).toHaveBeenCalledTimes(1);
    expect(setPreferenceMock).toHaveBeenCalledWith(PREF_WEEKLY_REVIEW_DAY, 'tuesday');
    expect(persisted).toEqual({
      timezone: 'America/New_York',
      weeklyReviewDay: 'tuesday',
      weeklyReviewTime: '09:00',
      morningBriefingTime: '08:30',
    });
  });
});
