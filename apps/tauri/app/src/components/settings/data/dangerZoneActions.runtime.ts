type DangerZoneResetTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface DangerZoneResetTimerHost {
  setTimeout: (
    callback: () => void,
    delayMs: number,
  ) => DangerZoneResetTimerHandle;
}

export function createBrowserDangerZoneResetTimerHost(): DangerZoneResetTimerHost {
  return {
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function scheduleDangerZoneResetReload(
  delayMs: number,
  reload: () => void,
  timerHost: DangerZoneResetTimerHost,
): void {
  timerHost.setTimeout(() => {
    reload();
  }, delayMs);
}
