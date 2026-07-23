import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { parseSyncErrorEnvelope } from '../../../app/src/lib/syncBackend/errorKind';

test('parseSyncErrorEnvelope accepts canonical wire envelopes', () => {
  const envelope = parseSyncErrorEnvelope(
    new Error(JSON.stringify({
      kind: 'timeout',
      message: 'Provider folder timed out',
      retryable: false,
      path: '/Users/alex/LorvexSync',
    })),
  );

  assert.deepEqual(envelope, {
    kind: 'timeout',
    message: 'Provider folder timed out',
    retryable: false,
    path: '/Users/alex/LorvexSync',
  });
});

test('parseSyncErrorEnvelope fails closed for malformed or unknown envelope payloads', () => {
  assert.deepEqual(
    parseSyncErrorEnvelope(
      new Error(JSON.stringify({
        kind: 'bogus',
        message: 'bad',
        retryable: false,
        path: '/tmp',
      })),
    ),
    {
      kind: 'unknown',
      message: '',
      retryable: false,
      path: null,
    },
  );

  assert.deepEqual(
    parseSyncErrorEnvelope('plain sync failure'),
    {
      kind: 'unknown',
      message: '',
      retryable: false,
      path: null,
    },
  );

  assert.deepEqual(
    parseSyncErrorEnvelope(
      new Error(JSON.stringify({
        kind: 'timeout',
        message: 'Provider folder timed out',
        retryable: false,
        path: '/Users/alex/LorvexSync',
        debug: true,
      })),
    ),
    {
      kind: 'unknown',
      message: '',
      retryable: false,
      path: null,
    },
  );
});

test('parseSyncErrorEnvelope rejects non-string path values while preserving null paths', () => {
  assert.deepEqual(
    parseSyncErrorEnvelope(
      new Error(JSON.stringify({
        kind: 'permissions',
        message: 'not allowed',
        retryable: true,
        path: { bad: true },
      })),
    ),
    {
      kind: 'unknown',
      message: '',
      retryable: false,
      path: null,
    },
  );

  assert.deepEqual(
    parseSyncErrorEnvelope(
      new Error(JSON.stringify({
        kind: 'offline',
        message: 'offline',
        retryable: true,
        path: null,
      })),
    ),
    {
      kind: 'offline',
      message: 'offline',
      retryable: true,
      path: null,
    },
  );
});

test('parseSyncErrorEnvelope delegates JSON parsing to the shared helper', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/syncBackend/errorKind.ts'),
    'utf8',
  );

  assert.match(source, /from '\.\.\/security\/jsonParse';/);
  assert.doesNotMatch(source, /JSON\.parse\(/);
});
