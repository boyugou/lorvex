export interface TaskListKeyboardRuntimeDeps {
  addWindowKeydownListener:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  disabled: boolean;
  onKeyDown: (event: KeyboardEvent) => void;
}

export interface TaskListKeyboardHintTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

interface TaskListKeyboardFocusableElement {
  focus: (options?: FocusOptions) => void;
}

interface TaskListKeyboardTaskElement {
  contains: (element: unknown) => boolean;
  isConnected: boolean;
  querySelector: (selectors: string) => TaskListKeyboardFocusableElement | null;
  scrollIntoView: (options?: ScrollIntoViewOptions) => void;
}

export interface TaskListKeyboardFocusHost {
  findTaskElement: (taskId: string) => TaskListKeyboardTaskElement | null;
  getActiveElement: () => unknown;
}

interface TaskListKeyboardDocumentBodyHost {
  getDocumentBody: () => EventTarget | null;
}

export type TaskListKeyboardHost =
  & Pick<TaskListKeyboardRuntimeDeps, 'addWindowKeydownListener'>
  & TaskListKeyboardDocumentBodyHost;

export interface TaskListKeyboardHintTimerState {
  handle: unknown | null;
}

const TASK_LIST_KEYBOARD_FOCUSABLE_SELECTOR =
  'button[aria-label], [role="button"][tabindex], button:not([disabled])';
export const TASK_LIST_KEYBOARD_HINT_DISMISS_DELAY_MS = 8_000;

function escapeTaskListKeyboardTaskIdSelectorValue(taskId: string): string {
  return taskId.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

export function createBrowserTaskListKeyboardHintTimerHost(): TaskListKeyboardHintTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function createBrowserTaskListKeyboardFocusHost(): TaskListKeyboardFocusHost {
  return {
    findTaskElement: typeof document === 'undefined'
      ? () => null
      : (taskId) => document.querySelector(
          `[data-task-id="${escapeTaskListKeyboardTaskIdSelectorValue(taskId)}"]`,
        ) as TaskListKeyboardTaskElement | null,
    getActiveElement: () =>
      typeof document === 'undefined' ? null : document.activeElement,
  };
}

export function createBrowserTaskListKeyboardHost(): TaskListKeyboardHost {
  return {
    addWindowKeydownListener: typeof window === 'undefined'
      ? null
      : (listener) => {
          window.addEventListener('keydown', listener);
          return () => window.removeEventListener('keydown', listener);
        },
    getDocumentBody: () =>
      typeof document === 'undefined' ? null : document.body,
  };
}

export function installTaskListKeyboardRuntime({
  addWindowKeydownListener,
  disabled,
  onKeyDown,
}: TaskListKeyboardRuntimeDeps): () => void {
  if (disabled || !addWindowKeydownListener) {
    return () => {};
  }

  return addWindowKeydownListener(onKeyDown);
}

export function isTaskListKeyboardDocumentBodyTarget(
  target: EventTarget | null,
  host: TaskListKeyboardDocumentBodyHost,
): boolean {
  const body = host.getDocumentBody();
  return body !== null && target === body;
}

export function syncTaskListKeyboardFocus({
  focusedId,
  focusHost,
  focusableSelector = TASK_LIST_KEYBOARD_FOCUSABLE_SELECTOR,
}: {
  focusedId: string | null;
  focusHost: TaskListKeyboardFocusHost;
  focusableSelector?: string;
}): void {
  if (!focusedId) return;

  const taskElement = focusHost.findTaskElement(focusedId);
  if (!taskElement || !taskElement.isConnected) return;

  // keyboard list-navigation must keep the
  // highlighted row pinned to the cursor on every keystroke.
  // `behavior: 'auto'` honors any ancestor `scroll-behavior:
  // smooth`, which on macOS Safari coalesces queued scrolls and
  // leaves the highlight visually trailing during ↓-skim. Force
  // `'instant'` so the viewport snaps in lockstep with focus
  // (matches CommandPalette).
  taskElement.scrollIntoView({ block: 'nearest', behavior: 'instant' });

  const focusable = taskElement.querySelector(focusableSelector);
  if (!focusable) return;

  const active = focusHost.getActiveElement();
  if (active === focusable) return;
  if (active && taskElement.contains(active)) return;

  focusable.focus({ preventScroll: true });
}

export function scheduleTaskListKeyboardHintDismiss({
  state,
  timerHost,
  onDismiss,
  delayMs = TASK_LIST_KEYBOARD_HINT_DISMISS_DELAY_MS,
}: {
  state: TaskListKeyboardHintTimerState;
  timerHost: TaskListKeyboardHintTimerHost;
  onDismiss: () => void;
  delayMs?: number;
}): void {
  clearTaskListKeyboardHintDismiss(state, timerHost.clearTimeout);
  state.handle = timerHost.setTimeout(() => {
    state.handle = null;
    onDismiss();
  }, delayMs);
}

export function clearTaskListKeyboardHintDismiss(
  state: TaskListKeyboardHintTimerState,
  clearTimer: (handle: unknown) => void,
): void {
  if (state.handle !== null) {
    clearTimer(state.handle);
  }
  state.handle = null;
}
