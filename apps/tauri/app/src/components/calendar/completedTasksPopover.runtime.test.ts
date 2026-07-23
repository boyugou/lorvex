import { describe, expect, it, vi } from 'vitest';

import {
  computeCompletedTasksPopoverPosition,
  focusCompletedTasksPopoverInitialTarget,
  restoreCompletedTasksPopoverTriggerFocus,
  scheduleCompletedTasksPopoverInitialFocus,
  shouldDismissCompletedTasksPopoverFromKeyEvent,
  type CompletedTasksPopoverFocusHost,
} from './completedTasksPopover.runtime';

function createFocusHost() {
  const callbacks = new Map<number, FrameRequestCallback>();
  let nextHandle = 1;
  const host: CompletedTasksPopoverFocusHost = {
    requestAnimationFrame: vi.fn((callback) => {
      const handle = nextHandle;
      nextHandle += 1;
      callbacks.set(handle, callback);
      return handle;
    }),
    cancelAnimationFrame: vi.fn((handle) => {
      callbacks.delete(handle);
    }),
  };

  return {
    callbacks,
    host,
  };
}

describe('shouldDismissCompletedTasksPopoverFromKeyEvent', () => {
  it('treats Escape as a dismiss key unless IME composition owns it', () => {
    expect(shouldDismissCompletedTasksPopoverFromKeyEvent({ key: 'Escape' })).toBe(true);
    expect(shouldDismissCompletedTasksPopoverFromKeyEvent({ key: 'Escape', isComposing: true })).toBe(false);
    expect(shouldDismissCompletedTasksPopoverFromKeyEvent({ key: 'Enter' })).toBe(false);
  });
});

describe('focusCompletedTasksPopoverInitialTarget', () => {
  it('focuses the first completed task button when focus is outside the panel', () => {
    const panel = { focus: vi.fn() };
    const firstItem = { focus: vi.fn() };

    const target = focusCompletedTasksPopoverInitialTarget({
      panel,
      firstItem,
      activeElement: null,
      isActiveElementInPanel: () => false,
    });

    expect(target).toBe('first-item');
    expect(firstItem.focus).toHaveBeenCalledTimes(1);
    expect(panel.focus).not.toHaveBeenCalled();
  });

  it('falls back to the panel when there is no task button to focus', () => {
    const panel = { focus: vi.fn() };

    const target = focusCompletedTasksPopoverInitialTarget({
      panel,
      firstItem: null,
      activeElement: null,
      isActiveElementInPanel: () => false,
    });

    expect(target).toBe('panel');
    expect(panel.focus).toHaveBeenCalledTimes(1);
  });

  it('preserves existing focus inside the panel', () => {
    const panel = { focus: vi.fn() };
    const firstItem = { focus: vi.fn() };
    const activeElement = {};

    const target = focusCompletedTasksPopoverInitialTarget({
      panel,
      firstItem,
      activeElement,
      isActiveElementInPanel: (candidate) => candidate === activeElement,
    });

    expect(target).toBe('active-element');
    expect(firstItem.focus).not.toHaveBeenCalled();
    expect(panel.focus).not.toHaveBeenCalled();
  });
});

describe('scheduleCompletedTasksPopoverInitialFocus', () => {
  it('moves focus to the first popover target on the next frame', () => {
    const { callbacks, host } = createFocusHost();
    const panel = { focus: vi.fn() };
    const firstItem = { focus: vi.fn() };

    scheduleCompletedTasksPopoverInitialFocus(host, () => ({
      panel,
      firstItem,
      activeElement: null,
      isActiveElementInPanel: () => false,
    }));

    expect(firstItem.focus).not.toHaveBeenCalled();
    callbacks.get(1)?.(0);
    expect(firstItem.focus).toHaveBeenCalledTimes(1);
    expect(panel.focus).not.toHaveBeenCalled();
  });

  it('lets callers cancel a pending initial focus move', () => {
    const { callbacks, host } = createFocusHost();
    const panel = { focus: vi.fn() };

    const cancel = scheduleCompletedTasksPopoverInitialFocus(host, () => ({
      panel,
      firstItem: null,
      activeElement: null,
      isActiveElementInPanel: () => false,
    }));
    cancel();
    callbacks.get(1)?.(0);

    expect(panel.focus).not.toHaveBeenCalled();
    expect(host.cancelAnimationFrame).toHaveBeenCalledWith(1);
  });
});

describe('restoreCompletedTasksPopoverTriggerFocus', () => {
  it('restores focus to the trigger on the next frame', () => {
    const { callbacks, host } = createFocusHost();
    const trigger = { focus: vi.fn() };

    restoreCompletedTasksPopoverTriggerFocus(host, () => trigger);

    expect(trigger.focus).not.toHaveBeenCalled();
    callbacks.get(1)?.(0);
    expect(trigger.focus).toHaveBeenCalledTimes(1);
  });
});

describe('computeCompletedTasksPopoverPosition', () => {
  it('clamps a fixed-position popover inside the viewport when the trigger is near the right edge', () => {
    const position = computeCompletedTasksPopoverPosition({
      triggerRect: {
        top: 120,
        bottom: 144,
        left: 380,
        width: 88,
      },
      popoverSize: {
        width: 220,
        height: 180,
      },
      viewport: {
        width: 480,
        height: 640,
      },
    });

    expect(position.left).toBe(252);
    expect(position.top).toBe(148);
    expect(position.maxHeight).toBe(180);
  });

  it('opens upward and clamps height when there is not enough room below the trigger', () => {
    const position = computeCompletedTasksPopoverPosition({
      triggerRect: {
        top: 560,
        bottom: 584,
        left: 24,
        width: 120,
      },
      popoverSize: {
        width: 220,
        height: 520,
      },
      viewport: {
        width: 390,
        height: 640,
      },
    });

    expect(position.openUpward).toBe(true);
    expect(position.top).toBe(236);
    expect(position.maxHeight).toBe(320);
    expect(position.left).toBe(24);
  });
});
