import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// vitest runs `app/` in `environment: 'node'`, and there's no React
// renderer in the workspace. We stand in a tiny harness that returns
// the body of `useCallback` directly — enough to exercise the
// `showSnapshotUndoToast` dispatcher without a render host. (Same
// pattern used by `useLazyRef.test.ts`.)
vi.mock('react', () => ({
  useCallback: <T>(fn: T): T => fn,
}));

vi.mock('@tanstack/react-query', () => ({
  useQueryClient: () => ({ tag: 'qc' }),
}));

const undoDeleteEntityMock = vi.fn();
vi.mock('@/lib/ipc/snapshotUndo', () => ({
  undoDeleteEntity: (...args: unknown[]) => undoDeleteEntityMock(...args),
}));

const reportClientErrorMock = vi.fn();
vi.mock('../errors/errorLogging', () => ({
  reportClientError: (...args: unknown[]) => reportClientErrorMock(...args),
}));

const tMock = vi.fn((key: string) => `[${key}]`);
vi.mock('../i18n', () => ({
  useI18n: () => ({ t: tMock }),
}));

const toastSuccess = vi.fn();
const toastInfo = vi.fn();
const toastError = vi.fn();
const toastWarning = vi.fn();
vi.mock('../notifications/toast', () => ({
  toast: {
    success: (...args: unknown[]) => toastSuccess(...args),
    info: (...args: unknown[]) => toastInfo(...args),
    error: (...args: unknown[]) => toastError(...args),
    warning: (...args: unknown[]) => toastWarning(...args),
  },
}));

import { useSnapshotUndoToast } from './useSnapshotUndoToast';

beforeEach(() => {
  vi.useFakeTimers();
  undoDeleteEntityMock.mockReset();
  reportClientErrorMock.mockReset();
  tMock.mockClear();
  toastSuccess.mockReset();
  toastInfo.mockReset();
  toastError.mockReset();
  toastWarning.mockReset();
});

afterEach(() => {
  vi.useRealTimers();
});

interface CapturedAction {
  label: string;
  onClick: () => void | Promise<void>;
}

/** Pull the `(message, action, context)` triple out of the
 *  most-recent `toast.success` call. */
function lastSuccessCall() {
  const call = toastSuccess.mock.calls.at(-1);
  if (!call) throw new Error('expected toast.success to have been called');
  const [message, action, context] = call as [string, CapturedAction, string];
  return { message, action, context };
}

