import type { TranslationKey } from '../locales';
import {
  type NativeCalendarProviderSource,
  syncLinuxCalendars,
  syncWindowsCalendars,
} from './ipc/calendar';
import {
  DEV_LINUX_CALENDAR_SYNC_ENABLED,
  DEV_WINDOWS_CALENDAR_SYNC_ENABLED,
  type DeviceStateKey,
} from './preferences/keys';
import type {
  NativeCalendarAdapterKind,
  NativeCalendarActivationState,
  RuntimeProfile,
} from './platform/platform';

export interface NativeCalendarSyncSummary {
  events_imported: number;
  events_updated: number;
  events_removed: number;
  available: boolean;
  error: string | null;
}

interface NativeCalendarRuntimeConfig {
  adapterKind: Exclude<NativeCalendarAdapterKind, 'none'>;
  activationState: Exclude<NativeCalendarActivationState, 'none'>;
  isAvailable: boolean;
  deviceStateKey: DeviceStateKey;
  clearProviderKind: NativeCalendarProviderSource;
  titleKey: TranslationKey;
  descKey: TranslationKey;
  inactiveMessageKey: TranslationKey;
  syncNow: () => Promise<NativeCalendarSyncSummary>;
}

interface NativeCalendarAdapterDefinition {
  deviceStateKey: DeviceStateKey;
  clearProviderKind: NativeCalendarProviderSource;
  titleKey: TranslationKey;
  descKey: TranslationKey;
  syncNow: () => Promise<NativeCalendarSyncSummary>;
}

const NATIVE_CALENDAR_ADAPTERS: Record<
  Exclude<NativeCalendarAdapterKind, 'none'>,
  NativeCalendarAdapterDefinition
> = {
  windows_appointments: {
    deviceStateKey: DEV_WINDOWS_CALENDAR_SYNC_ENABLED,
    clearProviderKind: 'windows_appointments',
    titleKey: 'settings.windowsCalTitle',
    descKey: 'settings.windowsCalDesc',
    syncNow: syncWindowsCalendars,
  },
  linux_ics: {
    deviceStateKey: DEV_LINUX_CALENDAR_SYNC_ENABLED,
    clearProviderKind: 'linux_ics',
    titleKey: 'settings.linuxCalTitle',
    descKey: 'settings.linuxCalDesc',
    syncNow: syncLinuxCalendars,
  },
};

export function getNativeCalendarRuntimeConfig(
  runtimeProfile: RuntimeProfile,
): NativeCalendarRuntimeConfig | null {
  const { nativeCalendarAdapterKind, nativeCalendarActivationState } = runtimeProfile;
  if (
    nativeCalendarAdapterKind === 'none'
    || nativeCalendarActivationState === 'none'
    || (
      nativeCalendarActivationState !== 'active'
      && nativeCalendarActivationState !== 'planned'
    )
  ) {
    return null;
  }

  const adapter = NATIVE_CALENDAR_ADAPTERS[nativeCalendarAdapterKind];
  if (!adapter) {
    return null;
  }
  return {
    adapterKind: nativeCalendarAdapterKind,
    activationState: nativeCalendarActivationState,
    isAvailable:
      nativeCalendarActivationState === 'active' && runtimeProfile.supportsNativeCalendarRead,
    deviceStateKey: adapter.deviceStateKey,
    clearProviderKind: adapter.clearProviderKind,
    titleKey: adapter.titleKey,
    descKey: adapter.descKey,
    inactiveMessageKey:
      nativeCalendarActivationState === 'planned'
        ? 'settings.nativeCalendarPlanned'
        : 'settings.nativeCalendarNotAvailable',
    syncNow: adapter.syncNow,
  };
}
