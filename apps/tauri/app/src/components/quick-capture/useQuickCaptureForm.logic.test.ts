import { describe, expect, it } from 'vitest';
import { MAX_TAG_NAME_LENGTH } from '@lorvex/shared/validation';
import type { ListWithCount } from '@/lib/ipc/tasks/models';

import {
  prepareQuickCaptureSubmission,
  quickCaptureSetupListSignature,
  readQuickCaptureDraftFromStorageValue,
  resolveQuickCaptureInitialState,
  resolveQuickCaptureSetupBootstrap,
  restoreLastListIdFromValue,
  shouldLoadQuickCaptureSetupStatus,
} from './useQuickCaptureForm.logic';
import {
  appendQuickCaptureTagDraft,
  clampQuickCaptureTagDraftInput,
  currentQuickCaptureTagToken,
  parseQuickCaptureTagDraft,
  replaceCurrentQuickCaptureTagToken,
  serializeQuickCaptureSubmissionTags,
} from './tagDraft';

function makeList(id: string, name: string): ListWithCount {
  return {
    id,
    name,
    color: null,
    icon: null,
    description: null,
    ai_notes: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    open_count: 0,
  };
}

const lists: ListWithCount[] = [makeList('list-a', 'Inbox'), makeList('list-b', 'Work')];

describe('quick capture tag draft helpers', () => {
  it('parses, trims, clamps, and deduplicates comma tag drafts', () => {
    const longTag = 'x'.repeat(MAX_TAG_NAME_LENGTH + 20);
    expect(parseQuickCaptureTagDraft(` alpha, , ALPHA, beta , ${longTag}`)).toEqual([
      'alpha',
      'beta',
      'x'.repeat(MAX_TAG_NAME_LENGTH),
    ]);
  });

  it('appends hashtag selections through the same normalized draft format used by toolbar selections', () => {
    expect(appendQuickCaptureTagDraft('', 'alpha')).toBe('alpha, ');
    expect(appendQuickCaptureTagDraft('alpha', 'beta')).toBe('alpha, beta, ');
    expect(appendQuickCaptureTagDraft('alpha, ', 'ALPHA')).toBe('alpha, ');
  });

  it('replaces the current toolbar token without duplicating existing tags', () => {
    expect(currentQuickCaptureTagToken('alpha, be')).toBe('be');
    expect(replaceCurrentQuickCaptureTagToken('alpha, be', 'beta')).toBe('alpha, beta, ');
    expect(replaceCurrentQuickCaptureTagToken('alpha, be', 'ALPHA')).toBe('alpha, ');
  });

  it('clamps typed toolbar tokens while preserving comma separators and draft spacing', () => {
    expect(clampQuickCaptureTagDraftInput(` alpha , ${'b'.repeat(MAX_TAG_NAME_LENGTH + 20)}  ,`)).toBe(
      ` alpha , ${'b'.repeat(MAX_TAG_NAME_LENGTH)}  ,`,
    );
  });

  it('clamps by code points, not UTF-16 code units, so multi-code-unit emoji at the boundary survive intact (#3680)', () => {
    // 🚀 (U+1F680) is a surrogate pair: 2 code units, 1 code point.
    // Build an input whose last "fitting" character is an emoji that
    // straddles the byte-length boundary if you slice by code units.
    const filler = 'a'.repeat(MAX_TAG_NAME_LENGTH - 1);
    const innerWithEmojiAtBoundary = `${filler}🚀extra`;
    const clamped = clampQuickCaptureTagDraftInput(innerWithEmojiAtBoundary);
    // Must NOT contain an unpaired surrogate. `\uD800-\uDFFF` covers
    // both halves; a well-formed string only contains them as paired
    // adjacent code units.
    for (let i = 0; i < clamped.length; i++) {
      const code = clamped.charCodeAt(i);
      const isHighSurrogate = code >= 0xd800 && code <= 0xdbff;
      const isLowSurrogate = code >= 0xdc00 && code <= 0xdfff;
      if (isHighSurrogate) {
        const next = clamped.charCodeAt(i + 1);
        expect(next >= 0xdc00 && next <= 0xdfff).toBe(true);
        i++; // skip the paired half we just validated
      } else {
        expect(isLowSurrogate).toBe(false);
      }
    }
    // The emoji either survived whole or was dropped whole.
    const codePointCount = Array.from(clamped).length;
    expect(codePointCount).toBeLessThanOrEqual(MAX_TAG_NAME_LENGTH);
  });

  it('parses emoji at the truncation boundary without creating lone surrogates (#3680)', () => {
    const filler = 'a'.repeat(MAX_TAG_NAME_LENGTH - 1);
    const overflow = `${filler}🚀extra`;
    const [tag] = parseQuickCaptureTagDraft(overflow);
    expect(tag).toBeDefined();
    // Same surrogate-pair invariant on the parsed output.
    for (let i = 0; i < tag!.length; i++) {
      const code = tag!.charCodeAt(i);
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = tag!.charCodeAt(i + 1);
        expect(next >= 0xdc00 && next <= 0xdfff).toBe(true);
        i++;
      } else {
        expect(code >= 0xdc00 && code <= 0xdfff).toBe(false);
      }
    }
  });

  it('serializes submission tags with the same normalization used by title and toolbar entry', () => {
    expect(serializeQuickCaptureSubmissionTags(' alpha, ALPHA, beta, ')).toEqual(['alpha', 'beta']);
    expect(serializeQuickCaptureSubmissionTags(' , ')).toBeNull();
  });
});

