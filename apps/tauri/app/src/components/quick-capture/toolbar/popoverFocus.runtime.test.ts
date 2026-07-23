import { describe, expect, it, vi } from 'vitest';

import {
  restoreQuickCapturePopoverTriggerFocus,
  type QuickCapturePopoverFocusHost,
} from './popoverFocus.runtime';

function createFocusHost() {
  const callbacks = new Map<number, FrameRequestCallback>();
  let nextHandle = 1;
  const host: QuickCapturePopoverFocusHost = {
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

describe('restoreQuickCapturePopoverTriggerFocus', () => {
  it('restores focus to the trigger on the next frame', () => {
    const { callbacks, host } = createFocusHost();
    const trigger = { focus: vi.fn() };

    restoreQuickCapturePopoverTriggerFocus(host, () => trigger);

    expect(trigger.focus).not.toHaveBeenCalled();
    callbacks.get(1)?.(0);
    expect(trigger.focus).toHaveBeenCalledTimes(1);
  });

  it('lets callers cancel a pending focus restore', () => {
    const { callbacks, host } = createFocusHost();
    const trigger = { focus: vi.fn() };

    const cancel = restoreQuickCapturePopoverTriggerFocus(host, () => trigger);
    cancel();
    callbacks.get(1)?.(0);

    expect(trigger.focus).not.toHaveBeenCalled();
    expect(host.cancelAnimationFrame).toHaveBeenCalledWith(1);
  });
});
