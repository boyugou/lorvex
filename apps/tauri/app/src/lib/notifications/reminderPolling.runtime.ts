import {
  createBrowserForegroundCatchUpHost,
  installForegroundCatchUpController,
  type ForegroundCatchUpRuntimeHost,
} from '../foregroundCatchUpController';

interface ReminderPollingRuntimeState {
  running: boolean;
}

interface ReminderPollingRuntimeDeps extends ForegroundCatchUpRuntimeHost {
  checkReminders: () => Promise<void>;
  clearInterval: (handle: unknown) => void;
  getUpcomingReminders: (lookaheadMinutes: number) => Promise<readonly unknown[]>;
  registerNotificationActions: () => Promise<unknown> | unknown;
  reportActionRegistrationError: (error: unknown) => void;
  reportCadenceError: (error: unknown) => void;
  setInterval: (callback: () => void, delayMs: number) => unknown;
  state: ReminderPollingRuntimeState;
  pollIntervalMs: number;
  urgentIntervalMs: number;
  urgentLookaheadMinutes: number;
}

export type ReminderPollingBrowserHost = Pick<
  ReminderPollingRuntimeDeps,
  | keyof ForegroundCatchUpRuntimeHost
  | 'clearInterval'
  | 'setInterval'
>;

export function createBrowserReminderPollingHost(): ReminderPollingBrowserHost {
  return {
    clearInterval: (handle) => {
      globalThis.clearInterval(handle as ReturnType<typeof globalThis.setInterval>);
    },
    ...createBrowserForegroundCatchUpHost(),
    setInterval: (callback, delayMs) => globalThis.setInterval(callback, delayMs),
  };
}

interface ReminderPollingRuntimeHandle {
  dispose: () => void;
}

export function installReminderPollingRuntime(
  deps: ReminderPollingRuntimeDeps,
): ReminderPollingRuntimeHandle {
  let cancelled = false;
  let currentIntervalMs = deps.pollIntervalMs;
  let intervalHandle: unknown | null = null;

  const runTick = async (): Promise<void> => {
    if (cancelled || deps.state.running) return;
    deps.state.running = true;
    try {
      await deps.checkReminders();
      if (cancelled) return;
      const upcoming = await deps.getUpcomingReminders(deps.urgentLookaheadMinutes);
      if (cancelled) return;

      const targetIntervalMs = upcoming.length > 0
        ? deps.urgentIntervalMs
        : deps.pollIntervalMs;
      if (targetIntervalMs !== currentIntervalMs) {
        currentIntervalMs = targetIntervalMs;
        if (intervalHandle !== null) {
          deps.clearInterval(intervalHandle);
        }
        if (!cancelled) {
          intervalHandle = deps.setInterval(() => {
            void runTick();
          }, currentIntervalMs);
        }
      }
    } catch (error) {
      if (!cancelled) {
        deps.reportCadenceError(error);
      }
    } finally {
      deps.state.running = false;
    }
  };

  const reportActionRegistrationError = (error: unknown) => {
    if (!cancelled) {
      deps.reportActionRegistrationError(error);
    }
  };

  try {
    void Promise.resolve(deps.registerNotificationActions()).catch(reportActionRegistrationError);
  } catch (error) {
    reportActionRegistrationError(error);
  }
  void runTick();
  intervalHandle = deps.setInterval(() => {
    void runTick();
  }, currentIntervalMs);

  const foregroundCatchUp = installForegroundCatchUpController({
    ...deps,
    runCatchUp: () => {
      void runTick();
    },
  });

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
