import assert from 'node:assert/strict';
import test from 'node:test';

import {
  normalizeInvokePayload,
  toIpcErrorMessage,
  toUserFacingErrorMessage,
} from '../../../app/src/lib/ipc/core.logic';

test('normalizeInvokePayload camel-cases snake_case keys and preserves values', () => {
  assert.deepEqual(
    normalizeInvokePayload({
      task_id: 'task-1',
      list_id: 'list-1',
      alreadyCamel: true,
      nested_value: { keep: 'shape' },
    }),
    {
      taskId: 'task-1',
      listId: 'list-1',
      alreadyCamel: true,
      nestedValue: { keep: 'shape' },
    },
  );
  assert.equal(normalizeInvokePayload(undefined), undefined);
});

test('normalizeInvokePayload copies enumerable data fields without invoking accessors', () => {
  let accessed = 0;
  const payload = {
    task_id: 'task-1',
  } as Record<string, unknown>;

  Object.defineProperty(payload, 'danger_value', {
    enumerable: true,
    get() {
      accessed += 1;
      return 'getter should not run';
    },
  });
  Object.defineProperty(payload, 'hidden_value', {
    enumerable: false,
    value: 'hidden',
  });

  assert.deepEqual(normalizeInvokePayload(payload), {
    taskId: 'task-1',
  });
  assert.equal(accessed, 0);
});

test('toIpcErrorMessage prefers nested message-like fields and falls back to JSON/string', () => {
  const nested = new Error('');
  (nested as Error & { cause?: unknown }).cause = { reason: 'deep reason' };
  assert.equal(toIpcErrorMessage(nested), 'deep reason');
  assert.equal(toIpcErrorMessage({ details: 'details field' }), 'details field');
  assert.equal(toIpcErrorMessage({ foo: 'bar' }), '{"foo":"bar"}');
  assert.equal(toIpcErrorMessage(42), '42');
});

test('toIpcErrorMessage preserves safe toJSON-backed fallback fields', () => {
  assert.equal(
    toIpcErrorMessage({ when: new Date('2024-01-02T03:04:05.000Z') }),
    '{"when":"2024-01-02T03:04:05.000Z"}',
  );
  assert.equal(
    toIpcErrorMessage({
      nested: {
        toJSON() {
          return { value: 'custom' };
        },
      },
    }),
    '{"nested":{"value":"custom"}}',
  );
});

test('toIpcErrorMessage preserves ordinary deep fallback payloads and boxed primitives', () => {
  assert.equal(
    toIpcErrorMessage({ arr: [[[[{ x: 1 }]]]] }),
    '{"arr":[[[[{"x":1}]]]]}',
  );
  assert.equal(toIpcErrorMessage(new String('abc')), '"abc"');
  assert.equal(toIpcErrorMessage({ value: new String('abc') }), '{"value":"abc"}');
  assert.equal(toIpcErrorMessage(new Number(42)), '42');
  assert.equal(toIpcErrorMessage({ value: new Boolean(false) }), '{"value":false}');
});

test('toIpcErrorMessage omits cyclic object edges without throwing', () => {
  const record: { value: string; self?: unknown } = { value: 'kept' };
  record.self = record;
  const array: unknown[] = [];
  array.push(array);

  assert.equal(toIpcErrorMessage(record), '{"value":"kept"}');
  assert.equal(toIpcErrorMessage(array), '[null]');
});

test('toIpcErrorMessage ignores untrusted inherited and array message fields', () => {
  const inherited = Object.create({ message: 'prototype leak' }) as Record<string, unknown>;
  inherited.foo = 'bar';
  const arrayWithMessage = Object.assign(['entry'], { message: 'array leak' });

  assert.equal(toIpcErrorMessage(inherited), '{"foo":"bar"}');
  assert.equal(toIpcErrorMessage(arrayWithMessage), '["entry"]');
});

test('toIpcErrorMessage ignores own accessors without invoking hostile getters', () => {
  for (const key of ['message', 'error', 'details', 'reason', 'cause'] as const) {
    let accessed = 0;
    const payload = Object.defineProperty({}, key, {
      enumerable: true,
      get() {
        accessed += 1;
        return `${key} getter should not run`;
      },
    });

    assert.equal(toIpcErrorMessage(payload), '[object Object]');
    assert.equal(accessed, 0);
  }
});

test('toIpcErrorMessage ignores Error accessors without invoking hostile getters', () => {
  const error = new Error('original');
  let messageAccessed = 0;
  let causeAccessed = 0;

  Object.defineProperty(error, 'message', {
    enumerable: true,
    get() {
      messageAccessed += 1;
      return 'getter should not run';
    },
  });
  Object.defineProperty(error, 'cause', {
    enumerable: true,
    get() {
      causeAccessed += 1;
      return { message: 'nested getter should not run' };
    },
  });
  Object.defineProperty(error, Symbol.toStringTag, {
    enumerable: true,
    get() {
      messageAccessed += 1;
      return 'Owned';
    },
  });

  assert.equal(toIpcErrorMessage(error), '[object Error]');
  assert.equal(toUserFacingErrorMessage(error, 'fallback'), 'fallback');
  assert.equal(toUserFacingErrorMessage(new Error(''), 'fallback'), 'fallback');
  assert.equal(messageAccessed, 0);
  assert.equal(causeAccessed, 0);
});

test('toUserFacingErrorMessage hides typed envelopes and backend internals', () => {
  const envelope = (payload: Record<string, unknown>) => JSON.stringify(payload);

  assert.equal(
    toUserFacingErrorMessage(
      envelope({ kind: 'disk_full', message: 'Local storage is full.', detail: 'no space left on device' }),
      'fallback',
    ),
    'fallback',
  );
  assert.equal(
    toUserFacingErrorMessage(
      envelope({ kind: 'internal', message: 'internal backend failure', detail: 'failed to lock writer connection' }),
      'fallback',
    ),
    'fallback',
  );
  assert.equal(
    toUserFacingErrorMessage('Failed to lock writer connection: PoisonError { .. }', 'fallback'),
    'fallback',
  );
  assert.equal(
    toUserFacingErrorMessage('sync failed at /Users/me/db.sqlite', 'fallback'),
    'fallback',
  );
});

test('toUserFacingErrorMessage strips stack tails and truncates very long strings', () => {
  assert.equal(
    toUserFacingErrorMessage('Readable message\n    at stack frame', 'fallback'),
    'Readable message',
  );
  const long = 'x'.repeat(220);
  const formatted = toUserFacingErrorMessage(long, 'fallback');
  assert.equal(formatted.length, 201);
  assert.ok(formatted.endsWith('\u2026'));
});
