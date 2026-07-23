import type { QueryClient } from '@tanstack/react-query';

import type { RuntimeClass, TrayPresentationKind } from '@/lib/platform/platform';
import type { SidebarModuleConfig } from '@/lib/sidebarModules';
import type { DesktopCloseActionPreference } from '@/components/settings/general/types';

export interface GeneralSettingsSnapshot {
  workingHoursStart: string;
  workingHoursEnd: string;
  autostart: boolean;
  trayIconVisible: boolean;
  desktopCloseAction: DesktopCloseActionPreference;
  timezone: string;
  weeklyReviewDay: string;
  weeklyReviewTime: string;
  morningBriefingTime: string;
  sidebarModuleConfig: SidebarModuleConfig;
  memoryLock: boolean;
}

export interface LoadGeneralSettingsSnapshotArgs {
  trayPresentationKind: TrayPresentationKind;
  systemTimezone: string;
}

export interface NormalizedAdvancedPreferences {
  timezone: string;
  weeklyReviewDay: string;
  weeklyReviewTime: string;
  morningBriefingTime: string;
}

export interface SaveAdvancedPreferencesArgs extends NormalizedAdvancedPreferences {
  queryClient: QueryClient;
  lastPersistedAdvanced: NormalizedAdvancedPreferences | null;
  runtimeClass: RuntimeClass;
  trayPresentationKind: TrayPresentationKind;
  desktopCloseActionDirty: boolean;
  desktopCloseAction: DesktopCloseActionPreference;
  ensureTrayIconVisibleForHideToTray: () => Promise<void>;
}

export interface SaveSidebarModulesPreferenceArgs {
  queryClient: QueryClient;
  config: SidebarModuleConfig;
}
