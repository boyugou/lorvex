export interface ForegroundCatchUpRuntimeHost {
  addVisibilityListener: ((handler: () => void) => () => void) | null;
  addWindowFocusListener: ((handler: () => void) => () => void) | null;
  getVisibilityState: () => DocumentVisibilityState;
}

interface ForegroundCatchUpRuntimeDeps extends ForegroundCatchUpRuntimeHost {
  runCatchUp: () => void;
}

interface ForegroundCatchUpRuntimeHandle {
  dispose: () => void;
}

export function createBrowserForegroundCatchUpHost(): ForegroundCatchUpRuntimeHost {
  return {
    addVisibilityListener: typeof document === 'undefined'
      ? null
      : (handler) => {
          document.addEventListener('visibilitychange', handler);
          return () => document.removeEventListener('visibilitychange', handler);
        },
    addWindowFocusListener: typeof window === 'undefined'
      ? null
      : (handler) => {
          window.addEventListener('focus', handler);
          return () => window.removeEventListener('focus', handler);
        },
    getVisibilityState: () => (typeof document === 'undefined' ? 'visible' : document.visibilityState),
  };
}

export function installForegroundCatchUpController(
  deps: ForegroundCatchUpRuntimeDeps,
): ForegroundCatchUpRuntimeHandle {
  let disposed = false;
  const removeNoop = (): void => {};
  const runIfVisible = (): void => {
    if (!disposed && deps.getVisibilityState() === 'visible') {
      deps.runCatchUp();
    }
  };
  const removeWindowFocusListener = deps.addWindowFocusListener
    ? deps.addWindowFocusListener(runIfVisible)
    : removeNoop;
  const removeVisibilityListener = deps.addVisibilityListener
    ? deps.addVisibilityListener(runIfVisible)
    : removeNoop;

  return {
    dispose: () => {
      disposed = true;
      removeWindowFocusListener();
      removeVisibilityListener();
    },
  };
}
