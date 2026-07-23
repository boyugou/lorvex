import { announce } from '../announce';
import type { TranslationKey } from '../i18n';
import { shouldIgnoreShortcut } from '../shortcutGuard';
import { priorityFromKeyboardKey } from './useTaskListKeyboard.logic';
import {
  isTaskListKeyboardDocumentBodyTarget,
  type TaskListKeyboardHost,
} from './useTaskListKeyboard.runtime';
import type { TaskListKeyboardActions } from './useTaskListKeyboard.types';

interface RefLike<T> {
  current: T;
}

interface TaskListKeyboardKeydownHandlerDeps {
  actionsRef: RefLike<TaskListKeyboardActions | undefined>;
  activateHints: () => void;
  dismissHints: () => void;
  keyboardActiveRef: RefLike<boolean>;
  onSelectRef: RefLike<((taskId: string) => void) | undefined>;
  resolveIndex: () => number;
  setFocusedTaskId: (taskId: string | null) => void;
  setKeyboardActive: (active: boolean) => void;
  taskIdsRef: RefLike<string[]>;
  taskListKeyboardHost: TaskListKeyboardHost;
  tRef: RefLike<(key: TranslationKey) => string>;
}

export function createTaskListKeyboardKeydownHandler({
  actionsRef,
  activateHints,
  dismissHints,
  keyboardActiveRef,
  onSelectRef,
  resolveIndex,
  setFocusedTaskId,
  setKeyboardActive,
  taskIdsRef,
  taskListKeyboardHost,
  tRef,
}: TaskListKeyboardKeydownHandlerDeps): (event: KeyboardEvent) => void {
  return (event: KeyboardEvent) => {
    if (taskIdsRef.current.length === 0) return;

    const currentIdx = resolveIndex();
    const getFocusedId = () =>
      currentIdx >= 0 ? taskIdsRef.current[currentIdx] : undefined;

    // Alt+Arrow = reorder (handled before the modifier guard)
    if (event.altKey && !event.metaKey && !event.ctrlKey && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
      if (shouldIgnoreShortcut(event.target)) return;
      const id = getFocusedId();
      if (id && actionsRef.current?.onReorder) {
        const direction: -1 | 1 = event.key === 'ArrowUp' ? -1 : 1;
        event.preventDefault();
        actionsRef.current.onReorder(id, direction);
        // Focus stays on the same task ID (it moved, index changes, but ID is stable)
      }
      return;
    }

    // Shift+F10 = open context menu (standard a11y shortcut, handled before the modifier guard)
    if (event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey && event.key === 'F10') {
      if (shouldIgnoreShortcut(event.target)) return;
      const id = getFocusedId();
      if (id && actionsRef.current?.onOpenContextMenu) {
        event.preventDefault();
        actionsRef.current.onOpenContextMenu(id);
      }
      return;
    }

    // Shift+Arrow = extend multi-select range (handled before the modifier guard)
    if (event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey
        && (event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
      if (shouldIgnoreShortcut(event.target)) return;
      if (actionsRef.current?.onExtendSelection) {
        event.preventDefault();
        setKeyboardActive(true);
        const direction: 'up' | 'down' = event.key === 'ArrowUp' ? 'up' : 'down';
        const focused = getFocusedId() ?? null;
        const nextFocused = actionsRef.current.onExtendSelection(direction, focused);
        if (nextFocused != null) {
          setFocusedTaskId(nextFocused);
        }
      }
      return;
    }

    // Ctrl/Cmd+A = select all visible rows in the list (handled before the modifier guard)
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey
        && (event.key === 'a' || event.key === 'A')) {
      if (shouldIgnoreShortcut(event.target)) return;
      if (actionsRef.current?.onSelectAll) {
        event.preventDefault();
        actionsRef.current.onSelectAll();
      }
      return;
    }

    // Ctrl+Arrow = move task to adjacent column/quadrant (handled before the modifier guard)
    if ((event.ctrlKey || event.metaKey) && !event.altKey && !event.shiftKey
        && (event.key === 'ArrowLeft' || event.key === 'ArrowRight' || event.key === 'ArrowUp' || event.key === 'ArrowDown')) {
      if (shouldIgnoreShortcut(event.target)) return;
      const id = getFocusedId();
      if (id && actionsRef.current?.onMoveInView) {
        const direction: -1 | 1 = (event.key === 'ArrowLeft' || event.key === 'ArrowUp') ? -1 : 1;
        const axis: 'horizontal' | 'vertical' =
          (event.key === 'ArrowLeft' || event.key === 'ArrowRight') ? 'horizontal' : 'vertical';
        const handled = actionsRef.current.onMoveInView(id, direction, axis);
        if (handled !== false) {
          event.preventDefault();
        }
      }
      return;
    }

    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (shouldIgnoreShortcut(event.target)) return;

    // bare single-key shortcuts (j/k/x/c/s/d/e/t/w/m/y
    // /r/a/f/1–3/./Esc) collided with screen-reader virtual-cursor
    // keys. When a VoiceOver / NVDA / TalkBack user navigates in
    // reading-mode, DOM focus stays on <body> — so we can use
    // "target is body and we haven't activated the keyboard flow
    // yet" as a signal the user isn't deliberately driving the
    // task list. The exit condition is intentionally narrow:
    // - once keyboardActive is true (they pressed j/k/arrow/Enter
    //   intentionally), subsequent bare keys work as before;
    // - navigation keys (j/k/arrows) STILL fire so the user can
    //   activate the flow from body focus;
    // - the context-menu + selection-toggle keys (. and Space) are
    //   let through because they have less collision surface with
    //   SR shortcuts.
    const isNavigationKey =
      event.key === 'j' || event.key === 'k' ||
      event.key === 'ArrowUp' || event.key === 'ArrowDown' ||
      event.key === 'Enter' || event.key === 'Escape' ||
      event.key === ' ' || event.key === '.';
    if (
      !keyboardActiveRef.current
      && !isNavigationKey
      && isTaskListKeyboardDocumentBodyTarget(event.target, taskListKeyboardHost)
    ) {
      return;
    }

    // Dismiss keyboard hints on any action key (not j/k/arrows which activate them)
    const isNavKey = event.key === 'j' || event.key === 'k' || event.key === 'ArrowDown' || event.key === 'ArrowUp';
    if (!isNavKey) {
      dismissHints();
    }

    const priorityShortcut = priorityFromKeyboardKey(event.key);
    if (event.key === 'j' || event.key === 'ArrowDown') {
      event.preventDefault();
      setKeyboardActive(true);
      activateHints();
      const ids = taskIdsRef.current;
      const nextIdx = Math.min(currentIdx + 1, ids.length - 1);
      setFocusedTaskId(ids[nextIdx] ?? null);
    } else if (event.key === 'k' || event.key === 'ArrowUp') {
      event.preventDefault();
      setKeyboardActive(true);
      activateHints();
      const ids = taskIdsRef.current;
      const prevIdx = Math.max(currentIdx - 1, 0);
      setFocusedTaskId(ids[prevIdx] ?? null);
    } else if (event.key === ' ') {
      // Space = toggle selection (no-op if onToggleSelected not provided)
      const id = getFocusedId();
      if (id && actionsRef.current?.onToggleSelected) {
        event.preventDefault();
        // Enable selection mode if not already active
        if (!actionsRef.current.selectionModeActive) {
          actionsRef.current.setSelectionModeEnabled?.(true);
        }
        actionsRef.current.onToggleSelected(id);
        // Do NOT advance focus — user stays on same task
      }
    } else if (
      event.key === 'Escape'
      && !actionsRef.current?.selectionModeActive
      && actionsRef.current?.hasSelection
      && actionsRef.current?.onClearSelection
    ) {
      // Escape clears modifier-driven multi-select before it exits
      // explicit checkbox mode.
      event.preventDefault();
      actionsRef.current.onClearSelection();
    } else if (event.key === 'Escape' && actionsRef.current?.selectionModeActive) {
      // Escape exits selection mode
      event.preventDefault();
      actionsRef.current.setSelectionModeEnabled?.(false);
    } else if (actionsRef.current?.selectionModeActive) {
      // in selection mode, non-selection keys were
      // silently swallowed with no UI feedback — a user hitting
      // `m` expecting bulk-move got nothing and could not tell if
      // the key was lost or if the action didn't exist. Announce
      // to screen readers and toast-less users via the shared
      // announce() live region. Guard on the user actually
      // pressing a printable / named key (not just a modifier
      // keydown heartbeat).
      if (event.key.length === 1 || event.key === 'Enter' || event.key === '.') {
        event.preventDefault();
        announce(tRef.current('tasks.bulkSelectHint'));
        // Dispatch a window-level event so the visible
        // BulkActionBar can flash, giving sighted users the same
        // signal screen-reader users get from the announce() call
        // above and surfacing the fact that single-key shortcuts
        // are intentionally suppressed in bulk-select mode. The
        // CustomEvent is namespaced so other listeners can't be
        // triggered by accident.
        if (typeof window !== 'undefined') {
          window.dispatchEvent(new CustomEvent('lorvex:bulk-select-miss'));
        }
      }
      return;
    } else if (event.key === 'Enter') {
      const id = getFocusedId();
      if (id && onSelectRef.current) {
        event.preventDefault();
        onSelectRef.current(id);
      }
    } else if (event.key === 'x') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onComplete) {
        event.preventDefault();
        actionsRef.current.onComplete(id);
      }
    } else if (event.key === 'c') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onCancelTask) {
        event.preventDefault();
        actionsRef.current.onCancelTask(id);
      }
    } else if (event.key === 'S') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onDeferNextWeek) {
        event.preventDefault();
        actionsRef.current.onDeferNextWeek(id);
      }
    } else if (event.key === 's') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onDefer) {
        event.preventDefault();
        actionsRef.current.onDefer(id);
      }
    } else if (event.key === 'e') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onEdit) {
        event.preventDefault();
        actionsRef.current.onEdit(id);
      }
    } else if (event.key === 'D') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onSetDueTomorrow) {
        event.preventDefault();
        actionsRef.current.onSetDueTomorrow(id);
      }
    } else if (event.key === 'd') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onSetDueToday) {
        event.preventDefault();
        actionsRef.current.onSetDueToday(id);
      }
    } else if (event.key === 't') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onSetDueDate) {
        event.preventDefault();
        actionsRef.current.onSetDueDate(id);
      }
    } else if (event.key === 'w') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onSetDuration) {
        event.preventDefault();
        actionsRef.current.onSetDuration(id);
      }
    } else if (priorityShortcut != null) {
      const id = getFocusedId();
      if (id && actionsRef.current?.onSetPriority) {
        event.preventDefault();
        actionsRef.current.onSetPriority(id, priorityShortcut);
      }
    } else if (event.key === 'R') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onSetRecurrence) {
        event.preventDefault();
        actionsRef.current.onSetRecurrence(id);
      }
    } else if (event.key === 'r') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onToggleRecurrence) {
        event.preventDefault();
        actionsRef.current.onToggleRecurrence(id);
      }
    } else if (event.key === 'a') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onPromoteToActive) {
        event.preventDefault();
        actionsRef.current.onPromoteToActive(id);
      }
    } else if (event.key === 'm') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onMoveToList) {
        event.preventDefault();
        actionsRef.current.onMoveToList(id);
      }
    } else if (event.key === 'y') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onDuplicate) {
        event.preventDefault();
        actionsRef.current.onDuplicate(id);
      }
    } else if (event.key === '.') {
      const id = getFocusedId();
      if (id && actionsRef.current?.onOpenContextMenu) {
        event.preventDefault();
        actionsRef.current.onOpenContextMenu(id);
      }
    }
  };
}
