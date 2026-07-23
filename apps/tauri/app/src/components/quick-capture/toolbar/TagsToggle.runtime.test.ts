import { describe, expect, it } from 'vitest';

import { resolveTagAutocompleteEscapeAction } from './TagsToggle.runtime';

describe('resolveTagAutocompleteEscapeAction', () => {
  it('closes suggestions before the whole quick-capture modal can own Escape', () => {
    expect(resolveTagAutocompleteEscapeAction({
      showDropdown: true,
      showInput: true,
    })).toBe('close-suggestions');
  });

  it('collapses the tag input before the whole quick-capture modal can own Escape', () => {
    expect(resolveTagAutocompleteEscapeAction({
      showDropdown: false,
      showInput: true,
    })).toBe('collapse-input');
  });

  it('does not consume Escape when the tag editor is already closed', () => {
    expect(resolveTagAutocompleteEscapeAction({
      showDropdown: false,
      showInput: false,
    })).toBe('none');
  });
});
