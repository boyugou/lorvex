import { useCallback, useEffect, useRef, useState } from 'react';

import { useI18n } from '../i18n';
import { createTaskListKeyboardKeydownHandler } from './useTaskListKeyboard.keydown';
import {
  clearTaskListKeyboardHintDismiss,
  createBrowserTaskListKeyboardFocusHost,
  createBrowserTaskListKeyboardHost,
  createBrowserTaskListKeyboardHintTimerHost,
  installTaskListKeyboardRuntime,
  scheduleTaskListKeyboardHintDismiss,
  syncTaskListKeyboardFocus,
  type TaskListKeyboardHintTimerState,
} from './useTaskListKeyboard.runtime';
import type {
  TaskListKeyboardOptions,
  TaskListKeyboardState,
} from './useTaskListKeyboard.types';

export type {
  TaskListKeyboardActions,
  TaskListKeyboardOptions,
  TaskListKeyboardState,
} from './useTaskListKeyboard.types';

// Session-level flag: once the hint has been shown and dismissed, don't show again.
let hintShownThisSession = false;
const taskListKeyboardFocusHost = createBrowserTaskListKeyboardFocusHost();
const taskListKeyboardHost = createBrowserTaskListKeyboardHost();
const taskListKeyboardHintTimerHost = createBrowserTaskListKeyboardHintTimerHost();

