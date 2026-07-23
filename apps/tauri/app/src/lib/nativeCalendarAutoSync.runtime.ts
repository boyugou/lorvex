import type { DeviceStateKey } from './preferences/keys';

interface NativeCalendarAutoSyncRuntimeConfig {
  deviceStateKey: DeviceStateKey;
  isAvailable: boolean;
  syncNow: () => Promise<unknown>;
}

interface NativeCalendarAutoSyncRuntimeState {
  firedInitialSync: boolean;
}

interface NativeCalendarAutoSyncRuntimeDeps {
  config: NativeCalendarAutoSyncRuntimeConfig | null;
  getDeviceState: (key: DeviceStateKey) => Promise<string | null>;
  reportSyncError: (error: unknown) => void;
  setInterval: (callback: () => void, delayMs: number) => unknown;
  clearInterval: (handle: unknown) => void;
  state: NativeCalendarAutoSyncRuntimeState;
  syncIntervalMs: number;
}

export type NativeCalendarAutoSyncIntervalHost = Pick<
  NativeCalendarAutoSyncRuntimeDeps,
  'clearInterval' | 'setInterval'
>;

export function createBrowserNativeCalendarAutoSyncIntervalHost(): NativeCalendarAutoSyncIntervalHost {
  return {
    clearInterval: (handle) => {
      globalThis.clearInterval(handle as ReturnType<typeof globalThis.setInterval>);
    },
    setInterval: (callback, delayMs) => globalThis.setInterval(callback, delayMs),
  };
}

interface NativeCalendarAutoSyncRuntimeHandle {
  dispose: () => void;
  installed: boolean;
}

async function runNativeCalendarAutoSyncOnce(
  deps: NativeCalendarAutoSyncRuntimeDeps,
  config: NativeCalendarAutoSyncRuntimeConfig,
  isCancelled: () => boolean,
): Promise<void> {
  try {
    const nativeCalendarEnabled = await deps.getDeviceState(config.deviceStateKey);
    if (!isCancelled() && nativeCalendarEnabled === 'true') {
      await config.syncNow();
    }
  } catch (error) {
    if (!isCancelled()) {
      deps.reportSyncError(error);
    }
  }
}

export function installNativeCalendarAutoSyncRuntime(
  deps: NativeCalendarAutoSyncRuntimeDeps,
): NativeCalendarAutoSyncRuntimeHandle {
  if (!deps.config?.isAvailable) {
    deps.state.firedInitialSync = false;
    return { dispose: () => {}, installed: false };
  }

  let cancelled = false;
  const config = deps.config;
  if (!deps.state.firedInitialSync) {
    deps.state.firedInitialSync = true;
    void runNativeCalendarAutoSyncOnce(deps, config, () => cancelled);
  }

  const intervalHandle = deps.setInterval(() => {
    void runNativeCalendarAutoSyncOnce(deps, config, () => cancelled);
  }, deps.syncIntervalMs);

  return {
    dispose: () => {
      cancelled = true;
      deps.clearInterval(intervalHandle);
      deps.state.firedInitialSync = false;
    },
    installed: true,
  };
}
