import { describe, expect, it } from 'vitest';

import {
  reduceKeyboardExtend,
  reduceModifierClick,
} from './useTaskSelection';

describe('task selection reducers', () => {
  it('filters non-selectable rows out of shift-arrow ranges', () => {
    const selectableIds = new Set(['today-1', 'today-2']);
    const result = reduceKeyboardExtend(
      ['focus-1', 'today-1', 'completed-1', 'today-2'],
      null,
      'focus-1',
      'down',
      selectableIds,
    );

    expect(result).not.toBeNull();
    expect(result?.nextFocusedId).toBe('today-1');
    expect([...result!.next]).toEqual(['today-1']);
  });

  it('filters non-selectable rows out of shift-click ranges', () => {
    const selectableIds = new Set(['today-1', 'today-2']);
    const result = reduceModifierClick(
      ['focus-1', 'today-1', 'completed-1', 'today-2'],
      new Set(),
      'focus-1',
      'today-2',
      { shiftKey: true, metaKey: false, ctrlKey: false },
      null,
      selectableIds,
    );

    expect([...result.next]).toEqual(['today-1', 'today-2']);
    expect(result.nextAnchor).toBe('focus-1');
  });
});