export function useTaskListKeyboard({
  taskIds,
  onSelect,
  actions,
  disabled = false,
}: TaskListKeyboardOptions): TaskListKeyboardState {
  const { t } = useI18n();
  // Mirror `t` into a ref so the keydown effect (registered once
  // per `disabled` toggle) can announce the bulk-select hint in the
  // user's current locale without re-binding the listener every
  // render.
  const tRef = useRef(t);
  tRef.current = t;
  // Track focus by task ID, not array index, so reordering the list
  // (same length, different order) keeps focus on the same task.
  // Don't show focus indicator until user actually presses a key.
  const [focusedTaskId, setFocusedTaskId] = useState<string | null>(null);
  const [keyboardActive, setKeyboardActive] = useState(false);
  const [showHints, setShowHints] = useState(false);
  const hintTimerRef = useRef<TaskListKeyboardHintTimerState>({ handle: null });
  const taskIdsRef = useRef(taskIds);
  taskIdsRef.current = taskIds;
  const onSelectRef = useRef(onSelect);
  onSelectRef.current = onSelect;
  const actionsRef = useRef(actions);
  actionsRef.current = actions;

  // Resolve the current index from the tracked ID.
  // If the tracked task is gone (e.g. deleted), clamp to the nearest valid position.
  const resolveIndex = useCallback((): number => {
    if (taskIdsRef.current.length === 0) return -1;
    if (focusedTaskId == null) return 0;
    const idx = taskIdsRef.current.indexOf(focusedTaskId);
    return idx >= 0 ? idx : Math.min(taskIdsRef.current.length - 1, 0);
  }, [focusedTaskId]);

  // When the list changes, keep focus on the same task if it still exists;
  // otherwise fall back to the first item.
  useEffect(() => {
    if (taskIds.length === 0) {
      setFocusedTaskId(null);
      return;
    }
    if (focusedTaskId == null || !taskIds.includes(focusedTaskId)) {
      setFocusedTaskId(taskIds[0] ?? null);
    }
  }, [taskIds, focusedTaskId]);

  // Helper ref so the keydown handler can read the current resolved index
  // without re-registering the listener on every render.
  const resolveIndexRef = useRef(resolveIndex);
  resolveIndexRef.current = resolveIndex;

  // Hint bar management
  const activateHints = useCallback(() => {
    if (hintShownThisSession) return;
    hintShownThisSession = true;
    setShowHints(true);
    scheduleTaskListKeyboardHintDismiss({
      state: hintTimerRef.current,
      timerHost: taskListKeyboardHintTimerHost,
      onDismiss: () => setShowHints(false),
    });
  }, []);

  const dismissHints = useCallback(() => {
    setShowHints(false);
    clearTaskListKeyboardHintDismiss(
      hintTimerRef.current,
      taskListKeyboardHintTimerHost.clearTimeout,
    );
  }, []);

  // Clean up hint timer on unmount.
  // We deliberately read `hintTimerRef.current` at cleanup time, not at
  // effect-mount time, because the timer handle is set later via
  // `scheduleTaskListKeyboardHintDismiss`. ESLint warns that the ref's
  // `.current` may have changed by cleanup — that is precisely the
  // intent here.
  useEffect(() => {
    return () => {
      clearTaskListKeyboardHintDismiss(
        // eslint-disable-next-line react-hooks/exhaustive-deps
        hintTimerRef.current,
        taskListKeyboardHintTimerHost.clearTimeout,
      );
    };
  }, []);

  // Only show focus when user has interacted with keyboard.
  // Before first keypress, focusedId is null → no highlight shown.
  const resolvedId = focusedTaskId != null && taskIds.includes(focusedTaskId)
    ? focusedTaskId
    : (taskIds[0] ?? null);
  const focusedId = keyboardActive ? resolvedId : null;

  const isFocused = useCallback(
    (taskId: string) => taskId === focusedId,
    [focusedId],
  );

  const resetFocus = useCallback(
    () => setFocusedTaskId(taskIdsRef.current[0] ?? null),
    [],
  );

  // Imperative focus setter for surfaces that layer
  // secondary keyboard bindings (cluster-jump shift+j/k in the
  // dependency graph). Activates the keyboard-focused state so the
  // focus ring becomes visible on the jumped-to row even if the user
  // arrived there without first pressing j/k.
  const focusTaskId = useCallback((taskId: string) => {
    if (!taskIdsRef.current.includes(taskId)) return;
    setFocusedTaskId(taskId);
    setKeyboardActive(true);
  }, []);

  const activateHintsRef = useRef(activateHints);
  activateHintsRef.current = activateHints;
  const dismissHintsRef = useRef(dismissHints);
  dismissHintsRef.current = dismissHints;
  // mirror keyboardActive into a ref so the SR-safety
  // guard inside the keydown effect reads the current value without
  // re-binding the listener on every toggle.
  const keyboardActiveRef = useRef(keyboardActive);
  keyboardActiveRef.current = keyboardActive;

  useEffect(() => {
    const onKeyDown = createTaskListKeyboardKeydownHandler({
      actionsRef,
      activateHints: () => activateHintsRef.current(),
      dismissHints: () => dismissHintsRef.current(),
      keyboardActiveRef,
      onSelectRef,
      resolveIndex: () => resolveIndexRef.current(),
      setFocusedTaskId,
      setKeyboardActive,
      taskIdsRef,
      taskListKeyboardHost,
      tRef,
    });

    return installTaskListKeyboardRuntime({
      disabled,
      onKeyDown,
      ...taskListKeyboardHost,
    });
  }, [disabled]);

  // Scroll the focused element into view AND move DOM focus so
  // screen readers follow the visual focus ring. Every task card
  // renders an inner `<button>` with an accessible name; prefer
  // that so SR announces "<title>, button".
  //
  // The scroll uses `behavior: 'auto'` (matching native OS focus
  // navigation), not `'smooth'`: a continuous scroll animation on
  // every j/k / arrow keypress is a vestibular trigger for
  // keyboard power-users and feels laggy. `'auto'` also sidesteps
  // `prefers-reduced-motion` entirely.
  useEffect(() => {
    syncTaskListKeyboardFocus({
      focusedId,
      focusHost: taskListKeyboardFocusHost,
    });
  }, [focusedId, taskIds]);

  return { focusedId, focusTaskId, isFocused, resetFocus, showKeyboardHints: showHints };
}
