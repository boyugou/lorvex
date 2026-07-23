import { describe, expect, it } from 'vitest';

import { isTaskPickerActivationKey } from './taskPickerKeyboard';

describe('isTaskPickerActivationKey', () => {
  it('accepts Enter and Space for aria-activedescendant listboxes', () => {
    expect(isTaskPickerActivationKey('Enter')).toBe(true);
    expect(isTaskPickerActivationKey(' ')).toBe(true);
  });

  it('rejects navigation and printable non-activation keys', () => {
    expect(isTaskPickerActivationKey('ArrowDown')).toBe(false);
    expect(isTaskPickerActivationKey('j')).toBe(false);
    expect(isTaskPickerActivationKey('Spacebar')).toBe(false);
  });
});
