type UiViewStatePersistenceTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface UiViewStatePersistenceTimerHost {
  clearTimeout: (handle: UiViewStatePersistenceTimerHandle) => void;
  setTimeout: (
    callback: () => void,
    delayMs: number,
  ) => UiViewStatePersistenceTimerHandle;
}

export function createBrowserUiViewStatePersistenceTimerHost(): UiViewStatePersistenceTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

interface InstallUiViewStatePersistenceRuntimeOptions {
  delayMs: number;
  flush: () => void;
  timerHost: UiViewStatePersistenceTimerHost;
}

export function installUiViewStatePersistenceRuntime(
  options: InstallUiViewStatePersistenceRuntimeOptions,
): () => void {
  const handle = options.timerHost.setTimeout(() => {
    options.flush();
  }, options.delayMs);

  return () => {
    options.timerHost.clearTimeout(handle);
  };
}
