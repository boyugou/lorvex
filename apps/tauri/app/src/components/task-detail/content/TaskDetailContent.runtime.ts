import { TASK_STATUS } from '@lorvex/shared/types';

type TaskDetailShortcutTarget = Pick<Window, 'addEventListener' | 'removeEventListener'>;

export type TaskDetailShortcutAction =
  | 'complete'
  | 'defer'
  | 'reopen'
  | 'close'
  | 'blur-editable';

interface TaskDetailShortcutEventLike {
  key: string;
  target: EventTarget | null;
  isComposing?: boolean | undefined;
  shiftKey?: boolean | undefined;
  metaKey?: boolean | undefined;
  ctrlKey?: boolean | undefined;
}

interface TaskDetailShortcutState {
  isComplete: boolean;
  taskStatus: string | null | undefined;
}

interface TaskDetailShortcutRuntimeController extends TaskDetailShortcutState {
  handleClose: () => void | Promise<void>;
  handleComplete: () => void | Promise<void>;
  handleDefer: (date: string | null) => void | Promise<void>;
  handleReopen: () => void | Promise<void>;
}

interface TaskDetailShortcutRuntimeDeps {
  windowTarget?: TaskDetailShortcutTarget | undefined;
  getController: () => TaskDetailShortcutRuntimeController;
  shouldIgnoreShortcutTarget: (target: EventTarget | null) => boolean;
  /**
   * Predicate that decides whether `event.target` is an editable
   * surface (input, textarea, contenteditable). The two-step Esc
   * model (Esc-1 blurs the editable, Esc-2 closes the panel)
   * matches macOS conventions and lets a quick double-Esc dismiss
   * the panel from any focus depth, instead of requiring the user
   * to Tab away from the editor first.
   */
  isEditableTarget: (target: EventTarget | null) => boolean;
}

function hasCommandModifier(event: TaskDetailShortcutEventLike): boolean {
  return Boolean(event.metaKey || event.ctrlKey);
}

export function resolveTaskDetailShortcutAction(
  event: TaskDetailShortcutEventLike,
  state: TaskDetailShortcutState,
  shouldIgnoreShortcutTarget: (target: EventTarget | null) => boolean,
  isEditableTarget: (target: EventTarget | null) => boolean = () => false,
): TaskDetailShortcutAction | null {
  if (event.isComposing) return null;

  // Esc gets a special two-step handling that ignores the
  // shouldIgnoreShortcutTarget gate (which suppresses ALL shortcuts
  // inside editables). When Esc fires inside an editable, return
  // 'blur-editable' so the runtime can blur the field and let a
  // subsequent Esc — which now lands on a non-editable target —
  // close the panel.
  if (event.key === 'Escape') {
    if (isEditableTarget(event.target)) return 'blur-editable';
    return 'close';
  }

  if (shouldIgnoreShortcutTarget(event.target)) return null;

  if (event.key === 'Enter' && hasCommandModifier(event)) {
    if (event.shiftKey) {
      return !state.isComplete && state.taskStatus !== TASK_STATUS.cancelled ? 'defer' : null;
    }

    return state.isComplete ? 'reopen' : 'complete';
  }

  return null;
}

export function runTaskDetailShortcutAction(
  action: TaskDetailShortcutAction,
  controller: TaskDetailShortcutRuntimeController,
  blurTarget?: EventTarget | null,
): void {
  if (action === 'blur-editable') {
    // Move focus off the editable element. The element commit-on-blur
    // handlers fire as part of the blur, then a subsequent Esc lands
    // on a non-editable target and routes through the 'close' branch.
    const node = blurTarget as unknown as { blur?: () => void } | null;
    if (node && typeof node.blur === 'function') {
      node.blur();
    }
    return;
  }

  if (action === 'defer') {
    void controller.handleDefer(null);
    return;
  }

  if (action === 'reopen') {
    void controller.handleReopen();
    return;
  }

  if (action === 'complete') {
    void controller.handleComplete();
    return;
  }

  void controller.handleClose();
}

export function installTaskDetailShortcutRuntime({
  windowTarget,
  getController,
  shouldIgnoreShortcutTarget,
  isEditableTarget,
}: TaskDetailShortcutRuntimeDeps): () => void {
  if (!windowTarget) return () => {};

  const onKeyDown = (event: KeyboardEvent) => {
    const controller = getController();
    const action = resolveTaskDetailShortcutAction(event, controller, shouldIgnoreShortcutTarget, isEditableTarget);
    if (!action) return;

    event.preventDefault();
    runTaskDetailShortcutAction(action, controller, event.target);
  };

  windowTarget.addEventListener('keydown', onKeyDown);
  return () => windowTarget.removeEventListener('keydown', onKeyDown);
}
