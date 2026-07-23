import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildUnhandledRejectionReport,
  buildWindowErrorReport,
  installAppRuntime,
} from '../../../app/src/app.runtime';

test('app runtime window-error report ignores ResizeObserver loop noise', () => {
  assert.equal(buildWindowErrorReport({ message: 'ResizeObserver loop completed with undelivered notifications.' }), null);
  assert.equal(buildWindowErrorReport({ message: 'ResizeObserver loop limit exceeded' }), null);
});

test('app runtime window-error report preserves useful location and error details', () => {
  assert.deepEqual(
    buildWindowErrorReport({
      colno: 7,
      error: new Error('boom'),
      filename: 'app.js',
      lineno: 42,
      message: 'Render failed',
    }),
    {
      source: 'frontend.window',
      message: 'Render failed',
      details: 'file=app.js line=42 col=7 error=Error: boom',
    },
  );

  assert.deepEqual(buildWindowErrorReport({}), {
    source: 'frontend.window',
    message: 'Unhandled window error',
    details: undefined,
  });
});

test('app runtime unhandled-rejection report preserves Error stack and normalizes non-errors', () => {
  const error = new Error('Rejected');
  assert.deepEqual(buildUnhandledRejectionReport({ reason: error }), {
    source: 'frontend.promise',
    message: 'Rejected',
    details: error.stack,
  });
  assert.deepEqual(buildUnhandledRejectionReport({ reason: null }), {
    source: 'frontend.promise',
    message: 'Unhandled promise rejection: null',
  });
});

test('app runtime installs global listeners, reports events, and tears down idempotently', () => {
  const listeners = new Map<string, EventListener>();
  const removed: string[] = [];
  const reports: Array<{ details?: string | undefined; message: string; source: string }> = [];
  let quitFlushInstalled = 0;
  let quitFlushTornDown = 0;

  const runtime = installAppRuntime({
    installQuitFlushListener: () => {
      quitFlushInstalled += 1;
      return () => {
        quitFlushTornDown += 1;
      };
    },
    reportClientError: (source, message, _error, details) => {
      reports.push({ source, message, details });
    },
    windowTarget: {
      addEventListener: (type, listener) => {
        listeners.set(type, listener);
      },
      removeEventListener: (type, listener) => {
        assert.equal(listeners.get(type), listener);
        listeners.delete(type);
        removed.push(type);
      },
    },
  });

  assert.equal(quitFlushInstalled, 1);
  assert.deepEqual([...listeners.keys()], ['error', 'unhandledrejection']);

  listeners.get('error')?.({
    filename: 'app.js',
    message: 'Window failed',
  } as Event);
  listeners.get('error')?.({
    message: 'ResizeObserver loop limit exceeded',
  } as Event);
  listeners.get('unhandledrejection')?.({
    reason: 'bad promise',
  } as Event);

  assert.deepEqual(reports, [
    {
      source: 'frontend.window',
      message: 'Window failed',
      details: 'file=app.js',
    },
    {
      source: 'frontend.promise',
      message: 'Unhandled promise rejection: bad promise',
      details: undefined,
    },
  ]);

  runtime.cleanup();
  runtime.cleanup();

  assert.deepEqual(removed, ['error', 'unhandledrejection']);
  assert.deepEqual([...listeners.keys()], []);
  assert.equal(quitFlushTornDown, 1);
});
