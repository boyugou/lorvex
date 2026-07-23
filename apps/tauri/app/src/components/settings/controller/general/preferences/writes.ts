import { setDeviceState, setPreference } from '@/lib/ipc/settings';
import {
  DEV_DESKTOP_CLOSE_ACTION,
  PREF_MORNING_BRIEFING_TIME,
  PREF_SIDEBAR_VISIBLE_MODULES,
  PREF_TIMEZONE,
  PREF_WEEKLY_REVIEW_DAY,
  PREF_WEEKLY_REVIEW_TIME,
  PREF_WORKING_HOURS,
} from '@/lib/preferences/keys';
import { invalidatePreferenceQueries } from '@/lib/query/queryKeys';
import { setPreferenceQueryData } from '@/lib/query/preferenceCache';
import {
  serializeSidebarModuleConfig,
  sidebarModuleConfigPreferenceValue,
} from '@/lib/sidebarModules';

import type {
  NormalizedAdvancedPreferences,
  SaveAdvancedPreferencesArgs,
  SaveSidebarModulesPreferenceArgs,
} from './types';

export async function saveWorkingHoursPreference(args: {
  queryClient: SaveSidebarModulesPreferenceArgs['queryClient'];
  workingHoursStart: string;
  workingHoursEnd: string;
}) {
  await setPreference(PREF_WORKING_HOURS, {
    start: args.workingHoursStart,
    end: args.workingHoursEnd,
  });
  invalidatePreferenceQueries(args.queryClient);
}

export async function saveAdvancedPreferences(
  args: SaveAdvancedPreferencesArgs,
): Promise<NormalizedAdvancedPreferences> {
  if (
    args.runtimeClass === 'desktop' &&
    args.trayPresentationKind !== 'none' &&
    args.desktopCloseActionDirty &&
    args.desktopCloseAction === 'hide_to_tray'
  ) {
    await args.ensureTrayIconVisibleForHideToTray();
  }

  const writes: Promise<unknown>[] = [];
  const lastPersisted = args.lastPersistedAdvanced;
  if (!lastPersisted || lastPersisted.timezone !== args.timezone) {
    writes.push(setPreference(PREF_TIMEZONE, args.timezone));
  }
  if (!lastPersisted || lastPersisted.weeklyReviewDay !== args.weeklyReviewDay) {
    writes.push(setPreference(PREF_WEEKLY_REVIEW_DAY, args.weeklyReviewDay));
  }
  if (!lastPersisted || lastPersisted.weeklyReviewTime !== args.weeklyReviewTime) {
    writes.push(setPreference(PREF_WEEKLY_REVIEW_TIME, args.weeklyReviewTime));
  }
  if (!lastPersisted || lastPersisted.morningBriefingTime !== args.morningBriefingTime) {
    writes.push(setPreference(PREF_MORNING_BRIEFING_TIME, args.morningBriefingTime));
  }

  if (args.runtimeClass === 'desktop' && args.desktopCloseActionDirty) {
    writes.push(setDeviceState(DEV_DESKTOP_CLOSE_ACTION, args.desktopCloseAction));
  }

  if (writes.length === 0) {
    invalidatePreferenceQueries(args.queryClient);
    return advancedSnapshotFromArgs(args);
  }

  const results = await Promise.allSettled(writes);
  const firstFailure = results.find(
    (result): result is PromiseRejectedResult => result.status === 'rejected',
  );
  if (firstFailure) {
    throw firstFailure.reason;
  }

  const persisted = advancedSnapshotFromArgs(args);

  invalidatePreferenceQueries(args.queryClient);
  return persisted;
}

function advancedSnapshotFromArgs(
  args: NormalizedAdvancedPreferences,
): NormalizedAdvancedPreferences {
  return {
    timezone: args.timezone,
    weeklyReviewDay: args.weeklyReviewDay,
    weeklyReviewTime: args.weeklyReviewTime,
    morningBriefingTime: args.morningBriefingTime,
  };
}

export async function saveSidebarModulesPreference({
  queryClient,
  config,
}: SaveSidebarModulesPreferenceArgs) {
  const serialized = serializeSidebarModuleConfig(config);
  setPreferenceQueryData(queryClient, PREF_SIDEBAR_VISIBLE_MODULES, serialized);
  await setPreference(PREF_SIDEBAR_VISIBLE_MODULES, sidebarModuleConfigPreferenceValue(config));
  invalidatePreferenceQueries(queryClient, { key: PREF_SIDEBAR_VISIBLE_MODULES });
}