describe('readQuickCaptureDraftFromStorageValue', () => {
  it('returns null for empty/null storage', () => {
    expect(readQuickCaptureDraftFromStorageValue(null)).toBeNull();
    expect(readQuickCaptureDraftFromStorageValue('')).toBeNull();
  });

  it('returns null for malformed JSON', () => {
    expect(readQuickCaptureDraftFromStorageValue('{not json')).toBeNull();
  });

  it('returns null when JSON is valid but contains unknown keys', () => {
    // Strict shape — extra keys must be rejected to prevent stale or
    // attacker-supplied storage from leaking unknown fields into the form.
    const raw = JSON.stringify({
      title: 't',
      body: 'b',
      tagsInput: '',
      selectedListId: null,
      extra: 'no',
    });
    expect(readQuickCaptureDraftFromStorageValue(raw)).toBeNull();
  });

  it('returns null when a known field has the wrong type', () => {
    const raw = JSON.stringify({ title: 1, body: 'b', tagsInput: '', selectedListId: null });
    expect(readQuickCaptureDraftFromStorageValue(raw)).toBeNull();
  });

  it('accepts a well-formed draft', () => {
    const raw = JSON.stringify({
      title: 'A',
      body: 'B',
      tagsInput: 'x,y',
      selectedListId: 'list-a',
    });
    expect(readQuickCaptureDraftFromStorageValue(raw)).toEqual({
      title: 'A',
      body: 'B',
      tagsInput: 'x,y',
      selectedListId: 'list-a',
    });
  });

  it('accepts null selectedListId', () => {
    const raw = JSON.stringify({ title: '', body: '', tagsInput: '', selectedListId: null });
    expect(readQuickCaptureDraftFromStorageValue(raw)?.selectedListId).toBeNull();
  });
});

describe('restoreLastListIdFromValue', () => {
  it('returns null for null input', () => {
    expect(restoreLastListIdFromValue(lists, null)).toBeNull();
  });

  it('returns the id when it still exists in the lists', () => {
    expect(restoreLastListIdFromValue(lists, 'list-b')).toBe('list-b');
  });

  it('returns null when the stored id has been deleted', () => {
    // Regression: a list could be deleted out from under the draft, and we
    // must not silently re-target an unrelated list. Returning null forces
    // the caller to fall back to its default selection.
    expect(restoreLastListIdFromValue(lists, 'list-deleted')).toBeNull();
  });
});

