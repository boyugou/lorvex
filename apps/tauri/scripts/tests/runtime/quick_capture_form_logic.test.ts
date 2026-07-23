import assert from 'node:assert/strict';
import test from 'node:test';

import {
  prepareQuickCaptureSubmission,
  quickCaptureSetupListSignature,
  readQuickCaptureDraftFromStorageValue,
  resolveQuickCaptureInitialState,
  resolveQuickCaptureSetupBootstrap,
  restoreLastListIdFromValue,
  shouldLoadQuickCaptureSetupStatus,
  type QuickCaptureDraft,
} from '../../../app/src/components/quick-capture/useQuickCaptureForm.logic';
import {
  appendQuickCaptureTagDraft,
  replaceCurrentQuickCaptureTagToken,
  serializeQuickCaptureSubmissionTags,
} from '../../../app/src/components/quick-capture/tagDraft';

const lists = [
  { id: 'list-inbox', name: 'Inbox', task_count: 0 },
  { id: 'list-ops', name: 'Ops', task_count: 2 },
];

test('quick capture deep-link intent wins over stored draft and restored list id', () => {
  const draft: QuickCaptureDraft = {
    title: 'draft title',
    body: 'draft body',
    tagsInput: 'alpha, beta',
    selectedListId: 'list-inbox',
  };

  const state = resolveQuickCaptureInitialState({
    lists,
    initialData: {
      title: 'launch checklist',
      list: 'Ops',
      due: '2026-04-25',
      priority: 2,
    },
    initialDraft: draft,
    storedLastListId: 'list-inbox',
  });

  assert.equal(state.title, 'launch checklist');
  assert.equal(state.body, 'draft body');
  assert.equal(state.showBody, true);
  assert.equal(state.selectedListId, 'list-ops');
  assert.equal(state.dateOption, 'custom');
  assert.equal(state.customDate, '2026-04-25');
  assert.equal(state.priority, 2);
  assert.equal(state.tagsInput, 'alpha, beta');
});

test('quick capture restores valid draft list before falling back to stored last list id', () => {
  const draft: QuickCaptureDraft = {
    title: 'draft title',
    body: '',
    tagsInput: '',
    selectedListId: 'missing-list',
  };

  const state = resolveQuickCaptureInitialState({
    lists,
    initialDraft: draft,
    storedLastListId: 'list-ops',
  });

  assert.equal(state.selectedListId, 'list-ops');
  assert.equal(state.title, 'draft title');
  assert.equal(state.dateOption, 'none');
  assert.equal(state.priority, null);
});

test('restoreLastListIdFromValue only returns ids that still exist in the current list set', () => {
  assert.equal(restoreLastListIdFromValue(lists, 'list-ops'), 'list-ops');
  assert.equal(restoreLastListIdFromValue(lists, 'missing-list'), null);
  assert.equal(restoreLastListIdFromValue(lists, null), null);
});

test('quick capture setup bootstrap derives default-list selection and readiness from one status snapshot', () => {
  assert.deepEqual(
    resolveQuickCaptureSetupBootstrap({
      lists,
      selectedListId: null,
      setupStatus: {
        default_list_id: 'list-ops',
        default_list_ready: true,
        normal_task_creation_ready: true,
      },
    }),
    {
      selectedListIdToApply: 'list-ops',
      resolvedListReady: true,
    },
  );

  assert.deepEqual(
    resolveQuickCaptureSetupBootstrap({
      lists: [],
      selectedListId: null,
      setupStatus: {
        default_list_id: null,
        default_list_ready: false,
        normal_task_creation_ready: false,
      },
    }),
    {
      selectedListIdToApply: null,
      resolvedListReady: false,
    },
  );
});

test('quick capture setup status reloads when the list snapshot changes before a list is selected', () => {
  const emptySignature = quickCaptureSetupListSignature([]);
  const loadedSignature = quickCaptureSetupListSignature(lists);

  assert.equal(
    shouldLoadQuickCaptureSetupStatus({
      selectedListId: null,
      currentListSignature: emptySignature,
      loadedListSignature: null,
    }),
    true,
  );
  assert.equal(
    shouldLoadQuickCaptureSetupStatus({
      selectedListId: null,
      currentListSignature: loadedSignature,
      loadedListSignature: emptySignature,
    }),
    true,
  );
  assert.equal(
    shouldLoadQuickCaptureSetupStatus({
      selectedListId: 'list-ops',
      currentListSignature: loadedSignature,
      loadedListSignature: emptySignature,
    }),
    false,
  );
});

test('quick capture title toolbar and submit tag paths share normalized draft semantics', () => {
  const afterTitleAccept = appendQuickCaptureTagDraft(' alpha, ', 'ALPHA');
  assert.equal(afterTitleAccept, 'alpha, ');
  const afterToolbarAccept = replaceCurrentQuickCaptureTagToken('alpha, be', 'beta');
  assert.equal(afterToolbarAccept, 'alpha, beta, ');
  assert.deepEqual(
    serializeQuickCaptureSubmissionTags(`${afterToolbarAccept}BETA, gamma`),
    ['alpha', 'beta', 'gamma'],
  );
});

test('prepareQuickCaptureSubmission cleans title, body, tags, and due payload', () => {
  const prepared = prepareQuickCaptureSubmission({
    title: 'ship docs tomorrow',
    body: '  detailed body  ',
    tagsInput: ' alpha, beta ,, gamma ',
    selectedListId: 'list-ops',
    resolvedDueDate: '2026-04-24',
    priority: 3,
    estimatedMinutesInput: '45',
    activeNlDateCleanTitle: 'ship docs',
  });

  assert.ok(prepared, 'submission should be prepared for valid duration input');
  assert.equal(prepared?.submitTitle, 'ship docs');
  assert.deepEqual(prepared?.input, {
    listId: 'list-ops',
    dueDate: '2026-04-24',
    priority: 3,
    estimatedMinutes: 45,
    body: 'detailed body',
    tags: ['alpha', 'beta', 'gamma'],
  });
});

test('prepareQuickCaptureSubmission rejects invalid duration input', () => {
  const prepared = prepareQuickCaptureSubmission({
    title: 'ship docs',
    body: '',
    tagsInput: '',
    selectedListId: null,
    resolvedDueDate: undefined,
    priority: null,
    estimatedMinutesInput: '999999',
  });

  assert.equal(prepared, null);
});

test('readQuickCaptureDraftFromStorageValue restores only well-formed draft payloads', () => {
  assert.deepEqual(
    readQuickCaptureDraftFromStorageValue('{"title":"Inbox zero","body":"notes","tagsInput":"ops","selectedListId":"list-ops"}'),
    {
      title: 'Inbox zero',
      body: 'notes',
      tagsInput: 'ops',
      selectedListId: 'list-ops',
    },
  );
  assert.equal(readQuickCaptureDraftFromStorageValue('{"body":"missing title"}'), null);
  assert.equal(
    readQuickCaptureDraftFromStorageValue('{"title":"Inbox zero","tagsInput":"ops","selectedListId":null}'),
    null,
  );
  assert.equal(
    readQuickCaptureDraftFromStorageValue('{"title":"Inbox zero","body":"notes","tagsInput":"ops","selectedListId":{"id":"list-ops"}}'),
    null,
  );
  assert.equal(
    readQuickCaptureDraftFromStorageValue('{"title":"Inbox zero","body":"notes","tagsInput":"ops","selectedListId":"list-ops","debug":true}'),
    null,
  );
  assert.equal(readQuickCaptureDraftFromStorageValue('{oops'), null);
});
