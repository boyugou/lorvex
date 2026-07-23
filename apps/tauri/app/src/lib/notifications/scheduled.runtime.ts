interface ScheduledNotificationsRuntimeState {
  running: boolean;
}

interface ScheduledNotificationsRuntimeDeps {
  checkHabitReminders: () => Promise<void>;
  checkScheduled: () => Promise<void>;
  clearInterval: (handle: unknown) => void;
  reportTickError: (error: unknown) => void;
  setInterval: (callback: () => void, delayMs: number) => unknown;
  state: ScheduledNotificationsRuntimeState;
  pollIntervalMs: number;
}

export type ScheduledNotificationsIntervalHost = Pick<
  ScheduledNotificationsRuntimeDeps,
  'clearInterval' | 'setInterval'
>;

export function createBrowserScheduledNotificationsIntervalHost(): ScheduledNotificationsIntervalHost {
  return {
    clearInterval: (handle) => {
      globalThis.clearInterval(handle as ReturnType<typeof globalThis.setInterval>);
    },
    setInterval: (callback, delayMs) => globalThis.setInterval(callback, delayMs),
  };
}

interface ScheduledNotificationsRuntimeHandle {
  dispose: () => void;
}

export function installScheduledNotificationsRuntime(
  deps: ScheduledNotificationsRuntimeDeps,
): ScheduledNotificationsRuntimeHandle {
  let cancelled = false;
  let intervalHandle: unknown | null = null;

  const runTick = (): void => {
    if (cancelled || deps.state.running) return;
    deps.state.running = true;
    void (async () => {
      await deps.checkScheduled();
      await deps.checkHabitReminders();
    })()
      .catch((error) => {
        if (!cancelled) {
          deps.reportTickError(error);
        }
      })
      .finally(() => {
        deps.state.running = false;
      });
  };

  runTick();
  intervalHandle = deps.setInterval(runTick, deps.pollIntervalMs);

  return {
    dispose: () => {
      cancelled = true;
      if (intervalHandle !== null) {
        deps.clearInterval(intervalHandle);
        intervalHandle = null;
      }
    },
  };
}
