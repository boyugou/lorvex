import {
  createVisibilityGatedIntervalController,
  type IntervalHost,
  type VisibilityIntervalHost,
} from './intervalControllers';

interface VisibilityIntervalRuntimeDeps {
  intervalMs: number;
  host: VisibilityIntervalHost;
  documentTarget: Pick<Document, 'addEventListener' | 'removeEventListener'> | null;
}

function createBrowserIntervalHost(runTick: () => void): IntervalHost {
  return {
    runTick,
    setInterval: (callback, delayMs) => {
      const timer = globalThis.setInterval(callback, delayMs);
      return () => {
        globalThis.clearInterval(timer as ReturnType<typeof globalThis.setInterval>);
      };
    },
  };
}

export function createBrowserVisibilityGatedIntervalRuntimeDeps(
  runTick: () => void,
): Pick<VisibilityIntervalRuntimeDeps, 'documentTarget' | 'host'> {
  return {
    documentTarget: typeof document === 'undefined' ? null : document,
    host: {
      ...createBrowserIntervalHost(runTick),
      isVisible: () => (typeof document === 'undefined' ? true : document.visibilityState === 'visible'),
    },
  };
}

export function startVisibilityGatedIntervalRuntime(
  deps: VisibilityIntervalRuntimeDeps,
): () => void {
  const controller = createVisibilityGatedIntervalController(deps.host, deps.intervalMs);
  const onVisibility = () => controller.handleVisibilityChange();
  controller.mount();
  deps.documentTarget?.addEventListener('visibilitychange', onVisibility);
  return () => {
    controller.dispose();
    deps.documentTarget?.removeEventListener('visibilitychange', onVisibility);
  };
}
