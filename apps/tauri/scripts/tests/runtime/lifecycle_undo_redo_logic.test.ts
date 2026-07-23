import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildLifecycleRedoToastAction,
  buildLifecycleUndoToastPlan,
  hasLifecycleToken,
} from '../../../app/src/lib/tasks/lifecycleUndoRedo.logic';
import {
  __TEST_ONLY__ as lifecycleUndoRedoModuleTestApi,
  showUndoOnlyToast,
  showUndoToastWithRedo,
} from '../../../app/src/lib/tasks/lifecycleUndoRedo';
import {
  __getToastsForTests,
  __resetToastsForTests,
} from '../../../app/src/lib/notifications/toast';

type LifecycleTestKey =
  | 'common.undo'
  | 'common.redo'
  | 'common.error'
  | 'task.undone'
  | 'task.redone';

const t = (key: LifecycleTestKey) => {
  switch (key) {
    case 'common.undo':
      return 'Undo';
    case 'common.redo':
      return 'Redo';
    case 'common.error':
      return 'Something went wrong';
    case 'task.undone':
      return 'Undone';
    case 'task.redone':
      return 'Redone';
  }
};

function makeOpts() {
  const state = {
    invalidateCalls: 0,
  };
  return {
    state,
    opts: {
      invalidate: () => {
        state.invalidateCalls += 1;
      },
      t,
      errorKeyPrefix: 'task.lifecycle',
      persist: {
        label: 'Completed: Task',
        action: 'complete' as const,
      },
    },
  };
}

async function flushAsyncWork(): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, 0));
}

function latestToast() {
  const toasts = __getToastsForTests();
  const toast = toasts.at(-1);
  assert.ok(toast, 'expected a toast to exist');
  return toast;
}

test.afterEach(() => {
  lifecycleUndoRedoModuleTestApi.resetDepsForTests();
  __resetToastsForTests();
});

test('hasLifecycleToken accepts only non-empty tokens', () => {
  assert.equal(hasLifecycleToken('token'), true);
  assert.equal(hasLifecycleToken(''), false);
});

test('buildLifecycleUndoToastPlan persists and exposes undo actions only when a usable token exists', () => {
  const plan = buildLifecycleUndoToastPlan('undo-token', t, {
    label: 'Completed: Task',
    action: 'complete',
  });
  assert.deepEqual(plan.action, {
    token: 'undo-token',
    label: 'Undo',
  });
  assert.equal(plan.persistedEntry?.token, 'undo-token');
  assert.equal(plan.persistedEntry?.label, 'Completed: Task');
  assert.equal(plan.persistedEntry?.action, 'complete');

  assert.deepEqual(buildLifecycleUndoToastPlan('', t, {
    label: 'Completed: Task',
    action: 'complete',
  }), {
    action: null,
    persistedEntry: null,
  });
});

test('buildLifecycleRedoToastAction fails closed when redo tokens are missing', () => {
  assert.deepEqual(buildLifecycleRedoToastAction('redo-token', t), {
    token: 'redo-token',
    label: 'Redo',
  });
  assert.equal(buildLifecycleRedoToastAction('', t), null);
});

test('showUndoOnlyToast and showUndoToastWithRedo fail closed when tokens are missing', () => {
  const persistedTokens: string[] = [];
  const { state, opts } = makeOpts();
  lifecycleUndoRedoModuleTestApi.setDepsForTests({
    recordUndoToken: (entry) => {
      persistedTokens.push(entry.token);
    },
    undoTaskLifecycle: async () => {
      throw new Error('undoTaskLifecycle should not run for empty tokens');
    },
    redoTaskLifecycle: async () => {
      throw new Error('redoTaskLifecycle should not run for empty tokens');
    },
  });

  showUndoOnlyToast('Saved', '', opts);
  showUndoToastWithRedo('Completed', '', opts);

  const toasts = __getToastsForTests();
  assert.equal(toasts.length, 2);
  assert.deepEqual(
    toasts.map((toast) => ({ message: toast.message, action: toast.action ?? null })),
    [
      { message: 'Saved', action: null },
      { message: 'Completed', action: null },
    ],
  );
  assert.deepEqual(persistedTokens, []);
  assert.equal(state.invalidateCalls, 0);
});

test('showUndoOnlyToast consumes the token and invalidates once after a successful undo', async () => {
  const undoCalls: string[] = [];
  const consumedTokens: string[] = [];
  const persistedTokens: string[] = [];
  const { state, opts } = makeOpts();
  lifecycleUndoRedoModuleTestApi.setDepsForTests({
    undoTaskLifecycle: async (token) => {
      undoCalls.push(token);
      return { redo_token: '' };
    },
    consumeUndoToken: (token) => {
      consumedTokens.push(token);
    },
    recordUndoToken: (entry) => {
      persistedTokens.push(entry.token);
    },
  });

  showUndoOnlyToast('Updated', 'undo-only-token', opts);
  const undoToast = latestToast();
  assert.equal(undoToast.action?.label, 'Undo');
  undoToast.action?.onClick();
  await flushAsyncWork();

  const toasts = __getToastsForTests();
  assert.equal(toasts.at(-1)?.message, 'Undone');
  assert.equal(toasts.at(-1)?.action, undefined);
  assert.deepEqual(undoCalls, ['undo-only-token']);
  assert.deepEqual(consumedTokens, ['undo-only-token']);
  assert.deepEqual(persistedTokens, ['undo-only-token']);
  assert.equal(state.invalidateCalls, 1);
});

test('showUndoToastWithRedo persists the fresh undo token returned by redo and consumes both undo legs', async () => {
  const undoCalls: string[] = [];
  const redoCalls: string[] = [];
  const consumedTokens: string[] = [];
  const persistedTokens: string[] = [];
  const { state, opts } = makeOpts();
  lifecycleUndoRedoModuleTestApi.setDepsForTests({
    undoTaskLifecycle: async (token) => {
      undoCalls.push(token);
      return { redo_token: token === 'initial-undo' ? 'redo-token' : '' };
    },
    redoTaskLifecycle: async (token) => {
      redoCalls.push(token);
      return { undo_token: 'undo-from-redo' };
    },
    consumeUndoToken: (token) => {
      consumedTokens.push(token);
    },
    recordUndoToken: (entry) => {
      persistedTokens.push(entry.token);
    },
  });

  showUndoToastWithRedo('Completed', 'initial-undo', opts);
  assert.deepEqual(persistedTokens, ['initial-undo']);

  latestToast().action?.onClick();
  await flushAsyncWork();
  assert.deepEqual(undoCalls, ['initial-undo']);
  assert.deepEqual(consumedTokens, ['initial-undo']);
  assert.equal(state.invalidateCalls, 1);

  const redoToast = latestToast();
  assert.equal(redoToast.message, 'Undone');
  assert.equal(redoToast.action?.label, 'Redo');
  redoToast.action?.onClick();
  await flushAsyncWork();

  assert.deepEqual(redoCalls, ['redo-token']);
  assert.deepEqual(persistedTokens, ['initial-undo', 'undo-from-redo']);
  assert.equal(state.invalidateCalls, 2);

  const freshUndoToast = latestToast();
  assert.equal(freshUndoToast.message, 'Redone');
  assert.equal(freshUndoToast.action?.label, 'Undo');
  freshUndoToast.action?.onClick();
  await flushAsyncWork();

  assert.deepEqual(undoCalls, ['initial-undo', 'undo-from-redo']);
  assert.deepEqual(consumedTokens, ['initial-undo', 'undo-from-redo']);
  assert.equal(state.invalidateCalls, 3);
  assert.equal(latestToast().message, 'Undone');
});
