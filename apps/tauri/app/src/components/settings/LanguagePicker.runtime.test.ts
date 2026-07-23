import { describe, expect, it } from 'vitest';

import { resolveLanguagePickerDropdownPosition } from './LanguagePicker.runtime';

describe('resolveLanguagePickerDropdownPosition', () => {
  it('clamps right-edge dropdowns using the explicit settings popover width', () => {
    const position = resolveLanguagePickerDropdownPosition(
      {
        top: 40,
        left: 290,
        bottom: 68,
      },
      {
        viewportWidth: 320,
        viewportHeight: 500,
      },
    );

    expect(position).toEqual({
      top: 74,
      left: 104,
    });
  });

  it('falls back to viewport padding when the language popover is wider than the viewport', () => {
    const position = resolveLanguagePickerDropdownPosition(
      {
        top: 40,
        left: 120,
        bottom: 68,
      },
      {
        viewportWidth: 180,
        viewportHeight: 500,
      },
    );

    expect(position.left).toBe(8);
  });
});
