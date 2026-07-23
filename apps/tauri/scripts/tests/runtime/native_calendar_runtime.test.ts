import assert from 'node:assert/strict';
import test from 'node:test';

import { getNativeCalendarRuntimeConfig } from '../../../app/src/lib/nativeCalendarRuntime';
import type { RuntimeProfile } from '../../../app/src/lib/platform/platform';

function makeRuntimeProfile(overrides: Partial<RuntimeProfile> = {}): RuntimeProfile {
  return {
    runtimeId: 'macos',
    runtimeClass: 'desktop',
    supportsBiometricLock: true,
    supportsMultipleWindows: true,
    supportsTitleBarOverlay: true,
    supportsMcpHosting: true,
    supportedSyncBackendKinds: [],
    trayPresentationKind: 'menu_bar',
    supportsDesktopOverlays: true,
    supportsAssistantCommandPolling: true,
    supportsAutostart: true,
    supportsNativeCalendarRead: true,
    supportsBackgroundSync: true,
    biometricAdapterKind: 'windows_hello',
    nativeCalendarAdapterKind: 'windows_appointments',
    nativeCalendarActivationState: 'active',
    ...overrides,
  };
}

test('getNativeCalendarRuntimeConfig returns the active adapter contract for supported runtimes', () => {
  const config = getNativeCalendarRuntimeConfig(makeRuntimeProfile());

  assert.ok(config);
  assert.equal(config?.adapterKind, 'windows_appointments');
  assert.equal(config?.activationState, 'active');
  assert.equal(config?.isAvailable, true);
  assert.equal(config?.deviceStateKey, 'windows_calendar_sync_enabled');
  assert.equal(config?.clearProviderKind, 'windows_appointments');
  assert.equal(config?.titleKey, 'settings.windowsCalTitle');
  assert.equal(config?.descKey, 'settings.windowsCalDesc');
  assert.equal(config?.inactiveMessageKey, 'settings.nativeCalendarNotAvailable');
});

test('getNativeCalendarRuntimeConfig keeps planned adapters visible but unavailable', () => {
  const config = getNativeCalendarRuntimeConfig(makeRuntimeProfile({
    runtimeId: 'linux',
    runtimeClass: 'desktop',
    supportsNativeCalendarRead: true,
    supportsBackgroundSync: false,
    trayPresentationKind: 'system_tray',
    supportsDesktopOverlays: true,
    supportsAssistantCommandPolling: true,
    supportsAutostart: false,
    biometricAdapterKind: 'none',
    nativeCalendarAdapterKind: 'linux_ics',
    nativeCalendarActivationState: 'planned',
  }));

  assert.ok(config);
  assert.equal(config?.adapterKind, 'linux_ics');
  assert.equal(config?.isAvailable, false);
  assert.equal(config?.inactiveMessageKey, 'settings.nativeCalendarPlanned');
});

test('getNativeCalendarRuntimeConfig fails closed for impossible adapter drift', () => {
  const driftedProfile = makeRuntimeProfile({
    nativeCalendarAdapterKind: 'totally_unknown' as RuntimeProfile['nativeCalendarAdapterKind'],
  });

  assert.equal(getNativeCalendarRuntimeConfig(driftedProfile), null);
});

test('getNativeCalendarRuntimeConfig fails closed for impossible activation-state drift', () => {
  const driftedProfile = makeRuntimeProfile({
    nativeCalendarActivationState: 'unexpected' as RuntimeProfile['nativeCalendarActivationState'],
  });

  assert.equal(getNativeCalendarRuntimeConfig(driftedProfile), null);
});
