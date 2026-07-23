import { describe, expect, it } from 'vitest';
import { themedSwatch } from './themedSwatch';

describe('themedSwatch', () => {
  it('returns var(--color-warning) when color is null', () => {
    expect(themedSwatch(null, 'dot')).toBe('var(--color-warning)');
    expect(themedSwatch(undefined, 'tile')).toBe('var(--color-warning)');
    expect(themedSwatch('', 'border')).toBe('var(--color-warning)');
  });

  it('mixes 85% user color against surface-2 for dot mode', () => {
    expect(themedSwatch('#ff0000', 'dot')).toBe(
      'color-mix(in oklch, #ff0000 85%, var(--color-surface-2))',
    );
  });

  it('mixes 60% user color against surface-2 for tile mode', () => {
    expect(themedSwatch('#3366cc', 'tile')).toBe(
      'color-mix(in oklch, #3366cc 60%, var(--color-surface-2))',
    );
  });

  it('mixes 85% user color against surface-2 for border mode', () => {
    expect(themedSwatch('rgb(10, 20, 30)', 'border')).toBe(
      'color-mix(in oklch, rgb(10, 20, 30) 85%, var(--color-surface-2))',
    );
  });
});
