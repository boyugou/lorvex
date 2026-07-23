import type { Dispatch, RefObject, SetStateAction } from 'react';
import type { RuntimeClass, TrayPresentationKind } from '@/lib/platform/platform';
import { useI18n } from '@/lib/i18n';
import type { SidebarModule, SidebarModuleConfig, SidebarModuleState } from '@/lib/sidebarModules';
import type { TranslationKey } from '@/locales';
import type { DesktopCloseActionPreference } from '@/components/settings/general/types';
import { useGeneralSettingsBootstrap } from './bootstrap';
import { useGeneralSettingsAutosave } from './autosave';
import { useGeneralSettingsActions } from './actions';
import { useGeneralSettingsPersistence } from './persistence';
import { useGeneralSettingsState } from './state';

interface UseGeneralSettingsControllerArgs {
  runtimeClass: RuntimeClass;
  trayPresentationKind: TrayPresentationKind;
  supportsBiometricLock: boolean;
  settingsMountedRef: RefObject<boolean>;
}

export interface GeneralSettingsController {
  ready: boolean;
  autosaveState: 'idle' | 'saving' | 'saved' | 'error';
  supportsBiometricLock: boolean;
  workingHoursStart: string;
  workingHoursEnd: string;
  autostart: boolean;
  autostartBusy: boolean;
  trayIconVisible: boolean;
  trayIconBusy: boolean;
  trayIconTitleKey: TranslationKey;
  trayIconDescKey: TranslationKey;
  trayIconVisibleKey: TranslationKey;
  trayIconHiddenKey: TranslationKey;
  desktopCloseAction: DesktopCloseActionPreference;
  memoryLock: boolean;
  memoryLockBusy: boolean;
  normalizedTimezone: string;
  timezoneOptions: string[];
  weeklyReviewDay: string;
  weeklyReviewTime: string;
  morningBriefingTime: string;
  sidebarModuleConfig: SidebarModuleConfig;
  setWorkingHoursStart: Dispatch<SetStateAction<string>>;
  setWorkingHoursEnd: Dispatch<SetStateAction<string>>;
  setWeeklyReviewDay: Dispatch<SetStateAction<string>>;
  setWeeklyReviewTime: Dispatch<SetStateAction<string>>;
  setMorningBriefingTime: Dispatch<SetStateAction<string>>;
  setTimezone: Dispatch<SetStateAction<string>>;
  handleUseSystemTimezone: () => void;
  handleAutostartToggle: (enabled: boolean) => Promise<void>;
  handleTrayIconToggle: (enabled: boolean) => Promise<void>;
  handleDesktopCloseActionChange: (next: DesktopCloseActionPreference) => void;
  handleMemoryLockToggle: (enabled: boolean) => Promise<void>;
  cycleSidebarModule: (moduleId: SidebarModule) => void;
  setSidebarModuleState: (moduleId: SidebarModule, state: SidebarModuleState) => void;
  resetSidebarModules: () => void;
}

export function useGeneralSettingsController({
  runtimeClass,
  trayPresentationKind,
  supportsBiometricLock,
  settingsMountedRef,
}: UseGeneralSettingsControllerArgs): GeneralSettingsController {
  const { t } = useI18n();
  const {
    autostart,
    desktopCloseAction,
    desktopCloseActionDirty,

    handleUseSystemTimezone,
    memoryLock,
    morningBriefingTime,
    normalizedTimezone,
    ready,
    settingsLoadSeqRef,
    setAutostart,
    setDesktopCloseAction,
    setDesktopCloseActionDirty,

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
    sidebarModuleConfig,
    systemTimezone,
    timezone,
    timezoneOptions,
    trayIconCopyKeys,
    trayIconVisible,
    weeklyReviewDay,
    weeklyReviewTime,
    workingHoursEnd,
    workingHoursStart,
  } = useGeneralSettingsState({
    trayPresentationKind,
  });

  const {
    logSettingsError,
    persistAdvanced,
    recordAdvancedPreferencesBaseline,

    persistWorkingHours,
  } = useGeneralSettingsPersistence({
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
  });

  useGeneralSettingsBootstrap({
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
  });

  const { autosaveState } = useGeneralSettingsAutosave({
    logSettingsError,
    persistAdvanced,

    persistWorkingHours,
    ready,
    t,
  });

  const {
    autostartBusy,
    cycleSidebarModule,
    setSidebarModuleState,
    handleAutostartToggle,
    handleDesktopCloseActionChange,
    handleMemoryLockToggle,
    handleTrayIconToggle,
    memoryLockBusy,
    resetSidebarModules,
    trayIconBusy,
  } = useGeneralSettingsActions({
    autostart,
    logSettingsError,
    memoryLock,
    settingsMountedRef,
    setAutostart,
    setDesktopCloseAction,
    setDesktopCloseActionDirty,
    setMemoryLock,
    setSidebarModuleConfig,
    setTrayIconVisible,
    t,
    trayIconRollbackKey: trayIconCopyKeys.rollbackKey,
    trayIconVisible,
  });

  return {
    ready,
    autosaveState,
    supportsBiometricLock,
    workingHoursStart,
    workingHoursEnd,

    autostart,
    autostartBusy,
    trayIconVisible,
    trayIconBusy,
    trayIconTitleKey: trayIconCopyKeys.titleKey,
    trayIconDescKey: trayIconCopyKeys.descriptionKey,
    trayIconVisibleKey: trayIconCopyKeys.visibleKey,
    trayIconHiddenKey: trayIconCopyKeys.hiddenKey,
    desktopCloseAction,
    memoryLock,
    memoryLockBusy,
    normalizedTimezone,
    timezoneOptions,
    weeklyReviewDay,
    weeklyReviewTime,
    morningBriefingTime,
    sidebarModuleConfig,
    setWorkingHoursStart,
    setWorkingHoursEnd,

    setWeeklyReviewDay,
    setWeeklyReviewTime,
    setMorningBriefingTime,
    setTimezone,
    handleUseSystemTimezone,
    handleAutostartToggle,
    handleTrayIconToggle,
    handleDesktopCloseActionChange,
    handleMemoryLockToggle,
    cycleSidebarModule,
    setSidebarModuleState,
    resetSidebarModules,
  };
}
