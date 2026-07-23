type TaskNotesPersistBody = (draft?: string) => Promise<boolean>;

interface TaskNotesPendingSave {
  persistBody: TaskNotesPersistBody;
  markdown: string;
}

export interface TaskNotesSaveState {
  timer: unknown | null;
  pending: TaskNotesPendingSave | null;
}

export interface TaskNotesSaveTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export const TASK_NOTES_SAVE_DEBOUNCE_MS = 800;

export function createBrowserTaskNotesSaveTimerHost(): TaskNotesSaveTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function createTaskNotesSaveState(): TaskNotesSaveState {
  return {
    timer: null,
    pending: null,
  };
}

export function scheduleTaskNotesSave({
  state,
  timerHost,
  pending,
  delayMs = TASK_NOTES_SAVE_DEBOUNCE_MS,
}: {
  state: TaskNotesSaveState;
  timerHost: TaskNotesSaveTimerHost;
  pending: TaskNotesPendingSave;
  delayMs?: number;
}): void {
  if (state.timer !== null) {
    timerHost.clearTimeout(state.timer);
  }
  state.pending = pending;
  state.timer = timerHost.setTimeout(() => {
    state.timer = null;
    const nextPending = state.pending;
    state.pending = null;
    if (nextPending) void nextPending.persistBody(nextPending.markdown);
  }, delayMs);
}

export function flushTaskNotesSave(
  state: TaskNotesSaveState,
  clearTimeout: (handle: unknown) => void,
): void {
  if (state.timer !== null) {
    clearTimeout(state.timer);
  }
  state.timer = null;
  const pending = state.pending;
  state.pending = null;
  if (pending) void pending.persistBody(pending.markdown);
}