describe('useSnapshotUndoToast', () => {
  it('surfaces a success toast keyed off the per-call translation keys', () => {
    const show = useSnapshotUndoToast();
    const invalidate = vi.fn();

    show({
      kind: 'list',
      token: 'tok-1',
      successKey: 'list.deleteSuccess',
      restoredKey: 'list.restored',
      invalidate,
    });

    const { message, action, context } = lastSuccessCall();
    expect(message).toBe('[list.deleteSuccess]');
    expect(action.label).toBe('[common.undo]');
    expect(context).toBe('tok-1');
  });

  it('uses undo.expired as the default failure key (no calendar.* leak)', async () => {
    undoDeleteEntityMock.mockRejectedValue(new Error('TTL'));
    const show = useSnapshotUndoToast();

    show({
      kind: 'list',
      token: 'tok-2',
      successKey: 'list.deleteSuccess',
      restoredKey: 'list.restored',
      invalidate: vi.fn(),
    });

    const { action } = lastSuccessCall();
    await action.onClick();
    await vi.runAllTimersAsync();

    expect(toastError).toHaveBeenCalledWith('[undo.expired]');
    // The legacy cross-domain key must NOT appear from this code path.
    expect(toastError).not.toHaveBeenCalledWith('[calendar.undoExpired]');
  });

  it('runs invalidate + restored toast on undo success', async () => {
    undoDeleteEntityMock.mockResolvedValue({ ok: true });
    const show = useSnapshotUndoToast();
    const invalidate = vi.fn();

    show({
      kind: 'calendar_event',
      token: 'tok-3',
      successKey: 'calendar.eventDeleted',
      restoredKey: 'calendar.eventRestored',
      invalidate,
    });

    await lastSuccessCall().action.onClick();
    await vi.runAllTimersAsync();

    expect(undoDeleteEntityMock).toHaveBeenCalledWith('tok-3');
    expect(invalidate).toHaveBeenCalledTimes(1);
    expect(toastInfo).toHaveBeenCalledWith('[calendar.eventRestored]');
  });

  it('fires onAfterUndoExpired only when the undo TTL elapses without a click', () => {
    const show = useSnapshotUndoToast();
    const onAfterUndoExpired = vi.fn();

    show({
      kind: 'list',
      token: 'tok-4',
      successKey: 'list.deleteSuccess',
      restoredKey: 'list.restored',
      invalidate: vi.fn(),
      onAfterUndoExpired,
    });

    expect(onAfterUndoExpired).not.toHaveBeenCalled();
    vi.advanceTimersByTime(7000);
    expect(onAfterUndoExpired).toHaveBeenCalledTimes(1);
  });

  it('suppresses onAfterUndoExpired when undo fires inside the TTL', async () => {
    undoDeleteEntityMock.mockResolvedValue({ ok: true });
    const show = useSnapshotUndoToast();
    const onAfterUndoExpired = vi.fn();

    show({
      kind: 'list',
      token: 'tok-5',
      successKey: 'list.deleteSuccess',
      restoredKey: 'list.restored',
      invalidate: vi.fn(),
      onAfterUndoExpired,
    });

    await lastSuccessCall().action.onClick();
    vi.advanceTimersByTime(10000);
    await vi.runAllTimersAsync();

    expect(onAfterUndoExpired).not.toHaveBeenCalled();
  });

  it('fires onAfterUndoExpired when the user clicked Undo but the IPC failed (#3435)', async () => {
    // Pre-fix this test asserted the opposite — "undo intent is
    // sticky" — but in practice the row never came back, so leaving
    // the user on a deleted-list view with no list to render
    // stranded them. The corrected contract: when the IPC bounces,
    // surface the error toast AND run `onAfterUndoExpired` so the
    // caller can navigate the user somewhere safe.
    undoDeleteEntityMock.mockRejectedValue(new Error('TTL'));
    const show = useSnapshotUndoToast();
    const onAfterUndoExpired = vi.fn();

    show({
      kind: 'list',
      token: 'tok-6',
      successKey: 'list.deleteSuccess',
      restoredKey: 'list.restored',
      invalidate: vi.fn(),
      onAfterUndoExpired,
    });

    await lastSuccessCall().action.onClick();
    vi.advanceTimersByTime(10000);
    await vi.runAllTimersAsync();

    expect(toastError).toHaveBeenCalledWith('[undo.expired]');
    expect(onAfterUndoExpired).toHaveBeenCalledTimes(1);
  });

  // #3472: thisAndFollowing edit creates a replacement series before
  // deleting the original; if the user clicks Undo, the snapshot
  // restores the original AND we must delete the replacement
  // ourselves — otherwise two overlapping series remain. The
  // `onAfterUndo` hook runs after the restore IPC succeeds.
  it('runs onAfterUndo after a successful restore, before the restored toast (#3472)', async () => {
    undoDeleteEntityMock.mockResolvedValue({ ok: true });
    const show = useSnapshotUndoToast();
    const onAfterUndo = vi.fn().mockResolvedValue(undefined);

    show({
      kind: 'calendar_event',
      token: 'tok-compound',
      successKey: 'calendar.eventUpdated',
      restoredKey: 'calendar.eventRestored',
      invalidate: vi.fn(),
      onAfterUndo,
    });

    await lastSuccessCall().action.onClick();
    await vi.runAllTimersAsync();

    expect(onAfterUndo).toHaveBeenCalledTimes(1);
    expect(toastInfo).toHaveBeenCalledWith('[calendar.eventRestored]');
    // Ordering: onAfterUndo must precede the restored info toast so
    // sibling cleanup lands before any UI redirect that watches for
    // the toast.
    const onAfterOrder = onAfterUndo.mock.invocationCallOrder[0]!;
    const toastOrder = toastInfo.mock.invocationCallOrder[0]!;
    expect(onAfterOrder).toBeLessThan(toastOrder);
  });

  it('does not run onAfterUndo when the restore IPC fails (#3472)', async () => {
    undoDeleteEntityMock.mockRejectedValue(new Error('TTL'));
    const show = useSnapshotUndoToast();
    const onAfterUndo = vi.fn();

    show({
      kind: 'calendar_event',
      token: 'tok-compound-fail',
      successKey: 'calendar.eventUpdated',
      restoredKey: 'calendar.eventRestored',
      invalidate: vi.fn(),
      onAfterUndo,
    });

    await lastSuccessCall().action.onClick();
    await vi.runAllTimersAsync();

    expect(onAfterUndo).not.toHaveBeenCalled();
  });

  it('reports onAfterUndo failures without aborting the restore (#3472)', async () => {
    undoDeleteEntityMock.mockResolvedValue({ ok: true });
    const show = useSnapshotUndoToast();
    const onAfterUndo = vi.fn().mockRejectedValue(new Error('cleanup-bad'));

    show({
      kind: 'calendar_event',
      token: 'tok-compound-cleanup',
      successKey: 'calendar.eventUpdated',
      restoredKey: 'calendar.eventRestored',
      invalidate: vi.fn(),
      onAfterUndo,
    });

    await lastSuccessCall().action.onClick();
    await vi.runAllTimersAsync();

    expect(reportClientErrorMock).toHaveBeenCalledWith(
      'undo-delete:calendar_event',
      'Snapshot undo onAfterUndo failed',
      expect.any(Error),
    );
    // #3488 / #3495: when the compound cleanup fails the user-facing
    // restored info toast is SUPPRESSED in favor of a WARNING toast
    // (not error) that explicitly tells the user the replacement still
    // exists. The restore itself succeeded — warning is the right
    // shape for partial success.
    expect(toastInfo).not.toHaveBeenCalledWith('[calendar.eventRestored]');
    expect(toastWarning).toHaveBeenCalledWith('[undo.replacementCleanupFailed]');
  });

  it('does not double-fire onAfterUndoExpired when the IPC failure precedes the timer grace window', async () => {
    // Once the failure path has called `onAfterUndoExpired`, the
    // timer must be cancelled — otherwise the user would be
    // navigated twice.
    undoDeleteEntityMock.mockRejectedValue(new Error('TTL'));
    const show = useSnapshotUndoToast();
    const onAfterUndoExpired = vi.fn();

    show({
      kind: 'list',
      token: 'tok-7',
      successKey: 'list.deleteSuccess',
      restoredKey: 'list.restored',
      invalidate: vi.fn(),
      onAfterUndoExpired,
    });

    await lastSuccessCall().action.onClick();
    vi.advanceTimersByTime(20000);
    await vi.runAllTimersAsync();

    expect(onAfterUndoExpired).toHaveBeenCalledTimes(1);
  });
});