describe('resolveQuickCaptureSetupBootstrap', () => {
  it('tracks setup-status loads by the current list snapshot', () => {
    const firstSignature = quickCaptureSetupListSignature([makeList('b', 'B'), makeList('a', 'A')]);
    const secondSignature = quickCaptureSetupListSignature([makeList('a', 'A'), makeList('c', 'C')]);

    expect(firstSignature).toBe('a\nb');
    expect(shouldLoadQuickCaptureSetupStatus({
      selectedListId: null,
      currentListSignature: firstSignature,
      loadedListSignature: null,
    })).toBe(true);
    expect(shouldLoadQuickCaptureSetupStatus({
      selectedListId: null,
      currentListSignature: firstSignature,
      loadedListSignature: firstSignature,
    })).toBe(false);
    expect(shouldLoadQuickCaptureSetupStatus({
      selectedListId: null,
      currentListSignature: secondSignature,
      loadedListSignature: firstSignature,
    })).toBe(true);
    expect(shouldLoadQuickCaptureSetupStatus({
      selectedListId: 'list-a',
      currentListSignature: secondSignature,
      loadedListSignature: firstSignature,
    })).toBe(false);
  });

  it('uses an explicit selected list as ready state without applying a default', () => {
    expect(
      resolveQuickCaptureSetupBootstrap({
        lists,
        selectedListId: 'list-a',
        setupStatus: null,
      }),
    ).toEqual({
      selectedListIdToApply: null,
      resolvedListReady: true,
    });
  });

  it('keeps no-list setup blocked until normal task creation is ready', () => {
    expect(
      resolveQuickCaptureSetupBootstrap({
        lists: [],
        selectedListId: null,
        setupStatus: {
          default_list_id: null,
          default_list_ready: false,
          normal_task_creation_ready: false,
        },
      }),
    ).toEqual({
      selectedListIdToApply: null,
      resolvedListReady: false,
    });
  });

  it('selects the default list when setup status and loaded lists agree', () => {
    expect(
      resolveQuickCaptureSetupBootstrap({
        lists,
        selectedListId: null,
        setupStatus: {
          default_list_id: 'list-b',
          default_list_ready: true,
          normal_task_creation_ready: true,
        },
      }),
    ).toEqual({
      selectedListIdToApply: 'list-b',
      resolvedListReady: true,
    });
  });

  it('treats backend default-list readiness as sufficient while local lists are still loading', () => {
    expect(
      resolveQuickCaptureSetupBootstrap({
        lists: [],
        selectedListId: null,
        setupStatus: {
          default_list_id: 'list-b',
          default_list_ready: true,
          normal_task_creation_ready: true,
        },
      }),
    ).toEqual({
      selectedListIdToApply: null,
      resolvedListReady: true,
    });
  });
});

describe('resolveQuickCaptureInitialState', () => {
  it('falls back to empty fields when nothing is provided', () => {
    const state = resolveQuickCaptureInitialState({
      lists,
      initialData: undefined,
      initialDraft: null,
      storedLastListId: null,
    });
    expect(state).toEqual({
      title: '',
      body: '',
      showBody: false,
      selectedListId: null,
      dateOption: 'none',
      customDate: '',
      priority: null,
      tagsInput: '',
    });
  });

  it('matches initialData.list by case-insensitive name', () => {
    const state = resolveQuickCaptureInitialState({
      lists,
      initialData: { list: 'WORK' },
      initialDraft: null,
      storedLastListId: null,
    });
    expect(state.selectedListId).toBe('list-b');
  });

  it('matches initialData.list by id when the name lookup fails', () => {
    const state = resolveQuickCaptureInitialState({
      lists,
      initialData: { list: 'list-a' },
      initialDraft: null,
      storedLastListId: null,
    });
    expect(state.selectedListId).toBe('list-a');
  });

  it('prefers initialData per-field but merges draft for fields initialData omits', () => {
    // initialData supplies title only; body + tags + listId fall back to the
    // draft. This is what makes the Retry affordance whole — failure data
    // only carries title/list/due/priority, but the user typed a body and
    // tags they expect to recover (UX bug U4).
    const state = resolveQuickCaptureInitialState({
      lists,
      initialData: { title: 'from-assistant' },
      initialDraft: { title: 'from-draft', body: 'B', tagsInput: 'tag1', selectedListId: 'list-b' },
      storedLastListId: null,
    });
    expect(state.title).toBe('from-assistant');
    expect(state.body).toBe('B');
    expect(state.tagsInput).toBe('tag1');
    expect(state.selectedListId).toBe('list-b');
  });

  it('initialData.list still wins over draft.selectedListId when both resolve', () => {
    const state = resolveQuickCaptureInitialState({
      lists,
      initialData: { list: 'list-a' },
      initialDraft: { title: '', body: '', tagsInput: '', selectedListId: 'list-b' },
      storedLastListId: null,
    });
    expect(state.selectedListId).toBe('list-a');
  });

  it('uses the draft.selectedListId only when that list still exists', () => {
    const state = resolveQuickCaptureInitialState({
      lists,
      initialData: undefined,
      initialDraft: { title: '', body: '', tagsInput: '', selectedListId: 'list-deleted' },
      storedLastListId: 'list-a',
    });
    // list-deleted is gone, fall through to storedLastListId.
    expect(state.selectedListId).toBe('list-a');
  });

  it('flips dateOption to "custom" when initialData.due is present', () => {
    const state = resolveQuickCaptureInitialState({
      lists,
      initialData: { due: '2026-05-01' },
      initialDraft: null,
      storedLastListId: null,
    });
    expect(state.dateOption).toBe('custom');
    expect(state.customDate).toBe('2026-05-01');
  });

  it('only accepts priorities 1, 2, 3 and rejects everything else', () => {
    for (const valid of [1, 2, 3]) {
      const state = resolveQuickCaptureInitialState({
        lists,
        initialData: { priority: valid },
        initialDraft: null,
        storedLastListId: null,
      });
      expect(state.priority).toBe(valid);
    }
    for (const invalid of [0, 4, -1, 99]) {
      const state = resolveQuickCaptureInitialState({
        lists,
        initialData: { priority: invalid },
        initialDraft: null,
        storedLastListId: null,
      });
      expect(state.priority).toBeNull();
    }
  });

  it('shows the body field only when the draft already has body content', () => {
    const withBody = resolveQuickCaptureInitialState({
      lists,
      initialData: undefined,
      initialDraft: { title: '', body: 'note', tagsInput: '', selectedListId: null },
      storedLastListId: null,
    });
    expect(withBody.showBody).toBe(true);

    const withoutBody = resolveQuickCaptureInitialState({
      lists,
      initialData: undefined,
      initialDraft: { title: '', body: '', tagsInput: '', selectedListId: null },
      storedLastListId: null,
    });
    expect(withoutBody.showBody).toBe(false);
  });
});

