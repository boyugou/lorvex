import assert from 'node:assert/strict';
import test from 'node:test';

import { installForegroundCatchUpController } from '../../../app/src/lib/foregroundCatchUpController';

function createHarness() {
  const visibilityListeners = new Set<() => void>();
  const focusListeners = new Set<() => void>();
  let visibilityState: DocumentVisibilityState = 'hidden';
  let catchUps = 0;

  const controller = installForegroundCatchUpController({
    addWindowFocusListener: (callback) => {
      focusListeners.add(callback);
      return () => focusListeners.delete(callback);
    },
    addVisibilityListener: (callback) => {
      visibilityListeners.add(callback);
      return () => visibilityListeners.delete(callback);
    },
    getVisibilityState: () => visibilityState,
    runCatchUp: () => {
      catchUps += 1;
    },
  });

  return {
    controller,
    focusListeners,
    visibilityListeners,
    setVisibilityState(nextVisibilityState: DocumentVisibilityState) {
      visibilityState = nextVisibilityState;
    },
    get catchUps() {
      return catchUps;
    },
    fireFocus() {
      for (const listener of [...focusListeners]) listener();
    },
    fireVisibilityChange() {
      for (const listener of [...visibilityListeners]) listener();
    },
  };
}

test('foreground catch-up controller triggers on visible resume and focused foreground windows only', () => {
  const harness = createHarness();

  assert.equal(harness.focusListeners.size, 1);
  assert.equal(harness.visibilityListeners.size, 1);

  harness.fireFocus();
  assert.equal(harness.catchUps, 0);

  harness.setVisibilityState('visible');
  harness.fireVisibilityChange();
  assert.equal(harness.catchUps, 1);

  harness.fireFocus();
  assert.equal(harness.catchUps, 2);
});

test('foreground catch-up controller dispose removes listeners and suppresses later events', () => {
  const harness = createHarness();
  const staleFocusListener = [...harness.focusListeners][0];
  const staleVisibilityListener = [...harness.visibilityListeners][0];
  harness.controller.dispose();

  assert.equal(harness.focusListeners.size, 0);
  assert.equal(harness.visibilityListeners.size, 0);

  harness.setVisibilityState('visible');
  staleVisibilityListener?.();
  staleFocusListener?.();
  assert.equal(harness.catchUps, 0);
});
