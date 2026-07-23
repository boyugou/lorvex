import assert from 'node:assert/strict';
import test from 'node:test';

import {
  installMonthGridMediaRuntime,
  MOBILE_BREAKPOINT_PX,
  readMonthGridNarrowMatch,
} from '../../../app/src/components/calendar/monthGrid.runtime';

test('month-grid narrow match reads matches fail-closed when matchMedia throws', () => {
  assert.equal(readMonthGridNarrowMatch(() => ({ matches: true })), true);
  assert.equal(
    readMonthGridNarrowMatch(() => {
      throw new Error('unsupported');
    }),
    false,
  );
  assert.equal(MOBILE_BREAKPOINT_PX, 480);
});

test('month-grid media runtime uses modern change listeners and cleans up', () => {
  const matches: boolean[] = [];
  let changeListener: ((event: { matches: boolean }) => void) | null = null;

  const cleanup = installMonthGridMediaRuntime({
    createMediaQueryList: () => ({
      matches: false,
      addEventListener: (_type, listener) => {
        changeListener = listener;
      },
      removeEventListener: (_type, listener) => {
        if (changeListener === listener) {
          changeListener = null;
        }
      },
    }),
    onMatchesChange: (next) => {
      matches.push(next);
    },
  });

  changeListener?.({ matches: true });
  assert.deepEqual(matches, [true]);

  cleanup();
  assert.equal(changeListener, null);
});

test('month-grid media runtime ignores legacy addListener/removeListener-only queries and fails closed when creation throws', () => {
  const matches: boolean[] = [];
  let changeListener: ((event: { matches: boolean }) => void) | null = null;

  const cleanup = installMonthGridMediaRuntime({
    createMediaQueryList: () => ({
      matches: false,
      addListener: (listener) => {
        changeListener = listener;
      },
      removeListener: (listener) => {
        if (changeListener === listener) {
          changeListener = null;
        }
      },
    }),
    onMatchesChange: (next) => {
      matches.push(next);
    },
  });

  assert.equal(changeListener, null);
  changeListener?.({ matches: false });
  assert.deepEqual(matches, []);

  cleanup();
  assert.equal(changeListener, null);

  const noopCleanup = installMonthGridMediaRuntime({
    createMediaQueryList: () => {
      throw new Error('unsupported');
    },
    onMatchesChange: () => {
      throw new Error('should not run');
    },
  });
  noopCleanup();
});