describe('prepareQuickCaptureSubmission', () => {
  const baseArgs = {
    title: 'Write report',
    body: '',
    tagsInput: '',
    selectedListId: null,
    resolvedDueDate: undefined,
    priority: null,
    estimatedMinutesInput: '',
  };

  it('builds the simplest possible submission for a bare title', () => {
    const out = prepareQuickCaptureSubmission(baseArgs);
    expect(out).toEqual({
      submitTitle: 'Write report',
      input: {
        priority: null,
        estimatedMinutes: null,
        tags: null,
      },
    });
  });

  it('encodes tags as a typed array for the IPC contract', () => {
    // IPC contract: tags are sent as a typed array. Trim each tag and
    // drop empties so "  alpha , , beta ,  " round-trips cleanly.
    const out = prepareQuickCaptureSubmission({
      ...baseArgs,
      tagsInput: '  alpha , , beta ,  ',
    });
    expect(out?.input.tags).toEqual(['alpha', 'beta']);
  });

  it('returns null tags when input is whitespace-only', () => {
    const out = prepareQuickCaptureSubmission({ ...baseArgs, tagsInput: '   ' });
    expect(out?.input.tags).toBeNull();
  });

  it('returns null when the estimated-minutes input is non-empty but invalid', () => {
    // Guard: a typo like "abc" or "0" must abort the submission rather than
    // silently coerce to 0/NaN minutes.
    expect(
      prepareQuickCaptureSubmission({ ...baseArgs, estimatedMinutesInput: 'abc' }),
    ).toBeNull();
    expect(
      prepareQuickCaptureSubmission({ ...baseArgs, estimatedMinutesInput: '0' }),
    ).toBeNull();
    expect(
      prepareQuickCaptureSubmission({ ...baseArgs, estimatedMinutesInput: '99999' }),
    ).toBeNull();
  });

  it('parses a valid integer estimated-minutes value', () => {
    const out = prepareQuickCaptureSubmission({
      ...baseArgs,
      estimatedMinutesInput: '45',
    });
    expect(out?.input.estimatedMinutes).toBe(45);
  });

  it('threads through listId / dueDate / body when provided', () => {
    const out = prepareQuickCaptureSubmission({
      ...baseArgs,
      selectedListId: 'list-a',
      resolvedDueDate: '2026-05-01',
      body: '  some details  ',
    });
    expect(out?.input.listId).toBe('list-a');
    expect(out?.input.dueDate).toBe('2026-05-01');
    expect(out?.input.body).toBe('some details');
  });

  it('drops a whitespace-only body so the API receives an undefined field instead of empty string', () => {
    const out = prepareQuickCaptureSubmission({ ...baseArgs, body: '   \n   ' });
    expect(out?.input.body).toBeUndefined();
  });

  it('uses activeNlDateCleanTitle when supplied so the date phrase is removed from the title', () => {
    // When the natural-language date parser strips "by friday" out of the
    // title, the cleaned title is what should be persisted, not the raw
    // user input.
    const out = prepareQuickCaptureSubmission({
      ...baseArgs,
      title: 'finish paper by friday',
      activeNlDateCleanTitle: 'finish paper',
      resolvedDueDate: '2026-04-17',
    });
    expect(out?.submitTitle).toBe('finish paper');
  });

  it('falls back to the trimmed raw title when no parsed clean title is provided', () => {
    const out = prepareQuickCaptureSubmission({ ...baseArgs, title: '  Write report  ' });
    expect(out?.submitTitle).toBe('Write report');
  });
});
