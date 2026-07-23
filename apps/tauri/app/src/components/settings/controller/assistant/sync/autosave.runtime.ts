import type { SyncBackendSaveState } from './types';

export type AssistantSyncAutosaveTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface AssistantSyncAutosaveTimerHost {
  clearTimeout: (handle: AssistantSyncAutosaveTimerHandle) => void;
  setTimeout: (callback: () => void, delayMs: number) => AssistantSyncAutosaveTimerHandle;
}

export interface AssistantSyncAutosaveResetTimerRef {
  current: AssistantSyncAutosaveTimerHandle | null;
}

export function createBrowserAssistantSyncAutosaveTimerHost(): AssistantSyncAutosaveTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

interface InstallAssistantSyncAutosaveRuntimeOptions {
  delayMs: number;
  onTick: () => void;
  timerHost: AssistantSyncAutosaveTimerHost;
}

interface RunAssistantSyncAutosaveTickOptions {
  isCurrent: () => boolean;
  isMounted: () => boolean;
  reportSaveError: (error: unknown) => void;
  resetDelayMs: number;
  resetTimerRef: AssistantSyncAutosaveResetTimerRef;
  save: () => Promise<void>;
  setSaveState: (value: SyncBackendSaveState) => void;
  timerHost: AssistantSyncAutosaveTimerHost;
}

export function cleanupAssistantSyncAutosaveReset(
  resetTimerRef: AssistantSyncAutosaveResetTimerRef,
  timerHost: Pick<AssistantSyncAutosaveTimerHost, 'clearTimeout'>,
): void {
  if (resetTimerRef.current === null) {
    return;
  }
  timerHost.clearTimeout(resetTimerRef.current);
  resetTimerRef.current = null;
}

export function installAssistantSyncAutosaveRuntime(
  options: InstallAssistantSyncAutosaveRuntimeOptions,
): () => void {
  const handle = options.timerHost.setTimeout(() => {
    options.onTick();
  }, options.delayMs);
  return () => {
    options.timerHost.clearTimeout(handle);
  };
}

export function runAssistantSyncAutosaveTick(
  options: RunAssistantSyncAutosaveTickOptions,
): void {
  if (options.isMounted()) {
    options.setSaveState('saving');
  }

  void options.save()
    .then(() => {
      if (!options.isMounted() || !options.isCurrent()) return;
      options.setSaveState('saved');
      cleanupAssistantSyncAutosaveReset(options.resetTimerRef, options.timerHost);
      options.resetTimerRef.current = options.timerHost.setTimeout(() => {
        if (!options.isMounted()) {
          options.resetTimerRef.current = null;
          return;
        }
        options.setSaveState('idle');
        options.resetTimerRef.current = null;
      }, options.resetDelayMs);
    })
    .catch((error: unknown) => {
      options.reportSaveError(error);
      if (!options.isMounted() || !options.isCurrent()) return;
      options.setSaveState('error');
    });
}
