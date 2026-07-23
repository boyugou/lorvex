import { describe, expect, it } from 'vitest';

import { resolveSelectedTagFilterPillLabels } from './TagFilterPills.runtime';

describe('resolveSelectedTagFilterPillLabels', () => {
  it('keeps selected tags visible even when absent from the current available tag list', () => {
    expect(
      resolveSelectedTagFilterPillLabels(
        ['deep-work', 'planning'],
        new Set(['focus', 'planning']),
      ),
    ).toEqual(['planning', 'focus']);
  });
});
