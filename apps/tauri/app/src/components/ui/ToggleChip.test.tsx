import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import { ToggleChip } from './ToggleChip';

describe('ToggleChip accessibility state', () => {
  it('exposes selected state as pressed button semantics by default', () => {
    const selected = renderToStaticMarkup(<ToggleChip selected>Month</ToggleChip>);
    const idle = renderToStaticMarkup(<ToggleChip selected={false}>Week</ToggleChip>);

    expect(selected).toContain('aria-pressed="true"');
    expect(idle).toContain('aria-pressed="false"');
  });

  it('does not add aria-pressed when callers provide explicit selection semantics', () => {
    const selectedTab = renderToStaticMarkup(
      <ToggleChip selected aria-selected="true" role="tab">
        Month
      </ToggleChip>,
    );

    expect(selectedTab).toContain('aria-selected="true"');
    expect(selectedTab).not.toContain('aria-pressed=');
  });
});
