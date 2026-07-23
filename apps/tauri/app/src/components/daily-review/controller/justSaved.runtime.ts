interface DailyReviewJustSavedRuntimeState {
  resetTimer: unknown | null;
}

export interface DailyReviewJustSavedTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

interface DailyReviewJustSavedScheduleDeps {
  delayMs: number;
  isMounted: () => boolean;
  setJustSaved: (value: boolean) => void;
  state: DailyReviewJustSavedRuntimeState;
  timerHost: DailyReviewJustSavedTimerHost;
}

export function createDailyReviewJustSavedRuntimeState(): DailyReviewJustSavedRuntimeState {
  return { resetTimer: null };
}

export function createBrowserDailyReviewTimerHost(): DailyReviewJustSavedTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function cleanupDailyReviewJustSavedReset(
  state: DailyReviewJustSavedRuntimeState,
  timerHost: Pick<DailyReviewJustSavedTimerHost, 'clearTimeout'>,
): void {
  if (state.resetTimer === null) return;
  timerHost.clearTimeout(state.resetTimer);
  state.resetTimer = null;
}

export function scheduleDailyReviewJustSavedReset({
  delayMs,
  isMounted,
  setJustSaved,
  state,
  timerHost,
}: DailyReviewJustSavedScheduleDeps): void {
  cleanupDailyReviewJustSavedReset(state, timerHost);
  state.resetTimer = timerHost.setTimeout(() => {
    state.resetTimer = null;
    if (isMounted()) {
      setJustSaved(false);
    }
  }, delayMs);
}
