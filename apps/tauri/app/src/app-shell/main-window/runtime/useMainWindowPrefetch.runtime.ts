interface MainWindowPrefetchRuntimeDeps {
  cancelIdleCallback: ((handle: unknown) => void) | null;
  clearTimeout: (handle: unknown) => void;
  fallbackDelayMs: number;
  prefetch: () => void;
  requestIdleCallback: ((callback: () => void) => unknown) | null;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export type MainWindowPrefetchBrowserHost = Pick<
  MainWindowPrefetchRuntimeDeps,
  | 'cancelIdleCallback'
  | 'clearTimeout'
  | 'requestIdleCallback'
  | 'setTimeout'
>;

type IdleCallbackWindow = Window & {
  cancelIdleCallback?: (handle: unknown) => void;
  requestIdleCallback?: (callback: () => void) => unknown;
};

export function createBrowserMainWindowPrefetchHost(): MainWindowPrefetchBrowserHost {
  const browserWindow = typeof window === 'undefined'
    ? null
    : window as IdleCallbackWindow;
  return {
    cancelIdleCallback: browserWindow?.cancelIdleCallback
      ? (handle) => browserWindow.cancelIdleCallback?.(handle)
      : null,
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    requestIdleCallback: browserWindow?.requestIdleCallback
      ? (callback) => browserWindow.requestIdleCallback?.(callback) ?? null
      : null,
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

interface MainWindowPrefetchRuntimeHandle {
  dispose: () => void;
}

export function installMainWindowPrefetchRuntime(
  deps: MainWindowPrefetchRuntimeDeps,
): MainWindowPrefetchRuntimeHandle {
  if (deps.requestIdleCallback) {
    const handle = deps.requestIdleCallback(deps.prefetch);
    return {
      dispose: () => {
        deps.cancelIdleCallback?.(handle);
      },
    };
  }

  const handle = deps.setTimeout(deps.prefetch, deps.fallbackDelayMs);
  return {
    dispose: () => {
      deps.clearTimeout(handle);
    },
  };
}
