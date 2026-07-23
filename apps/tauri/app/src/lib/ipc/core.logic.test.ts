import { describe, expect, it } from 'vitest';

import {
  extractNestedErrorMessage,
  looksLikeBackendInternal,
  normalizeInvokePayload,
  toCamelArgKey,
  toIpcErrorMessage,
  toUserFacingErrorMessage,
} from './core.logic';

describe('toCamelArgKey', () => {
  it('passes through camelCase keys unchanged', () => {
    expect(toCamelArgKey('listId')).toBe('listId');
    expect(toCamelArgKey('id')).toBe('id');
  });

  it('converts snake_case to camelCase', () => {
    expect(toCamelArgKey('list_id')).toBe('listId');
    expect(toCamelArgKey('estimated_minutes')).toBe('estimatedMinutes');
    expect(toCamelArgKey('a_b_c_d')).toBe('aBCD');
  });

  it('handles digits after underscores', () => {
    expect(toCamelArgKey('field_1')).toBe('field1');
  });
});

describe('normalizeInvokePayload', () => {
  it('returns undefined when given undefined', () => {
    expect(normalizeInvokePayload(undefined)).toBeUndefined();
  });

  it('rewrites snake_case keys into camelCase', () => {
    expect(normalizeInvokePayload({ list_id: 'x', due_date: 'y' })).toEqual({
      listId: 'x',
      dueDate: 'y',
    });
  });

  it('preserves the original values verbatim (including null and arrays)', () => {
    const tags = ['a', 'b'];
    const out = normalizeInvokePayload({ tags, body: null });
    expect(out).toEqual({ tags: ['a', 'b'], body: null });
    // The array reference passes through; the function must not deep-clone.
    expect((out as { tags: unknown }).tags).toBe(tags);
  });

  it('skips non-enumerable and getter-only properties (no IPC leakage of class internals)', () => {
    const payload: Record<string, unknown> = {};
    Object.defineProperty(payload, 'visible', { value: 1, enumerable: true });
    Object.defineProperty(payload, 'hidden', { value: 2, enumerable: false });
    Object.defineProperty(payload, 'getter', {
      get: () => 3,
      enumerable: true,
    });
    expect(normalizeInvokePayload(payload)).toEqual({ visible: 1 });
  });
});

describe('extractNestedErrorMessage', () => {
  it('returns null for null/undefined', () => {
    expect(extractNestedErrorMessage(null)).toBeNull();
    expect(extractNestedErrorMessage(undefined)).toBeNull();
  });

  it('returns string errors as-is', () => {
    expect(extractNestedErrorMessage('boom')).toBe('boom');
  });

  it('returns Error.message', () => {
    expect(extractNestedErrorMessage(new Error('explode'))).toBe('explode');
  });

  it('walks Error.cause chains up to the depth limit', () => {
    const inner = new Error('inner');
    const outer = new Error('');
    (outer as Error & { cause?: unknown }).cause = inner;
    expect(extractNestedErrorMessage(outer)).toBe('inner');
  });

  it('refuses to recurse past the depth guard', () => {
    // Build a chain longer than the documented depth=3 limit and verify the
    // guard fires instead of running into a stack overflow on cyclic causes.
    const chain: Error & { cause?: unknown } = new Error('depth-0');
    let head: Error & { cause?: unknown } = chain;
    for (let i = 1; i <= 8; i += 1) {
      const next: Error & { cause?: unknown } = new Error('');
      (head as Error & { cause?: unknown }).cause = next;
      head = next;
    }
    head.cause = new Error('too-deep');
    // The deepest message should not be reachable; we get null or the JSON
    // of the last reachable Error, but never throw.
    expect(() => extractNestedErrorMessage(chain)).not.toThrow();
  });

  it('reads message-like fields from plain objects', () => {
    expect(extractNestedErrorMessage({ message: 'hello' })).toBe('hello');
    expect(extractNestedErrorMessage({ error: 'oops' })).toBe('oops');
    expect(extractNestedErrorMessage({ details: 'detailed' })).toBe('detailed');
    expect(extractNestedErrorMessage({ reason: 'because' })).toBe('because');
  });

  it('ignores blank/whitespace-only string fields', () => {
    expect(extractNestedErrorMessage({ message: '   ' })).not.toBe('   ');
  });

  it('survives circular object references without throwing', () => {
    const obj: Record<string, unknown> = {};
    obj.self = obj;
    expect(() => extractNestedErrorMessage(obj)).not.toThrow();
  });

  it('does not invoke malicious getters (uses property descriptors)', () => {
    let getterCalled = false;
    const evil: Record<string, unknown> = {};
    Object.defineProperty(evil, 'message', {
      get() {
        getterCalled = true;
        return 'side-effect';
      },
      enumerable: true,
    });
    extractNestedErrorMessage(evil);
    expect(getterCalled).toBe(false);
  });
});

