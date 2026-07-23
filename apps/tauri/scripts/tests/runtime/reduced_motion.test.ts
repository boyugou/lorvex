import assert from 'node:assert/strict';
import test from 'node:test';

import {
  prefersReducedMotion,
  REDUCED_MOTION_QUERY,
} from '../../../app/src/lib/reducedMotion';

test('prefersReducedMotion fails closed without a usable matchMedia implementation', () => {
  assert.equal(prefersReducedMotion(undefined), false);
  assert.equal(prefersReducedMotion({}), false);
});

test('prefersReducedMotion uses the canonical reduced-motion media query', () => {
  const queries: string[] = [];
  const result = prefersReducedMotion({
    matchMedia: (query) => {
      queries.push(query);
      return { matches: true };
    },
  });

  assert.equal(result, true);
  assert.deepEqual(queries, [REDUCED_MOTION_QUERY]);
});

test('prefersReducedMotion fails closed when matchMedia throws or reports no match', () => {
  assert.equal(
    prefersReducedMotion({
      matchMedia: () => {
        throw new Error('unsupported');
      },
    }),
    false,
  );

  assert.equal(
    prefersReducedMotion({
      matchMedia: () => ({ matches: false }),
    }),
    false,
  );
});
