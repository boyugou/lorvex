export interface TaskDetailRelationSearchTimerState {
  timer: unknown | null;
}

export interface TaskDetailRelationSearchTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export const TASK_DETAIL_RELATION_SEARCH_DEBOUNCE_MS = 250;

export function createBrowserTaskDetailRelationSearchTimerHost(): TaskDetailRelationSearchTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function createTaskDetailRelationSearchTimerState(): TaskDetailRelationSearchTimerState {
  return { timer: null };
}

export function scheduleTaskDetailRelationSearch({
  state,
  timerHost,
  runSearch,
  delayMs = TASK_DETAIL_RELATION_SEARCH_DEBOUNCE_MS,
}: {
  state: TaskDetailRelationSearchTimerState;
  timerHost: TaskDetailRelationSearchTimerHost;
  runSearch: () => void;
  delayMs?: number;
}): void {
  clearTaskDetailRelationSearchTimer(state, timerHost.clearTimeout);
  state.timer = timerHost.setTimeout(() => {
    state.timer = null;
    runSearch();
  }, delayMs);
}

export function clearTaskDetailRelationSearchTimer(
  state: TaskDetailRelationSearchTimerState,
  clearTimeout: (handle: unknown) => void,
): void {
  if (state.timer !== null) {
    clearTimeout(state.timer);
  }
  state.timer = null;
}