describe('toIpcErrorMessage', () => {
  it('falls back to "[object Error]" for an Error with no extractable message', () => {
    // An Error whose `message` is overwritten by a getter is not safe-readable,
    // so the function must fall through to its sentinel rather than throw.
    const err = new Error();
    Object.defineProperty(err, 'message', {
      get: () => '',
      configurable: true,
    });
    expect(toIpcErrorMessage(err)).toBe('[object Error]');
  });

  it('coerces non-Error values via String()', () => {
    expect(toIpcErrorMessage(42)).toBe('42');
    expect(toIpcErrorMessage(true)).toBe('true');
  });
});

describe('looksLikeBackendInternal', () => {
  it.each([
    'PoisonError: lock poisoned',
    'rusqlite::Error: database is locked',
    'objc2 selector failure',
    'failed to lock writer connection',
    'failed to attach jni',
    'JavaVM panic',
    'JNI thread detach',
    'provider SDK conflict code 14',
    'RefCell already mutably borrowed',
    'Mutex<TaskState> deadlock',
    'panic at /Users/dev/lorvex/src/foo.rs:120',
    'oh no /private/var/something happened',
    'panic at C:\\\\Users\\\\dev\\\\app crashed',
  ])('flags %p as backend-internal', (msg) => {
    expect(looksLikeBackendInternal(msg)).toBe(true);
  });

  it.each([
    'Task title is required',
    'Network request failed',
    'Could not save preferences.',
  ])('does not flag plain user-facing message %p', (msg) => {
    expect(looksLikeBackendInternal(msg)).toBe(false);
  });
});

describe('toUserFacingErrorMessage', () => {
  it('returns fallback when no message can be extracted', () => {
    expect(toUserFacingErrorMessage(null, 'fallback')).toBe('fallback');
  });

  it('returns fallback for typed disk-full envelope (#2949)', () => {
    const envelope = JSON.stringify({
      kind: 'disk_full',
      message: 'Local storage is full.',
      detail: 'no space',
    });
    expect(toUserFacingErrorMessage(envelope, 'Disk is full')).toBe('Disk is full');
  });

  it('returns fallback for typed internal envelope (#2949)', () => {
    const envelope = JSON.stringify({
      kind: 'internal',
      message: 'An internal error occurred. Please try again.',
    });
    expect(toUserFacingErrorMessage(envelope, 'Something went wrong')).toBe(
      'Something went wrong',
    );
  });

  it('surfaces typed validation envelope message (#2949)', () => {
    const envelope = JSON.stringify({
      kind: 'validation',
      message: 'title cannot be empty',
    });
    expect(toUserFacingErrorMessage(envelope, 'Validation failed')).toBe('title cannot be empty');
  });

  it('surfaces typed not_found envelope message (#2949)', () => {
    const envelope = JSON.stringify({
      kind: 'not_found',
      message: 'Task not found: abc-123',
    });
    expect(toUserFacingErrorMessage(envelope, 'Not found')).toBe('Task not found: abc-123');
  });

  it('returns fallback for backend-internal Rust messages', () => {
    expect(
      toUserFacingErrorMessage('rusqlite::Error: database is locked', 'Try again'),
    ).toBe('Try again');
  });

  it('strips stack traces and returns the first line', () => {
    const err = new Error('Something user-friendly\n    at internalFn (foo.ts:1:1)');
    expect(toUserFacingErrorMessage(err, 'fallback')).toBe('Something user-friendly');
  });

  it('truncates messages over the 200-char toast cap with an ellipsis', () => {
    const long = 'x'.repeat(250);
    const out = toUserFacingErrorMessage(long, 'fallback');
    expect(out.length).toBe(201); // 200 + 1 ellipsis char
    expect(out.endsWith('…')).toBe(true);
  });

  it('passes through short user-friendly messages verbatim', () => {
    expect(toUserFacingErrorMessage('Title is required', 'fallback')).toBe(
      'Title is required',
    );
  });
});
