import {
  createBrowserForegroundCatchUpHost,
  installForegroundCatchUpController,
  type ForegroundCatchUpRuntimeHost,
} from '../foregroundCatchUpController';

interface AtRiskNotificationsRuntimeState {
  running: boolean;
}

interface AtRiskNotificationsRuntimeDeps extends ForegroundCatchUpRuntimeHost {
  checkAtRiskDeadlines: () => Promise<void>;
  clearInterval: (handle: unknown) => void;
  enabled: boolean;
  reportTickError: (error: unknown) => void;
  setInterval: (callback: () => void, delayMs: number) => unknown;
  state: AtRiskNotificationsRuntimeState;
  pollIntervalMs: number;
}

export type AtRiskNotificationsBrowserHost = Pick<
  AtRiskNotificationsRuntimeDeps,
  | keyof ForegroundCatchUpRuntimeHost
  | 'clearInterval'
  | 'setInterval'
>;

export function createBrowserAtRiskNotificationsHost(): AtRiskNotificationsBrowserHost {
  return {
    clearInterval: (handle) => {
      globalThis.clearInterval(handle as ReturnType<typeof globalThis.setInterval>);
    },
    ...createBrowserForegroundCatchUpHost(),
    setInterval: (callback, delayMs) => globalThis.setInterval(callback, delayMs),
  };
}

interface AtRiskNotificationsRuntimeHandle {
  dispose: () => void;
}

export function installAtRiskNotificationsRuntime(
  deps: AtRiskNotificationsRuntimeDeps,
): AtRiskNotificationsRuntimeHandle {
  if (!deps.enabled) {
    return { dispose: () => {} };
  }

  let cancelled = false;
  let intervalHandle: unknown | null = null;

  const runTick = (): void => {
    if (cancelled || deps.state.running) return;
    deps.state.running = true;
    void deps.checkAtRiskDeadlines()
      .catch((error) => {
        if (!cancelled) {
          deps.reportTickError(error);
        }
      })
      .finally(() => {
        deps.state.running = false;
      });
  };

  const foregroundCatchUp = installForegroundCatchUpController({
    ...deps,
    runCatchUp: (): void => {
      runTick();
    },
  });

  runTick();
  intervalHandle = deps.setInterval(runTick, deps.pollIntervalMs);

  return {
    dispose: () => {
      cancelled = true;
      if (intervalHandle !== null) {
        deps.clearInterval(intervalHandle);
        intervalHandle = null;
      }
      foregroundCatchUp.dispose();
    },
  };
}
