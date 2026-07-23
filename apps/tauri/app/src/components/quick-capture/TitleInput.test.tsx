import { createRef } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import type { HashtagAutocompleteState } from '../tag-autocomplete/useHashtagAutocomplete';

const hashtagState = vi.hoisted(() => ({
  current: null as HashtagAutocompleteState | null,
}));

vi.mock('../tag-autocomplete/useHashtagAutocomplete', async () => {
  const actual = await vi.importActual<typeof import('../tag-autocomplete/useHashtagAutocomplete')>(
    '../tag-autocomplete/useHashtagAutocomplete',
  );
  return {
    ...actual,
    useHashtagAutocomplete: () => {
      if (!hashtagState.current) throw new Error('missing hashtag autocomplete test state');
      return hashtagState.current;
    },
  };
});

import TitleInput from './TitleInput';

function createHashtagState(): HashtagAutocompleteState {
  const listboxId = 'quick-capture-hashtag-listbox';
  const getOptionId = (index: number) => `${listboxId}-option-${index}`;
  return {
    accept: vi.fn(),
    activeOptionId: getOptionId(1),
    dismiss: vi.fn(),
    fragment: null,
    getOptionId,
    highlightIndex: 1,
    listboxId,
    onInputKeyDown: vi.fn(() => false),
    open: true,
    setHighlightIndex: vi.fn(),
    suggestions: [
      { display_name: 'focus', color: null },
      { display_name: 'follow-up', color: '#22c55e' },
    ],
  };
}

const t = (key: string): string => ({
  'capture.placeholder': 'Task title',
  'tags.autocomplete.label': 'Tag suggestions',
})[key] ?? key;

describe('Quick Capture hashtag combobox semantics', () => {
  it('links the title input to the keyboard-highlighted hashtag option', () => {
    hashtagState.current = createHashtagState();

    const html = renderToStaticMarkup(
      <TitleInput
        title="Email #fo"
        setTitle={vi.fn()}
        body=""
        setBody={vi.fn()}
        showBody={false}
        setShowBody={vi.fn()}
        isComposing={false}
        setIsComposing={vi.fn()}
        onSubmit={vi.fn()}
        onSubmitAndContinue={vi.fn()}
        canSubmit
        inputRef={createRef<HTMLInputElement>()}
        isMobile={false}
        t={t}
        tagsInput=""
        setTagsInput={vi.fn()}
      />,
    );

    expect(html).toContain('role="combobox"');
    expect(html).toContain('aria-controls="quick-capture-hashtag-listbox"');
    expect(html).toContain('aria-activedescendant="quick-capture-hashtag-listbox-option-1"');
    expect(html).toContain('id="quick-capture-hashtag-listbox"');
    expect(html).toContain('id="quick-capture-hashtag-listbox-option-0"');
    expect(html).toContain('id="quick-capture-hashtag-listbox-option-1"');
    expect(html).toContain('aria-selected="true"');
  });
});
