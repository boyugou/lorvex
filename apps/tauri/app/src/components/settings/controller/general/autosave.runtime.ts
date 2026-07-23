export type GeneralSettingsAutosaveState = 'idle' | 'saving' | 'saved' | 'error';
export type GeneralSettingsAutosaveTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface GeneralSettingsAutosaveTimerHost {
  clearTimeout: (handle: GeneralSettingsAutosaveTimerHandle) => void;
  setTimeout: (callback: () => void, delayMs: number) => GeneralSettingsAutosaveTimerHandle;
}

export interface GeneralSettingsAutosaveResetTimerRef {
  current: GeneralSettingsAutosaveTimerHandle | null;
}

export function createBrowserGeneralSettingsAutosaveTimerHost(): GeneralSettingsAutosaveTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

interface InstallGeneralSettingsAutosaveRuntimeOptions {
  delayMs: number;
  onTick: () => void;
  timerHost: GeneralSettingsAutosaveTimerHost;
}

interface RunGeneralSettingsAutosaveTickOptions {
  action: () => Promise<void>;
  reportSaveError: (error: unknown) => void;
  resetDelayMs: number;
  resetTimerRef: GeneralSettingsAutosaveResetTimerRef;
  setAutosaveState: (value: GeneralSettingsAutosaveState) => void;
  timerHost: GeneralSettingsAutosaveTimerHost;
}

export function cleanupGeneralSettingsAutosaveReset(
  resetTimerRef: GeneralSettingsAutosaveResetTimerRef,
  timerHost: Pick<GeneralSettingsAutosaveTimerHost, 'clearTimeout'>,
): void {
  if (resetTimerRef.current === null) {
    return;
  }
  timerHost.clearTimeout(resetTimerRef.current);
  resetTimerRef.current = null;
}

export function installGeneralSettingsAutosaveRuntime(
  options: InstallGeneralSettingsAutosaveRuntimeOptions,
): () => void {
  const handle = options.timerHost.setTimeout(() => {
    options.onTick();
  }, options.delayMs);
  return () => {
    options.timerHost.clearTimeout(handle);
  };
}

export function runGeneralSettingsAutosaveTick(
  options: RunGeneralSettingsAutosaveTickOptions,
): void {
  void options.action()
    .then(() => {
      options.setAutosaveState('saved');
      cleanupGeneralSettingsAutosaveReset(options.resetTimerRef, options.timerHost);
      options.resetTimerRef.current = options.timerHost.setTimeout(() => {
        options.setAutosaveState('idle');
        options.resetTimerRef.current = null;
      }, options.resetDelayMs);
    })
    .catch((error) => {
      options.reportSaveError(error);
      options.setAutosaveState('error');
    });
}
