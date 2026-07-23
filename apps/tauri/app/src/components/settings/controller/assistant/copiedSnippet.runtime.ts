interface AssistantCopiedSnippetRuntimeState {
  resetTimer: unknown | null;
}

export interface AssistantCopiedSnippetTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

interface AssistantCopiedSnippetResetDeps<SnippetKey extends string> {
  delayMs: number;
  isMounted: () => boolean;
  key: SnippetKey;
  setCopiedSnippet: (
    updater: (current: SnippetKey | null) => SnippetKey | null,
  ) => void;
  state: AssistantCopiedSnippetRuntimeState;
  timerHost: AssistantCopiedSnippetTimerHost;
}

export function createAssistantCopiedSnippetRuntimeState(): AssistantCopiedSnippetRuntimeState {
  return { resetTimer: null };
}

export function createBrowserAssistantCopiedSnippetTimerHost(): AssistantCopiedSnippetTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function cleanupAssistantCopiedSnippetReset(
  state: AssistantCopiedSnippetRuntimeState,
  timerHost: Pick<AssistantCopiedSnippetTimerHost, 'clearTimeout'>,
): void {
  if (state.resetTimer === null) return;
  timerHost.clearTimeout(state.resetTimer);
  state.resetTimer = null;
}

export function scheduleAssistantCopiedSnippetReset<SnippetKey extends string>({
  delayMs,
  isMounted,
  key,
  setCopiedSnippet,
  state,
  timerHost,
}: AssistantCopiedSnippetResetDeps<SnippetKey>): void {
  cleanupAssistantCopiedSnippetReset(state, timerHost);
  state.resetTimer = timerHost.setTimeout(() => {
    state.resetTimer = null;
    if (!isMounted()) return;
    setCopiedSnippet((current) => (current === key ? null : current));
  }, delayMs);
}
