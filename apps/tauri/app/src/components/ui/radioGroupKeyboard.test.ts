import { describe, expect, it, vi } from 'vitest';

import {
  handleRovingRadioGroupKeyDown,
  handleRovingRadioSpaceKey,
  moveRovingRadioIndex,
} from './radioGroupKeyboard';

describe('roving radio group keyboard support', () => {
  it.each([
    ['ArrowRight', 1],
    ['ArrowDown', 1],
    ['ArrowLeft', 2],
    ['ArrowUp', 2],
    ['Home', 0],
    ['End', 2],
  ])('moves from index 0 with %s', (key, expected) => {
    expect(moveRovingRadioIndex(0, 3, key)).toBe(expected);
  });

  it('ignores unsupported keys and empty option lists', () => {
    expect(moveRovingRadioIndex(1, 3, 'Tab')).toBe(1);
    expect(moveRovingRadioIndex(0, 0, 'ArrowRight')).toBe(0);
  });

  it('prevents default, selects, and focuses the next option for navigation keys', () => {
    const preventDefault = vi.fn();
    const onSelect = vi.fn();
    const focusOption = vi.fn();

    const handled = handleRovingRadioGroupKeyDown({
      currentIndex: 0,
      focusOption,
      key: 'ArrowRight',
      onSelect,
      optionCount: 3,
      preventDefault,
    });

    expect(handled).toBe(true);
    expect(preventDefault).toHaveBeenCalledTimes(1);
    expect(onSelect).toHaveBeenCalledWith(1);
    expect(focusOption).toHaveBeenCalledWith(1);
  });

  it('handles Space as selection for a focused radio', () => {
    const preventDefault = vi.fn();
    const onSelect = vi.fn();

    const handled = handleRovingRadioSpaceKey({
      key: ' ',
      onSelect,
      preventDefault,
    });

    expect(handled).toBe(true);
    expect(preventDefault).toHaveBeenCalledTimes(1);
    expect(onSelect).toHaveBeenCalledTimes(1);
  });
});
