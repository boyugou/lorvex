import assert from 'node:assert/strict';
import test from 'node:test';

import {
  clampListPickerFocusIndex,
  getNextListPickerFocusIndex,
} from '../../../app/src/components/ui/ListPickerOverlay.runtime';

test('list picker focus index clamps to a valid option when async results arrive', () => {
  assert.equal(clampListPickerFocusIndex(-1, 0), -1);
  assert.equal(clampListPickerFocusIndex(-1, 3), 0);
  assert.equal(clampListPickerFocusIndex(5, 3), 2);
});

test('list picker arrow navigation no-ops while there are no options', () => {
  assert.equal(getNextListPickerFocusIndex('ArrowDown', 0, 0), -1);
  assert.equal(getNextListPickerFocusIndex('ArrowUp', -1, 0), -1);
});

test('list picker arrow navigation never returns a negative active option when options exist', () => {
  assert.equal(getNextListPickerFocusIndex('ArrowDown', -1, 3), 0);
  assert.equal(getNextListPickerFocusIndex('ArrowUp', -1, 3), 0);
  assert.equal(getNextListPickerFocusIndex('ArrowDown', 2, 3), 2);
  assert.equal(getNextListPickerFocusIndex('ArrowUp', 0, 3), 0);
});
