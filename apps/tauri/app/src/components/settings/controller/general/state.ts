import {
  useCallback,
  useMemo,
  useRef,
  useState,
  type Dispatch,
  type RefObject,
  type SetStateAction,
} from 'react';

import {
  DEFAULT_SIDEBAR_MODULE_CONFIG,
  cloneSidebarModuleConfig,
  type SidebarModuleConfig,
} from '@/lib/sidebarModules';
import { getSystemTimezone, normalizeTimezonePreference, resolveTimezoneOptions } from '@/lib/dates/timezone';
import type { DesktopCloseActionPreference } from '@/components/settings/general/types';
import {
  DEFAULT_MORNING_BRIEFING_TIME,
  DEFAULT_WEEKLY_REVIEW_DAY,
  DEFAULT_WEEKLY_REVIEW_TIME,
  DEFAULT_WORKING_HOURS_END,
  DEFAULT_WORKING_HOURS_START,
} from './preferences';
import type { TrayPresentationKind } from '@/lib/platform/platform';
import { resolveTrayIconCopyKeys } from './runtime';

interface UseGeneralSettingsStateArgs {
  trayPresentationKind: TrayPresentationKind;
}

interface GeneralSettingsState {
  workingHoursStart: string;
  workingHoursEnd: string;
  autostart: boolean;
  trayIconVisible: boolean;
  desktopCloseAction: DesktopCloseActionPreference;
  desktopCloseActionDirty: boolean;
  timezone: string;
  weeklyReviewDay: string;
  weeklyReviewTime: string;
  morningBriefingTime: string;
  sidebarModuleConfig: SidebarModuleConfig;
  memoryLock: boolean;
  ready: boolean;
  settingsLoadSeqRef: RefObject<number>;
  systemTimezone: string;
  normalizedTimezone: string;
  timezoneOptions: string[];
  trayIconCopyKeys: ReturnType<typeof resolveTrayIconCopyKeys>;
  setWorkingHoursStart: Dispatch<SetStateAction<string>>;
  setWorkingHoursEnd: Dispatch<SetStateAction<string>>;
  setAutostart: Dispatch<SetStateAction<boolean>>;
  setTrayIconVisible: Dispatch<SetStateAction<boolean>>;
  setDesktopCloseAction: Dispatch<SetStateAction<DesktopCloseActionPreference>>;
  setDesktopCloseActionDirty: Dispatch<SetStateAction<boolean>>;
  setTimezone: Dispatch<SetStateAction<string>>;
  setWeeklyReviewDay: Dispatch<SetStateAction<string>>;
  setWeeklyReviewTime: Dispatch<SetStateAction<string>>;
  setMorningBriefingTime: Dispatch<SetStateAction<string>>;
  setSidebarModuleConfig: Dispatch<SetStateAction<SidebarModuleConfig>>;
  setMemoryLock: Dispatch<SetStateAction<boolean>>;
  setReady: Dispatch<SetStateAction<boolean>>;
  handleUseSystemTimezone: () => void;
}

export function useGeneralSettingsState({
  trayPresentationKind,
}: UseGeneralSettingsStateArgs): GeneralSettingsState {
  const trayIconCopyKeys = useMemo(
    () => resolveTrayIconCopyKeys(trayPresentationKind),
    [trayPresentationKind],
  );
  const [workingHoursStart, setWorkingHoursStart] = useState(DEFAULT_WORKING_HOURS_START);
  const [workingHoursEnd, setWorkingHoursEnd] = useState(DEFAULT_WORKING_HOURS_END);
  const [autostart, setAutostart] = useState(false);
  const [trayIconVisible, setTrayIconVisible] = useState(true);
  const [desktopCloseAction, setDesktopCloseAction] = useState<DesktopCloseActionPreference>(
    trayPresentationKind === 'menu_bar' ? 'hide_to_tray' : 'quit',
  );
  const [desktopCloseActionDirty, setDesktopCloseActionDirty] = useState(false);
  const [timezone, setTimezone] = useState('');
  const [weeklyReviewDay, setWeeklyReviewDay] = useState(DEFAULT_WEEKLY_REVIEW_DAY);
  const [weeklyReviewTime, setWeeklyReviewTime] = useState(DEFAULT_WEEKLY_REVIEW_TIME);
  const [morningBriefingTime, setMorningBriefingTime] = useState(DEFAULT_MORNING_BRIEFING_TIME);
  const [sidebarModuleConfig, setSidebarModuleConfig] = useState<SidebarModuleConfig>(
    () => cloneSidebarModuleConfig(DEFAULT_SIDEBAR_MODULE_CONFIG),
  );
  const [memoryLock, setMemoryLock] = useState(true);
  const [ready, setReady] = useState(false);
  const settingsLoadSeqRef = useRef(0);
  const systemTimezone = getSystemTimezone();
  const normalizedTimezone = useMemo(
    () => normalizeTimezonePreference(timezone, systemTimezone),
    [timezone, systemTimezone],
  );
  const timezoneOptions = useMemo(
    () => resolveTimezoneOptions(normalizedTimezone, systemTimezone),
    [normalizedTimezone, systemTimezone],
  );
  const handleUseSystemTimezone = useCallback(() => {
    setTimezone(systemTimezone);
  }, [systemTimezone]);

  return {
    workingHoursStart,
    workingHoursEnd,
    autostart,
    trayIconVisible,
    desktopCloseAction,
    desktopCloseActionDirty,
    timezone,
    weeklyReviewDay,
    weeklyReviewTime,
    morningBriefingTime,
    sidebarModuleConfig,
    memoryLock,
    ready,
    settingsLoadSeqRef,
    systemTimezone,
    normalizedTimezone,
    timezoneOptions,
    trayIconCopyKeys,
    setWorkingHoursStart,
    setWorkingHoursEnd,
    setAutostart,
    setTrayIconVisible,
    setDesktopCloseAction,
    setDesktopCloseActionDirty,
    setTimezone,
    setWeeklyReviewDay,
    setWeeklyReviewTime,
    setMorningBriefingTime,
    setSidebarModuleConfig,
    setMemoryLock,
    setReady,
    handleUseSystemTimezone,
  };
}
