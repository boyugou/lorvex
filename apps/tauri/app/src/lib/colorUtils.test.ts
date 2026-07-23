import { describe, expect, it } from 'vitest';

import { eventColorStyles } from './colorUtils';

describe('eventColorStyles', () => {
  it('uses logical inline-start borders for event accents', () => {
    expect(eventColorStyles('#336699', 'soft', 2)).toEqual({
      backgroundColor: 'oklch(from #336699 l c h / 0.1)',
      borderInlineStart: '2px solid color-mix(in oklch, #336699 85%, var(--color-surface-2))',
    });
  });

  it('keeps the warning fallback on the logical inline-start edge', () => {
    expect(eventColorStyles(null, 'medium')).toEqual({
      backgroundColor: 'color-mix(in oklch, var(--color-warning) 15%, transparent)',
      borderInlineStart: '3px solid var(--color-warning)',
    });
  });
});
