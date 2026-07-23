import { describe, expect, it } from 'vitest';

import { focusSavedQueriesMenuInitialTarget } from './SavedQueriesMenu.runtime';

describe('SavedQueriesMenu dialog focus handling', () => {
  it('uses natural dialog focus targets without a roving menu pointer', () => {
    const calls: string[] = [];
    const panel = { focus: () => { calls.push('panel'); } };
    const firstItem = { focus: () => { calls.push('first-item'); } };
    const nameInput = { focus: () => { calls.push('name-input'); } };

    expect(focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: false,
      savedQueryCount: 1,
      firstItem,
      nameInput,
    })).toBe('first-item');

    expect(focusSavedQueriesMenuInitialTarget({
      panel,
      activeElement: null,
      isActiveElementInPanel: () => false,
      isLoading: false,
      savedQueryCount: 0,
      firstItem: null,
      nameInput,
    })).toBe('name-input');

    expect(calls).toEqual(['first-item', 'name-input']);
  });
});
