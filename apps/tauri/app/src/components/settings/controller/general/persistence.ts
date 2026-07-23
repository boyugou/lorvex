import { useCallback, useRef, type Dispatch, type SetStateAction } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { appendClientErrorLog } from '@/lib/errors/errorLogging';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import type { RuntimeClass, TrayPresentationKind } from '@/lib/platform/platform';
import type { DesktopCloseActionPreference } from '@/components/settings/general/types';
import {
  normalizeAdvancedPreferenceDraft,
  saveAdvancedPreferences,
  saveWorkingHoursPreference,
  type NormalizedAdvancedPreferences,
} from './preferences';
import { ensureTrayIconVisibleForHideToTray } from './runtime';

interface UseGeneralSettingsPersistenceArgs {
  runtimeClass: RuntimeClass;
  trayPresentationKind: TrayPresentationKind;
  workingHoursStart: string;
  workingHoursEnd: string;
  timezone: string;
  systemTimezone: string;
  weeklyReviewDay: string;
  weeklyReviewTime: string;
  morningBriefingTime: string;
  desktopCloseActionDirty: boolean;
  desktopCloseAction: DesktopCloseActionPreference;
  trayIconVisible: boolean;
  setDesktopCloseActionDirty: Dispatch<SetStateAction<boolean>>;
  setTimezone: Dispatch<SetStateAction<string>>;
  setWeeklyReviewDay: Dispatch<SetStateAction<string>>;
  setWeeklyReviewTime: Dispatch<SetStateAction<string>>;
  setMorningBriefingTime: Dispatch<SetStateAction<string>>;
  setTrayIconVisible: Dispatch<SetStateAction<boolean>>;
}

export function useGeneralSettingsPersistence({
  desktopCloseAction,
  desktopCloseActionDirty,
  runtimeClass,
  morningBriefingTime,
  setDesktopCloseActionDirty,
  setMorningBriefingTime,
  setTimezone,
  setTrayIconVisible,
  setWeeklyReviewDay,
  setWeeklyReviewTime,
  systemTimezone,
  timezone,
  trayPresentationKind,
  trayIconVisible,
  weeklyReviewDay,
  weeklyReviewTime,
  workingHoursEnd,
  workingHoursStart,
}: UseGeneralSettingsPersistenceArgs) {
  const qc = useQueryClient();
  const lastPersistedAdvancedRef = useRef<NormalizedAdvancedPreferences | null>(null);

  const logSettingsError = useCallback((source: string, message: string, error: unknown) => {
    const details = toIpcErrorMessage(error);
    void appendClientErrorLog(source, message, error, details, 'error');
  }, []);

  const persistWorkingHours = useCallback(async () => {
    await saveWorkingHoursPreference({
      queryClient: qc,
      workingHoursStart,
      workingHoursEnd,
    });
  }, [qc, workingHoursEnd, workingHoursStart]);

  const persistAdvanced = useCallback(async () => {
    const normalized = normalizeAdvancedPreferenceDraft({
      timezone,
      systemTimezone,
      weeklyReviewDay,
      weeklyReviewTime,
      morningBriefingTime,
    });

    if (normalized.timezone !== timezone) {
      setTimezone(normalized.timezone);
    }
    if (normalized.weeklyReviewDay !== weeklyReviewDay) {
      setWeeklyReviewDay(normalized.weeklyReviewDay);
    }
    if (normalized.weeklyReviewTime !== weeklyReviewTime) {
      setWeeklyReviewTime(normalized.weeklyReviewTime);
    }
    if (normalized.morningBriefingTime !== morningBriefingTime) {
      setMorningBriefingTime(normalized.morningBriefingTime);
    }

    const persistedAdvanced = await saveAdvancedPreferences({
      queryClient: qc,
      lastPersistedAdvanced: lastPersistedAdvancedRef.current,
      runtimeClass,
      trayPresentationKind,
      desktopCloseActionDirty,
      desktopCloseAction,
      ensureTrayIconVisibleForHideToTray: () => ensureTrayIconVisibleForHideToTray({
        trayPresentationKind,
        trayIconVisible,
        logSettingsError,
        setTrayIconVisible,
      }),
      timezone: normalized.timezone,
      weeklyReviewDay: normalized.weeklyReviewDay,
      weeklyReviewTime: normalized.weeklyReviewTime,
      morningBriefingTime: normalized.morningBriefingTime,
    });
    lastPersistedAdvancedRef.current = persistedAdvanced;

    if (desktopCloseActionDirty) {
      setDesktopCloseActionDirty(false);
    }
  }, [
    desktopCloseAction,
    desktopCloseActionDirty,
    logSettingsError,
    morningBriefingTime,
    qc,
    runtimeClass,
    setDesktopCloseActionDirty,
    setMorningBriefingTime,
    setTimezone,
    setTrayIconVisible,
    setWeeklyReviewDay,
    setWeeklyReviewTime,
    systemTimezone,
    timezone,
    trayPresentationKind,
    trayIconVisible,
    weeklyReviewDay,
    weeklyReviewTime,
  ]);

  const recordAdvancedPreferencesBaseline = useCallback((snapshot: NormalizedAdvancedPreferences) => {
    lastPersistedAdvancedRef.current = snapshot;
  }, []);

  return {
    logSettingsError,
    persistWorkingHours,
    persistAdvanced,
    recordAdvancedPreferencesBaseline,
  };
}
