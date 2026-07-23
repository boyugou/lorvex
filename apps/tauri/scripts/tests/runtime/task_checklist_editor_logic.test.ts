import assert from 'node:assert/strict';
import test from 'node:test';

import {
  buildChecklistProgressLabel,
  reconcileChecklistItemDraft,
} from '../../../app/src/components/task-detail/TaskChecklistEditor.logic';

test('checklist progress label localizes both completed and total counts', () => {
  assert.equal(buildChecklistProgressLabel('en', 3, 8), '3/8');
  assert.equal(buildChecklistProgressLabel('ar-EG', 3, 8), '٣/٨');
  assert.equal(buildChecklistProgressLabel('en', 0, 0), null);
});

test('checklist draft reconcile ignores echoed committed value and then clears the skip guard', () => {
  const first = reconcileChecklistItemDraft({
    dirty: false,
    currentDraft: 'edited',
    incomingValue: 'edited',
    skipValue: 'edited',
  });
  assert.deepEqual(first, {
    nextDraft: 'edited',
    nextSkipValue: null,
    shouldUpdateDraft: false,
  });

  const second = reconcileChecklistItemDraft({
    dirty: false,
    currentDraft: 'edited',
    incomingValue: 'remote value',
    skipValue: first.nextSkipValue,
  });
  assert.deepEqual(second, {
    nextDraft: 'remote value',
    nextSkipValue: null,
    shouldUpdateDraft: true,
  });
});

test('checklist draft reconcile preserves dirty local input against incoming refetches', () => {
  assert.deepEqual(reconcileChecklistItemDraft({
    dirty: true,
    currentDraft: 'local draft',
    incomingValue: 'server text',
    skipValue: null,
  }), {
    nextDraft: 'local draft',
    nextSkipValue: null,
    shouldUpdateDraft: false,
  });
});
