import { describe, expect, it, vi } from 'vitest';

import {
  clearTaskCardCompletionRefresh,
  createTaskCardCompletionRefreshAbortToken,
  scheduleTaskCardCompletionRefresh,
  type TaskCardCompletionRefreshTimerHost,
} from './taskCardCompletionRefresh.runtime';

interface RecordedTimer {
  callback: () => void;
  delayMs: number;
}

function createFakeTimerHost(): TaskCardCompletionRefreshTimerHost & {
  __recorded: RecordedTimer[];
  __cleared: unknown[];
} {
  const recorded: RecordedTimer[] = [];
  const cleared: unknown[] = [];
  return {
    __recorded: recorded,
    __cleared: cleared,
    setTimeout: (callback, delayMs) => {
      const handle = recorded.length;
      recorded.push({ callback, delayMs });
      return handle;
    },
    clearTimeout: (handle) => { cleared.push(handle); },
  };
}

describe('createTaskCardCompletionRefreshAbortToken', () => {
  it('starts un-aborted', () => {
    const token = createTaskCardCompletionRefreshAbortToken();
    expect(token.aborted).toBe(false);
  });

  it('flips to aborted after abort()', () => {
    const token = createTaskCardCompletionRefreshAbortToken();
    token.abort();
    expect(token.aborted).toBe(true);
  });

  it('abort() is idempotent', () => {
    const token = createTaskCardCompletionRefreshAbortToken();
    token.abort();
    token.abort();
    expect(token.aborted).toBe(true);
  });
});

describe('scheduleTaskCardCompletionRefresh', () => {
  it('runs the refresh when no abort token is supplied', () => {
    const refresh = vi.fn();
    const timerHost = createFakeTimerHost();
    scheduleTaskCardCompletionRefresh({ delayMs: 200, refresh, timerHost });
    expect(timerHost.__recorded.length).toBe(1);
    timerHost.__recorded[0]!.callback();
    expect(refresh).toHaveBeenCalledOnce();
  });

  it('runs the refresh when the abort token is still active at fire time', () => {
    const refresh = vi.fn();
    const timerHost = createFakeTimerHost();
    const token = createTaskCardCompletionRefreshAbortToken();
    scheduleTaskCardCompletionRefresh({ delayMs: 200, refresh, timerHost, abortToken: token });
    timerHost.__recorded[0]!.callback();
    expect(refresh).toHaveBeenCalledOnce();
  });

  it('skips the refresh when the abort token is aborted before fire time', () => {
    const refresh = vi.fn();
    const timerHost = createFakeTimerHost();
    const token = createTaskCardCompletionRefreshAbortToken();
    scheduleTaskCardCompletionRefresh({ delayMs: 200, refresh, timerHost, abortToken: token });
    token.abort();
    timerHost.__recorded[0]!.callback();
    expect(refresh).not.toHaveBeenCalled();
  });

  it('exposes the underlying timer handle for explicit clearing', () => {
    const refresh = vi.fn();
    const timerHost = createFakeTimerHost();
    const token = createTaskCardCompletionRefreshAbortToken();
    const handle = scheduleTaskCardCompletionRefresh({ delayMs: 200, refresh, timerHost, abortToken: token });
    clearTaskCardCompletionRefresh(timerHost, handle);
    expect(timerHost.__cleared).toEqual([handle]);
  });

  it('the abort gate alone is enough to cancel even if the timer fires', () => {
    // The undo path may abort the token but fail to clear the timer
    // (e.g. the handle was lost across an unmount). The abort gate
    // inside scheduleTaskCardCompletionRefresh's wrapper is the
    // safety net that still suppresses the refresh.
    const refresh = vi.fn();
    const timerHost = createFakeTimerHost();
    const token = createTaskCardCompletionRefreshAbortToken();
    scheduleTaskCardCompletionRefresh({ delayMs: 200, refresh, timerHost, abortToken: token });
    token.abort();
    // Clear was NOT called — simulate the leaked-handle case.
    timerHost.__recorded[0]!.callback();
    expect(refresh).not.toHaveBeenCalled();
  });
});
