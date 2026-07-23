import { describe, expect, test } from 'vitest';

import {
  reconcileTaskDraftField,
  shouldPersistTaskDetailDrafts,
} from './drafts.logic';

// `reconcileTaskDraftField` decides whether a server-pushed value (the
// "incoming" task title/body) should overwrite the local draft. The
// rule has three branches:
//   1. dirty=true       → never overwrite (user is mid-edit)
//   2. skipValue match  → drop the skip (we just saved it; it's a
//                          self-echo, not a peer's edit)
//   3. otherwise        → adopt incoming, mark draft for update if changed
// Each branch has its own observable outcome. These cases pin the
// contract so a refactor that re-orders the conditions or merges arms
// surfaces here, not as a "draft kept disappearing" bug report.

describe('reconcileTaskDraftField', () => {
  test('dirty: keep current draft, retain non-null skip value, do not update', () => {
    const result = reconcileTaskDraftField({
      dirty: true,
      currentDraft: 'local edit',
      incomingValue: 'remote update',
      skipValue: 'previous-save',
    });
    expect(result).toEqual({
      nextDraft: 'local edit',
      nextSkipValue: 'previous-save',
      shouldUpdateDraft: false,
    });
  });

  test('dirty + null skip: normalize undefined skip to null', () => {
    const result = reconcileTaskDraftField({
      dirty: true,
      currentDraft: 'local edit',
      incomingValue: 'remote update',
      skipValue: undefined,
    });
    expect(result).toEqual({
      nextDraft: 'local edit',
      nextSkipValue: null,
      shouldUpdateDraft: false,
    });
  });

  test('clean + incoming matches skip: drop skip, do not overwrite (self-echo of a save)', () => {
    const result = reconcileTaskDraftField({
      dirty: false,
      currentDraft: 'local current',
      incomingValue: 'just-saved',
      skipValue: 'just-saved',
    });
    expect(result).toEqual({
      nextDraft: 'local current',
      nextSkipValue: null,
      shouldUpdateDraft: false,
    });
  });

  test('clean + incoming differs from current (real peer edit): adopt and mark dirty', () => {
    const result = reconcileTaskDraftField({
      dirty: false,
      currentDraft: 'old',
      incomingValue: 'peer update',
      skipValue: null,
    });
    expect(result).toEqual({
      nextDraft: 'peer update',
      nextSkipValue: null,
      shouldUpdateDraft: true,
    });
  });

  test('clean + incoming equals current: adopt but no update needed (no-op render)', () => {
    const result = reconcileTaskDraftField({
      dirty: false,
      currentDraft: 'same',
      incomingValue: 'same',
      skipValue: null,
    });
    expect(result).toEqual({
      nextDraft: 'same',
      nextSkipValue: null,
      shouldUpdateDraft: false,
    });
  });

  test('clean + skip value present but does NOT match incoming: adopt incoming, clear skip', () => {
    // The skip was for a prior save; a different peer change has
    // arrived since. We don't keep the skip — it's stale.
    const result = reconcileTaskDraftField({
      dirty: false,
      currentDraft: 'old',
      incomingValue: 'peer update',
      skipValue: 'stale-prior-save',
    });
    expect(result).toEqual({
      nextDraft: 'peer update',
      nextSkipValue: null,
      shouldUpdateDraft: true,
    });
  });
});

describe('shouldPersistTaskDetailDrafts', () => {
  test('persists when either field is dirty', () => {
    expect(shouldPersistTaskDetailDrafts({ titleDirty: true, bodyDirty: false })).toBe(true);
    expect(shouldPersistTaskDetailDrafts({ titleDirty: false, bodyDirty: true })).toBe(true);
    expect(shouldPersistTaskDetailDrafts({ titleDirty: true, bodyDirty: true })).toBe(true);
  });

  test('does not persist when nothing is dirty', () => {
    expect(shouldPersistTaskDetailDrafts({ titleDirty: false, bodyDirty: false })).toBe(false);
  });
});
