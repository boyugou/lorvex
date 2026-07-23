import { useEffect, type Dispatch, type RefObject, type SetStateAction } from 'react';

import type { RuntimeClass, TrayPresentationKind } from '@/lib/platform/platform';
import type { DesktopCloseActionPreference } from '@/components/settings/general/types';
import type { SidebarModuleConfig } from '@/lib/sidebarModules';
import { loadGeneralSettingsSnapshot } from './preferences';
import type { NormalizedAdvancedPreferences } from './preferences';
import { loadAutostartPreference } from './runtime';

interface UseGeneralSettingsBootstrapArgs {
  runtimeClass: RuntimeClass;
  trayPresentationKind: TrayPresentationKind;
  logSettingsError: (source: string, message: string, error: unknown) => void;
  recordAdvancedPreferencesBaseline: (snapshot: NormalizedAdvancedPreferences) => void;
  setAutostart: Dispatch<SetStateAction<boolean>>;
  setDesktopCloseAction: Dispatch<SetStateAction<DesktopCloseActionPreference>>;

  setMemoryLock: Dispatch<SetStateAction<boolean>>;
  setMorningBriefingTime: Dispatch<SetStateAction<string>>;
  setReady: Dispatch<SetStateAction<boolean>>;
  setSidebarModuleConfig: Dispatch<SetStateAction<SidebarModuleConfig>>;
  setTimezone: Dispatch<SetStateAction<string>>;
  setTrayIconVisible: Dispatch<SetStateAction<boolean>>;
  setWeeklyReviewDay: Dispatch<SetStateAction<string>>;
  setWeeklyReviewTime: Dispatch<SetStateAction<string>>;
  setWorkingHoursEnd: Dispatch<SetStateAction<string>>;
  setWorkingHoursStart: Dispatch<SetStateAction<string>>;
  settingsLoadSeqRef: RefObject<number>;
  settingsMountedRef: RefObject<boolean>;
  systemTimezone: string;
}

export function useGeneralSettingsBootstrap({
  runtimeClass,
  trayPresentationKind,
  logSettingsError,
  recordAdvancedPreferencesBaseline,
  setAutostart,
  setDesktopCloseAction,

  setMemoryLock,
  setMorningBriefingTime,
  setReady,
  setSidebarModuleConfig,
  setTimezone,
  setTrayIconVisible,
  setWeeklyReviewDay,
  setWeeklyReviewTime,
  setWorkingHoursEnd,
  setWorkingHoursStart,
  settingsLoadSeqRef,
  settingsMountedRef,
  systemTimezone,
}: UseGeneralSettingsBootstrapArgs): void {
  useEffect(() => {
    let cancelled = false;
    const loadSeq = settingsLoadSeqRef.current + 1;
    settingsLoadSeqRef.current = loadSeq;
    const isCurrentLoad = () =>
      settingsMountedRef.current && !cancelled && settingsLoadSeqRef.current === loadSeq;

    async function load() {
      try {
        const snapshot = await loadGeneralSettingsSnapshot({
          trayPresentationKind,
          systemTimezone,
        });
        if (!isCurrentLoad()) return;

        setWorkingHoursStart(snapshot.workingHoursStart);
        setWorkingHoursEnd(snapshot.workingHoursEnd);
        setTimezone(snapshot.timezone);
        setWeeklyReviewDay(snapshot.weeklyReviewDay);
        setWeeklyReviewTime(snapshot.weeklyReviewTime);
        setMorningBriefingTime(snapshot.morningBriefingTime);
        recordAdvancedPreferencesBaseline({
          timezone: snapshot.timezone,
          weeklyReviewDay: snapshot.weeklyReviewDay,
          weeklyReviewTime: snapshot.weeklyReviewTime,
          morningBriefingTime: snapshot.morningBriefingTime,
        });
        setSidebarModuleConfig(snapshot.sidebarModuleConfig);
        setMemoryLock(snapshot.memoryLock);
        setTrayIconVisible(snapshot.trayIconVisible);
        setDesktopCloseAction(snapshot.desktopCloseAction);

        if (runtimeClass === 'desktop') {
          const autostartEnabled = await loadAutostartPreference();
          if (!isCurrentLoad()) return;
          setAutostart(autostartEnabled);
        }
      } catch (error) {
        if (isCurrentLoad()) {
          logSettingsError('frontend.settings.load', 'Load settings failed', error);
        }
      } finally {
        if (isCurrentLoad()) {
          setReady(true);
        }
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [
    runtimeClass,
    trayPresentationKind,
    logSettingsError,
    recordAdvancedPreferencesBaseline,
    setAutostart,
    setDesktopCloseAction,
  
    setMemoryLock,
    setMorningBriefingTime,
    setReady,
    setSidebarModuleConfig,
    setTimezone,
    setTrayIconVisible,
    setWeeklyReviewDay,
    setWeeklyReviewTime,
    setWorkingHoursEnd,
    setWorkingHoursStart,
    settingsLoadSeqRef,
    settingsMountedRef,
    systemTimezone,
  ]);
}
