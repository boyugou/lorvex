import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import type { Task } from '../../../app/src/lib/ipc';
import {
  __TEST_ONLY__ as deferralUndoTestApi,
  captureDeferralSnapshot,
  runTaskDeferralWithUndo,
} from '../../../app/src/lib/tasks/deferralUndo';

const repoRoot = process.cwd();

const task = {
  id: 'task-1',
  list_id: 'list-1',
  planned_date: '2026-05-08',
  defer_count: 7,
  last_deferred_at: '2026-05-01T12:00:00.000Z',
  last_defer_reason: 'not_today',
} as Task;

test.afterEach(() => {
  deferralUndoTestApi.resetDepsForTests();
});

test('captureDeferralSnapshot preserves every deferral field needed for exact undo', () => {
  assert.deepEqual(captureDeferralSnapshot(task), {
    planned_date: '2026-05-08',
    defer_count: 7,
    last_deferred_at: '2026-05-01T12:00:00.000Z',
    last_defer_reason: 'not_today',
  });
});

test('runTaskDeferralWithUndo restores the captured full deferral snapshot from the toast action', async () => {
  const restored: Array<{ id: string; snapshot: ReturnType<typeof captureDeferralSnapshot> }> = [];
  const successToasts: Array<{ message: string; action?: { label: string; onClick: () => void | Promise<void> } }> = [];
  const infoToasts: string[] = [];
  let forwardRuns = 0;
  let invalidations = 0;

  deferralUndoTestApi.setDepsForTests({
    restoreTaskDeferral: async (id, snapshot) => {
      restored.push({ id, snapshot });
      return task;
    },
    successToast: (message, action) => {
      successToasts.push({ message, action: typeof action === 'string' ? undefined : action });
    },
    infoToast: (message) => {
      infoToasts.push(message);
    },
  });

  await runTaskDeferralWithUndo({
    task,
    runDefer: async () => {
      forwardRuns += 1;
      return task;
    },
    invalidate: () => {
      invalidations += 1;
    },
    successMessage: 'Deferred',
    undoLabel: 'Undo',
    undoSuccessMessage: 'Undone',
    forwardErrorSource: 'test.defer',
    forwardErrorMessage: 'Failed to defer',
    forwardErrorToastMessage: 'Error',
    undoErrorSource: 'test.undoDefer',
    undoErrorMessage: 'Failed to undo defer',
    undoErrorToastMessage: 'Error',
  });

  assert.equal(forwardRuns, 1);
  assert.equal(invalidations, 1);
  assert.equal(successToasts.length, 1);
  assert.equal(successToasts[0]?.message, 'Deferred');
  assert.equal(successToasts[0]?.action?.label, 'Undo');

  await successToasts[0]?.action?.onClick();

  assert.deepEqual(restored, [{
    id: 'task-1',
    snapshot: {
      planned_date: '2026-05-08',
      defer_count: 7,
      last_deferred_at: '2026-05-01T12:00:00.000Z',
      last_defer_reason: 'not_today',
    },
  }]);
  assert.equal(invalidations, 2);
  assert.deepEqual(infoToasts, ['Undone']);
});

test('runTaskDeferralWithUndo lets surfaces preserve custom error reporters', async () => {
  const successToasts: Array<{ action?: { label: string; onClick: () => void | Promise<void> } }> = [];
  const reports: string[] = [];
  const errorToasts: string[] = [];

  deferralUndoTestApi.setDepsForTests({
    restoreTaskDeferral: async () => {
      throw new Error('restore failed');
    },
    successToast: (_message, action) => {
      successToasts.push({ action: typeof action === 'string' ? undefined : action });
    },
    errorWithDetailToast: (_error, fallback) => {
      errorToasts.push(fallback);
    },
    reportClientError: () => {
      reports.push('default');
    },
  });

  await runTaskDeferralWithUndo({
    task,
    runDefer: async () => {
      throw new Error('defer failed');
    },
    invalidate: () => {},
    successMessage: 'Deferred',
    undoLabel: 'Undo',
    reportForwardError: () => reports.push('forward'),
    forwardErrorSource: 'test.defer',
    forwardErrorMessage: 'Failed to defer',
    forwardErrorToastMessage: 'Forward error',
    undoErrorSource: 'test.undoDefer',
    undoErrorMessage: 'Failed to undo defer',
    undoErrorToastMessage: 'Undo error',
  });

  await runTaskDeferralWithUndo({
    task,
    runDefer: async () => task,
    invalidate: () => {},
    successMessage: 'Deferred',
    undoLabel: 'Undo',
    forwardErrorSource: 'test.defer',
    forwardErrorMessage: 'Failed to defer',
    forwardErrorToastMessage: 'Forward error',
    reportUndoError: () => reports.push('undo'),
    undoErrorSource: 'test.undoDefer',
    undoErrorMessage: 'Failed to undo defer',
    undoErrorToastMessage: 'Undo error',
  });
  await successToasts[0]?.action?.onClick();

  assert.deepEqual(reports, ['forward', 'undo']);
  assert.deepEqual(errorToasts, ['Forward error', 'Undo error']);
});

test('defer undo surfaces delegate to the shared full-snapshot helper instead of reset/update pairs', () => {
  const requiredHelperConsumers = [
    'app/src/lib/tasks/taskActions/scheduling.ts',
    'app/src/components/task-card/deferPresets.ts',
    'app/src/components/task-card/useSwipeableTaskCardActions.ts',
    'app/src/components/task-card/useTaskCardQuickActionHandlers.ts',
    'app/src/components/task-detail/controller/mutations/lifecycle.ts',
    'app/src/components/command-palette/controller/mutations.ts',
  ];

  for (const relativePath of requiredHelperConsumers) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.match(
      source,
      /runTaskDeferralWithUndo/,
      `${relativePath} should delegate defer undo to runTaskDeferralWithUndo`,
    );
  }

  for (const relativePath of [
    'app/src/lib/tasks/taskActions/scheduling.ts',
    'app/src/components/task-card/deferPresets.ts',
    'app/src/components/task-card/useSwipeableTaskCardActions.ts',
    'app/src/components/task-card/useTaskCardQuickActionHandlers.ts',
    'app/src/components/command-palette/controller/mutations.ts',
  ]) {
    const source = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(
      source,
      /resetTaskDeferral/,
      `${relativePath} should not reset deferral state when offering defer undo`,
    );
    assert.doesNotMatch(
      source,
      /planned_date:\s*(?:prevPlannedDate|task\.planned_date)/,
      `${relativePath} should not hand-roll planned-date-only defer undo snapshots`,
    );
  }

  const taskDetailLifecycle = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/controller/mutations/lifecycle.ts'),
    'utf8',
  );
  const handleDeferBody = taskDetailLifecycle.match(/const handleDefer = useCallback[\s\S]*?const handleReopen = useCallback/)?.[0] ?? '';
  assert.match(handleDeferBody, /runTaskDeferralWithUndo/);
  assert.doesNotMatch(handleDeferBody, /resetTaskDeferral/);
  assert.doesNotMatch(handleDeferBody, /planned_date:\s*prevPlannedDate/);
});
