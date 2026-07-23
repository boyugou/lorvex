import { describe, expect, it } from 'vitest';
import { weekTimelineLaneStyle } from './WeekTimeline.logic';

describe('weekTimelineLaneStyle', () => {
  it('spans the full column for a lone chip (no slot)', () => {
    expect(weekTimelineLaneStyle(undefined)).toEqual({
      insetInlineStart: 'calc(0.125rem + (100% - 0.25rem) * 0 / 1)',
      width: 'calc((100% - 0.25rem) / 1 - 0px)',
    });
  });

  it('spans the full column, no gap, when count is 1', () => {
    expect(weekTimelineLaneStyle({ index: 0, count: 1 })).toEqual({
      insetInlineStart: 'calc(0.125rem + (100% - 0.25rem) * 0 / 1)',
      width: 'calc((100% - 0.25rem) / 1 - 0px)',
    });
  });

  it('splits overlapping chips into equal side-by-side columns with a gap', () => {
    expect(weekTimelineLaneStyle({ index: 0, count: 2 })).toEqual({
      insetInlineStart: 'calc(0.125rem + (100% - 0.25rem) * 0 / 2)',
      width: 'calc((100% - 0.25rem) / 2 - 1px)',
    });
    expect(weekTimelineLaneStyle({ index: 1, count: 2 })).toEqual({
      insetInlineStart: 'calc(0.125rem + (100% - 0.25rem) * 1 / 2)',
      width: 'calc((100% - 0.25rem) / 2 - 1px)',
    });
  });

  it('treats a degenerate zero count as a single full-width column', () => {
    expect(weekTimelineLaneStyle({ index: 0, count: 0 })).toEqual({
      insetInlineStart: 'calc(0.125rem + (100% - 0.25rem) * 0 / 1)',
      width: 'calc((100% - 0.25rem) / 1 - 0px)',
    });
  });
});
