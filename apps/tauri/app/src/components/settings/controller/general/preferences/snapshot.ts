import { getDeviceState, getPreference } from '@/lib/ipc/settings';
import {
  DEV_DESKTOP_CLOSE_ACTION,
  DEV_MENU_BAR_ICON_VISIBLE,
  PREF_MEMORY_LOCK_ENABLED,
  PREF_MORNING_BRIEFING_TIME,
  PREF_SIDEBAR_VISIBLE_MODULES,
  PREF_TIMEZONE,
  PREF_WEEKLY_REVIEW_DAY,
  PREF_WEEKLY_REVIEW_TIME,
  PREF_WORKING_HOURS,
} from '@/lib/preferences/keys';
import {
  DEFAULT_SIDEBAR_MODULE_CONFIG,
  cloneSidebarModuleConfig,
  parseSidebarModuleConfig,
} from '@/lib/sidebarModules';
import { parseBooleanPreference, parsePreferenceJson } from '@/lib/preferences/parser';
import { normalizeTimezonePreference } from '@/lib/dates/timezone';

import {
  DEFAULT_MORNING_BRIEFING_TIME,
  DEFAULT_WEEKLY_REVIEW_DAY,
  DEFAULT_WEEKLY_REVIEW_TIME,
  DEFAULT_WORKING_HOURS_END,
  DEFAULT_WORKING_HOURS_START,
  normalizeScheduledTimePreference,
  normalizeScheduledWeekdayPreference,
  normalizeWorkingHoursPreference,
} from './normalization';
import type { GeneralSettingsSnapshot, LoadGeneralSettingsSnapshotArgs } from './types';

export async function loadGeneralSettingsSnapshot({
  trayPresentationKind,
  systemTimezone,
}: LoadGeneralSettingsSnapshotArgs): Promise<GeneralSettingsSnapshot> {
  const snapshot: GeneralSettingsSnapshot = {
    workingHoursStart: DEFAULT_WORKING_HOURS_START,
    workingHoursEnd: DEFAULT_WORKING_HOURS_END,
    autostart: false,
    trayIconVisible: true,
    desktopCloseAction: trayPresentationKind === 'menu_bar' ? 'hide_to_tray' : 'quit',
    timezone: normalizeTimezonePreference(null, systemTimezone),
    weeklyReviewDay: DEFAULT_WEEKLY_REVIEW_DAY,
    weeklyReviewTime: DEFAULT_WEEKLY_REVIEW_TIME,
    morningBriefingTime: DEFAULT_MORNING_BRIEFING_TIME,
    sidebarModuleConfig: cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG),
    memoryLock: true,
  };

  const workingHoursRaw = await getPreference(PREF_WORKING_HOURS);
  const workingHours = normalizeWorkingHoursPreference(parsePreferenceJson(workingHoursRaw));
  snapshot.workingHoursStart = workingHours.start;
  snapshot.workingHoursEnd = workingHours.end;

  const timezoneRaw = await getPreference(PREF_TIMEZONE);
  snapshot.timezone = normalizeTimezonePreference(
    parsePreferenceJson(timezoneRaw),
    systemTimezone,
  );

  const reviewDayRaw = await getPreference(PREF_WEEKLY_REVIEW_DAY);
  snapshot.weeklyReviewDay = normalizeScheduledWeekdayPreference(
    parsePreferenceJson(reviewDayRaw),
    DEFAULT_WEEKLY_REVIEW_DAY,
  );

  const reviewTimeRaw = await getPreference(PREF_WEEKLY_REVIEW_TIME);
  snapshot.weeklyReviewTime = normalizeScheduledTimePreference(
    parsePreferenceJson(reviewTimeRaw),
    DEFAULT_WEEKLY_REVIEW_TIME,
  );

  const morningTimeRaw = await getPreference(PREF_MORNING_BRIEFING_TIME);
  snapshot.morningBriefingTime = normalizeScheduledTimePreference(
    parsePreferenceJson(morningTimeRaw),
    DEFAULT_MORNING_BRIEFING_TIME,
  );

  const sidebarModulesRaw = await getPreference(PREF_SIDEBAR_VISIBLE_MODULES);
  snapshot.sidebarModuleConfig = parseSidebarModuleConfig(sidebarModulesRaw);

  const memoryLockRaw = await getPreference(PREF_MEMORY_LOCK_ENABLED);
  snapshot.memoryLock = parseBooleanPreference(memoryLockRaw, true);

  const trayIconRaw = await getDeviceState(DEV_MENU_BAR_ICON_VISIBLE);
  snapshot.trayIconVisible = parseBooleanPreference(trayIconRaw, true);

  const closeActionRaw = await getDeviceState(DEV_DESKTOP_CLOSE_ACTION);
  const closeAction = parsePreferenceJson(closeActionRaw);
  if (closeAction === 'quit' || closeAction === 'hide_to_tray') {
    snapshot.desktopCloseAction = closeAction;
  }

  return snapshot;
}
