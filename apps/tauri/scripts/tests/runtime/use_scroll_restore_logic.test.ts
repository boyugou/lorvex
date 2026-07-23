import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createScrollRestoreController,
  type ScrollPositionStore,
} from '../../../app/src/lib/useScrollRestore.logic';

test('scroll restore restores a saved positive scrollTop once per key', () => {
  const values = new Map<string, number>([['list-a', 240]]);
  const store: ScrollPositionStore = {
    get: (key) => values.get(key),
    set: (key, scrollTop) => { values.set(key, scrollTop); },
  };
  const controller = createScrollRestoreController(store);
  const element = { scrollTop: 0 };

  controller.restore('list-a', element);
  assert.equal(element.scrollTop, 240);
  assert.equal(controller.getLastRestoredKey(), 'list-a');

  element.scrollTop = 10;
  controller.restore('list-a', element);
  assert.equal(element.scrollTop, 10);
});

test('scroll restore re-runs when the key changes', () => {
  const values = new Map<string, number>([
    ['list-a', 120],
    ['list-b', 360],
  ]);
  const store: ScrollPositionStore = {
    get: (key) => values.get(key),
    set: (key, scrollTop) => { values.set(key, scrollTop); },
  };
  const controller = createScrollRestoreController(store);
  const element = { scrollTop: 0 };

  controller.restore('list-a', element);
  assert.equal(element.scrollTop, 120);

  element.scrollTop = 0;
  controller.restore('list-b', element);
  assert.equal(element.scrollTop, 360);
  assert.equal(controller.getLastRestoredKey(), 'list-b');
});

test('scroll restore ignores missing or zero positions but still records the restored key', () => {
  const values = new Map<string, number>([
    ['zero', 0],
  ]);
  const store: ScrollPositionStore = {
    get: (key) => values.get(key),
    set: (key, scrollTop) => { values.set(key, scrollTop); },
  };
  const controller = createScrollRestoreController(store);
  const element = { scrollTop: 75 };

  controller.restore('missing', element);
  assert.equal(element.scrollTop, 75);
  assert.equal(controller.getLastRestoredKey(), 'missing');

  controller.restore('zero', element);
  assert.equal(element.scrollTop, 75);
  assert.equal(controller.getLastRestoredKey(), 'zero');
});

test('scroll restore remember persists the latest scrollTop', () => {
  const writes: Array<{ key: string; scrollTop: number }> = [];
  const controller = createScrollRestoreController({
    get: () => undefined,
    set: (key, scrollTop) => {
      writes.push({ key, scrollTop });
    },
  });

  controller.remember('list-a', 512);
  assert.deepEqual(writes, [{ key: 'list-a', scrollTop: 512 }]);
});
