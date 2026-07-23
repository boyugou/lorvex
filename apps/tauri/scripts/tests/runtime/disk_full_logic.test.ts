import assert from 'node:assert/strict';
import test from 'node:test';

import {
  extractDiskFullDetails,
  isDiskFullError,
} from '../../../app/src/lib/recovery/diskFull.logic';

function diskFullEnvelope(message: string, detail?: string): string {
  return JSON.stringify({
    kind: 'disk_full',
    message,
    ...(detail === undefined ? {} : { detail }),
  });
}

test('extractDiskFullDetails returns the trimmed diagnostic only for disk-full envelopes', () => {
  assert.equal(
    extractDiskFullDetails(diskFullEnvelope('Local storage is full.', 'no space left on device')),
    'no space left on device',
  );
  assert.equal(
    extractDiskFullDetails({ message: diskFullEnvelope('Local storage is full.', '  database full  ') }),
    'database full',
  );
});

test('extractDiskFullDetails fails closed for non-matching error shapes', () => {
  assert.equal(extractDiskFullDetails('plain failure'), null);
  assert.equal(
    extractDiskFullDetails({ message: JSON.stringify({ kind: 'timeout', message: 'boom' }) }),
    null,
  );
  assert.equal(
    extractDiskFullDetails(Object.create({ message: diskFullEnvelope('Local storage is full.', 'prototype leak') })),
    null,
  );
  assert.equal(isDiskFullError({ message: diskFullEnvelope('Local storage is full.', 'x') }), true);
  assert.equal(isDiskFullError({ message: 'x' }), false);
});
