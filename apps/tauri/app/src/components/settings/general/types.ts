import type { Dispatch, SetStateAction } from 'react';

import type { SidebarModule, SidebarModuleConfig, SidebarModuleState } from '@/lib/sidebarModules';
import type { RuntimeClass } from '@/lib/platform/platform';
import type { TranslationKey } from '@/locales';

export type DesktopCloseActionPreference = 'quit' | 'hide_to_tray';

interface GeneralPreferencesContentProps {
  runtimeClass: RuntimeClass;
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
  onWorkingHoursStartChange: Dispatch<SetStateAction<string>>;
  onWorkingHoursEndChange: Dispatch<SetStateAction<string>>;
  onAutostartToggle: (enabled: boolean) => Promise<void>;
  onTrayIconToggle: (enabled: boolean) => Promise<void>;
  onDesktopCloseActionChange: (next: DesktopCloseActionPreference) => void;
  onMemoryLockToggle: (enabled: boolean) => Promise<void>;
  onTimezoneChange: Dispatch<SetStateAction<string>>;
  onUseSystemTimezone: () => void;
  onWeeklyReviewDayChange: Dispatch<SetStateAction<string>>;
  onWeeklyReviewTimeChange: Dispatch<SetStateAction<string>>;
  onMorningBriefingTimeChange: Dispatch<SetStateAction<string>>;
  onSetSidebarModuleState: (moduleId: SidebarModule, state: SidebarModuleState) => void;
  onResetSidebarModules: () => void;
}

export type GeneralPreferencesSectionProps = GeneralPreferencesContentProps;

export type SidebarModulesPanelProps = Pick<
  GeneralPreferencesContentProps,
  | 'runtimeClass'
  | 'sidebarModuleConfig'
  | 'onSetSidebarModuleState'
  | 'onResetSidebarModules'
>;

export type WorkflowPreferencesPanelProps = Pick<
  GeneralPreferencesContentProps,
  | 'workingHoursStart'
  | 'workingHoursEnd'
  | 'onWorkingHoursStartChange'
  | 'onWorkingHoursEndChange'
>;

export type DesktopBehaviorPanelProps = Pick<
  GeneralPreferencesContentProps,
  | 'runtimeClass'
  | 'supportsBiometricLock'
  | 'autostart'
  | 'autostartBusy'
  | 'trayIconVisible'
  | 'trayIconBusy'
  | 'trayIconTitleKey'
  | 'trayIconDescKey'
  | 'trayIconVisibleKey'
  | 'trayIconHiddenKey'
  | 'desktopCloseAction'
  | 'memoryLock'
  | 'memoryLockBusy'
  | 'onAutostartToggle'
  | 'onTrayIconToggle'
  | 'onDesktopCloseActionChange'
  | 'onMemoryLockToggle'
>;

export type AdvancedPreferencesPanelProps = Pick<
  GeneralPreferencesSectionProps,
  | 'normalizedTimezone'
  | 'timezoneOptions'
  | 'weeklyReviewDay'
  | 'weeklyReviewTime'
  | 'morningBriefingTime'
  | 'onTimezoneChange'
  | 'onUseSystemTimezone'
  | 'onWeeklyReviewDayChange'
  | 'onWeeklyReviewTimeChange'
  | 'onMorningBriefingTimeChange'
>;
