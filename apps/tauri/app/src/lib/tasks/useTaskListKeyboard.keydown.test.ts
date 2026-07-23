import { describe, expect, it, vi } from 'vitest';

import { createTaskListKeyboardKeydownHandler } from './useTaskListKeyboard.keydown';
import type { TaskListKeyboardActions } from './useTaskListKeyboard.types';

function makeHandler(actions: TaskListKeyboardActions) {
  return createTaskListKeyboardKeydownHandler({
    actionsRef: { current: actions },
    activateHints: vi.fn(),
    dismissHints: vi.fn(),
    keyboardActiveRef: { current: true },
    onSelectRef: { current: undefined },
    resolveIndex: () => 0,
    setFocusedTaskId: vi.fn(),
    setKeyboardActive: vi.fn(),
    taskIdsRef: { current: ['task-1'] },
    taskListKeyboardHost: {
      addWindowKeydownListener: null,
      getDocumentBody: () => null,
    },
    tRef: { current: (key) => key },
  });
}

function makeCtrlArrowEvent(key: 'ArrowLeft' | 'ArrowRight' | 'ArrowUp' | 'ArrowDown') {
  return {
    altKey: false,
    ctrlKey: true,
    key,
    metaKey: false,
    preventDefault: vi.fn(),
    shiftKey: false,
    target: null,
  } as unknown as KeyboardEvent & { preventDefault: ReturnType<typeof vi.fn> };
}

describe('createTaskListKeyboardKeydownHandler move-in-view shortcuts', () => {
  it('does not consume Ctrl+vertical arrows when the view rejects the vertical axis', () => {
    const onMoveInView = vi.fn(() => false);
    const handler = makeHandler({ onMoveInView });
    const event = makeCtrlArrowEvent('ArrowUp');

    handler(event);

    expect(onMoveInView).toHaveBeenCalledWith('task-1', -1, 'vertical');
    expect(event.preventDefault).not.toHaveBeenCalled();
  });

  it('consumes Ctrl+horizontal arrows when the view accepts the horizontal axis', () => {
    const onMoveInView = vi.fn(() => true);
    const handler = makeHandler({ onMoveInView });
    const event = makeCtrlArrowEvent('ArrowRight');

    handler(event);

    expect(onMoveInView).toHaveBeenCalledWith('task-1', 1, 'horizontal');
    expect(event.preventDefault).toHaveBeenCalledOnce();
  });

  it('preserves legacy void handlers as handled shortcuts', () => {
    const onMoveInView = vi.fn();
    const handler = makeHandler({ onMoveInView });
    const event = makeCtrlArrowEvent('ArrowLeft');

    handler(event);

    expect(onMoveInView).toHaveBeenCalledWith('task-1', -1, 'horizontal');
    expect(event.preventDefault).toHaveBeenCalledOnce();
  });
});
