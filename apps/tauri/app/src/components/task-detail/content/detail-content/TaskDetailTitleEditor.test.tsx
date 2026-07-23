import { createRef } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import type { HashtagAutocompleteState } from '@/components/tag-autocomplete/useHashtagAutocomplete';

import { TaskDetailTitleEditor } from './TaskDetailTitleEditor';

function createHashtagState(): HashtagAutocompleteState {
  const listboxId = 'task-detail-hashtag-listbox';
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
  'tags.autocomplete.label': 'Tag suggestions',
  'task.title': 'Task title',
})[key] ?? key;

describe('TaskDetailTitleEditor hashtag combobox semantics', () => {
  it('links the title input to the keyboard-highlighted hashtag option', () => {
    const html = renderToStaticMarkup(
      <TaskDetailTitleEditor
        handleTitleBlur={vi.fn()}
        handleTitleChange={vi.fn()}
        handleTitleCompositionEnd={vi.fn()}
        handleTitleCompositionStart={vi.fn()}
        handleTitleKeyDown={vi.fn()}
        hashtag={createHashtagState()}
        isComplete={false}
        resolvedTitleRef={createRef<HTMLInputElement>()}
        t={t}
        titleDraft="Email #fo"
      />,
    );

    expect(html).toContain('role="combobox"');
    expect(html).toContain('aria-controls="task-detail-hashtag-listbox"');
    expect(html).toContain('aria-activedescendant="task-detail-hashtag-listbox-option-1"');
    expect(html).toContain('id="task-detail-hashtag-listbox"');
    expect(html).toContain('id="task-detail-hashtag-listbox-option-0"');
    expect(html).toContain('id="task-detail-hashtag-listbox-option-1"');
    expect(html).toContain('aria-selected="true"');
  });
});
