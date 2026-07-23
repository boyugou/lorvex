import { describe, expect, it } from 'vitest';

import { areViewsEqual } from './support';

describe('areViewsEqual', () => {
  it('treats settings section changes as navigation changes', () => {
    expect(
      areViewsEqual(
        { type: 'settings', sectionId: 'settings-section-general' },
        { type: 'settings', sectionId: 'settings-section-sync' },
      ),
    ).toBe(false);

    expect(
      areViewsEqual(
        { type: 'settings', sectionId: 'settings-section-sync' },
        { type: 'settings', sectionId: 'settings-section-sync' },
      ),
    ).toBe(true);
  });
});
