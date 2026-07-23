interface ChangelogActionFeedbackRuntimeState {
  resetTimer: unknown | null;
}

export interface ChangelogActionFeedbackTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

interface ChangelogActionFeedbackResetDeps {
  delayMs: number;
  isMounted: () => boolean;
  setActionMessage: (value: string | null) => void;
  state: ChangelogActionFeedbackRuntimeState;
  timerHost: ChangelogActionFeedbackTimerHost;
}

export function createChangelogActionFeedbackRuntimeState(): ChangelogActionFeedbackRuntimeState {
  return { resetTimer: null };
}

export function createBrowserChangelogActionFeedbackTimerHost(): ChangelogActionFeedbackTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function cleanupChangelogActionFeedbackReset(
  state: ChangelogActionFeedbackRuntimeState,
  timerHost: Pick<ChangelogActionFeedbackTimerHost, 'clearTimeout'>,
): void {
  if (state.resetTimer === null) return;
  timerHost.clearTimeout(state.resetTimer);
  state.resetTimer = null;
}

export function scheduleChangelogActionFeedbackReset({
  delayMs,
  isMounted,
  setActionMessage,
  state,
  timerHost,
}: ChangelogActionFeedbackResetDeps): void {
  cleanupChangelogActionFeedbackReset(state, timerHost);
  state.resetTimer = timerHost.setTimeout(() => {
    state.resetTimer = null;
    if (isMounted()) {
      setActionMessage(null);
    }
  }, delayMs);
}
