import { describe, expect, test } from 'vitest';

import { getRuntimeProfile } from './platform';

describe('getRuntimeProfile', () => {
  test('returns a stable profile reference for the current runtime id', () => {
    expect(getRuntimeProfile()).toBe(getRuntimeProfile());
  });
});
