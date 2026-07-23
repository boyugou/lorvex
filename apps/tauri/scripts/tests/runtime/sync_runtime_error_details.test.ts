import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { syncTickErrorDetails } from '../../../app/src/lib/sync/runtime';

test('sync tick error details preserve safe Error stacks', () => {
  const nativeError = new Error('native boom');
  assert.match(syncTickErrorDetails(nativeError) ?? '', /^Error: native boom\n\s+at /);

  const error = new Error('boom');
  Object.defineProperty(error, 'stack', {
    configurable: true,
    value: '  Error: boom\n    at tick  ',
  });

  assert.equal(syncTickErrorDetails(error), 'Error: boom\n    at tick');
});

test('sync tick error details do not invoke stack or object serialization accessors', () => {
  let accessed = 0;
  const error = new Error('boom');
  Object.defineProperty(error, 'stack', {
    enumerable: false,
    get() {
      accessed += 1;
      return 'getter should not run';
    },
  });

  const objectPayload = Object.defineProperty({}, 'detail', {
    enumerable: true,
    get() {
      accessed += 1;
      return 'getter should not run';
    },
  });
  const ownToJsonPayload = Object.defineProperty({}, 'toJSON', {
    enumerable: true,
    get() {
      accessed += 1;
      return () => ({ detail: 'getter should not run' });
    },
  });
  const inheritedToJsonPayload = Object.create(Object.defineProperty({}, 'toJSON', {
    enumerable: true,
    get() {
      accessed += 1;
      return () => ({ detail: 'getter should not run' });
    },
  })) as Record<string, unknown>;
  inheritedToJsonPayload.safe = 'value';

  assert.equal(syncTickErrorDetails(error), 'boom');
  assert.equal(syncTickErrorDetails(objectPayload), undefined);
  assert.equal(syncTickErrorDetails(ownToJsonPayload), undefined);
  assert.equal(syncTickErrorDetails(inheritedToJsonPayload), '{"safe":"value"}');
  assert.equal(accessed, 0);
});

test('sync tick error details use the shared safe IPC formatter for object payloads', () => {
  assert.equal(syncTickErrorDetails({ details: 'disk unavailable' }), 'disk unavailable');
  assert.equal(syncTickErrorDetails({ foo: 'bar' }), '{"foo":"bar"}');
  assert.equal(syncTickErrorDetails('plain failure'), undefined);
});

test('background sync runtime keeps tick detail formatting delegated to the tested helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/sync/runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function syncTickErrorDetails\(error: unknown\)/);
  assert.match(source, /const details = syncTickErrorDetails\(err\);/);
  assert.doesNotMatch(source, /JSON\.stringify\(error\)/);
  assert.doesNotMatch(source, /error\.stack\?/);
});
