import assert from 'node:assert/strict';
import test from 'node:test';

import {
  reconcileTaskDraftField,
  shouldPersistTaskDetailDrafts,
} from '../../../app/src/components/task-detail/controller/drafts.logic';

test('clean task-detail draft ignores one stale pre-persist echo and clears the skip value', () => {
  const result = reconcileTaskDraftField({
    dirty: false,
    currentDraft: 'new title',
    incomingValue: 'old title',
    skipValue: 'old title',
  });

  assert.equal(result.shouldUpdateDraft, false);
  assert.equal(result.nextDraft, 'new title');
  assert.equal(result.nextSkipValue, null);
});

test('clean task-detail draft accepts fresh task data once the stale echo is gone', () => {
  const result = reconcileTaskDraftField({
    dirty: false,
    currentDraft: 'new title',
    incomingValue: 'fresh title',
    skipValue: null,
  });

  assert.equal(result.shouldUpdateDraft, true);
  assert.equal(result.nextDraft, 'fresh title');
  assert.equal(result.nextSkipValue, null);
});

test('dirty task-detail draft never gets clobbered by incoming task data', () => {
  const result = reconcileTaskDraftField({
    dirty: true,
    currentDraft: 'local unsaved edit',
    incomingValue: 'remote change',
    skipValue: 'stale server value',
  });

  assert.equal(result.shouldUpdateDraft, false);
  assert.equal(result.nextDraft, 'local unsaved edit');
  assert.equal(result.nextSkipValue, 'stale server value');
});

test('body-style empty skip values still suppress a matching stale echo exactly once', () => {
  const first = reconcileTaskDraftField({
    dirty: false,
    currentDraft: 'body draft',
    incomingValue: '',
    skipValue: '',
  });

  assert.equal(first.shouldUpdateDraft, false);
  assert.equal(first.nextDraft, 'body draft');
  assert.equal(first.nextSkipValue, null);

  const second = reconcileTaskDraftField({
    dirty: false,
    currentDraft: first.nextDraft,
    incomingValue: 'fresh body',
    skipValue: first.nextSkipValue,
  });

  assert.equal(second.shouldUpdateDraft, true);
  assert.equal(second.nextDraft, 'fresh body');
  assert.equal(second.nextSkipValue, null);
});

test('task-detail draft persistence uses the synchronous dirty source of truth', () => {
  assert.equal(shouldPersistTaskDetailDrafts({
    bodyDirty: false,
    titleDirty: false,
  }), false);

  assert.equal(shouldPersistTaskDetailDrafts({
    bodyDirty: true,
    titleDirty: false,
  }), true);

  assert.equal(shouldPersistTaskDetailDrafts({
    bodyDirty: false,
    titleDirty: true,
  }), true);
});
