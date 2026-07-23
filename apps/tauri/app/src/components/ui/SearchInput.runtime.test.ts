import { describe, expect, it, vi } from 'vitest';

import { handleSearchInputKeyDown } from './SearchInput.runtime';

describe('handleSearchInputKeyDown', () => {
  it('owns Escape before clearing and blurring search text', () => {
    const calls: string[] = [];
    const event = {
      key: 'Escape',
      preventDefault: vi.fn(() => calls.push('preventDefault')),
      stopPropagation: vi.fn(() => calls.push('stopPropagation')),
    };

    expect(
      handleSearchInputKeyDown(
        event,
        () => calls.push('clear'),
        () => calls.push('blur'),
      ),
    ).toBe(true);

    expect(calls).toEqual(['preventDefault', 'stopPropagation', 'clear', 'blur']);
  });

  it('leaves non-Escape keys for the input to handle normally', () => {
    const event = {
      key: 'Enter',
      preventDefault: vi.fn(),
      stopPropagation: vi.fn(),
    };
    const clear = vi.fn();
    const blur = vi.fn();

    expect(handleSearchInputKeyDown(event, clear, blur)).toBe(false);

    expect(event.preventDefault).not.toHaveBeenCalled();
    expect(event.stopPropagation).not.toHaveBeenCalled();
    expect(clear).not.toHaveBeenCalled();
    expect(blur).not.toHaveBeenCalled();
  });
});
